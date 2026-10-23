#if os(macOS)
import AppKit
import SwiftUI
import Observation

/// Platform policy for macOS document-window tabs (standard since 2.1).
@MainActor
enum MacDocumentTabPolicy {
    static let tabbingIdentifier = "NeonVisionEditor.NativeDocuments"
    static let projectSidebarVisibilityPreferenceKey = "NativeDocumentTabsProjectSidebarVisible"
    static let projectSidebarWidthPreferenceKey = "NativeDocumentTabsProjectSidebarWidth"
    static let projectSidebarModePreferenceKey = "NativeDocumentTabsProjectSidebarMode"

    static func makeWindowModel(isSafeMode: Bool = false) -> EditorViewModel {
        EditorViewModel(isSafeModeRecoveryWindow: isSafeMode)
    }

    static func draftSnapshotKey(for model: EditorViewModel) -> String {
        model.isSafeModeRecoveryWindow
            ? "UnsavedDraftSnapshotV2.NativeDocumentWindows.SafeMode"
            : "UnsavedDraftSnapshotV2.NativeDocumentWindows"
    }

    static func windowTitle(for model: EditorViewModel) -> String {
        model.selectedTab?.name ?? "Untitled"
    }

    static func configureWindowChrome(_ window: NSWindow) {
        // AppKit is the only chrome owner, for the SwiftUI-created primary
        // window and every AppKit-created tab. Do not add scene-only SwiftUI
        // toolbar/container backgrounds: those affect only the first tab.
        if window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = false }
        if window.backgroundColor != .windowBackgroundColor { window.backgroundColor = .windowBackgroundColor }
        if window.toolbarStyle != .unified { window.toolbarStyle = .unified }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
    }

    static func applyDocumentMetadata(title: String, url: URL?, edited: Bool, to window: NSWindow) {
        // Native setters notify the tab group and can synchronize WindowServer
        // transactions even when the metadata is unchanged.
        if window.tab.title != title { window.tab.title = title }
        if window.title != title { window.title = title }
        if window.representedURL != url { window.representedURL = url }
        if window.isDocumentEdited != edited { window.isDocumentEdited = edited }
    }
}

/// Native tabs group windows, not editor buffers. A destination model is created
/// before opening a file so asynchronous loads/saves never change document owner.
@MainActor
final class MacDocumentWindowTabs {
    static let shared = MacDocumentWindowTabs()

    private struct Entry {
        weak var model: EditorViewModel?
        weak var window: NSWindow?
        let synchronizeProjectFolder: (URL?) -> Void
        let openWindow: (UUID) -> Void
        let persistDrafts: () -> Void
        /// False for a background tab's shell, which has no session state of
        /// its own until its editor registers.
        var ownsPersistence = true
    }
    private struct Pending {
        let model: EditorViewModel
        weak var parent: NSWindow?
    }
    private final class Parent {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var pending: [UUID: Pending] = [:]
    private var parents: [ObjectIdentifier: Parent] = [:]
    private var order: [ObjectIdentifier] = []
    private var projectPreviewSessions: [ObjectIdentifier: MarkdownProjectPreviewSession] = [:]
    private var presentationStates: [ObjectIdentifier: EditorDocumentPresentationState] = [:]
    private var editorSurfaceGroups: [ObjectIdentifier: NativeEditorSurfaceGroup] = [:]
    private var toolbarCoordinators: [ObjectIdentifier: MacDocumentToolbar.ToolbarCoordinator] = [:]
    private var surfaceDeactivationActions: [ObjectIdentifier: () -> Void] = [:]
    private var metadataObservationGenerations: [ObjectIdentifier: Int] = [:]
    private var windowControllers: [ObjectIdentifier: NSWindowController] = [:]
    // A closed document's views can still receive a final SwiftUI update.
    // Weak, so a later model reusing the same address is not affected.
    private let closedModels = NSHashTable<EditorViewModel>.weakObjects()
    private var sceneOpenRequests: [(id: UUID, open: (UUID) -> Void)] = []
    private var sceneOpenScheduled = false
    private let scheduleSceneOpen: (@escaping @MainActor @Sendable () -> Void) -> Void
    private var selectionToReveal: ObjectIdentifier?
    private weak var activeNativeWindow: NSWindow?
    private var isPresentingPendingWindow = false
    private var tabMouseMonitor: NativeTabMouseMonitor?
    private(set) var isTerminating = false

    init(scheduleSceneOpen: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void = { action in
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { action() }
        }
    }) {
        self.scheduleSceneOpen = scheduleSceneOpen
    }

    var models: [EditorViewModel] {
        var seen = Set<ObjectIdentifier>()
        let byID = Dictionary((entries.values.compactMap(\.model) + pending.values.map(\.model))
            .map { (ObjectIdentifier($0), $0) }, uniquingKeysWith: { first, _ in first })
        let byWindow = Dictionary(entries.values.compactMap { entry -> (ObjectIdentifier, EditorViewModel)? in
            guard let window = entry.window, let model = entry.model else { return nil }
            return (ObjectIdentifier(window), model)
        }, uniquingKeysWith: { first, _ in first })
        var result: [EditorViewModel] = []
        for id in order {
            guard let model = byID[id], !seen.contains(id) else { continue }
            if let window = entries[id]?.window {
                for tabbedWindow in window.tabbedWindows ?? [window] {
                    if let member = byWindow[ObjectIdentifier(tabbedWindow)],
                       seen.insert(ObjectIdentifier(member)).inserted {
                        result.append(member)
                    }
                }
            }
            if seen.insert(id).inserted { result.append(model) }
        }
        return result
    }

    var selectedModel: EditorViewModel? {
        guard let id = selectionToReveal else { return nil }
        return entries[id]?.model ?? pending.values.first { ObjectIdentifier($0.model) == id }?.model
    }

    /// Every owner persists the shared session; its selected document must
    /// come from the selected owner, not whichever window persisted last.
    var sessionSelectionModel: EditorViewModel? {
        selectedModel
            ?? activeNativeWindow.flatMap { window in entries.values.first { $0.window === window }?.model }
            ?? models.first
    }

    /// Re-persist the session from a remaining owner, e.g. after a tab closes.
    func persistSessionFromSelectedOwner() {
        guard !isTerminating else { return }
        persistingOwner()?.persistDrafts()
    }

    /// The selected owner's entry, or any registered editor when the selected
    /// tab is still an unmounted shell.
    private func persistingOwner() -> Entry? {
        if let model = sessionSelectionModel, let entry = entries[ObjectIdentifier(model)], entry.ownsPersistence {
            return entry
        }
        return models.lazy.compactMap { self.entries[ObjectIdentifier($0)] }.first(where: \.ownsPersistence)
    }

    func presentationState(for model: EditorViewModel) -> EditorDocumentPresentationState {
        let identity = ObjectIdentifier(model)
        if let state = presentationStates[identity] { return state }
        let state = EditorDocumentPresentationState()
        guard !closedModels.contains(model) else { return state }
        presentationStates[identity] = state
        return state
    }

    func editorSurfaceGroup(for model: EditorViewModel, window _: NSWindow) -> NativeEditorSurfaceGroup {
        let identity = ObjectIdentifier(model)
        // Native tabs select already-backed windows. Moving one complete
        // SwiftUI graph between them forces synchronous focus traversal and
        // document-environment updates on every selection. Mount each visited
        // document once; unopened background tabs still retain only their shell.
        if let existing = editorSurfaceGroups[identity] { return existing }
        let group = NativeEditorSurfaceGroup()
        guard !closedModels.contains(model) else { return group }
        editorSurfaceGroups[identity] = group
        return group
    }

    /// Window-level SwiftUI presentation belongs on the content root, not in a
    /// nested hosting view below the temporary loading surface. The controller
    /// retains document lifetime/close protection independently of that root.
    @discardableResult
    func installRootEditorHost(_ host: NSView, for model: EditorViewModel, in window: NSWindow) -> Bool {
        guard windowControllers[ObjectIdentifier(model)]?.window === window else { return false }
        if window.contentView !== host { window.contentView = host }
        return true
    }

    func isForeignDocumentWindow(_ window: NSWindow, for model: EditorViewModel) -> Bool {
        entries.values.contains { $0.window === window && $0.model !== model }
    }

    func bindToolbar(_ configuration: MacDocumentToolbar, to window: NSWindow) {
        guard !closedModels.contains(configuration.owner),
              !isForeignDocumentWindow(window, for: configuration.owner) else { return }
        let identity = ObjectIdentifier(configuration.owner)
        let coordinator = toolbarCoordinators[identity] ?? MacDocumentToolbar.ToolbarCoordinator(configuration)
        toolbarCoordinators[identity] = coordinator
        coordinator.configuration = configuration
        coordinator.bind(window)
    }

    func registerSurfaceDeactivation(for model: EditorViewModel, action: @escaping () -> Void) {
        surfaceDeactivationActions[ObjectIdentifier(model)] = action
    }

    func deactivateSurface(for model: EditorViewModel) {
        surfaceDeactivationActions[ObjectIdentifier(model)]?()
    }

    func refreshWindowMetadata(for model: EditorViewModel) {
        guard let window = entries[ObjectIdentifier(model)]?.window else { return }
        MacDocumentTabPolicy.applyDocumentMetadata(title: MacDocumentTabPolicy.windowTitle(for: model),
            url: model.selectedTab?.fileURL, edited: model.tabs.contains(where: \.isDirty), to: window)
    }

    private func observeWindowMetadata(for model: EditorViewModel, window: NSWindow) {
        let identity = ObjectIdentifier(model)
        let generation = (metadataObservationGenerations[identity] ?? 0) &+ 1
        metadataObservationGenerations[identity] = generation
        let metadata = withObservationTracking {
            (MacDocumentTabPolicy.windowTitle(for: model), model.selectedTab?.fileURL,
             model.tabs.contains(where: \.isDirty))
        } onChange: { [weak self, weak model, weak window] in
            Task { @MainActor [weak self, weak model, weak window] in
                guard let self, let model, let window,
                      self.metadataObservationGenerations[identity] == generation,
                      self.entries[identity]?.window === window else { return }
                self.observeWindowMetadata(for: model, window: window)
            }
        }
        MacDocumentTabPolicy.applyDocumentMetadata(title: metadata.0, url: metadata.1, edited: metadata.2, to: window)
    }

    func projectPreviewSession(for model: EditorViewModel) -> MarkdownProjectPreviewSession {
        let identity = ObjectIdentifier(model)
        if let session = projectPreviewSessions[identity] { return session }
        let session = MarkdownProjectPreviewSession()
        guard !closedModels.contains(model) else { return session }
        projectPreviewSessions[identity] = session
        return session
    }

    /// Construct a native document window directly. Re-entering SwiftUI's scene
    /// registry for every file rebuilds the scene and orders/layouts its toolbar
    /// before the pending document has even attached.
    @discardableResult
    func presentPendingWindow(for id: UUID, makeContent: @escaping () -> NSView) -> NSWindow? {
        guard !isTerminating, let item = pending[id] else { return nil }
        return EditorPerformanceMonitor.shared.measureNativeWindowCreation {
            isPresentingPendingWindow = true
            defer { isPresentingPendingWindow = false }
            let identity = ObjectIdentifier(item.model)
            let previousSelection = item.parent?.tabGroup?.selectedWindow ?? item.parent
            let shouldSelect = selectionToReveal == identity && previousSelection?.attachedSheet == nil
            let size = item.parent?.contentLayoutRect.size ?? NSSize(width: 1400, height: 900)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.minSize = NSSize(width: 600, height: 400)
            MacDocumentTabPolicy.configureWindowChrome(window)
            MacDocumentToolbar.prepare(window)
            window.title = MacDocumentTabPolicy.windowTitle(for: item.model)
            window.isDocumentEdited = item.model.tabs.contains(where: \.isDirty)
            window.tabbingIdentifier = MacDocumentTabPolicy.tabbingIdentifier
            window.tabbingMode = .preferred
            // Publish the lightweight tab before constructing its editor. A
            // restored background file must not instantiate WebKit, project
            // indexing, toolbars and editor layout before it is selected.
            let parentEntry = entries.values.first(where: { $0.window === item.parent })
            if let parentEntry {
                entries[identity] = Entry(model: item.model, window: window,
                    synchronizeProjectFolder: { _ in }, openWindow: parentEntry.openWindow,
                    persistDrafts: {}, ownsPersistence: false)
                observeWindowMetadata(for: item.model, window: window)
            }
            installTabMouseMonitorIfNeeded()
            let content = NativeDocumentContentHost(makeContent: makeContent,
                model: item.model, store: self,
                onClose: { [weak self, weak model = item.model] in
                    guard let model else { return }
                    self?.unregister(model)
                    // The parent may have closed. Persist from a live owner
                    // after AppKit selects the next tab, as editor owners do.
                    DispatchQueue.main.async { self?.persistSessionFromSelectedOwner() }
                })
            windowControllers[identity] = NativeDocumentWindowController(window: window, lifetime: content)
            // AppKit owns geometry. A hosting view keeps SwiftUI toolbar bridging
            // without a content controller applying its preferred window size.
            content.frame = NSRect(origin: .zero, size: window.contentView?.bounds.size ?? size)
            content.autoresizingMask = [.width, .height]
            window.contentView = content
            EditorPerformanceMonitor.shared.measureNativeWindowStage("native_tab_attach") {
                attachPendingWindow(window, for: id)
                let selection = shouldSelect ? window : previousSelection
                if window.tabGroup?.selectedWindow !== selection {
                    window.tabGroup?.selectedWindow = selection
                }
            }
            // AppKit attachment can adopt the new tab's minimum frame. Apply
            // the source geometry at the end of attachment, before first show.
            EditorPerformanceMonitor.shared.measureNativeWindowStage("native_group_frame") {
                if let parent = item.parent { window.setFrame(parent.frame, display: false) }
            }
            EditorPerformanceMonitor.shared.measureNativeWindowStage("native_window_order") {
                if shouldSelect, !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            }
            content.finishAttachment()
            return window
        }
    }

    func takePendingModel(for id: UUID) -> EditorViewModel? {
        guard let item = pending[id] else { return nil }
        if let parent = item.parent { parents[ObjectIdentifier(item.model)] = Parent(parent) }
        return item.model
    }

    /// Attach at the scene root, before AppKit presents the window. Waiting for
    /// the editor's registration allows SwiftUI to display a standalone window.
    func attachPendingWindow(_ window: NSWindow, for id: UUID) {
        guard let item = pending[id], let parent = item.parent, parent !== window else { return }
        window.tabbingIdentifier = MacDocumentTabPolicy.tabbingIdentifier
        window.tabbingMode = .preferred
        if window.tabGroup !== parent.tabGroup || window.tabGroup == nil {
            if let group = parent.tabGroup, let index = group.windows.firstIndex(where: { $0 === parent }) {
                // Insert restored/background tabs without selecting and ordering
                // each window. Only the requested final selection is presented.
                group.insertWindow(window, at: index + 1)
            } else {
                parent.addTabbedWindow(window, ordered: .above)
            }
        }
        parents.removeValue(forKey: ObjectIdentifier(item.model))
    }

    func noteBecameKey(_ model: EditorViewModel) {
        activeNativeWindow = entries[ObjectIdentifier(model)]?.window
        // Actual user selection supersedes a saved startup selection. Passive
        // creation of restored tabs is not a selection request.
        if !isPresentingPendingWindow { selectionToReveal = ObjectIdentifier(model) }
        updateTabAppearance(for: model)
    }

    /// SwiftUI's value-based WindowGroup creates a nil-value scene when AppKit
    /// invokes `newWindowForTab:` from its native tab-bar plus button. Assign a
    /// pending owner to that already-created scene so it joins the source group
    /// instead of leaving an empty standalone window behind.
    func prepareNativeTabScene() -> UUID? {
        guard let parent = activeNativeWindow,
              entries.values.contains(where: { $0.window === parent }) else { return nil }
        let source = entries.values.first { $0.window === parent }?.model
        let model = MacDocumentTabPolicy.makeWindowModel(isSafeMode: source?.isSafeModeRecoveryWindow == true)
        if let source { projectPreviewSessions[ObjectIdentifier(model)] = projectPreviewSession(for: source) }
        let id = UUID()
        pending[id] = Pending(model: model, parent: parent)
        order.append(ObjectIdentifier(model))
        selectionToReveal = ObjectIdentifier(model)
        return id
    }

    func register(_ model: EditorViewModel, window: NSWindow,
                  synchronizeProjectFolder: @escaping (URL?) -> Void = { _ in },
                  persistDrafts: @escaping () -> Void = {}, openWindow: @escaping (UUID) -> Void) {
        let identity = ObjectIdentifier(model)
        let wasPending = pending.values.contains { $0.model === model }
        closedModels.remove(model)
        if !order.contains(identity) { order.append(identity) }
        pending = pending.filter { $0.value.model !== model }
        entries[ObjectIdentifier(model)] = Entry(model: model, window: window,
                                                synchronizeProjectFolder: synchronizeProjectFolder,
                                                openWindow: openWindow, persistDrafts: persistDrafts)
        observeWindowMetadata(for: model, window: window)
        installTabMouseMonitorIfNeeded()
        if window.isKeyWindow { activeNativeWindow = window }
        window.tabbingIdentifier = MacDocumentTabPolicy.tabbingIdentifier
        window.tabbingMode = .preferred
        model.nativeDocumentDestination = { [weak self, weak model] url, reuseBlank in
            guard let self, let model else { return nil }
            return self.destination(from: model, url: url, reuseBlank: reuseBlank)
        }
        model.nativeFocusFile = { [weak self, weak model] url in
            guard let self, let model else { return false }
            return self.focusFile(url, excluding: model)
        }
        model.nativeRevealWindow = { [weak self, weak model] in
            guard let model else { return }
            self?.reveal(model)
        }
        if let parent = parents.removeValue(forKey: identity)?.window, parent !== window {
            if window.tabGroup !== parent.tabGroup || window.tabGroup == nil {
                parent.addTabbedWindow(window, ordered: .above)
            }
        }
        if wasPending, windowControllers[identity] == nil, !isPresentingPendingWindow,
           pending.isEmpty, let selectionToReveal,
           let selectedWindow = entries[selectionToReveal]?.window {
            selectedWindow.makeKeyAndOrderFront(nil)
        }
        updateTabAppearance(for: model)
    }

    func unregister(_ model: EditorViewModel) {
        guard !isTerminating else { return }
        closedModels.add(model)
        // Stops the closed document's preview refresh, secondary tasks and
        // shared-import observer, which would otherwise outlive the tab.
        surfaceDeactivationActions.removeValue(forKey: ObjectIdentifier(model))?()
        presentationStates.removeValue(forKey: ObjectIdentifier(model))
        editorSurfaceGroups.removeValue(forKey: ObjectIdentifier(model))
        toolbarCoordinators.removeValue(forKey: ObjectIdentifier(model))?.release()
        metadataObservationGenerations.removeValue(forKey: ObjectIdentifier(model))
        if let session = projectPreviewSessions.removeValue(forKey: ObjectIdentifier(model)),
           !projectPreviewSessions.values.contains(where: { $0 === session }) {
            session.model.stopLoadingWork()
            session.nativePane.release()
        }
        entries.removeValue(forKey: ObjectIdentifier(model))
        if entries.isEmpty { tabMouseMonitor = nil }
        pending = pending.filter { $0.value.model !== model }
        windowControllers.removeValue(forKey: ObjectIdentifier(model))
        parents.removeValue(forKey: ObjectIdentifier(model))
        order.removeAll { $0 == ObjectIdentifier(model) }
        model.nativeDocumentDestination = nil
        model.nativeFocusFile = nil
        model.nativeRevealWindow = nil
    }

    func beginTermination() {
        guard !isTerminating else { return }
        persistingOwner()?.persistDrafts()
        isTerminating = true
        tabMouseMonitor = nil
        sceneOpenRequests.removeAll()
    }

    private func installTabMouseMonitorIfNeeded() {
        guard tabMouseMonitor == nil, !entries.isEmpty else { return }
        guard let token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleTabDoubleClick(event) == true }
            return handled ? nil : event
        }) else { return }
        tabMouseMonitor = NativeTabMouseMonitor(token)
    }

    /// A double-click's first click has already selected the native document.
    /// Use public accessibility roles rather than AppKit-private view classes
    /// or guessed titlebar geometry; toolbar controls and close buttons pass through.
    @discardableResult
    func handleTabDoubleClick(_ event: NSEvent) -> Bool {
        guard !isTerminating, event.type == .leftMouseDown, event.clickCount == 2,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              let window = event.window, window.attachedSheet == nil,
              entries.values.contains(where: { $0.window === window }) else { return false }
        let selected = window.tabGroup?.selectedWindow ?? window
        guard entries.values.contains(where: { $0.window === selected }) else { return false }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        guard let element = window.accessibilityHitTest(screenPoint) as? NSAccessibilityProtocol,
              element.accessibilitySubrole() == .tabButtonSubrole,
              (element.accessibilityValue() as? NSNumber)?.boolValue == true,
              let parent = element.accessibilityParent() as? NSAccessibilityProtocol,
              parent.accessibilityRole() == .tabGroup else { return false }
        // AppKit's window-level hit test can return the enclosing tab even
        // over its close button. Exclude the actual child control frames.
        let childButtons = (element.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol }
            .filter { $0.accessibilityRole() == .button }
        guard !childButtons.contains(where: { $0.accessibilityFrame().contains(screenPoint) }) else { return false }
        // Never close the model directly: performClose retains the owning
        // window's existing unsaved-change/save/cancel validation.
        selected.performClose(nil)
        return true
    }

    func models(inGroupOf source: EditorViewModel) -> [EditorViewModel] {
        guard let window = entries[ObjectIdentifier(source)]?.window else { return [source] }
        let byWindow = modelsByWindow()
        return (window.tabbedWindows ?? [window]).compactMap { byWindow[ObjectIdentifier($0)] }
    }

    private func modelsByWindow() -> [ObjectIdentifier: EditorViewModel] {
        Dictionary(entries.values.compactMap { entry in
            entry.window.flatMap { window in entry.model.map { (ObjectIdentifier(window), $0) } }
        }, uniquingKeysWith: { first, _ in first })
    }

    func synchronizeProjectFolder(_ folderURL: URL?, from source: EditorViewModel) {
        for model in models(inGroupOf: source) where model !== source {
            entries[ObjectIdentifier(model)]?.synchronizeProjectFolder(folderURL)
        }
    }

    /// AppKit orders out unselected tab windows but keeps their layer backing
    /// stores. Hidden content lets CoreAnimation release them; the selected
    /// window is revealed from the selection change, before it is displayed.
    func updateInactiveTabContent(around window: NSWindow) {
        guard let group = window.tabGroup, let selected = group.selectedWindow else {
            if window.contentView?.isHidden == true { window.contentView?.isHidden = false }
            return
        }
        // Every tab's host calls this on each selection change; keep it linear.
        let owned = modelsByWindow()
        for member in group.windows where owned[ObjectIdentifier(member)] != nil {
            let hidden = member !== selected
            if member.contentView?.isHidden != hidden { member.contentView?.isHidden = hidden }
        }
    }

    func updateTabAppearance(for model: EditorViewModel) {
        guard let window = entries[ObjectIdentifier(model)]?.window else { return }
        let selectedWindow = window.tabGroup?.selectedWindow ?? window
        for member in models(inGroupOf: model) {
            guard let memberWindow = entries[ObjectIdentifier(member)]?.window else { continue }
            let title = memberWindow === selectedWindow
                ? NSAttributedString(string: MacDocumentTabPolicy.windowTitle(for: member),
                                     attributes: [.foregroundColor: NSColor.controlAccentColor])
                : nil
            if memberWindow.tab.attributedTitle != title {
                memberWindow.tab.attributedTitle = title
            }
        }
    }

    private func scheduleNextSceneOpen() {
        guard !sceneOpenScheduled, !sceneOpenRequests.isEmpty, !isTerminating else { return }
        sceneOpenScheduled = true
        scheduleSceneOpen { [weak self] in
            guard let self else { return }
            self.sceneOpenScheduled = false
            guard !self.isTerminating, !self.sceneOpenRequests.isEmpty else { return }
            let request = self.sceneOpenRequests.removeFirst()
            if self.pending[request.id] != nil { request.open(request.id) }
            self.scheduleNextSceneOpen()
        }
    }

    private func destination(from source: EditorViewModel, url: URL?, reuseBlank: Bool) -> EditorViewModel? {
        guard let entry = entries[ObjectIdentifier(source)] else { return nil }
        if reuseBlank, source.canReuseNativeBlankDocument { return nil }
        let model = MacDocumentTabPolicy.makeWindowModel(isSafeMode: source.isSafeModeRecoveryWindow)
        projectPreviewSessions[ObjectIdentifier(model)] = projectPreviewSession(for: source)
        let id = UUID()
        pending[id] = Pending(model: model, parent: entry.window)
        order.append(ObjectIdentifier(model))
        selectionToReveal = ObjectIdentifier(model)
        // Routing also works before SwiftUI attaches the new scene.
        model.nativeDocumentDestination = { [weak self, weak model] url, reuseBlank in
            guard let self, let model else { return nil }
            return self.destination(from: model, url: url, reuseBlank: reuseBlank)
        }
        model.nativeRevealWindow = { [weak self, weak model] in
            guard let model else { return }
            self?.reveal(model)
        }
        // A restored owner is populated by the caller after this returns. Opening
        // its SwiftUI scene here would synchronously render a blank document and
        // re-enter startup while the rest of the session is only partly restored.
        sceneOpenRequests.append((id, entry.openWindow))
        scheduleNextSceneOpen()
        return model
    }

    private func focusFile(_ url: URL, excluding source: EditorViewModel) -> Bool {
        for model in models where model !== source && model.hasOpenFile(url: url) {
            // Unselected tabs are ordered out and never report the active
            // space; their group's selected window is the one on screen.
            let window = entries[ObjectIdentifier(model)]?.window
            if UserDefaults.standard.bool(forKey: "SettingsOpenFilesOnCurrentDesktop"),
               let window, !(window.tabGroup?.selectedWindow ?? window).isOnActiveSpace { continue }
            _ = model.focusTabIfOpen(for: url)
            reveal(model)
            return true
        }
        return false
    }

    private func reveal(_ model: EditorViewModel) {
        selectionToReveal = ObjectIdentifier(model)
        if let window = entries[ObjectIdentifier(model)]?.window {
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// Background tabs need only an AppKit shell until first selection. The same
/// close/save guard protects recovered drafts before the full editor is mounted.
// The token is immutable; NotificationCenter removal is thread-safe during ARC teardown.
nonisolated private final class NativeWindowNotification: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

nonisolated private final class NativeTabMouseMonitor: @unchecked Sendable {
    let token: Any
    init(_ token: Any) { self.token = token }
    deinit { NSEvent.removeMonitor(token) }
}

@MainActor
private final class NativeDocumentWindowController: NSWindowController {
    // Installing the editor root must not destroy its document's close delegate
    // or notification observations along with the loading surface.
    private let lifetime: NativeDocumentContentHost

    init(window: NSWindow, lifetime: NativeDocumentContentHost) {
        self.lifetime = lifetime
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class NativeDocumentContentHost: NSView {
    private var makeContent: (() -> NSView)?
    private var isAttaching = true
    private weak var model: EditorViewModel?
    private weak var store: MacDocumentWindowTabs?
    // The editor host replaces this view as the window's content root, which
    // clears `window`. The tab's selection observers must keep their window.
    private weak var documentWindow: NSWindow?
    private var isObservingInitialLoad = false
    private var loadingIndicator: NSProgressIndicator?
    private var selectionObservation: NSKeyValueObservation?
    private var groupObservation: NSKeyValueObservation?
    private var closeObserver: NativeWindowNotification?
    private var keyObserver: NativeWindowNotification?
    private let onClose: () -> Void
    private let closeGuard = WindowCloseConfirmationDelegate()

    init(makeContent: @escaping () -> NSView, model: EditorViewModel,
         store: MacDocumentWindowTabs, onClose: @escaping () -> Void) {
        self.makeContent = makeContent
        self.model = model
        self.store = store
        self.onClose = onClose
        super.init(frame: .zero)
        closeGuard.shouldConfirm = { [weak self] in
            self?.makeContent != nil &&
                (UserDefaults.standard.object(forKey: "SettingsConfirmCloseDirtyTab") as? Bool ?? true)
        }
        closeGuard.hasDirtyTabs = { [weak model] in model?.tabs.contains(where: \.isDirty) == true }
        closeGuard.saveAllDirtyTabsAsync = { [weak model] in
            guard let model else { return false }
            return await model.saveDirtyDocumentsBeforeWindowClose()
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The controller also owns this lifetime after the temporary loading
        // view leaves the hierarchy. Preserve observations until window close.
        guard let window, window !== documentWindow else { return }
        documentWindow = window
        selectionObservation = nil
        groupObservation = nil
        closeObserver = nil
        keyObserver = nil
        if makeContent != nil { window.delegate = closeGuard }
        closeObserver = NativeWindowNotification(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClose() }
        })
        keyObserver = NativeWindowNotification(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfSelected() }
        })
        groupObservation = window.observe(\.tabGroup, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.observeSelection() }
        }
        observeSelection()
    }

    private func observeSelection() {
        selectionObservation = documentWindow?.tabGroup?.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.installIfSelected() }
        }
        installIfSelected()
    }

    func installIfSelected() {
        if !isAttaching, let documentWindow { store?.updateInactiveTabContent(around: documentWindow) }
        guard !isAttaching, let window = documentWindow, let makeContent,
              window.tabGroup?.selectedWindow === window || window.isKeyWindow else { return }
        if let model, model.selectedTab?.isLoadingContent == true {
            if loadingIndicator == nil {
                let indicator = NSProgressIndicator()
                indicator.style = .spinning
                indicator.controlSize = .small
                indicator.setAccessibilityLabel(NSLocalizedString("Loading document…", comment: "Editor accessibility help during activation"))
                indicator.translatesAutoresizingMaskIntoConstraints = false
                addSubview(indicator)
                NSLayoutConstraint.activate([
                    indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
                    indicator.centerYAnchor.constraint(equalTo: centerYAnchor)
                ])
                indicator.startAnimation(nil)
                loadingIndicator = indicator
            }
            guard !isObservingInitialLoad else { return }
            isObservingInitialLoad = true
            withObservationTracking {
                _ = model.selectedTab?.isLoadingContent
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isObservingInitialLoad = false
                    self.installIfSelected()
                }
            }
            return
        }
        self.makeContent = nil
        loadingIndicator?.stopAnimation(nil)
        loadingIndicator?.removeFromSuperview()
        loadingIndicator = nil
        let content = EditorPerformanceMonitor.shared.measureNativeWindowStage("native_content_create", makeContent)
        EditorPerformanceMonitor.shared.measureNativeWindowStage("native_content_size") {
            content.frame = bounds
            content.autoresizingMask = [.width, .height]
        }
        EditorPerformanceMonitor.shared.measureNativeWindowStage("native_content_attach") {
            if let editor = content as? NativeEditorSurfaceView,
               editor.installAsWindowRoot(in: window) {
                return
            }
            addSubview(content)
        }
        // AppKit's display cycle lays out the newly attached host. Forcing it
        // here also lays out transient onAppear/preference states before their
        // queued updates can coalesce, including expensive secondary panes.
    }

    func finishAttachment() {
        isAttaching = false
        installIfSelected()
    }

}

/// A zero-size scene-root attachment, independent of expensive editor startup.
/// `viewWillMove` runs before the hosting window orders its content on screen.
@MainActor
struct NativeDocumentTabAttachment: NSViewRepresentable {
    let windowID: UUID
    var store: MacDocumentWindowTabs = .shared

    final class AttachmentView: NSView {
        var attach: ((NSWindow) -> Void)?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let newWindow { attach?(newWindow) }
            super.viewWillMove(toWindow: newWindow)
        }
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView(frame: .zero)
        view.attach = { window in store.attachPendingWindow(window, for: windowID) }
        return view
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.attach = { window in store.attachPendingWindow(window, for: windowID) }
    }
}
#endif
