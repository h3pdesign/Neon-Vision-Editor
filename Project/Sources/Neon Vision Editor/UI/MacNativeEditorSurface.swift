#if os(macOS)
import AppKit
import SwiftUI

@MainActor
struct NativeEditorSurfaceConfiguration {
    let model: EditorViewModel
    let startupBehavior: ContentView.StartupBehavior
    let safeModeMessage: String?
    let frameAutosaveName: String?
    let initialLayout: String?
    let support: SupportPurchaseManager
    let updates: AppUpdateManager
    let showGrokError: Binding<Bool>
    let grokErrorMessage: Binding<String>
    let actions: NativeEditorWindowActions
}

/// A document retains its rendering graph after first selection. Tab selection
/// must not move the graph or substitute another document's environment.
@MainActor
final class NativeEditorSurfaceGroup {
    private var host: NSHostingView<NativeEditorSurfaceRoot>?
    private weak var activeModel: EditorViewModel?
    var hostedView: NSView? { host }

    func install(_ configuration: NativeEditorSurfaceConfiguration, in surface: NativeEditorSurfaceView,
                 window: NSWindow? = nil) {
        if host?.superview === surface, activeModel === configuration.model { return }
        if let current = host?.superview, current !== surface,
           current.window?.attachedSheet != nil { return }
        // Local SwiftUI state belongs to this permanent document host. Never
        // substitute another document's environment into its existing graph.
        precondition(activeModel == nil || activeModel === configuration.model)
        if let host, host.superview !== surface {
            host.removeFromSuperview()
        }
        activeModel = configuration.model
        let host: NSHostingView<NativeEditorSurfaceRoot>
        if let existing = self.host {
            host = existing
            host.rootView = NativeEditorSurfaceRoot(configuration: configuration)
        } else {
            host = NSHostingView(rootView: NativeEditorSurfaceRoot(configuration: configuration))
            host.sizingOptions = []
            // The enclosing SwiftUI scene (primary) or AppKit coordinator (child)
            // owns window presentation. A nested document host must not install
            // a second window-presentation bridge on the same physical window.
            host.sceneBridgingOptions = []
            self.host = host
        }
        if let window = window ?? surface.window,
           MacDocumentWindowTabs.shared.installRootEditorHost(host, for: configuration.model, in: window) {
            return
        }
        if host.superview !== surface {
            host.removeFromSuperview()
            host.frame = surface.bounds
            host.autoresizingMask = [.width, .height]
            surface.addSubview(host)
        }
    }
}

@MainActor
private struct NativeEditorSurfaceRoot: View {
    let configuration: NativeEditorSurfaceConfiguration
    @AppStorage("SettingsAppearance") private var appearance = "system"
    @AppStorage("SettingsAppLanguageCode") private var languageCode = "system"

    var body: some View {
        ContentView(startupBehavior: configuration.startupBehavior,
            safeModeMessage: configuration.safeModeMessage,
            windowFrameAutosaveName: configuration.frameAutosaveName,
            initialEditorLayoutPresetRawValue: configuration.initialLayout,
            markdownProjectPreviewSession: MacDocumentWindowTabs.shared.projectPreviewSession(for: configuration.model))
            .environment(configuration.model)
            .environment(\.editorDocumentPresentation, MacDocumentWindowTabs.shared.presentationState(for: configuration.model))
            .environmentObject(configuration.support)
            .environmentObject(configuration.updates)
            .environment(\.showGrokError, configuration.showGrokError)
            .environment(\.grokErrorMessage, configuration.grokErrorMessage)
            .environment(\.nativeEditorWindowActions, configuration.actions)
            .environment(\.locale, languageCode == "system" ? .autoupdatingCurrent : Locale(identifier: languageCode))
            .navigationTitle(MacDocumentTabPolicy.windowTitle(for: configuration.model))
            .preferredColorScheme(ReleaseRuntimePolicy.preferredColorScheme(for: appearance))
            .tint(.blue)
    }
}

@MainActor
final class NativeEditorSurfaceView: NSView {
    var configuration: NativeEditorSurfaceConfiguration
    private var selection: NSKeyValueObservation?
    private var group: NSKeyValueObservation?
    private weak var installedGroup: NativeEditorSurfaceGroup?

    init(configuration: NativeEditorSurfaceConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    func installAsWindowRoot(in window: NSWindow) -> Bool {
        let target = MacDocumentWindowTabs.shared.editorSurfaceGroup(for: configuration.model, window: window)
        target.install(configuration, in: self, window: window)
        return window.contentView === target.hostedView
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let newWindow { MacDocumentTabPolicy.configureWindowChrome(newWindow) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        selection = nil
        group = nil
        guard let window else { return }
        group = window.observe(\.tabGroup, options: [.initial, .new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                self?.selection = window.tabGroup?.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.activateIfSelected() }
                }
                self?.activateIfSelected()
            }
        }
    }

    func activateIfSelected() {
        if let window { MacDocumentWindowTabs.shared.updateInactiveTabContent(around: window) }
        guard let window,
              window.tabGroup == nil || window.tabGroup?.selectedWindow === window else { return }
        let target = MacDocumentWindowTabs.shared.editorSurfaceGroup(for: configuration.model, window: window)
        if installedGroup !== target {
            subviews.forEach { $0.removeFromSuperview() }
            installedGroup = target
        }
        target.install(configuration, in: self)
        if window.isKeyWindow { MacDocumentWindowTabs.shared.noteBecameKey(configuration.model) }
    }
}

/// A native document editor is a window-root surface on every creation path.
/// AppKit-created tabs install its host as `window.contentView`, spanning the
/// full-size content area under the unified toolbar. A SwiftUI scene otherwise
/// lays this representable out inside its titlebar-inset safe area, so the first
/// window's editor (and its backdrop) started below the toolbar while every
/// later tab's started at the window top. Ignoring the container safe area gives
/// scene-created windows the same frame; the hosted editor then derives the
/// toolbar inset from AppKit exactly as the root-installed tabs do.
struct NativeEditorSurface: View {
    let configuration: NativeEditorSurfaceConfiguration
    var body: some View {
        NativeEditorSurfaceRepresentable(configuration: configuration)
            .ignoresSafeArea(.container)
    }
}

private struct NativeEditorSurfaceRepresentable: NSViewRepresentable {
    let configuration: NativeEditorSurfaceConfiguration
    func makeNSView(context: Context) -> NativeEditorSurfaceView {
        NativeEditorSurfaceView(configuration: configuration)
    }
    func updateNSView(_ view: NativeEditorSurfaceView, context: Context) {
        view.configuration = configuration
        view.activateIfSelected()
    }
}
#endif
