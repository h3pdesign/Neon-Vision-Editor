#if os(macOS)
import AppKit

/// A launch-scoped preference: changing Settings never converts live documents.
@MainActor
enum MacDocumentTabPolicy {
    static let preferenceKey = "SettingsNativeDocumentTabsMac"
    static let enabledForLaunch = UserDefaults.standard.bool(forKey: preferenceKey)
    static let tabbingIdentifier = "NeonVisionEditor.NativeDocuments"
}

/// Native tabs group windows, not editor buffers. A destination model is created
/// before opening a file so asynchronous loads/saves never change document owner.
@MainActor
final class MacDocumentWindowTabs {
    static let shared = MacDocumentWindowTabs()

    private struct Entry {
        weak var model: EditorViewModel?
        weak var window: NSWindow?
        let openWindow: (UUID) -> Void
        let persistDrafts: () -> Void
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
    private var selectionToReveal: ObjectIdentifier?
    private weak var activeNativeWindow: NSWindow?
    private(set) var isTerminating = false

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
        models.first { ObjectIdentifier($0) == selectionToReveal }
    }

    func takePendingModel(for id: UUID) -> EditorViewModel? {
        guard let item = pending[id] else { return nil }
        if let parent = item.parent { parents[ObjectIdentifier(item.model)] = Parent(parent) }
        return item.model
    }

    func noteBecameKey(_ model: EditorViewModel) {
        activeNativeWindow = entries[ObjectIdentifier(model)]?.window
    }

    /// SwiftUI's value-based WindowGroup creates a nil-value scene when AppKit
    /// invokes `newWindowForTab:` from its native tab-bar plus button. Assign a
    /// pending owner to that already-created scene so it joins the source group
    /// instead of leaving an empty standalone window behind.
    func prepareNativeTabScene() -> UUID? {
        guard let parent = activeNativeWindow,
              entries.values.contains(where: { $0.window === parent }) else { return nil }
        let model = EditorViewModel(usesNativeDocumentTabs: true)
        let id = UUID()
        pending[id] = Pending(model: model, parent: parent)
        order.append(ObjectIdentifier(model))
        selectionToReveal = ObjectIdentifier(model)
        return id
    }

    func register(_ model: EditorViewModel, window: NSWindow,
                  persistDrafts: @escaping () -> Void = {}, openWindow: @escaping (UUID) -> Void) {
        guard model.usesNativeDocumentTabs else { return }
        let identity = ObjectIdentifier(model)
        let wasPending = pending.values.contains { $0.model === model }
        if !order.contains(identity) { order.append(identity) }
        pending = pending.filter { $0.value.model !== model }
        entries[ObjectIdentifier(model)] = Entry(model: model, window: window,
                                                openWindow: openWindow, persistDrafts: persistDrafts)
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
            parent.addTabbedWindow(window, ordered: .above)
        }
        if wasPending, pending.isEmpty, let selectionToReveal,
           let selectedWindow = entries[selectionToReveal]?.window {
            selectedWindow.makeKeyAndOrderFront(nil)
        }
    }

    func unregister(_ model: EditorViewModel) {
        guard !isTerminating else { return }
        entries.removeValue(forKey: ObjectIdentifier(model))
        parents.removeValue(forKey: ObjectIdentifier(model))
        order.removeAll { $0 == ObjectIdentifier(model) }
        model.nativeDocumentDestination = nil
        model.nativeFocusFile = nil
        model.nativeRevealWindow = nil
    }

    func beginTermination() {
        guard !isTerminating else { return }
        entries.values.first?.persistDrafts()
        isTerminating = true
    }

    func models(inGroupOf source: EditorViewModel) -> [EditorViewModel] {
        guard let window = entries[ObjectIdentifier(source)]?.window else { return [source] }
        let windows = window.tabbedWindows ?? [window]
        return windows.compactMap { candidate in
            entries.values.first { $0.window === candidate }?.model
        }
    }

    private func destination(from source: EditorViewModel, url: URL?, reuseBlank: Bool) -> EditorViewModel? {
        guard let entry = entries[ObjectIdentifier(source)] else { return nil }
        if reuseBlank, source.canReuseNativeBlankDocument { return nil }
        let model = EditorViewModel(usesNativeDocumentTabs: true)
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
        entry.openWindow(id)
        return model
    }

    private func focusFile(_ url: URL, excluding source: EditorViewModel) -> Bool {
        for model in models where model !== source && model.hasOpenFile(url: url) {
            let window = entries[ObjectIdentifier(model)]?.window
            if UserDefaults.standard.bool(forKey: "SettingsOpenFilesOnCurrentDesktop"),
               let window, !window.isOnActiveSpace { continue }
            _ = model.focusTabIfOpen(for: url)
            reveal(model)
            return true
        }
        return false
    }

    private func reveal(_ model: EditorViewModel) {
        selectionToReveal = ObjectIdentifier(model)
        entries[ObjectIdentifier(model)]?.window?.makeKeyAndOrderFront(nil)
    }
}
#endif
