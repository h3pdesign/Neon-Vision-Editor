#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import Combine
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class MacDocumentWindowTabsTests: XCTestCase {
    private struct NativeSurfaceFixture: View {
        let model: EditorViewModel
        let support: SupportPurchaseManager
        let updates: AppUpdateManager
        @Environment(\.openWindow) private var openWindow
        @Environment(\.openSettings) private var openSettings
        var body: some View {
            NativeEditorSurface(configuration: NativeEditorSurfaceConfiguration(
                model: model, startupBehavior: .nativeDocument, safeModeMessage: nil,
                frameAutosaveName: nil, initialLayout: nil, support: support, updates: updates,
                showGrokError: .constant(false), grokErrorMessage: .constant(""),
                actions: NativeEditorWindowActions(openWindow: openWindow, openSettings: openSettings)))
        }
    }

    func testNativeTabSelectionKeepsEachEditorAttachedAndPreservesInactiveCloseProtection() async throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: SettingsPreferenceKey.markdownPreviewDefaultMode)
        defaults.set("edit", forKey: SettingsPreferenceKey.markdownPreviewDefaultMode)
        defer {
            if let previousMode { defaults.set(previousMode, forKey: SettingsPreferenceKey.markdownPreviewDefaultMode) }
            else { defaults.removeObject(forKey: SettingsPreferenceKey.markdownPreviewDefaultMode) }
        }
        let store = MacDocumentWindowTabs.shared
        let first = MacDocumentTabPolicy.makeWindowModel()
        let second = MacDocumentTabPolicy.makeWindowModel()
        first.renameTab(tabID: try XCTUnwrap(first.selectedTabID), newName: "First.swift")
        second.renameTab(tabID: try XCTUnwrap(second.selectedTabID), newName: "Second.md")
        first.updateTabContent(tabID: try XCTUnwrap(first.selectedTabID), content: "let first = 17")
        second.updateTabContent(tabID: try XCTUnwrap(second.selectedTabID), content: "# Second")
        let firstWindow = window("First.swift")
        let secondWindow = window("Second.md")
        let support = SupportPurchaseManager(loadProducts: { [] }, canMakePayments: { false })
        let updates = AppUpdateManager(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        updates.setAutoCheckEnabled(false)
        defer { store.unregister(first); store.unregister(second); firstWindow.close(); secondWindow.close() }
        store.register(first, window: firstWindow) { _ in }
        store.register(second, window: secondWindow) { _ in }
        firstWindow.addTabbedWindow(secondWindow, ordered: .above)
        for (owner, window) in [(first, firstWindow), (second, secondWindow)] {
            let root = NSHostingView(rootView: NativeSurfaceFixture(model: owner, support: support, updates: updates))
            root.sceneBridgingOptions = owner === first ? .all : []
            window.contentView = root
        }
        firstWindow.tabGroup?.selectedWindow = firstWindow
        firstWindow.makeKeyAndOrderFront(nil)
        for _ in 0..<20 { await Task.yield(); firstWindow.displayIfNeeded() }
        let group = store.editorSurfaceGroup(for: first, window: firstWindow)
        let host = try XCTUnwrap(group.hostedView)
        let firstToolbar = try XCTUnwrap(firstWindow.toolbar)
        secondWindow.tabGroup?.selectedWindow = secondWindow
        secondWindow.makeKeyAndOrderFront(nil)
        for _ in 0..<20 { await Task.yield(); secondWindow.displayIfNeeded() }
        let secondGroup = store.editorSurfaceGroup(for: second, window: secondWindow)
        let secondHost = try XCTUnwrap(secondGroup.hostedView)
        let secondToolbar = try XCTUnwrap(secondWindow.toolbar)
        XCTAssertFalse(group === secondGroup, "Selection cannot reparent the full editor graph")
        XCTAssertTrue(group.hostedView === host)
        XCTAssertTrue(host.window === firstWindow)
        XCTAssertTrue(secondHost.window === secondWindow)
        let firstCanvas = try XCTUnwrap(nativeEditorCanvas(in: host))
        let secondCanvas = try XCTUnwrap(nativeEditorCanvas(in: secondHost))
        firstCanvas.doCommand(by: #selector(NSResponder.moveToBeginningOfDocument(_:)))
        firstCanvas.doCommand(by: #selector(NSResponder.moveRight(_:)))
        secondCanvas.doCommand(by: #selector(NSResponder.moveToBeginningOfDocument(_:)))
        secondCanvas.doCommand(by: #selector(NSResponder.moveRight(_:)))
        secondCanvas.doCommand(by: #selector(NSResponder.moveRight(_:)))
        for _ in 0..<10 { await Task.yield() }
        for _ in 0..<3 {
            firstWindow.tabGroup?.selectedWindow = firstWindow
            firstWindow.makeKeyAndOrderFront(nil)
            firstWindow.displayIfNeeded()
            secondWindow.tabGroup?.selectedWindow = secondWindow
            secondWindow.makeKeyAndOrderFront(nil)
            secondWindow.displayIfNeeded()
        }
        XCTAssertTrue(nativeEditorCanvas(in: host) === firstCanvas)
        XCTAssertTrue(nativeEditorCanvas(in: secondHost) === secondCanvas)
        XCTAssertEqual(firstCanvas.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertEqual(secondCanvas.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertTrue(host.window === firstWindow)
        XCTAssertTrue(secondHost.window === secondWindow)
        XCTAssertEqual(firstWindow.tab.title, "First.swift")
        XCTAssertEqual(secondWindow.tab.title, "Second.md")
        XCTAssertEqual(firstWindow.title, "First.swift")
        XCTAssertEqual(secondWindow.title, "Second.md")
        XCTAssertTrue(firstWindow.toolbar === firstToolbar, "Window presentation bridging must not replace native controls")
        XCTAssertTrue(secondWindow.toolbar === secondToolbar)
        XCTAssertTrue((firstWindow.delegate as? WindowCloseConfirmationDelegate)?.hasDirtyTabs?() == true)
        XCTAssertEqual(first.selectedTab?.document.string(), "let first = 17")
        XCTAssertEqual(second.selectedTab?.document.string(), "# Second")
    }

    /// The primary window is created by a SwiftUI scene; later tabs install
    /// their editor host as the AppKit content root. Both must give the editor
    /// the full-size content area and the same toolbar safe-area inset.
    func testSceneHostedEditorSurfaceUsesTheSameFullWindowGeometryAsAppKitTabs() async throws {
        let owner = MacDocumentTabPolicy.makeWindowModel()
        let candidate = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                                 styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        candidate.isReleasedWhenClosed = false
        candidate.tabbingMode = .disallowed
        MacDocumentTabPolicy.configureWindowChrome(candidate)
        MacDocumentToolbar.prepare(candidate)
        let support = SupportPurchaseManager(loadProducts: { [] }, canMakePayments: { false })
        let updates = AppUpdateManager(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        updates.setAutoCheckEnabled(false)
        defer { MacDocumentWindowTabs.shared.unregister(owner); candidate.close() }
        let root = NSHostingView(rootView: NativeSurfaceFixture(model: owner, support: support, updates: updates))
        candidate.contentView = root
        candidate.makeKeyAndOrderFront(nil)
        for _ in 0..<20 { await Task.yield(); candidate.displayIfNeeded() }
        let titlebarInset = root.bounds.height - candidate.contentLayoutRect.height
        XCTAssertGreaterThan(titlebarInset, 0, "Fixture must have a titlebar region to cover")
        let surface = try XCTUnwrap(firstSubview(of: NativeEditorSurfaceView.self, in: root))
        XCTAssertEqual(surface.convert(surface.bounds, to: nil), root.convert(root.bounds, to: nil),
                       "Scene-hosted editor surface must span the full window like a root-installed tab")
        let host = try XCTUnwrap(MacDocumentWindowTabs.shared.editorSurfaceGroup(for: owner, window: candidate).hostedView)
        XCTAssertEqual(host.safeAreaInsets.top, titlebarInset, accuracy: 0.5,
                       "The editor must derive the toolbar inset from AppKit, as root-installed tabs do")
    }

    /// A new native tab must accept typing and paste without a click: its
    /// editor becomes the window's first responder when it is attached.
    func testNewNativeDocumentEditorReceivesKeyboardFocus() async throws {
        let owner = MacDocumentTabPolicy.makeWindowModel()
        let candidate = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                                 styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        candidate.isReleasedWhenClosed = false
        candidate.tabbingMode = .disallowed
        let support = SupportPurchaseManager(loadProducts: { [] }, canMakePayments: { false })
        let updates = AppUpdateManager(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        updates.setAutoCheckEnabled(false)
        defer { MacDocumentWindowTabs.shared.unregister(owner); candidate.close() }
        candidate.contentView = NSHostingView(rootView: NativeSurfaceFixture(model: owner, support: support, updates: updates))
        candidate.makeKeyAndOrderFront(nil)
        for _ in 0..<20 { await Task.yield(); candidate.displayIfNeeded() }
        let host = try XCTUnwrap(MacDocumentWindowTabs.shared.editorSurfaceGroup(for: owner, window: candidate).hostedView)
        let canvas = try XCTUnwrap(nativeEditorCanvas(in: host))
        XCTAssertTrue(candidate.firstResponder === canvas, "Paste into a new tab must not require a click first")
    }

    /// AppKit tabs replace their loading root with the editor host. Selecting
    /// them again must still reveal their content, also once the first window
    /// of the group (the only scene-hosted surface) has closed.
    func testRootInstalledTabsAreRevealedWhenReselectedAfterFirstWindowCloses() throws {
        // The app's store: content hosts must report to the store that made them.
        let store = MacDocumentWindowTabs.shared
        let source = MacDocumentTabPolicy.makeWindowModel()
        let first = window("First")
        var created: [(EditorViewModel, NSWindow)] = []
        defer {
            for (owner, candidate) in created { store.unregister(owner); candidate.close() }
            store.unregister(source); first.close()
        }
        first.makeKeyAndOrderFront(nil)
        store.register(source, window: first) { id in
            guard let owner = store.takePendingModel(for: id),
                  let candidate = store.presentPendingWindow(for: id, makeContent: { NSView() })
            else { return XCTFail("Missing new tab") }
            created.append((owner, candidate))
        }
        source.addNewTab()
        source.addNewTab()
        // The shared store opens queued scenes from the main run loop.
        for _ in 0..<10 where created.count < 2 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(created.count, 2)
        for (owner, candidate) in created {
            candidate.tabGroup?.selectedWindow = candidate
            XCTAssertTrue(store.installRootEditorHost(NSView(), for: owner, in: candidate))
        }
        store.unregister(source)
        first.close()
        let (_, firstTab) = created[0], (_, secondTab) = created[1]
        for selected in [firstTab, secondTab, firstTab] {
            selected.tabGroup?.selectedWindow = selected
            XCTAssertEqual(selected.contentView?.isHidden, false, "\(selected.title) must be visible when selected")
            let other = selected === firstTab ? secondTab : firstTab
            XCTAssertEqual(other.contentView?.isHidden, true, "Inactive tabs still release their backing")
        }
    }

    private func firstSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let match = root as? T { return match }
        return root.subviews.lazy.compactMap { self.firstSubview(of: type, in: $0) }.first
    }

    /// The shared session's selection follows the selected owner, and a closed
    /// owner hands persistence to a remaining one instead of keeping its file.
    func testSessionSelectionFollowsSelectedOwnerAndSurvivesClose() throws {
        let store = immediateStore()
        let first = MacDocumentTabPolicy.makeWindowModel()
        let second = MacDocumentTabPolicy.makeWindowModel()
        let firstWindow = window("First.swift")
        let secondWindow = window("Second.swift")
        defer { store.unregister(first); store.unregister(second); firstWindow.close(); secondWindow.close() }
        var persisted: [String] = []
        store.register(first, window: firstWindow, persistDrafts: { persisted.append("first") }) { _ in }
        store.register(second, window: secondWindow, persistDrafts: { persisted.append("second") }) { _ in }

        store.noteBecameKey(second)
        XCTAssertTrue(store.sessionSelectionModel === second, "A background owner must not supply the selection")
        store.persistSessionFromSelectedOwner()
        XCTAssertEqual(persisted, ["second"])

        store.unregister(second)
        XCTAssertTrue(store.sessionSelectionModel === first, "A closed owner must not remain the session selection")
        store.persistSessionFromSelectedOwner()
        XCTAssertEqual(persisted, ["second", "first"])
    }

    func testUnmountedTabShellNeverPersistsThroughItsClosedParent() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel()
        let other = MacDocumentTabPolicy.makeWindowModel()
        let sourceWindow = window("Shell parent")
        let otherWindow = window("Live owner")
        var child: EditorViewModel?
        var childWindow: NSWindow?
        var persisted: [String] = []
        store.register(source, window: sourceWindow, persistDrafts: { persisted.append("source") }) { id in
            child = store.takePendingModel(for: id)
            childWindow = store.presentPendingWindow(for: id) { NSView() }
        }
        store.register(other, window: otherWindow, persistDrafts: { persisted.append("other") }) { _ in }
        defer {
            if let child { store.unregister(child) }
            store.unregister(other)
            childWindow?.close(); sourceWindow.close(); otherWindow.close()
        }
        sourceWindow.makeKeyAndOrderFront(nil)
        source.addNewTab()
        let shell = try XCTUnwrap(child)
        XCTAssertTrue(store.sessionSelectionModel === shell)

        store.unregister(source)
        store.persistSessionFromSelectedOwner()
        XCTAssertEqual(persisted, ["other"], "A shell must not persist the closed parent's session")
        store.unregister(other)
        store.persistSessionFromSelectedOwner()
        XCTAssertEqual(persisted, ["other"], "Without a registered editor there is no session owner")
    }

    func testClosedOwnerStopsSurfaceWorkAndIsNotCachedAgain() {
        let store = immediateStore()
        let model = MacDocumentTabPolicy.makeWindowModel()
        let documentWindow = window("Closed owner")
        let lateToolbarWindow = window("Late toolbar update")
        defer { documentWindow.close(); lateToolbarWindow.close() }
        var deactivations = 0
        store.register(model, window: documentWindow) { _ in }
        store.registerSurfaceDeactivation(for: model) { deactivations += 1 }
        XCTAssertTrue(store.presentationState(for: model) === store.presentationState(for: model))

        store.unregister(model)
        store.unregister(model)
        XCTAssertEqual(deactivations, 1, "Closing must stop the document's surface work exactly once")
        // A final SwiftUI update of the closed document must not re-cache state.
        XCTAssertFalse(store.presentationState(for: model) === store.presentationState(for: model))
        XCTAssertFalse(store.editorSurfaceGroup(for: model, window: documentWindow)
            === store.editorSurfaceGroup(for: model, window: documentWindow))
        XCTAssertFalse(store.projectPreviewSession(for: model) === store.projectPreviewSession(for: model))
        store.bindToolbar(MacDocumentToolbar(owner: model, groups: [], isVisible: true, label: { $0 },
            control: { _ in AnyView(EmptyView()) }, overflow: { _ in AnyView(EmptyView()) }), to: lateToolbarWindow)
        XCTAssertNil(lateToolbarWindow.toolbar, "A closed document must not bind a new toolbar coordinator")
    }

    /// Each native tab's window owns one document, so Side by Side and Compare
    /// Open Tabs must find the other documents through the tab group.
    func testSideBySideFindsOtherDocumentsOnlyInTheSameTabGroup() throws {
        let store = immediateStore()
        let first = MacDocumentTabPolicy.makeWindowModel()
        let second = MacDocumentTabPolicy.makeWindowModel()
        let standalone = MacDocumentTabPolicy.makeWindowModel()
        let firstWindow = window("First.swift")
        let secondWindow = window("Second.swift")
        let standaloneWindow = window("Standalone.swift")
        defer {
            store.unregister(first); store.unregister(second); store.unregister(standalone)
            firstWindow.close(); secondWindow.close(); standaloneWindow.close()
        }
        store.register(first, window: firstWindow) { _ in }
        store.register(second, window: secondWindow) { _ in }
        store.register(standalone, window: standaloneWindow) { _ in }
        firstWindow.addTabbedWindow(secondWindow, ordered: .above)
        let firstID = try XCTUnwrap(first.selectedTabID)
        let secondID = try XCTUnwrap(second.selectedTabID)
        let standaloneID = try XCTUnwrap(standalone.selectedTabID)

        // The 2.1.0 candidates came from this window's model only.
        XCTAssertEqual(first.tabs.map(\.id), [firstID], "A native tab's model holds only its own document")
        XCTAssertEqual(store.openDocuments(inGroupOf: first).map(\.id), [firstID, secondID])
        XCTAssertTrue(store.owner(ofDocument: secondID, inGroupOf: first) === second)
        XCTAssertTrue(store.owner(ofDocument: firstID, inGroupOf: second) === first)
        XCTAssertNil(store.owner(ofDocument: standaloneID, inGroupOf: first),
                     "A separate window is not one of this window's tabs")

        secondWindow.moveTabToNewWindow(nil)
        XCTAssertNil(store.owner(ofDocument: secondID, inGroupOf: first), "A tab moved out leaves the group")
        firstWindow.addTabbedWindow(secondWindow, ordered: .above)
        XCTAssertTrue(store.owner(ofDocument: secondID, inGroupOf: first) === second)

        store.unregister(second)
        XCTAssertNil(store.owner(ofDocument: secondID, inGroupOf: first), "A closed tab's document is gone")
        XCTAssertEqual(store.openDocuments(inGroupOf: first).map(\.id), [firstID])
    }

    func testTabGroupMembershipChangesAreAnnounced() {
        let store = immediateStore()
        let model = MacDocumentTabPolicy.makeWindowModel()
        let documentWindow = window("Announced.swift")
        defer { documentWindow.close() }
        let registered = expectation(forNotification: .nativeDocumentTabGroupDidChange, object: nil)
        store.register(model, window: documentWindow) { _ in }
        wait(for: [registered], timeout: 2)
        let closed = expectation(forNotification: .nativeDocumentTabGroupDidChange, object: nil)
        store.unregister(model)
        wait(for: [closed], timeout: 2)
    }

    /// Save applies to the Side by Side pane being typed in, whose document
    /// another window owns.
    func testSaveWritesTheFocusedSideBySideDocumentThroughItsOwner() async throws {
        let store = immediateStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstFile = root.appendingPathComponent("First.txt")
        let secondFile = root.appendingPathComponent("Second.txt")
        try "first\n".write(to: firstFile, atomically: true, encoding: .utf8)
        try "second\n".write(to: secondFile, atomically: true, encoding: .utf8)
        let first = MacDocumentTabPolicy.makeWindowModel()
        let second = MacDocumentTabPolicy.makeWindowModel()
        // Opened before registration, so each file stays in its own model.
        XCTAssertTrue(first.openFile(url: firstFile))
        XCTAssertTrue(second.openFile(url: secondFile))
        let firstWindow = window("First.txt")
        let secondWindow = window("Second.txt")
        defer {
            store.unregister(first); store.unregister(second)
            firstWindow.close(); secondWindow.close()
            try? FileManager.default.removeItem(at: root)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while first.selectedTab?.isLoadingContent != false || second.selectedTab?.isLoadingContent != false,
              ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        store.register(first, window: firstWindow) { _ in }
        store.register(second, window: secondWindow) { _ in }
        firstWindow.addTabbedWindow(secondWindow, ordered: .above)
        let firstID = try XCTUnwrap(first.selectedTabID)
        let secondID = try XCTUnwrap(second.selectedTabID)
        XCTAssertTrue(second.applyTabContentEdit(tabID: secondID, range: NSRange(location: 0, length: 0), replacement: "edited "))

        XCTAssertFalse(store.saveFocusedSideBySideDocument(for: first, focusedDocumentID: nil))
        XCTAssertFalse(store.saveFocusedSideBySideDocument(for: first, focusedDocumentID: firstID),
                       "The window's own document is saved by the normal path")
        XCTAssertTrue(store.saveFocusedSideBySideDocument(for: first, focusedDocumentID: secondID))
        while (try? String(contentsOf: secondFile, encoding: .utf8)) != "edited second\n",
              ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(try String(contentsOf: secondFile, encoding: .utf8), "edited second\n")
        XCTAssertEqual(try String(contentsOf: firstFile, encoding: .utf8), "first\n")
        XCTAssertEqual(second.selectedTab?.isDirty, false)

        store.unregister(second)
        XCTAssertFalse(store.saveFocusedSideBySideDocument(for: first, focusedDocumentID: secondID),
                       "A closed tab's document is no longer a save target")
    }

    /// Unselected tabs hide their content so their layer backing can be
    /// released; selecting a tab, or leaving the group, reveals it again.
    func testOnlyTheSelectedNativeTabKeepsVisibleContent() throws {
        let store = immediateStore()
        let first = MacDocumentTabPolicy.makeWindowModel()
        let second = MacDocumentTabPolicy.makeWindowModel()
        let firstWindow = window("First.swift")
        let secondWindow = window("Second.swift")
        let foreign = window("Settings")
        defer {
            store.unregister(first); store.unregister(second)
            firstWindow.close(); secondWindow.close(); foreign.close()
        }
        store.register(first, window: firstWindow) { _ in }
        store.register(second, window: secondWindow) { _ in }
        firstWindow.addTabbedWindow(secondWindow, ordered: .above)
        firstWindow.addTabbedWindow(foreign, ordered: .above)
        let firstContent = NSView(), secondContent = NSView(), foreignContent = NSView()
        firstWindow.contentView = firstContent
        secondWindow.contentView = secondContent
        foreign.contentView = foreignContent

        firstWindow.tabGroup?.selectedWindow = firstWindow
        store.updateInactiveTabContent(around: firstWindow)
        XCTAssertFalse(firstContent.isHidden)
        XCTAssertTrue(secondContent.isHidden)
        XCTAssertFalse(foreignContent.isHidden, "Only registered document windows are managed")

        firstWindow.tabGroup?.selectedWindow = secondWindow
        store.updateInactiveTabContent(around: secondWindow)
        XCTAssertFalse(secondContent.isHidden, "The selected tab must be revealed before display")
        XCTAssertTrue(firstContent.isHidden)

        firstWindow.tabGroup?.removeWindow(firstWindow)
        store.updateInactiveTabContent(around: firstWindow)
        XCTAssertFalse(firstContent.isHidden, "A window leaving the group must not stay hidden")
    }

    func testWindowMetadataUpdatesWithoutAnInstalledEditorGraph() async throws {
        let store = immediateStore()
        let owner = MacDocumentTabPolicy.makeWindowModel()
        let candidate = window("Metadata owner")
        defer { store.unregister(owner); candidate.close() }
        store.register(owner, window: candidate) { _ in }
        owner.renameTab(tabID: try XCTUnwrap(owner.selectedTabID), newName: "Renamed.swift")
        owner.updateTabContent(tabID: try XCTUnwrap(owner.selectedTabID), content: "unsaved")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(candidate.title, "Renamed.swift")
        XCTAssertEqual(candidate.tab.title, "Renamed.swift")
        XCTAssertTrue(candidate.isDocumentEdited)
    }

    private final class PresentationCapture {
        var count: Binding<Int>?
        var optional: Binding<String?>?
        var capturedOwner: (() -> EditorViewModel)?
        var reference: PresentationReference?
    }

    private final class PresentationReference {}

    private struct PresentationProbe: View {
        @EditorDocumentModel var model
        @EditorDocumentState("count") var count = 0
        @EditorDocumentState("optional") var optional: String? = "initial"
        @EditorDocumentState("reference") var reference = PresentationReference()
        let capture: PresentationCapture
        var body: some View {
            let _ = { capture.count = $count; capture.optional = $optional
                capture.reference = reference
                capture.capturedOwner = { self.model } }()
            Text("\(count):\(optional ?? "nil")")
        }
    }

    func testReusedSurfaceRestoresDocumentStateAndKeepsOldBindingsWithTheirOwner() async throws {
        let store = immediateStore()
        let first = MacDocumentTabPolicy.makeWindowModel()
        let second = MacDocumentTabPolicy.makeWindowModel()
        let capture = PresentationCapture()
        func root(_ model: EditorViewModel) -> some View {
            PresentationProbe(capture: capture).environment(model)
                .environment(\.editorDocumentPresentation, store.presentationState(for: model))
        }
        let host = NSHostingView(rootView: root(first))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        let candidate = window("Reused presentation fixture")
        candidate.contentView = host
        candidate.makeKeyAndOrderFront(nil)
        defer { store.unregister(first); store.unregister(second); candidate.close() }
        host.layoutSubtreeIfNeeded()
        let firstBinding = try XCTUnwrap(capture.count)
        let firstOwner = try XCTUnwrap(capture.capturedOwner)
        let firstReference = try XCTUnwrap(capture.reference)
        firstBinding.wrappedValue = 17
        try XCTUnwrap(capture.optional).wrappedValue = nil
        host.rootView = root(second)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(capture.count?.wrappedValue, 0)
        XCTAssertEqual(capture.optional?.wrappedValue, "initial")
        XCTAssertTrue(capture.capturedOwner?() === second)
        XCTAssertFalse(capture.reference === firstReference, "Reference-valued defaults cannot be shared across owners")
        XCTAssertTrue(firstOwner() === first)
        firstBinding.wrappedValue = 29
        XCTAssertEqual(capture.count?.wrappedValue, 0, "A delayed callback cannot target the newly selected document")
        capture.count?.wrappedValue = 53
        host.rootView = root(first)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(capture.count?.wrappedValue, 29)
        XCTAssertTrue(capture.reference === firstReference)
        XCTAssertNil(capture.optional?.wrappedValue ?? nil, "An explicitly nil value cannot fall back to another value")
        XCTAssertEqual(store.presentationState(for: second).box(for: "count", initialValue: 0).value, 53)
    }

    func testDocumentPresentationStoreIsStableAndReleasedWhenItsOwnerCloses() {
        let store = immediateStore()
        let model = MacDocumentTabPolicy.makeWindowModel()
        weak var captured: EditorDocumentPresentationState?
        do {
            let state = store.presentationState(for: model)
            captured = state
            XCTAssertTrue(state === store.presentationState(for: model))
            state.box(for: "optional", initialValue: Optional("initial")).value = nil
            let optional: EditorDocumentPresentationState.ValueBox<String?> = state.box(for: "optional", initialValue: "replacement")
            XCTAssertNil(optional.value)
        }
        XCTAssertNotNil(captured)
        store.unregister(model)
        XCTAssertNil(captured)
    }

    private final class MetadataWindow: NSWindow {
        var titleWrites = 0
        var urlWrites = 0
        var dirtyWrites = 0
        var addTabCalls = 0
        override var title: String {
            get { super.title }
            set { titleWrites += 1; super.title = newValue }
        }
        override var representedURL: URL? {
            get { super.representedURL }
            set { urlWrites += 1; super.representedURL = newValue }
        }
        override var isDocumentEdited: Bool {
            get { super.isDocumentEdited }
            set { dirtyWrites += 1; super.isDocumentEdited = newValue }
        }
        override func addTabbedWindow(_ window: NSWindow, ordered: NSWindow.OrderingMode) {
            addTabCalls += 1
            super.addTabbedWindow(window, ordered: ordered)
        }
    }

    func testUnchangedDocumentMetadataDoesNotRepeatNativeWindowUpdates() {
        let candidate = MetadataWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        candidate.isReleasedWhenClosed = false
        defer { candidate.close() }
        let url = URL(fileURLWithPath: "/tmp/metadata-fixture.swift")
        MacDocumentTabPolicy.applyDocumentMetadata(title: "Fixture.swift", url: url, edited: true, to: candidate)
        let counts = [candidate.titleWrites, candidate.urlWrites, candidate.dirtyWrites]
        for _ in 0..<5 {
            MacDocumentTabPolicy.applyDocumentMetadata(title: "Fixture.swift", url: url, edited: true, to: candidate)
        }
        XCTAssertEqual([candidate.titleWrites, candidate.urlWrites, candidate.dirtyWrites], counts)
        MacDocumentTabPolicy.applyDocumentMetadata(title: "Renamed.swift", url: nil, edited: false, to: candidate)
        XCTAssertEqual(candidate.title, "Renamed.swift")
        XCTAssertNil(candidate.representedURL)
        XCTAssertFalse(candidate.isDocumentEdited)
    }

    func testBackgroundInsertionUsesExistingGroupWithoutSelectingTheNewTab() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel()
        let parent = MetadataWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        parent.isReleasedWhenClosed = false
        let sibling = window("Existing sibling")
        let added = window("Background insertion")
        var child: EditorViewModel?
        defer {
            if let child { store.unregister(child) }
            store.unregister(source); added.close(); sibling.close(); parent.close()
        }
        parent.addTabbedWindow(sibling, ordered: .above)
        parent.tabGroup?.selectedWindow = parent
        parent.addTabCalls = 0
        store.register(source, window: parent) { id in
            child = store.takePendingModel(for: id)
            store.attachPendingWindow(added, for: id)
        }
        source.addNewTab()
        XCTAssertNotNil(child)
        XCTAssertTrue(parent.tabGroup?.windows.contains(added) == true)
        XCTAssertTrue(parent.tabGroup?.selectedWindow === parent)
        XCTAssertEqual(parent.addTabCalls, 0, "An existing tab group must not repeat the window-level attach/order path")
    }

    private final class TabCloseDelegate: NSObject, NSWindowDelegate {
        var requests = 0
        var allowsClose = false
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            requests += 1
            return allowsClose
        }
    }

    func testNewFileBuildsItsEditorOnlyAfterTheInitialLoadCompletes() async throws {
        var scheduled: [@MainActor @Sendable () -> Void] = []
        let store = MacDocumentWindowTabs(scheduleSceneOpen: { scheduled.append($0) })
        let source = MacDocumentTabPolicy.makeWindowModel()
        source.updateTabContent(tabID: try XCTUnwrap(source.selectedTabID), content: "Existing document")
        let parent = window("File-load fixture")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("New.swift")
        try "let loadedSnapshot = true\n".write(to: file, atomically: true, encoding: .utf8)
        var child: EditorViewModel?
        var candidate: NSWindow?
        var constructions = 0
        defer {
            if let child { store.unregister(child) }
            store.unregister(source); candidate?.close(); parent.close()
            try? FileManager.default.removeItem(at: root)
        }
        parent.makeKeyAndOrderFront(nil)
        store.register(source, window: parent) { id in
            child = store.takePendingModel(for: id)
            candidate = store.presentPendingWindow(for: id) {
                XCTAssertFalse(child?.selectedTab?.isLoadingContent ?? true,
                    "Do not build a temporary empty editor and rebuild it for the loaded file")
                constructions += 1
                return NSTextField(labelWithString: "Loaded editor")
            }
        }
        XCTAssertTrue(source.openFile(url: file))
        while !scheduled.isEmpty { scheduled.removeFirst()() }
        XCTAssertNotNil(candidate, "The lightweight native tab must appear immediately")
        XCTAssertEqual(constructions, 0)
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        parent.tabGroup?.selectedWindow = parent
        parent.makeKeyAndOrderFront(nil)
        while child?.selectedTab?.isLoadingContent == true, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(constructions, 0, "A completed load must not build a tab the user has since hidden")
        parent.tabGroup?.selectedWindow = candidate
        candidate?.makeKeyAndOrderFront(nil)
        while constructions == 0, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(constructions, 1)
        XCTAssertEqual(child?.selectedTab?.document.string(), "let loadedSnapshot = true\n")
    }

    func testNativeDocumentTabActivationPerformanceWithRealEditors() async throws {
        guard ProcessInfo.processInfo.environment["NVE_RUN_NATIVE_TAB_BENCHMARK"] == "1",
              Bundle.main.bundleIdentifier?.hasPrefix("h3p.NeonNativeTabPerformance") == true else {
            throw XCTSkip("Run the full-editor benchmark only in its explicitly enabled disposable app host")
        }
        let store = MacDocumentWindowTabs.shared
        let monitor = EditorPerformanceMonitor.shared
        let source = MacDocumentTabPolicy.makeWindowModel()
        source.updateTabContent(tabID: try XCTUnwrap(source.selectedTabID), content: "Benchmark anchor")
        let parent = window("Performance anchor")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let support = SupportPurchaseManager(loadProducts: { [] }, canMakePayments: { false })
        let updateDefaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let updates = AppUpdateManager(defaults: updateDefaults)
        updates.setAutoCheckEnabled(false)
        var created: [(model: EditorViewModel, window: NSWindow)] = []
        var coldOpenStarted: TimeInterval = 0
        var coldOpenBeforeWindowMilliseconds: Double = 0
        defer {
            for item in created { store.unregister(item.model); item.window.close() }
            store.unregister(source); parent.close()
            try? FileManager.default.removeItem(at: root)
        }
        parent.makeKeyAndOrderFront(nil)
        func create(_ id: UUID) {
            guard let owner = store.takePendingModel(for: id) else { return }
            coldOpenBeforeWindowMilliseconds = (ProcessInfo.processInfo.systemUptime - coldOpenStarted) * 1_000
            if let tabID = owner.selectedTabID { monitor.beginTabSwitch(tabID: tabID) }
            guard let candidate = store.presentPendingWindow(for: id, makeContent: {
                let host = NSHostingView(rootView: ContentView(startupBehavior: .nativeDocument,
                    markdownProjectPreviewSession: store.projectPreviewSession(for: owner))
                    .environment(owner).environmentObject(support).environmentObject(updates))
                host.sizingOptions = []
                host.sceneBridgingOptions = .all
                return host
            }) else { return }
            created.append((owner, candidate))
        }
        func waitForDraw(in candidate: NSWindow) async throws -> Int {
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while monitor.recentTabSwitchEvents(limit: 1).isEmpty,
                  ProcessInfo.processInfo.systemUptime < deadline {
                candidate.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(5))
            }
            return try XCTUnwrap(monitor.recentTabSwitchEvents(limit: 1).last,
                "A selection must reach the actual editor draw, not merely create a window").elapsedMilliseconds
        }
        let fixtures = [
            ("Small.swift", String(repeating: "let number = 42\n", count: 100)),
            ("Unicode.json", "[" + Array(repeating: "{\"text\":\"café 中文 😀\",\"number\":123}", count: 8_000).joined(separator: ",") + "]"),
            ("Large.md", String(repeating: "## Heading **bold** `code`\n\nMarkdown text café 中文 😀.\n", count: 12_000))
        ]
        for (name, content) in fixtures {
            let url = root.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            store.register(source, window: parent, openWindow: create)
            monitor.clearRecentTabSwitchEvents()
            let started = ProcessInfo.processInfo.systemUptime
            coldOpenStarted = started
            XCTAssertTrue(source.openFile(url: url))
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while created.last?.model.selectedTab?.fileURL != url,
                  ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            let item = try XCTUnwrap(created.last)
            XCTAssertEqual(item.model.selectedTab?.fileURL, url)
            while item.model.selectedTab?.isLoadingContent != false
                    || nativeEditorCanvas(in: item.window.contentView!) == nil
                    || nativeEditorCanvas(in: item.window.contentView!)?.isViewportActivationPending == true
                    || nativeEditorCanvas(in: item.window.contentView!)?.accessibilityNumberOfCharacters()
                        != item.model.selectedTab?.document.utf16Length {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    XCTFail("The requested file must be installed before measuring its draw")
                    return
                }
                item.window.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(5))
            }
            let draw = try await waitForDraw(in: item.window)
            let total = coldOpenBeforeWindowMilliseconds + Double(draw)
            let readinessObserved = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            print("NATIVE_TAB_BENCH cold file=\(name) bytes=\(content.utf8.count) open_to_first_draw_ms=\(total) readiness_observed_ms=\(readinessObserved) window_create_ms=\(monitor.lastNativeWindowCreationLatencyMilliseconds ?? -1) stages=\(monitor.lastNativeWindowStageMilliseconds)")
            if name.hasSuffix(".md"), UserDefaults.standard.string(forKey: SettingsPreferenceKey.markdownPreviewDefaultMode) != "edit" {
                let previewDeadline = ProcessInfo.processInfo.systemUptime + 5
                while nativeWebPreview(in: item.window.contentView!) == nil,
                      ProcessInfo.processInfo.systemUptime < previewDeadline {
                    try await Task.sleep(for: .milliseconds(5))
                }
                XCTAssertNotNil(nativeWebPreview(in: item.window.contentView!),
                    "Deferring WebKit must not prevent the preview from appearing after the editor draws")
            }
        }
        // Let initial preview work settle before measuring returning to retained
        // editors. Each sample includes an explicit native redraw, not only the
        // tab group's synchronous selectedWindow assignment.
        try await Task.sleep(for: .milliseconds(500))
        var warm: [Int] = []
        for _ in 0..<3 {
            for item in created.reversed() {
                guard item.window.tabGroup?.selectedWindow !== item.window else { continue }
                let canvas = try XCTUnwrap(nativeEditorCanvas(in: item.window.contentView!))
                monitor.clearRecentTabSwitchEvents()
                monitor.beginTabSwitch(tabID: try XCTUnwrap(item.model.selectedTabID))
                item.window.tabGroup?.selectedWindow = item.window
                item.window.makeKeyAndOrderFront(nil)
                canvas.needsDisplay = true
                warm.append(try await waitForDraw(in: item.window))
                XCTAssertTrue(nativeEditorCanvas(in: item.window.contentView!) === canvas,
                    "Returning to a document must retain its editor rather than rebuild it")
            }
        }
        let sorted = warm.sorted()
        print("NATIVE_TAB_BENCH warm_draw_ms samples=\(warm) median=\(sorted[sorted.count / 2]) max=\(sorted.last ?? -1)")
    }

    private func nativeEditorCanvas(in root: NSView) -> VirtualEditorCanvas? {
        if let canvas = root as? VirtualEditorCanvas { return canvas }
        return root.subviews.lazy.compactMap { self.nativeEditorCanvas(in: $0) }.first
    }

    private func nativeWebPreview(in root: NSView) -> WKWebView? {
        if let web = root as? WKWebView { return web }
        return root.subviews.lazy.compactMap { self.nativeWebPreview(in: $0) }.first
    }

    func testNativeTabDoubleClickUsesCloseValidationAndLeavesOtherControlsAlone() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel()
        let other = MacDocumentTabPolicy.makeWindowModel()
        let first = window("Same filename.md")
        let second = window("Same filename.md")
        let delegate = TabCloseDelegate()
        defer {
            first.delegate = nil
            store.unregister(source); store.unregister(other)
            first.close(); second.close()
        }
        store.register(source, window: first) { _ in }
        store.register(other, window: second) { _ in }
        first.addTabbedWindow(second, ordered: .above)
        first.tabGroup?.selectedWindow = first
        first.makeKeyAndOrderFront(nil)
        first.delegate = delegate
        let tab = try XCTUnwrap(nativeTabElements(in: first).first {
            ($0.accessibilityValue() as? NSNumber)?.boolValue == true
        }, "The system must expose a selected native tab, even with duplicate filenames")
        let frame = tab.accessibilityFrame()
        let point = first.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        func click(_ count: Int, point: NSPoint? = nil, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point ?? first.convertPoint(fromScreen:
                NSPoint(x: frame.midX, y: frame.midY)), modifierFlags: flags, timestamp: 0,
                windowNumber: first.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1))
        }
        XCTAssertFalse(store.handleTabDoubleClick(try click(1)))
        XCTAssertFalse(store.handleTabDoubleClick(try click(3)))
        XCTAssertFalse(store.handleTabDoubleClick(try click(2, flags: .command)))
        XCTAssertFalse(store.handleTabDoubleClick(try click(2, point: NSPoint(x: 400, y: 200))))
        let close = try XCTUnwrap((tab.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol }
            .first { $0.accessibilityRole() == .button })
        let closeFrame = close.accessibilityFrame()
        XCTAssertFalse(store.handleTabDoubleClick(try click(2, point: first.convertPoint(fromScreen:
            NSPoint(x: closeFrame.midX, y: closeFrame.midY)))))
        XCTAssertEqual(delegate.requests, 0)
        XCTAssertTrue(store.handleTabDoubleClick(try click(2, point: point)))
        XCTAssertEqual(delegate.requests, 1, "Unsaved-change cancellation must be consulted")
        XCTAssertTrue(first.isVisible)
        XCTAssertEqual(first.tabGroup?.windows.count, 2)
        delegate.allowsClose = true
        XCTAssertTrue(store.handleTabDoubleClick(try click(2, point: point)))
        XCTAssertEqual(delegate.requests, 2)
        XCTAssertFalse(first.isVisible)
        XCTAssertTrue(second.isVisible, "The other document with the same filename must remain open")
    }

    private func nativeTabElements(in element: NSAccessibilityProtocol, depth: Int = 0) -> [NSAccessibilityProtocol] {
        guard depth < 12 else { return [] }
        if element.accessibilitySubrole() == .tabButtonSubrole { return [element] }
        return (element.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol }
            .flatMap { nativeTabElements(in: $0, depth: depth + 1) }
    }

    func testPromotedEditorRootRetainsCloseProtectionAndUnregistersOnClose() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel()
        let first = window("Root lifetime source")
        var child: EditorViewModel?
        var candidate: NSWindow?
        store.register(source, window: first) { id in
            child = store.takePendingModel(for: id)
            candidate = store.presentPendingWindow(for: id) { NSTextField(labelWithString: "Loading surface") }
        }
        defer {
            if let child { store.unregister(child) }
            store.unregister(source)
            candidate?.close(); first.close()
        }
        first.makeKeyAndOrderFront(nil)
        source.addNewTab()
        let owner = try XCTUnwrap(child)
        let window = try XCTUnwrap(candidate)
        owner.updateTabContent(tabID: try XCTUnwrap(owner.selectedTabID), content: "Unsaved owner")
        weak let closeGuard = window.delegate as? WindowCloseConfirmationDelegate
        let root = NSHostingView(rootView: Text("Document root"))
        root.sceneBridgingOptions = .title
        let loadingSurface = window.contentView
        XCTAssertFalse(store.installRootEditorHost(root, for: source, in: window), "A different document cannot replace this window's root")
        XCTAssertTrue(window.contentView === loadingSurface)
        XCTAssertTrue(store.installRootEditorHost(root, for: owner, in: window))
        XCTAssertTrue(window.contentView === root)
        XCTAssertNotNil(closeGuard, "Replacing the loading hierarchy must not release the close delegate")
        XCTAssertTrue(closeGuard?.hasDirtyTabs?() == true)
        window.close()
        XCTAssertFalse(store.models.contains { $0 === owner }, "The retained lifetime must still unregister the closed window")
    }

    func testQueuedBackgroundTabsStayLightweightAndDoNotStealSelection() throws {
        var scheduled: [@MainActor @Sendable () -> Void] = []
        let store = MacDocumentWindowTabs(scheduleSceneOpen: { scheduled.append($0) })
        let source = MacDocumentTabPolicy.makeWindowModel()
        let first = window("Selected startup document")
        var created: [(EditorViewModel, NSWindow)] = []
        var installations = 0
        defer {
            for (owner, candidate) in created { store.unregister(owner); candidate.close() }
            store.unregister(source); first.close()
        }
        first.makeKeyAndOrderFront(nil)
        store.register(source, window: first) { id in
            guard let owner = store.takePendingModel(for: id),
                  let candidate = store.presentPendingWindow(for: id, makeContent: {
                      installations += 1
                      return NSTextField(labelWithString: "Mounted editor")
                  }) else { return XCTFail("Missing queued owner") }
            created.append((owner, candidate))
        }
        source.addNewTab()
        source.addNewTab()
        source.nativeRevealWindow?()
        scheduled.removeFirst()()
        XCTAssertEqual(installations, 0, "Background restoration must not construct hidden editor trees")
        XCTAssertTrue(first.tabGroup?.selectedWindow === first)
        let (interactedOwner, interactedWindow) = try XCTUnwrap(created.first)
        first.tabGroup?.selectedWindow = interactedWindow
        store.noteBecameKey(interactedOwner)
        while !scheduled.isEmpty { scheduled.removeFirst()() }
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(installations, 1, "Only the tab selected by the user may construct its editor")
        XCTAssertTrue(first.tabGroup?.selectedWindow === interactedWindow,
                      "Finishing restoration must not override a user's selection")
        let (owner, selected) = try XCTUnwrap(created.last)
        first.tabGroup?.selectedWindow = selected
        store.noteBecameKey(owner)
        store.register(owner, window: selected) { _ in }
        XCTAssertEqual(installations, 2)
        XCTAssertTrue(first.tabGroup?.selectedWindow === selected,
                      "Late editor registration must not restore an obsolete startup selection")
        XCTAssertTrue(store.selectedModel === owner)
    }

    func testRestoringAnotherTabPreservesAnAttachedDecisionSheet() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel()
        let first = window("Conflict owner")
        let sheet = window("Existing file decision")
        var child: EditorViewModel?
        var created: NSWindow?
        defer {
            first.endSheet(sheet)
            sheet.orderOut(nil)
            if let child { store.unregister(child) }
            store.unregister(source); created?.close(); first.close(); sheet.close()
        }
        first.makeKeyAndOrderFront(nil)
        first.beginSheet(sheet)
        store.register(source, window: first) { id in
            child = store.takePendingModel(for: id)
            created = store.presentPendingWindow(for: id) {
                XCTFail("A pending decision must not be replaced by background editor installation")
                return NSView()
            }
        }
        source.addNewTab()
        XCTAssertNotNil(created)
        XCTAssertTrue(first.attachedSheet === sheet)
        XCTAssertTrue(first.tabGroup?.selectedWindow === first)
    }

    func testBackgroundRecoveredDraftHasCloseProtectionBeforeEditorInstallation() throws {
        var scheduled: [@MainActor @Sendable () -> Void] = []
        let store = MacDocumentWindowTabs(scheduleSceneOpen: { scheduled.append($0) })
        let source = MacDocumentTabPolicy.makeWindowModel()
        let first = window("Draft source")
        var child: EditorViewModel?
        var created: NSWindow?
        defer {
            if let child { store.unregister(child) }
            store.unregister(source); created?.close(); first.close()
        }
        first.makeKeyAndOrderFront(nil)
        store.register(source, window: first) { id in
            child = store.takePendingModel(for: id)
            created = store.presentPendingWindow(for: id) {
                XCTFail("An unselected recovered draft must not instantiate its editor")
                return NSView()
            }
        }
        let snapshots = ["Active draft", "Unsaved background edits"].map { text in
            EditorViewModel.RestoredTabSnapshot(name: text, content: text, language: "plain", fileURL: nil,
                languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
                lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)
        }
        source.restoreTabsFromSnapshot(snapshots, selectedIndex: 0)
        while !scheduled.isEmpty { scheduled.removeFirst()() }
        let guardDelegate = try XCTUnwrap(created?.delegate as? WindowCloseConfirmationDelegate)
        XCTAssertTrue(guardDelegate.hasDirtyTabs?() == true)
        XCTAssertNotNil(guardDelegate.saveAllDirtyTabsAsync)
        XCTAssertEqual(child?.selectedTab?.document.string(), "Unsaved background edits")
        XCTAssertTrue(child?.selectedTab?.isDirty == true)
    }

    private final class WindowStorageBindings {
        var focus: Binding<Bool>?
        var width: Binding<Double>?
        var expansion: Binding<String>?
    }

    private struct WindowStorageProbe: View {
        @EditorWindowStorage("EditorWindowStorageTests.Focus") var focus = false
        @EditorWindowStorage("EditorWindowStorageTests.Width") var width = 250.0
        @EditorWindowStorage("EditorWindowStorageTests.Expansion") var expansion = ""
        let bindings: WindowStorageBindings
        let onAppear: () -> Void

        var body: some View {
            Text(verbatim: "\(focus) / \(width) / \(expansion)")
                .onAppear {
                    bindings.focus = $focus
                    bindings.width = $width
                    bindings.expansion = $expansion
                    onAppear()
                }
        }
    }

    func testAppKitHostedWindowStorageRetainsValuesAndIsolatesWindows() async throws {
        let first = window("First storage")
        let second = window("Second storage")
        defer { first.close(); second.close() }
        let left = WindowStorageBindings()
        let right = WindowStorageBindings()
        let mounted = expectation(description: "Both AppKit document hosts mounted")
        mounted.expectedFulfillmentCount = 2
        for (candidate, bindings) in [(first, left), (second, right)] {
            candidate.contentView = NSHostingView(rootView:
                WindowStorageProbe(bindings: bindings, onAppear: { mounted.fulfill() }))
            candidate.makeKeyAndOrderFront(nil)
        }
        await fulfillment(of: [mounted], timeout: 3)
        let focus = try XCTUnwrap(left.focus)
        let width = try XCTUnwrap(left.width)
        let expansion = try XCTUnwrap(left.expansion)
        XCTAssertFalse(focus.wrappedValue)
        XCTAssertEqual(width.wrappedValue, 250)
        XCTAssertEqual(expansion.wrappedValue, "")
        focus.wrappedValue = true
        width.wrappedValue = 420
        expansion.wrappedValue = "{\"project\":[\"Sources\"]}"
        first.contentView?.layoutSubtreeIfNeeded()
        // SceneStorage in an NSHostingView without a scene returns defaults
        // here instead. This asserts actual storage, not warning suppression.
        XCTAssertTrue(focus.wrappedValue)
        XCTAssertEqual(width.wrappedValue, 420)
        XCTAssertEqual(expansion.wrappedValue, "{\"project\":[\"Sources\"]}")
        XCTAssertFalse(try XCTUnwrap(right.focus).wrappedValue)
        XCTAssertEqual(try XCTUnwrap(right.width).wrappedValue, 250)
        XCTAssertEqual(try XCTUnwrap(right.expansion).wrappedValue, "")
        first.addTabbedWindow(second, ordered: .above)
        first.tabGroup?.selectedWindow = second
        first.tabGroup?.selectedWindow = first
        XCTAssertTrue(focus.wrappedValue)
        focus.wrappedValue = false
        width.wrappedValue = 0
        expansion.wrappedValue = ""
        XCTAssertFalse(focus.wrappedValue)
        XCTAssertEqual(width.wrappedValue, 0)
        XCTAssertEqual(expansion.wrappedValue, "")
    }

    func testNativeHostingPreservesSwiftUIToolbar() {
        let host = NSHostingController(rootView: Text("Probe").frame(width: 600, height: 400)
            .toolbar { ToolbarItem { Button("Probe") {} } })
        let candidate = NSWindow(contentViewController: host)
        candidate.isReleasedWhenClosed = false
        defer { candidate.close() }
        candidate.makeKeyAndOrderFront(nil)
        host.view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(candidate.toolbar, "Direct AppKit hosting must preserve SwiftUI toolbar integration")
    }

    func testDirectNativeWindowFactoryKeepsToolbarAndDocumentGroup() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel()
        let first = window("Source")
        first.makeKeyAndOrderFront(nil)
        XCTAssertTrue(first.tabbedWindows?.allSatisfy { $0 === first } ?? true)
        let originalWidth = first.frame.width
        var child: EditorViewModel?
        var created: NSWindow?
        defer {
            if let child { store.unregister(child) }
            store.unregister(source)
            created?.close()
            first.close()
        }
        store.register(source, window: first) { id in
            child = store.takePendingModel(for: id)
            created = store.presentPendingWindow(for: id) {
                let host = NSHostingView(rootView: Text("Document").frame(minWidth: 600, minHeight: 400)
                    .toolbar { ToolbarItem { Button("Save fixture") {} } })
                host.sizingOptions = []
                host.sceneBridgingOptions = .all
                return host
            }
        }
        source.addNewTab()
        let owner = try XCTUnwrap(child)
        let destination = try XCTUnwrap(created)
        store.register(owner, window: destination) { _ in }
        XCTAssertTrue(first.tabGroup === destination.tabGroup)
        XCTAssertTrue(destination.tabGroup?.selectedWindow === destination)
        XCTAssertEqual(destination.toolbarStyle, .unified)
        XCTAssertNotNil(destination.toolbar)
        XCTAssertEqual(destination.frame.width, originalWidth)
        XCTAssertEqual(first.frame.width, originalWidth)
        XCTAssertTrue(owner !== source)
        XCTAssertEqual(source.tabs.count, 1)
        XCTAssertEqual(owner.tabs.count, 1)
    }

    func testUnknownNativeWindowRequestDoesNotConstructContent() {
        let store = immediateStore()
        XCTAssertNil(store.presentPendingWindow(for: UUID()) {
            XCTFail("Only pending document owners may create a native window")
            return NSView()
        })
    }

    func testProjectCardsStateIsSharedByNativeTabsButNotIndependentGroups() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel()
        let first = window()
        defer { store.unregister(source); first.close() }
        let session = store.projectPreviewSession(for: source)
        session.setProjectRoot(URL(fileURLWithPath: "/tmp/cards-project"))
        session.isPresented = true
        session.width = 620
        session.lastRefreshSignature = "prepared"
        var request: UUID?
        store.register(source, window: first) { request = $0 }
        source.addNewTab()
        let child = try XCTUnwrap(store.takePendingModel(for: XCTUnwrap(request)))
        defer { store.unregister(child) }
        let shared = store.projectPreviewSession(for: child)
        XCTAssertTrue(session === shared)
        XCTAssertTrue(session.model === shared.model)
        XCTAssertTrue(shared.isPresented)
        XCTAssertEqual(shared.width, 620)
        XCTAssertEqual(shared.lastRefreshSignature, "prepared")
        let independent = MacDocumentTabPolicy.makeWindowModel()
        defer { store.unregister(independent) }
        XCTAssertFalse(store.projectPreviewSession(for: independent) === session)
        store.unregister(source)
        XCTAssertTrue(shared.isPresented)
        XCTAssertEqual(shared.lastRefreshSignature, "prepared")
    }

    func testProjectCardSurfaceAndScrollViewSurviveNativeTabSelection() throws {
        let pane = MacProjectCardsPane()
        let first = window("First cards")
        let second = window("Second cards")
        defer { pane.release(); first.close(); second.close() }
        let root = AnyView(ScrollView {
            VStack { ForEach(0..<100) { Text("Project card \($0)") } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity))
        let left = MacProjectCardsContainer(pane: pane, root: root)
        let right = MacProjectCardsContainer(pane: pane, root: root)
        left.frame = first.contentView!.bounds
        right.frame = second.contentView!.bounds
        first.contentView = left
        second.contentView = right
        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(second, ordered: .above)
        first.tabGroup?.selectedWindow = first
        pane.activate(left)
        let host = try XCTUnwrap(pane.host)
        host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(nativeScrollView(in: host))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        let origin = scroll.contentView.bounds.origin
        XCTAssertGreaterThan(origin.y, 0, "The fixture must actually scroll before testing preservation")
        first.tabGroup?.selectedWindow = second
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(pane.host === host, "Document selection must not recreate the project pane")
        XCTAssertTrue(host.superview === right, "Group selection must move the existing surface")
        XCTAssertTrue(nativeScrollView(in: host) === scroll)
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        first.tabGroup?.selectedWindow = first
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.superview === left)
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        pane.release()
        XCTAssertNil(pane.host)
        XCTAssertNil(host.superview)
    }

    private func nativeScrollView(in root: NSView) -> NSScrollView? {
        var candidates = [root]
        while let candidate = candidates.popLast() {
            if let scroll = candidate as? NSScrollView { return scroll }
            candidates.append(contentsOf: candidate.subviews)
        }
        return nil
    }

    func testProjectCardsAreRetainedForSameFolderAndClearedWhenProjectChanges() async throws {
        let session = MarkdownProjectPreviewSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Card.md")
        try "# Cached card\n\nShared project content".write(to: file, atomically: true, encoding: .utf8)
        session.setProjectRoot(root)
        session.isPresented = true
        let finished = expectation(description: "Project card prepared")
        let token = session.model.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        session.model.refresh(entries: [ProjectFileIndex.Entry(url: file, standardizedPath: file.path,
            relativePath: file.lastPathComponent, displayName: file.lastPathComponent,
            contentModificationDate: nil, fileSize: nil)], projectRoot: root, reason: "Test")
        await fulfillment(of: [finished], timeout: 5)
        withExtendedLifetime(token) {}
        XCTAssertEqual(session.model.cards.count, 1)
        session.setProjectRoot(root)
        XCTAssertEqual(session.model.cards.count, 1, "Another tab attaching the same project must not clear cards")
        session.setProjectRoot(nil)
        XCTAssertTrue(session.model.cards.isEmpty)
        XCTAssertFalse(session.isPresented)
    }

    func testIdlePreviewCancellationDoesNotPublishDuringInitialInstallation() {
        let model = MarkdownProjectPreviewModel()
        var publications = 0
        let token = model.objectWillChange.sink { publications += 1 }
        model.cancel()
        model.cancel()
        XCTAssertEqual(publications, 0, "An already-empty preview has no state transition to publish")
        withExtendedLifetime(token) {}
    }

    func testLastPreviewOwnerTeardownStopsWorkWithoutPublishingIntoTheRemovingView() async throws {
        let store = immediateStore()
        let owner = MacDocumentTabPolicy.makeWindowModel()
        let session = store.projectPreviewSession(for: owner)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Card.md")
        try "# Teardown regression".write(to: file, atomically: true, encoding: .utf8)
        session.setProjectRoot(root)
        let entries = [ProjectFileIndex.Entry(url: file, standardizedPath: file.path,
            relativePath: file.lastPathComponent, displayName: file.lastPathComponent,
            contentModificationDate: nil, fileSize: nil)]
        let finished = expectation(description: "Preview prepared before teardown")
        let loading = session.model.$isLoading.dropFirst().filter { !$0 }.prefix(1)
            .sink { _ in finished.fulfill() }
        session.model.refresh(entries: entries, projectRoot: root, reason: "Test")
        await fulfillment(of: [finished], timeout: 5)
        withExtendedLifetime(loading) {}
        XCTAssertEqual(session.model.cards.count, 1)
        var publications = 0
        let token = session.model.objectWillChange.sink { publications += 1 }
        store.unregister(owner)
        XCTAssertEqual(publications, 0, "View teardown must cancel producers, not reset observed state")
        XCTAssertEqual(session.model.cards.count, 1)
        // Explicit user/project reset still clears retained data after teardown.
        session.model.cancel()
        XCTAssertTrue(session.model.cards.isEmpty)
        XCTAssertEqual(publications, 1)
        withExtendedLifetime(token) {}
    }

    private func immediateStore() -> MacDocumentWindowTabs {
        MacDocumentWindowTabs(scheduleSceneOpen: { $0() })
    }

    private func window(_ title: String = "Native document tabs QA") -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // The app-hosted suite has its own SwiftUI window. Do not let AppKit
        // automatically merge fixtures into that unrelated group on first show.
        window.tabbingMode = .disallowed
        window.title = title
        window.contentView = NSTextField(labelWithString: title)
        return window
    }

    func testWindowOwnersUseNativeTabsRegardlessOfRetiredPreference() {
        let defaults = UserDefaults.standard
        let retiredKey = "SettingsNativeDocumentTabsMac"
        let previous = defaults.object(forKey: retiredKey)
        defer {
            if let previous { defaults.set(previous, forKey: retiredKey) }
            else { defaults.removeObject(forKey: retiredKey) }
        }
        for oldPreference in [false, true] {
            defaults.set(oldPreference, forKey: retiredKey)
            let model = MacDocumentTabPolicy.makeWindowModel()
            XCTAssertFalse(model.isSafeModeRecoveryWindow)
            XCTAssertEqual(model.tabs.count, 1)
        }
    }

    func testSafeModeStartupResetStaysInOriginalOwnerAndPreservesNormalRecoveryNamespace() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel(isSafeMode: true)
        let host = window("Safe Mode")
        defer { store.unregister(source); host.close() }
        store.register(source, window: host) { _ in XCTFail("Startup reset must not open another window") }
        source.updateTabContent(tabID: try XCTUnwrap(source.selectedTabID), content: "discarded startup buffer")
        source.resetToBlankDocumentForStartup()
        XCTAssertTrue(source.isSafeModeRecoveryWindow)
        XCTAssertEqual(source.tabs.count, 1)
        XCTAssertEqual(source.selectedTab?.document.string(), "")
        XCTAssertFalse(source.selectedTab?.isDirty ?? true)
        XCTAssertEqual(store.models.count, 1)
        XCTAssertNotEqual(MacDocumentTabPolicy.draftSnapshotKey(for: source),
                          MacDocumentTabPolicy.draftSnapshotKey(for: MacDocumentTabPolicy.makeWindowModel()))
    }

    func testNewTabsAndNativePlusInheritSafeModeRecoveryIsolation() throws {
        let store = immediateStore()
        let source = MacDocumentTabPolicy.makeWindowModel(isSafeMode: true)
        let host = window("Safe Mode source")
        defer { store.unregister(source); host.close() }
        var requests: [UUID] = []
        store.register(source, window: host) { requests.append($0) }
        source.addNewTab()
        let commandChild = try XCTUnwrap(store.takePendingModel(for: XCTUnwrap(requests.first)))
        XCTAssertTrue(commandChild.isSafeModeRecoveryWindow)
        store.noteBecameKey(source)
        let plusChild = try XCTUnwrap(store.takePendingModel(for: XCTUnwrap(store.prepareNativeTabScene())))
        XCTAssertTrue(plusChild.isSafeModeRecoveryWindow)
        XCTAssertEqual(MacDocumentTabPolicy.draftSnapshotKey(for: commandChild),
                       MacDocumentTabPolicy.draftSnapshotKey(for: plusChild))
        XCTAssertEqual(source.tabs.count, 1)
    }

    func testNativeWindowTitleTracksSelectedDocumentFilename() throws {
        let model = EditorViewModel()
        XCTAssertEqual(MacDocumentTabPolicy.windowTitle(for: model), "Untitled 1")

        model.restoreTabsFromSnapshot([
            .init(name: "Notes.md", content: "notes", language: "markdown", fileURL: nil,
                  languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
                  lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue),
            .init(name: "Config.json", content: "{}", language: "json", fileURL: nil,
                  languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
                  lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)
        ], selectedIndex: 0)

        XCTAssertEqual(MacDocumentTabPolicy.windowTitle(for: model), "Notes.md")
        model.selectTab(id: model.tabs[1].id)
        XCTAssertEqual(MacDocumentTabPolicy.windowTitle(for: model), "Config.json")
    }

    func testRestoredDraftsArePopulatedBeforeNativeScenesAreCreated() async throws {
        let store = MacDocumentWindowTabs()
        let source = EditorViewModel()
        let host = window("Restore source")
        defer { store.unregister(source); host.close() }
        let opened = expectation(description: "Restored scenes requested after restoring owners")
        opened.expectedFulfillmentCount = 2
        var requests: [UUID] = []
        store.register(source, window: host) { id in
            requests.append(id)
            let owner = store.takePendingModel(for: id)
            XCTAssertTrue(owner?.selectedTab?.isDirty == true)
            XCTAssertTrue(["second dirty draft", "third dirty draft"].contains(owner?.selectedTab?.document.string() ?? ""),
                          "A scene must never see the temporary blank owner during recovery")
            opened.fulfill()
        }
        let snapshots = ["first dirty draft", "second dirty draft", "third dirty draft"].map { text in
            EditorViewModel.RestoredTabSnapshot(name: text, content: text, language: "plain", fileURL: nil,
                languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
                lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)
        }
        source.restoreTabsFromSnapshot(snapshots, selectedIndex: 1)
        XCTAssertTrue(requests.isEmpty, "Scene creation must leave the startup restoration transaction first")
        XCTAssertEqual(store.models.compactMap { $0.selectedTab?.document.string() }, snapshots.map(\.content))
        await fulfillment(of: [opened], timeout: 3)
        XCTAssertEqual(requests.count, 2)
    }

    func testTerminationCancelsScenesWaitingForWindowCreation() {
        var scheduled: [@MainActor @Sendable () -> Void] = []
        let store = MacDocumentWindowTabs(scheduleSceneOpen: { scheduled.append($0) })
        let source = EditorViewModel()
        let host = window("Pending scene source")
        defer { host.close() }
        store.register(source, window: host) { _ in XCTFail("Termination must not create another window") }
        source.addNewTab()
        XCTAssertEqual(store.models.count, 2, "The pending owner still participates in draft recovery")
        XCTAssertEqual(scheduled.count, 1)
        store.beginTermination()
        scheduled.removeFirst()()
    }

    func testSceneRootJoinsTabGroupBeforeWindowIsPresented() throws {
        let store = immediateStore()
        let source = EditorViewModel()
        let first = window("Source")
        let second = window("New document")
        defer { store.unregister(source); first.close(); second.close() }
        var request: UUID?
        store.register(source, window: first) { request = $0 }
        source.addNewTab()
        let id = try XCTUnwrap(request)
        let child = try XCTUnwrap(store.takePendingModel(for: id))
        defer { store.unregister(child) }

        // Mount the actual scene-root bridge without registering/rendering the
        // expensive editor, and without ordering the destination on screen.
        let hosting = NSHostingView(rootView: NativeDocumentTabAttachment(windowID: id, store: store))
        second.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        XCTAssertFalse(second.isVisible)
        XCTAssertTrue(first.tabGroup === second.tabGroup)
        XCTAssertEqual(first.tabbedWindows?.count, 2)

        store.register(child, window: second) { _ in }
        XCTAssertEqual(first.tabbedWindows?.count, 2, "Editor registration must not merge/reorder a second time")
        XCTAssertTrue(child !== source)
        XCTAssertEqual(source.tabs.count, 1)
    }

    func testNativePlusBootstrapAttachesBeforeOwnerIsConsumed() throws {
        let store = immediateStore()
        let source = EditorViewModel()
        let first = window("Plus source")
        let second = window("Plus destination")
        defer { store.unregister(source); first.close(); second.close() }
        store.register(source, window: first) { _ in XCTFail("Plus reuses its existing scene") }
        store.noteBecameKey(source)
        let id = try XCTUnwrap(store.prepareNativeTabScene())
        store.attachPendingWindow(second, for: id)
        XCTAssertFalse(second.isVisible)
        XCTAssertTrue(first.tabGroup === second.tabGroup)
        let child = try XCTUnwrap(store.takePendingModel(for: id))
        defer { store.unregister(child) }
        store.attachPendingWindow(second, for: id)
        store.register(child, window: second) { _ in }
        XCTAssertEqual(first.tabbedWindows?.count, 2)
        XCTAssertTrue(store.models.contains { $0 === child })
    }

    func testUnknownSceneAttachmentNeverGroupsUtilityWindows() {
        let store = immediateStore()
        let utility = window("Independent preview")
        defer { utility.close() }
        utility.tabbingMode = .disallowed
        store.attachPendingWindow(utility, for: UUID())
        XCTAssertEqual(utility.tabbingMode, .disallowed)
        XCTAssertNil(utility.tabGroup)
        XCTAssertTrue(store.models.isEmpty)
    }

    func testActiveNativeTabUsesAccentColorAndUpdatesAfterSelectionAndRename() throws {
        let store = immediateStore()
        let source = EditorViewModel()
        let first = window("First document")
        let second = window("Second document")
        defer { store.unregister(source); first.close(); second.close() }
        var request: UUID?
        store.register(source, window: first) { request = $0 }
        source.addNewTab()
        let child = try XCTUnwrap(store.takePendingModel(for: XCTUnwrap(request)))
        defer { store.unregister(child) }
        store.register(child, window: second) { _ in }
        first.tabGroup?.selectedWindow = first
        store.noteBecameKey(source)
        XCTAssertNotNil(first.tab.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        XCTAssertNil(second.tab.attributedTitle)
        first.tabGroup?.selectedWindow = second
        store.noteBecameKey(child)
        XCTAssertNil(first.tab.attributedTitle)
        XCTAssertNotNil(second.tab.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        child.renameTab(tabID: try XCTUnwrap(child.selectedTabID), newName: "Renamed.md")
        store.updateTabAppearance(for: child)
        XCTAssertEqual(second.tab.attributedTitle?.string, "Renamed.md")
    }

    func testProjectSidebarFolderSelectionIsSharedWithinNativeTabGroup() throws {
        let store = immediateStore()
        let source = EditorViewModel()
        let first = window("Project source")
        let second = window("Project peer")
        defer {
            store.unregister(source)
            first.close()
            second.close()
        }

        var sourceUpdates = 0
        var childUpdates: [URL?] = []
        var pendingIDs: [UUID] = []
        store.register(source, window: first, synchronizeProjectFolder: { _ in sourceUpdates += 1 }) {
            pendingIDs.append($0)
        }
        source.addNewTab()
        let pendingID = try XCTUnwrap(pendingIDs.first)
        let child = try XCTUnwrap(store.takePendingModel(for: pendingID))
        defer { store.unregister(child) }
        store.register(child, window: second, synchronizeProjectFolder: { childUpdates.append($0) }) { _ in }

        let projectURL = URL(fileURLWithPath: "/tmp/SharedProject")
        store.synchronizeProjectFolder(projectURL, from: source)
        store.synchronizeProjectFolder(nil, from: source)

        XCTAssertEqual(sourceUpdates, 0, "The source window already applied its own folder change")
        XCTAssertEqual(childUpdates, [projectURL, nil])
    }

    func testNewNativeTabGetsItsOwnModelWithoutMovingDirtyBuffer() throws {
        let store = immediateStore()
        let source = EditorViewModel()
        let window = window()
        defer { store.unregister(source); window.close() }
        var requests: [UUID] = []
        store.register(source, window: window) { requests.append($0) }
        let original = try XCTUnwrap(source.selectedTab)
        source.updateTabContent(tabID: original.id, content: "unsaved 中文 😀")
        source.addNewTab()
        XCTAssertEqual(requests.count, 1)
        let destination = try XCTUnwrap(store.takePendingModel(for: requests[0]))
        XCTAssertFalse(source === destination)
        XCTAssertTrue(source.selectedTab === original)
        XCTAssertEqual(original.document.string(), "unsaved 中文 😀")
        XCTAssertTrue(original.isDirty)
        XCTAssertEqual(source.tabs.count, 1)
        XCTAssertEqual(destination.tabs.count, 1)
        XCTAssertFalse(destination.selectedTab?.isDirty ?? true)
        XCTAssertEqual(store.models.count, 2, "Pending scenes participate in persistence before attachment")
        XCTAssertTrue(store.takePendingModel(for: requests[0]) === destination)
    }

    func testAttachingChildUsesRealAppKitWindowTabsAndUnregistersOnlyItsOwner() throws {
        let store = immediateStore()
        let source = EditorViewModel()
        let first = window("First document")
        let second = window("Second document")
        defer { first.close(); second.close() }
        var request: UUID?
        store.register(source, window: first) { request = $0 }
        source.addNewTab()
        let child = try XCTUnwrap(store.takePendingModel(for: XCTUnwrap(request)))
        store.register(child, window: second) { _ in }
        XCTAssertEqual(first.tabbingIdentifier, MacDocumentTabPolicy.tabbingIdentifier)
        XCTAssertEqual(second.tabbingMode, .preferred)
        XCTAssertEqual(first.tabbedWindows?.count, 2)
        XCTAssertTrue(first.tabbedWindows?.contains(where: { $0 === second }) == true)
        first.addTabbedWindow(second, ordered: .below)
        XCTAssertEqual(store.models.count, 2)
        XCTAssertTrue(source.selectedTab !== child.selectedTab)
        store.unregister(child)
        XCTAssertNil(child.nativeDocumentDestination)
        XCTAssertEqual(store.models.count, 1)
        XCTAssertTrue(store.models.first === source)
        store.unregister(source)
        XCTAssertTrue(store.models.isEmpty)
    }

    func testNativeTabBarSceneGetsAnOwnerAndJoinsTheActiveWindowGroup() throws {
        let store = immediateStore()
        let source = EditorViewModel()
        let first = window("Active native document")
        let second = window("AppKit plus scene")
        defer { store.unregister(source); first.close(); second.close() }
        store.register(source, window: first) { _ in }
        store.noteBecameKey(source)

        let sceneID = try XCTUnwrap(store.prepareNativeTabScene())
        let destination = try XCTUnwrap(store.takePendingModel(for: sceneID))
        store.register(destination, window: second) { _ in }

        XCTAssertTrue(first.tabbedWindows?.contains(where: { $0 === second }) == true)
        XCTAssertTrue(store.models.contains(where: { $0 === destination }))
        XCTAssertTrue(store.selectedModel === destination)
    }

    func testNativeFileOpenReusesOnlyBlankOwnerAndDeduplicatesPendingScenes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.txt")
        let secondURL = directory.appendingPathComponent("second.unknown")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second 中文".write(to: secondURL, atomically: true, encoding: .utf8)
        let store = immediateStore()
        let source = EditorViewModel()
        let window = window()
        defer { store.unregister(source); window.close() }
        var requests: [UUID] = []
        store.register(source, window: window) { requests.append($0) }
        XCTAssertTrue(source.openFile(url: firstURL))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(source.openFile(url: secondURL))
        XCTAssertEqual(requests.count, 1)
        let child = try XCTUnwrap(store.takePendingModel(for: requests[0]))
        XCTAssertTrue(source.openFile(url: secondURL))
        XCTAssertEqual(requests.count, 1)
        for _ in 0..<200 where source.selectedTab?.isLoadingContent == true || child.selectedTab?.isLoadingContent == true {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(source.tabs.count, 1)
        XCTAssertEqual(child.tabs.count, 1)
        XCTAssertEqual(source.selectedTab?.document.string(), "first")
        XCTAssertEqual(child.selectedTab?.document.string(), "second 中文")
    }

    func testNativeDraftRestoreKeepsEveryUnsavedDocumentInSeparateOwners() throws {
        let store = immediateStore()
        let source = EditorViewModel()
        let window = window()
        defer { store.unregister(source); window.close() }
        var requests: [UUID] = []
        store.register(source, window: window) { requests.append($0) }
        let snapshots = ["one 😀", "two 中文", "three"].map { text in
            EditorViewModel.RestoredTabSnapshot(name: text, content: text, language: "plain", fileURL: nil,
                languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
                lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)
        }
        source.restoreTabsFromSnapshot(snapshots, selectedIndex: 1)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(store.models.count, 3)
        XCTAssertEqual(store.models.map { $0.tabs.count }, [1, 1, 1])
        XCTAssertEqual(store.models.compactMap { $0.selectedTab?.document.string() }, ["one 😀", "two 中文", "three"])
        XCTAssertTrue(store.models.allSatisfy { $0.selectedTab?.isDirty == true })
        XCTAssertEqual(store.selectedModel?.selectedTab?.document.string(), "two 中文")
        let lastWindow = self.window("Last restored draft")
        let selectedWindow = self.window("Selected restored draft")
        defer { lastWindow.close(); selectedWindow.close() }
        let last = try XCTUnwrap(store.takePendingModel(for: requests[1]))
        let selected = try XCTUnwrap(store.takePendingModel(for: requests[0]))
        store.register(last, window: lastWindow) { _ in }
        store.register(selected, window: selectedWindow) { _ in }
        XCTAssertTrue(window.tabGroup?.selectedWindow === selectedWindow)
        store.unregister(last)
        store.unregister(selected)
    }

    func testNativeRemoteOpenDoesNotLeaveAnExtraBlankDocument() {
        let model = EditorViewModel()
        model.openRemoteDocument(name: "remote.txt", remotePath: "/remote.txt", content: "remote",
                                 isReadOnly: false)
        XCTAssertEqual(model.tabs.count, 1)
        model.openRemoteDocument(name: "remote.txt", remotePath: "/remote.txt", content: "updated",
                                 isReadOnly: false)
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.selectedTab?.document.string(), "updated")
    }

    func testSaveBeforeNativeWindowCloseAwaitsWritesAndPreservesModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("saved.txt")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        let model = EditorViewModel()
        XCTAssertTrue(model.openFile(url: url))
        for _ in 0..<200 where model.selectedTab?.isLoadingContent == true {
            try await Task.sleep(for: .milliseconds(10))
        }
        let tab = try XCTUnwrap(model.selectedTab)
        model.updateTabContent(tabID: tab.id, content: "new 😀")
        let saved = await model.saveDirtyDocumentsBeforeWindowClose()
        XCTAssertTrue(saved)
        XCTAssertFalse(tab.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new 😀")
        XCTAssertTrue(model.selectedTab === tab, "The window delegate, not saving, owns closing")
    }

    func testNativeWindowSelectionAndDetachDoNotChangeBufferOwners() throws {
        let store = immediateStore()
        let model = EditorViewModel()
        let first = window("First editable document")
        let second = window("Second editable document")
        defer { first.close(); second.close() }
        var request: UUID?
        store.register(model, window: first) { request = $0 }
        let firstTab = try XCTUnwrap(model.selectedTab)
        model.updateTabContent(tabID: firstTab.id, content: "First unsaved")
        model.addNewTab()
        let child = try XCTUnwrap(store.takePendingModel(for: XCTUnwrap(request)))
        let secondTab = try XCTUnwrap(child.selectedTab)
        child.updateTabContent(tabID: secondTab.id, content: "Second unsaved")
        store.register(child, window: second) { _ in }
        let start = ContinuousClock.now
        for _ in 0..<100 {
            first.tabGroup?.selectedWindow = first
            first.selectNextTab(nil)
            second.selectPreviousTab(nil)
        }
        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed, .seconds(5), "Native selection must not load or copy document buffers")
        XCTAssertTrue(model.selectedTab === firstTab)
        XCTAssertTrue(child.selectedTab === secondTab)
        XCTAssertEqual(firstTab.document.string(), "First unsaved")
        XCTAssertEqual(secondTab.document.string(), "Second unsaved")
        XCTAssertTrue(firstTab.isDirty)
        XCTAssertTrue(secondTab.isDirty)
        second.moveTabToNewWindow(nil)
        XCTAssertTrue(model.selectedTab === firstTab)
        XCTAssertTrue(child.selectedTab === secondTab)
        first.addTabbedWindow(second, ordered: .above)
        XCTAssertEqual(first.tabbedWindows?.count, 2)
        let image = try XCTUnwrap(first.contentView?.bitmapImageRepForCachingDisplay(in: first.contentView!.bounds))
        first.contentView?.cacheDisplay(in: first.contentView!.bounds, to: image)
        let attachment = XCTAttachment(data: try XCTUnwrap(image.representation(using: .png, properties: [:])),
                                      uniformTypeIdentifier: "public.png")
        attachment.name = "Native document group content"
        attachment.lifetime = .keepAlways
        add(attachment)
        store.unregister(child)
        store.unregister(model)
    }

    func testTerminationPersistsCompleteDraftSetBeforeFreezingWindowTeardown() {
        let store = immediateStore()
        let model = EditorViewModel()
        let window = window()
        defer { window.close() }
        var persisted = 0
        store.register(model, window: window, persistDrafts: {
            XCTAssertFalse(store.isTerminating)
            XCTAssertEqual(store.models.count, 1)
            persisted += 1
        }) { _ in }
        store.beginTermination()
        store.unregister(model)
        store.beginTermination()
        XCTAssertTrue(store.isTerminating)
        XCTAssertEqual(persisted, 1)
        XCTAssertEqual(store.models.count, 1, "Window teardown must not replace recovery with a partial session")
    }

    func testFailedNativeWindowSaveKeepsDirtyDocumentOpen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = EditorViewModel()
        model.restoreTabsFromSnapshot([.init(name: "invalid target", content: "Keep this unsaved text", language: "plain",
            fileURL: directory, languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
            lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)], selectedIndex: 0)
        let tab = try XCTUnwrap(model.selectedTab)
        let saved = await model.saveDirtyDocumentsBeforeWindowClose()
        XCTAssertFalse(saved)
        XCTAssertTrue(model.selectedTab === tab)
        XCTAssertTrue(tab.isDirty)
        XCTAssertEqual(tab.document.string(), "Keep this unsaved text")
    }

    func testPDFAndAttachedNoteRemainACompositeWindowWithoutLosingTheSource() throws {
        let model = EditorViewModel()
        let source = try XCTUnwrap(model.selectedTab)
        let noteID = model.addPDFNoteTab(name: "source.pdf.notes.md", content: "Note content")
        XCTAssertTrue(model.tabs.contains { $0 === source })
        XCTAssertEqual(model.selectedTabID, noteID)
        model.selectTab(id: source.id)
        XCTAssertEqual(model.tabs.first { $0.id == noteID }?.document.string(), "Note content")
    }

    func testFocusingAnEmptyDirtyDraftDoesNotReloadItsOldDiskContents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("emptied.txt")
        try "Previous disk contents".write(to: url, atomically: true, encoding: .utf8)
        let model = EditorViewModel()
        model.restoreTabsFromSnapshot([.init(name: url.lastPathComponent, content: "", language: "plain",
            fileURL: url, languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
            lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)], selectedIndex: 0)
        XCTAssertTrue(model.openFile(url: url))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.selectedTab?.isLoadingContent ?? true)
        XCTAssertTrue(model.selectedTab?.isDirty ?? false)
        XCTAssertEqual(model.selectedTab?.document.string(), "")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Previous disk contents")
    }
}
#endif
