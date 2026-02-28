import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: EditorViewModel? {
        didSet {
            guard let viewModel else { return }
            Task { @MainActor in
                self.flushPendingURLs(into: viewModel)
            }
        }
    }
    weak var appUpdateManager: AppUpdateManager?
    private var pendingOpenURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if let existing = WindowViewModelRegistry.shared.viewModel(containing: url) {
                    _ = existing.viewModel.focusTabIfOpen(for: url)
                    if let window = NSApp.window(withWindowNumber: existing.windowNumber) {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    continue
                }
                let target = WindowViewModelRegistry.shared.activeViewModel() ?? self.viewModel
                if let target {
                    target.openFile(url: url)
                } else {
                    self.pendingOpenURLs.append(url)
                }
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return NSApp.windows.isEmpty && pendingOpenURLs.isEmpty
    }

    func applicationWillTerminate(_ notification: Notification) {
        appUpdateManager?.applicationWillTerminate()
    }

    @MainActor
    private func flushPendingURLs(into viewModel: EditorViewModel) {
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        urls.forEach { viewModel.openFile(url: $0) }
    }
}

private struct DetachedWindowContentView: View {
    @State private var viewModel = EditorViewModel()
    @ObservedObject var supportPurchaseManager: SupportPurchaseManager
    @ObservedObject var appUpdateManager: AppUpdateManager
    @Binding var showGrokError: Bool
    @Binding var grokErrorMessage: String

    var body: some View {
        ContentView(startupBehavior: .forceBlankDocument)
            .environment(viewModel)
            .environmentObject(supportPurchaseManager)
            .environmentObject(appUpdateManager)
            .environment(\.showGrokError, $showGrokError)
            .environment(\.grokErrorMessage, $grokErrorMessage)
            .frame(minWidth: 600, minHeight: 400)
    }
}
#endif

@main
struct NeonVisionEditorApp: App {
    @State private var viewModel = EditorViewModel()
    @StateObject private var supportPurchaseManager = SupportPurchaseManager()
    @StateObject private var appUpdateManager = AppUpdateManager()
    @AppStorage("SettingsAppearance") private var appearance: String = "system"
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var useAppleIntelligence: Bool = true
    @State private var appleAIStatus: String = "Apple Intelligence: Checking…"
    @State private var appleAIRoundTripMS: Double? = nil
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    @State private var showGrokError: Bool = false
    @State private var grokErrorMessage: String = ""

    private var preferredAppearance: ColorScheme? {
        ReleaseRuntimePolicy.preferredColorScheme(for: appearance)
    }

#if os(macOS)
    private var appKitAppearance: NSAppearance? {
        switch appearance {
        case "light":
            return NSAppearance(named: .aqua)
        case "dark":
            return NSAppearance(named: .darkAqua)
        default:
            return nil
        }
    }

    private func applyGlobalAppearanceOverride() {
        let override = appKitAppearance
        NSApp.appearance = override
        for window in NSApp.windows {
            window.appearance = override
            window.invalidateShadow()
            window.displayIfNeeded()
        }
    }

    private func applyMacWindowTabbingPolicy() {
        // Use app-native file tab pills only; disable NSWindow tab bar to avoid duplicate tab systems.
        NSWindow.allowsAutomaticWindowTabbing = false
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
        }
        hideNativeTabBarMenuItems()
    }

    private func hideNativeTabBarMenuItems() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let targets = ["Show Tab Bar", "Hide Tab Bar", "Move Tab to New Window", "Merge All Windows"]

        func filter(menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu {
                    filter(menu: submenu)
                }
            }
            menu.items.removeAll { item in
                targets.contains(item.title)
            }
        }

        filter(menu: mainMenu)
    }
#endif

#if os(iOS)
    private var userInterfaceStyle: UIUserInterfaceStyle {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return .unspecified
        }
    }

    private func applyIOSAppearanceOverride() {
        let style = userInterfaceStyle
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
                scene.windows.forEach { window in
                    if window.overrideUserInterfaceStyle != style {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
    }
#endif

    init() {
        let defaults = UserDefaults.standard
        // Default editor behavior:
        // - keep line numbers on
        // - keep style/space visualization toggles off unless user enables them in Settings
        defaults.register(defaults: [
            "SettingsShowLineNumbers": true,
            "SettingsHighlightCurrentLine": false,
            "SettingsHighlightMatchingBrackets": false,
            "SettingsShowScopeGuides": false,
            "SettingsHighlightScopeBackground": false,
            "SettingsLineWrapEnabled": false,
            "SettingsShowInvisibleCharacters": false,
            "SettingsUseSystemFont": false,
            "SettingsIndentStyle": "spaces",
            "SettingsIndentWidth": 4,
            "SettingsAutoIndent": true,
            "SettingsAutoCloseBrackets": false,
            "SettingsTrimTrailingWhitespace": false,
            "SettingsTrimWhitespaceForSyntaxDetection": false,
            "SettingsCompletionEnabled": false,
            "SettingsCompletionFromDocument": false,
            "SettingsCompletionFromSyntax": false,
            "SettingsReopenLastSession": true,
            "SettingsOpenWithBlankDocument": true,
            "SettingsDefaultNewFileLanguage": "plain",
            "SettingsConfirmCloseDirtyTab": true,
            "SettingsConfirmClearEditor": true,
            "SettingsAutoCheckForUpdates": true,
            "SettingsUpdateCheckInterval": AppUpdateCheckInterval.daily.rawValue,
            "SettingsAutoDownloadUpdates": false
        ])
        let vimResetMigrationKey = "SettingsMigrationVimModeResetV1"
        if !defaults.bool(forKey: vimResetMigrationKey) {
            // One-time safety reset: avoid stale NORMAL-mode state making editor appear non-editable.
            defaults.set(false, forKey: "EditorVimModeEnabled")
            defaults.set(true, forKey: vimResetMigrationKey)
        }
        let whitespaceMigrationKey = "SettingsMigrationWhitespaceGlyphResetV1"
        if !defaults.bool(forKey: whitespaceMigrationKey) {
            defaults.set(false, forKey: "SettingsShowInvisibleCharacters")
            defaults.set(false, forKey: "NSShowAllInvisibles")
            defaults.set(false, forKey: "NSShowControlCharacters")
            defaults.set(true, forKey: whitespaceMigrationKey)
        }
    }

#if os(macOS)
    private var activeWindowNumber: Int? {
        NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber
    }

    private var activeEditorViewModel: EditorViewModel {
        WindowViewModelRegistry.shared.activeViewModel() ?? viewModel
    }

    private func postWindowCommand(_ name: Notification.Name, object: Any? = nil) {
        var userInfo: [AnyHashable: Any] = [:]
        if let activeWindowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = activeWindowNumber
        }
        NotificationCenter.default.post(
            name: name,
            object: object,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
#endif

    var body: some Scene {
#if os(macOS)
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environmentObject(supportPurchaseManager)
                .environmentObject(appUpdateManager)
                .onAppear {
                    appDelegate.viewModel = viewModel
                    appDelegate.appUpdateManager = appUpdateManager
                }
                .onAppear { applyGlobalAppearanceOverride() }
                .onAppear { applyMacWindowTabbingPolicy() }
                .onChange(of: appearance) { _, _ in applyGlobalAppearanceOverride() }
                .environment(\.showGrokError, $showGrokError)
                .environment(\.grokErrorMessage, $grokErrorMessage)
                .tint(.blue)
                .preferredColorScheme(preferredAppearance)
                .frame(minWidth: 600, minHeight: 400)
                .task {
                    if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
                        appUpdateManager.startAutomaticChecks()
                    }
                    #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                    do {
                        let start = Date()
                        _ = try await AppleFM.appleFMHealthCheck()
                        let end = Date()
                        appleAIStatus = "Apple Intelligence: Ready"
                        appleAIRoundTripMS = end.timeIntervalSince(start) * 1000.0
                        AIActivityLog.record(
                            "Startup AI health check succeeded (\(String(format: "%.1f", appleAIRoundTripMS ?? 0)) ms).",
                            source: "Startup"
                        )
                    } catch {
                        appleAIStatus = "Apple Intelligence: Error — \(error.localizedDescription)"
                        appleAIRoundTripMS = nil
                        AIActivityLog.record(
                            "Startup AI health check failed: \(error.localizedDescription)",
                            level: .error,
                            source: "Startup"
                        )
                    }
                    #else
                    appleAIStatus = "Apple Intelligence: Unavailable (build without USE_FOUNDATION_MODELS)"
                    AIActivityLog.record(
                        "Startup AI health check unavailable (built without USE_FOUNDATION_MODELS).",
                        level: .warning,
                        source: "Startup"
                    )
                    #endif
                }
        }
        .defaultSize(width: 1000, height: 600)
        .handlesExternalEvents(matching: ["*"])

        WindowGroup("New Window", id: "blank-window") {
            DetachedWindowContentView(
                supportPurchaseManager: supportPurchaseManager,
                appUpdateManager: appUpdateManager,
                showGrokError: $showGrokError,
                grokErrorMessage: $grokErrorMessage
            )
            .onAppear { applyGlobalAppearanceOverride() }
            .onAppear { applyMacWindowTabbingPolicy() }
            .onChange(of: appearance) { _, _ in applyGlobalAppearanceOverride() }
            .tint(.blue)
            .preferredColorScheme(preferredAppearance)
        }
        .defaultSize(width: 1000, height: 600)
        .handlesExternalEvents(matching: [])

        Settings {
            NeonSettingsView(
                supportsOpenInTabs: false,
                supportsTranslucency: true
            )
                .environmentObject(supportPurchaseManager)
                .environmentObject(appUpdateManager)
                .onAppear { applyGlobalAppearanceOverride() }
                .onAppear { applyMacWindowTabbingPolicy() }
                .onChange(of: appearance) { _, _ in applyGlobalAppearanceOverride() }
                .tint(.blue)
                .preferredColorScheme(preferredAppearance)
        }

        Window("AI Activity Log", id: "ai-logs") {
            AIActivityLogView()
                .frame(minWidth: 720, minHeight: 420)
                .preferredColorScheme(preferredAppearance)
                .tint(.blue)
        }
        .defaultSize(width: 860, height: 520)
        .handlesExternalEvents(matching: [])

        MenuBarExtra("Welcome Tour", systemImage: "sparkles.rectangle.stack") {
            Button {
                postWindowCommand(.showWelcomeTourRequested)
            } label: {
                Label("Show Welcome Tour", systemImage: "sparkles.rectangle.stack")
            }

            Divider()

            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }

            if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
                Button {
                    postWindowCommand(.showUpdaterRequested, object: true)
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath.circle")
                }
            }
        }

        .commands {
            NeonVisionMacAppCommands(
                activeEditorViewModel: { activeEditorViewModel },
                openNewWindow: { openWindow(id: "blank-window") },
                openAIDiagnosticsWindow: { openWindow(id: "ai-logs") },
                postWindowCommand: { name, object in
                    postWindowCommand(name, object: object)
                },
                isUpdaterEnabled: ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution,
                useAppleIntelligence: $useAppleIntelligence,
                appleAIStatus: $appleAIStatus,
                appleAIRoundTripMS: $appleAIRoundTripMS,
                showGrokError: $showGrokError,
                grokErrorMessage: $grokErrorMessage
            )
        }
#else
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environmentObject(supportPurchaseManager)
                .environmentObject(appUpdateManager)
                .environment(\.showGrokError, $showGrokError)
                .environment(\.grokErrorMessage, $grokErrorMessage)
                .tint(.blue)
                .onAppear { applyIOSAppearanceOverride() }
                .onChange(of: appearance) { _, _ in applyIOSAppearanceOverride() }
                .preferredColorScheme(preferredAppearance)
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    UIApplication.shared.sendAction(Selector(("undo:")), to: nil, from: nil, for: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    UIApplication.shared.sendAction(Selector(("redo:")), to: nil, from: nil, for: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
#endif
    }

}

struct ShowGrokErrorKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

struct GrokErrorMessageKey: EnvironmentKey {
    static let defaultValue: Binding<String> = .constant("")
}

extension EnvironmentValues {
    var showGrokError: Binding<Bool> {
        get { self[ShowGrokErrorKey.self] }
        set { self[ShowGrokErrorKey.self] = newValue }
    }

    var grokErrorMessage: Binding<String> {
        get { self[GrokErrorMessageKey.self] }
        set { self[GrokErrorMessageKey.self] = newValue }
    }
}
