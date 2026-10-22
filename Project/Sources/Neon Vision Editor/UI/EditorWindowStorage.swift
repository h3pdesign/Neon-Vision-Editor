import SwiftUI
import Observation

struct EditorDocumentSelectionContext: Equatable {
    let owner: ObjectIdentifier
    let tabID: UUID?
}

struct EditorDocumentFileContext: Equatable {
    let owner: ObjectIdentifier
    let fileURL: URL?
}

/// Document presentation values outlive a physical SwiftUI editor surface.
/// Bindings capture a typed box, never a mutable "current document" pointer.
#if os(macOS)
@MainActor
final class EditorDocumentPresentationState {
    @Observable
    final class ValueBox<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private var values: [String: Any] = [:]

    func box<Value>(for key: String, initialValue: @autoclosure () -> Value) -> ValueBox<Value> {
        if let existing = values[key] {
            guard let box = existing as? ValueBox<Value> else {
                preconditionFailure("Document presentation key reused with a different type")
            }
            return box
        }
        let box = ValueBox(initialValue())
        values[key] = box
        return box
    }
}

private struct EditorDocumentPresentationKey: EnvironmentKey {
    static let defaultValue: EditorDocumentPresentationState? = nil
}

extension EnvironmentValues {
    var editorDocumentPresentation: EditorDocumentPresentationState? {
        get { self[EditorDocumentPresentationKey.self] }
        set { self[EditorDocumentPresentationKey.self] = newValue }
    }
}

/// A surface may change documents, but callbacks already issued by that surface
/// must continue to address the document that created them.
@propertyWrapper
struct EditorDocumentState<Value>: DynamicProperty {
    @Environment(\.editorDocumentPresentation) private var presentation
    @State private var fallback: Value
    private let key: String
    private let initialValue: Value
    private var installedBox: EditorDocumentPresentationState.ValueBox<Value>?

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.initialValue = wrappedValue
        _fallback = State(initialValue: wrappedValue)
    }

    init(_ key: String) where Value: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil, key)
    }

    mutating func update() {
        installedBox = presentation?.box(for: key, initialValue: initialValue)
    }

    var wrappedValue: Value {
        get {
            if let installedBox { return installedBox.value }
            return fallback
        }
        nonmutating set {
            if let installedBox { installedBox.value = newValue }
            else { fallback = newValue }
        }
    }

    var projectedValue: Binding<Value> {
        if let installedBox {
            return Binding(get: { installedBox.value }, set: { installedBox.value = $0 })
        }
        return $fallback
    }
}

@propertyWrapper
struct EditorDocumentModel: DynamicProperty {
    @Environment(EditorViewModel.self) private var environmentModel
    private var installedModel: EditorViewModel?
    mutating func update() { installedModel = environmentModel }
    var wrappedValue: EditorViewModel { installedModel ?? environmentModel }
}
#else
// Mobile retains its existing State storage and update cost. Only AppKit moves
// a rendering surface between independently owned document windows.
typealias EditorDocumentState<Value> = State<Value>
extension State {
    init(wrappedValue: Value, _ key: String) {
        self.init(wrappedValue: wrappedValue)
    }
    init(_ key: String) where Value: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil)
    }
}
#endif

#if os(macOS)
private struct EditorSceneStorageKey: EnvironmentKey {
    static let defaultValue: EditorSceneStorageBindings? = nil
}

extension EnvironmentValues {
    fileprivate var editorSceneStorage: EditorSceneStorageBindings? {
        get { self[EditorSceneStorageKey.self] }
        set { self[EditorSceneStorageKey.self] = newValue }
    }
}

fileprivate struct EditorSceneStorageBindings {
    let values: [String: Any]
    func binding<Value>(for key: String) -> Binding<Value>? {
        values[key] as? Binding<Value>
    }
}

/// Install only at a SwiftUI WindowGroup boundary, never in an NSHostingView.
struct EditorSceneStorageModifier: ViewModifier {
    @SceneStorage("ProjectSidebarWidth") private var sidebarWidth = 450.0
    @SceneStorage("ProjectSidebarMode") private var sidebarMode = "project"
    @SceneStorage("EditorFocusModeEnabled") private var focusMode = false
    @SceneStorage("TOCSidebarWidth") private var tocWidth = 250.0
    @SceneStorage("PreviewPaneWidthV3") private var previewWidth = 0.0
    @SceneStorage("MarkdownProjectPreviewWidthV1") private var cardsWidth = 500.0
    @SceneStorage("ProjectSidebarExpandedDirectories.v1") private var expansion = ""

    func body(content: Content) -> some View {
        content.environment(\.editorSceneStorage, EditorSceneStorageBindings(values: [
            "ProjectSidebarWidth": $sidebarWidth,
            "ProjectSidebarMode": $sidebarMode,
            "EditorFocusModeEnabled": $focusMode,
            "TOCSidebarWidth": $tocWidth,
            "PreviewPaneWidthV3": $previewWidth,
            "MarkdownProjectPreviewWidthV1": $cardsWidth,
            "ProjectSidebarExpandedDirectories.v1": $expansion
        ]))
    }
}
#endif

/// Scene restoration belongs to SwiftUI-managed scenes. An AppKit-owned
/// document host instead keeps these values for the lifetime of its view.
@propertyWrapper
struct EditorWindowStorage<Value>: DynamicProperty {
#if os(macOS)
    @Environment(\.editorSceneStorage) private var sceneBindings
    private let key: String
#else
    @SceneStorage private var sceneValue: Value
#endif
    @EditorDocumentState private var windowValue: Value

    init(wrappedValue: Value, _ key: String) where Value == Bool {
#if os(macOS)
        self.key = key
#else
        _sceneValue = SceneStorage(wrappedValue: wrappedValue, key)
#endif
        _windowValue = EditorDocumentState(wrappedValue: wrappedValue, "window:" + key)
    }

    init(wrappedValue: Value, _ key: String) where Value == Double {
#if os(macOS)
        self.key = key
#else
        _sceneValue = SceneStorage(wrappedValue: wrappedValue, key)
#endif
        _windowValue = EditorDocumentState(wrappedValue: wrappedValue, "window:" + key)
    }

    init(wrappedValue: Value, _ key: String) where Value == String {
#if os(macOS)
        self.key = key
#else
        _sceneValue = SceneStorage(wrappedValue: wrappedValue, key)
#endif
        _windowValue = EditorDocumentState(wrappedValue: wrappedValue, "window:" + key)
    }

    var wrappedValue: Value {
        get {
#if os(macOS)
            let binding: Binding<Value>? = sceneBindings?.binding(for: key)
            return binding?.wrappedValue ?? windowValue
#else
            return sceneValue
#endif
        }
        nonmutating set {
#if os(macOS)
            if let binding: Binding<Value> = sceneBindings?.binding(for: key) {
                binding.wrappedValue = newValue
            } else {
                windowValue = newValue
            }
#else
            sceneValue = newValue
#endif
        }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
