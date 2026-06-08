import SwiftUI
import ObjectiveC.runtime
import Synchronization
#if canImport(FoundationModels)
import FoundationModels
#endif
#if os(macOS)
import AppKit
#endif
#if os(iOS) || os(visionOS)
import UIKit
#endif

// MARK: - Runtime Language Override

nonisolated(unsafe) private var runtimeLanguageBundleAssociationKey: UInt8 = 0

private final class RuntimeLanguageBundle: Bundle, @unchecked Sendable {
    nonisolated override init?(path: String) {
        super.init(path: path)
    }

    nonisolated override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let languageBundle = objc_getAssociatedObject(self, &runtimeLanguageBundleAssociationKey) as? Bundle {
            return languageBundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

private enum RuntimeLanguageOverride {
    nonisolated private static let didInstallBundleOverride = Mutex(false)

    static func apply(languageCode: String) {
        installBundleOverrideIfNeeded()
        let bundle = languageBundle(for: languageCode)
        objc_setAssociatedObject(
            Bundle.main,
            &runtimeLanguageBundleAssociationKey,
            bundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private static func installBundleOverrideIfNeeded() {
        didInstallBundleOverride.withLock { didInstallBundleOverride in
            guard !didInstallBundleOverride else { return }
            object_setClass(Bundle.main, RuntimeLanguageBundle.self)
            didInstallBundleOverride = true
        }
    }

    private static func languageBundle(for languageCode: String) -> Bundle? {
        guard languageCode != "system" else { return nil }
        if let exact = Bundle.main.path(forResource: languageCode, ofType: "lproj").flatMap(Bundle.init(path:)) {
            return exact
        }
        let fallbackCode = languageCode.split(separator: "-").first.map(String.init) ?? languageCode
        return Bundle.main.path(forResource: fallbackCode, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

#if os(macOS)
// MARK: - macOS App Delegate

@MainActor
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
                if ShareImportHandoff.isShareImportURL(url) {
                    NotificationCenter.default.post(name: .sharedImportURLRequested, object: url)
                    continue
                }
                let importURLs = ShareImportHandoff.importedFileURLs(from: url)
                if !importURLs.isEmpty {
                    SharedImportStore.remember(importURLs)
                    guard UserDefaults.standard.object(forKey: "SettingsShareImportsAutoOpen") as? Bool ?? true else {
                        continue
                    }
                }
                let fileURLs = importURLs.isEmpty ? [url] : importURLs
                for fileURL in fileURLs {
                if let existing = WindowViewModelRegistry.shared.viewModel(containing: fileURL) {
                    _ = existing.viewModel.focusTabIfOpen(for: fileURL)
                    if let window = NSApp.window(withWindowNumber: existing.windowNumber) {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    continue
                }
                let target = WindowViewModelRegistry.shared.activeViewModel() ?? self.viewModel
                if let target {
                    if target.openFile(url: fileURL) {
                        self.bringEditorWindowToFront(for: target)
                    }
                } else {
                    self.pendingOpenURLs.append(fileURL)
                }
                }
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return NSApp.windows.isEmpty && pendingOpenURLs.isEmpty
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard hasVisibleWindows else { return true }
        if let key = sender.keyWindow {
            key.makeKeyAndOrderFront(nil)
        } else if let main = sender.mainWindow {
            main.makeKeyAndOrderFront(nil)
        } else if let first = sender.windows.first(where: { $0.isVisible && !$0.isMiniaturized }) {
            first.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appUpdateManager?.applicationWillTerminate()
        RuntimeReliabilityMonitor.shared.markGracefulTermination()
    }

    @MainActor
    private func flushPendingURLs(into viewModel: EditorViewModel) {
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        let didOpenFile = urls.reduce(false) { didOpen, url in
            let opened = viewModel.openFile(url: url)
            return didOpen || opened
        }
        if didOpenFile {
            bringEditorWindowToFront(for: viewModel)
        }
    }

    @MainActor
    private func bringEditorWindowToFront(for viewModel: EditorViewModel) {
        let registeredWindow = WindowViewModelRegistry.shared.windowNumber(for: viewModel)
            .flatMap { NSApp.window(withWindowNumber: $0) }
        let fallbackWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { window in
            window.isVisible && !window.isMiniaturized
        }
        if let window = registeredWindow ?? fallbackWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
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

private struct FocusModeContentView: View {
    @State private var viewModel = EditorViewModel()
    @ObservedObject var supportPurchaseManager: SupportPurchaseManager
    @ObservedObject var appUpdateManager: AppUpdateManager
    @Binding var showGrokError: Bool
    @Binding var grokErrorMessage: String

    var body: some View {
        FocusModeView(viewModel: viewModel)
            .environmentObject(supportPurchaseManager)
            .environmentObject(appUpdateManager)
            .environment(\.showGrokError, $showGrokError)
            .environment(\.grokErrorMessage, $grokErrorMessage)
            .frame(minWidth: 500, minHeight: 300)
    }
}

private struct FocusModeView: View {
    @State var viewModel: EditorViewModel
    @AppStorage("SettingsEditorFontSize") private var editorFontSize: Double = 14
    @AppStorage("SettingsEditorFontName") private var editorFontName: String = ""
    @AppStorage("SettingsShowLineNumbers") private var showLineNumbers: Bool = true
    @AppStorage("SettingsLineWrapEnabled") private var settingsLineWrapEnabled: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Focus Mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let tab = viewModel.selectedTab {
                    Text(tab.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            ContentView(startupBehavior: .forceBlankDocument)
                .environment(viewModel)
                .toolbar(.hidden)
        }
    }
}
#endif

// MARK: - App Entry Point

@main
struct NeonVisionEditorApp: App {
    @State private var viewModel = EditorViewModel()
    @StateObject private var supportPurchaseManager = SupportPurchaseManager()
    @StateObject private var appUpdateManager = AppUpdateManager()
    @AppStorage("SettingsAppearance") private var appearance: String = "system"
    @AppStorage("SettingsAppLanguageCode") private var appLanguageCode: String = "system"
    @Environment(\.scenePhase) private var scenePhase
    private let mainStartupBehavior: ContentView.StartupBehavior
    private let startupSafeModeMessage: String?
    @State private var didMarkLaunchCompleted: Bool = false
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var useAppleIntelligence: Bool = true
    @State private var appleAIStatus: String = "Apple Intelligence: Checking…"
    @State private var appleAIRoundTripMS: Double? = nil
    @State private var macWindowChromePolicyPending: Bool = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    @State private var showGrokError: Bool = false
    @State private var grokErrorMessage: String = ""

    // MARK: - Appearance and Startup Helpers

    private var preferredAppearance: ColorScheme? {
        ReleaseRuntimePolicy.preferredColorScheme(for: appearance)
    }

    private var preferredLocale: Locale {
        appLanguageCode == "system"
            ? .autoupdatingCurrent
            : Locale(identifier: appLanguageCode)
    }

    private func applyRuntimeLanguageOverride() {
        RuntimeLanguageOverride.apply(languageCode: appLanguageCode)
    }

    private func completeLaunchReliabilityTrackingIfNeeded() {
        guard !didMarkLaunchCompleted else { return }
        didMarkLaunchCompleted = true
        RuntimeReliabilityMonitor.shared.markLaunchCompleted()
    }

    private func markLaunchCompletedAfterStableWindowDelay() async {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled else { return }
        completeLaunchReliabilityTrackingIfNeeded()
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
        }
    }

    private func scheduleMacWindowChromePolicy() {
        RuntimeReliabilityMonitor.shared.markLaunchPhase(.windowSceneAppeared)
        guard !macWindowChromePolicyPending else { return }
        macWindowChromePolicyPending = true
        DispatchQueue.main.async {
            RuntimeReliabilityMonitor.shared.markLaunchPhase(.windowChromeScheduled)
            applyGlobalAppearanceOverride()
            applyMacWindowTabbingPolicy()
            macWindowChromePolicyPending = false
        }
    }

    private func runDeferredMacStartupDiagnostics() async {
        guard mainStartupBehavior != .safeMode else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled else { return }
        RuntimeReliabilityMonitor.shared.markLaunchPhase(.startupDiagnosticsStarted)
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
            appleAIStatus = "Apple Intelligence: Error - \(error.localizedDescription)"
            appleAIRoundTripMS = nil
            AIActivityLog.record(
                "Startup AI health check failed.",
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

#if os(iOS) || os(visionOS)
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
        let launchCountKey = "AppLaunchCountV1"
        defaults.set(defaults.integer(forKey: launchCountKey) + 1, forKey: launchCountKey)
        // Default editor behavior:
        // - keep line numbers on
        // - keep style/space visualization toggles off unless user enables them in Settings
        defaults.register(defaults: [
            "SettingsShowLineNumbers": true,
            "SettingsHighlightCurrentLine": false,
            "SettingsHighlightMatchingBrackets": false,
            "SettingsShowScopeGuides": false,
            "SettingsHighlightScopeBackground": false,
            "SettingsShowCodeMinimap": false,
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
            "SettingsOpenWithBlankDocument": false,
            "SettingsShareImportsAutoOpen": true,
            "SettingsAppLanguageCode": "system",
            "SettingsDefaultNewFileLanguage": "plain",
            "SettingsConfirmCloseDirtyTab": true,
            "SettingsConfirmClearEditor": true,
            "SettingsRemoteSessionsEnabled": false,
            "SettingsRemoteHost": "",
            "SettingsRemoteUsername": "",
            "SettingsRemotePort": 22,
            "SettingsRemotePreparedTarget": "",
            "SettingsAutoCheckForUpdates": true,
            "SettingsUpdateCheckInterval": AppUpdateCheckInterval.daily.rawValue,
            "SettingsAutoDownloadUpdates": false,
            AppearanceThemeCloudSync.enabledKey: false
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
        RuntimeReliabilityMonitor.shared.markLaunch()
        let safeModeDecision = RuntimeReliabilityMonitor.shared.consumeSafeModeLaunchDecision()
        self.mainStartupBehavior = safeModeDecision.isEnabled ? .safeMode : .standard
        self.startupSafeModeMessage = safeModeDecision.message
        RuntimeReliabilityMonitor.shared.startMainThreadWatchdog()
        EditorPerformanceMonitor.shared.markLaunchConfigured()
        RuntimeLanguageOverride.apply(
            languageCode: defaults.string(forKey: "SettingsAppLanguageCode") ?? "system"
        )
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

    // MARK: - Scene Definition

    var body: some Scene {
#if os(macOS)
        WindowGroup {
            ContentView(
                startupBehavior: mainStartupBehavior,
                safeModeMessage: startupSafeModeMessage
            )
                .environment(viewModel)
                .environmentObject(supportPurchaseManager)
                .environmentObject(appUpdateManager)
                .onAppear {
                    appDelegate.viewModel = viewModel
                    appDelegate.appUpdateManager = appUpdateManager
                }
                .onAppear { _ = AppearanceThemeCloudSync.syncIfEnabled() }
                .onAppear { scheduleMacWindowChromePolicy() }
                .onChange(of: appearance) { _, _ in applyGlobalAppearanceOverride() }
                .onAppear { applyRuntimeLanguageOverride() }
                .onChange(of: appLanguageCode) { _, _ in applyRuntimeLanguageOverride() }
                .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                    if AppearanceThemeCloudSync.syncIfEnabled()?.didApplyRemoteSettings == true {
                        applyGlobalAppearanceOverride()
                    }
                }
                .environment(\.showGrokError, $showGrokError)
                .environment(\.grokErrorMessage, $grokErrorMessage)
                .environment(\.locale, preferredLocale)
                .tint(.blue)
                .preferredColorScheme(preferredAppearance)
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await markLaunchCompletedAfterStableWindowDelay()
                    }
                    if AppearanceThemeCloudSync.syncIfEnabled()?.didApplyRemoteSettings == true {
                        applyGlobalAppearanceOverride()
                    }
                }
                .frame(minWidth: 600, minHeight: 400)
                .task {
                    async let stableLaunchMarker: Void = markLaunchCompletedAfterStableWindowDelay()
                    async let diagnostics: Void = runDeferredMacStartupDiagnostics()
                    _ = await (stableLaunchMarker, diagnostics)
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
            .onAppear { _ = AppearanceThemeCloudSync.syncIfEnabled() }
            .onAppear { scheduleMacWindowChromePolicy() }
            .onChange(of: appearance) { _, _ in applyGlobalAppearanceOverride() }
            .onAppear { applyRuntimeLanguageOverride() }
            .onChange(of: appLanguageCode) { _, _ in applyRuntimeLanguageOverride() }
            .environment(\.locale, preferredLocale)
            .tint(.blue)
            .preferredColorScheme(preferredAppearance)
        }
        .defaultSize(width: 1000, height: 600)
        .handlesExternalEvents(matching: [])

        WindowGroup("Focus Mode", id: "focus-mode") {
            FocusModeContentView(
                supportPurchaseManager: supportPurchaseManager,
                appUpdateManager: appUpdateManager,
                showGrokError: $showGrokError,
                grokErrorMessage: $grokErrorMessage
            )
            .onAppear { _ = AppearanceThemeCloudSync.syncIfEnabled() }
            .onAppear { scheduleMacWindowChromePolicy() }
            .onChange(of: appearance) { _, _ in applyGlobalAppearanceOverride() }
            .onAppear { applyRuntimeLanguageOverride() }
            .onChange(of: appLanguageCode) { _, _ in applyRuntimeLanguageOverride() }
            .environment(\.locale, preferredLocale)
            .tint(.blue)
            .preferredColorScheme(preferredAppearance)
        }
        .defaultSize(width: 900, height: 600)
        .handlesExternalEvents(matching: [])

        Settings {
            ConfiguredSettingsView(
                supportsOpenInTabs: false,
                supportsTranslucency: true,
                editorViewModel: activeEditorViewModel,
                supportPurchaseManager: supportPurchaseManager,
                appUpdateManager: appUpdateManager
            )
                .onAppear { _ = AppearanceThemeCloudSync.syncIfEnabled() }
                .onAppear { scheduleMacWindowChromePolicy() }
                .onChange(of: appearance) { _, _ in applyGlobalAppearanceOverride() }
                .onAppear { applyRuntimeLanguageOverride() }
                .onChange(of: appLanguageCode) { _, _ in applyRuntimeLanguageOverride() }
                .environment(\.locale, preferredLocale)
                .tint(.blue)
                .preferredColorScheme(preferredAppearance)
        }

        Window("AI Activity Log", id: "ai-logs") {
            AIActivityLogView()
                .frame(minWidth: 720, minHeight: 420)
                .onAppear { applyRuntimeLanguageOverride() }
                .onChange(of: appLanguageCode) { _, _ in applyRuntimeLanguageOverride() }
                .environment(\.locale, preferredLocale)
                .preferredColorScheme(preferredAppearance)
                .tint(.blue)
        }
        .defaultSize(width: 860, height: 520)
        .handlesExternalEvents(matching: [])

        MenuBarExtra("Welcome Tour", systemImage: "chevron.left.forwardslash.chevron.right") {
            Button {
                postWindowCommand(.showWelcomeTourRequested)
            } label: {
                Label("Show Welcome Tour", systemImage: "sparkles.rectangle.stack")
            }

            Button {
                postWindowCommand(.showEditorHelpRequested)
            } label: {
                Label("Toolbar Help…", systemImage: "questionmark.circle")
            }

            Button {
                postWindowCommand(.showSupportPromptRequested)
            } label: {
                Label("Support Neon Vision Editor…", systemImage: "heart.circle.fill")
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
                hasActiveEditorWindow: { WindowViewModelRegistry.shared.activeViewModel() != nil },
                openNewWindow: { openWindow(id: "blank-window") },
                openFocusModeWindow: { openWindow(id: "focus-mode") },
                openAIDiagnosticsWindow: { openWindow(id: "ai-logs") },
                postWindowCommand: { name, object in
                    postWindowCommand(name, object: object)
                },
                isUpdaterEnabled: ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution,
                recentFilesProvider: { RecentFilesStore.items(limit: 10) },
                clearRecentFiles: { RecentFilesStore.clearUnpinned() },
                useAppleIntelligence: $useAppleIntelligence,
                appleAIStatus: $appleAIStatus,
                appleAIRoundTripMS: $appleAIRoundTripMS,
                showGrokError: $showGrokError,
                grokErrorMessage: $grokErrorMessage
            )
        }
#else
        WindowGroup {
            ContentView(
                startupBehavior: mainStartupBehavior,
                safeModeMessage: startupSafeModeMessage
            )
                .environment(viewModel)
                .environmentObject(supportPurchaseManager)
                .environmentObject(appUpdateManager)
                .environment(\.showGrokError, $showGrokError)
                .environment(\.grokErrorMessage, $grokErrorMessage)
                .environment(\.locale, preferredLocale)
                .onAppear { applyRuntimeLanguageOverride() }
                .onChange(of: appLanguageCode) { _, _ in applyRuntimeLanguageOverride() }
                .tint(.blue)
                .onAppear { applyIOSAppearanceOverride() }
                .onAppear { _ = AppearanceThemeCloudSync.syncIfEnabled() }
                .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                    if AppearanceThemeCloudSync.syncIfEnabled()?.didApplyRemoteSettings == true {
                        applyIOSAppearanceOverride()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await markLaunchCompletedAfterStableWindowDelay()
                    }
                    if AppearanceThemeCloudSync.syncIfEnabled()?.didApplyRemoteSettings == true {
                        applyIOSAppearanceOverride()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    RuntimeReliabilityMonitor.shared.markGracefulTermination()
                }
                .onChange(of: appearance) { _, _ in applyIOSAppearanceOverride() }
                .preferredColorScheme(preferredAppearance)
                .task {
                    await markLaunchCompletedAfterStableWindowDelay()
                }
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

            CommandMenu("File") {
                Button("Open File…") {
                    viewModel.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Folder…") {
                    NotificationCenter.default.post(name: .openProjectFolderRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("New Tab") {
                    viewModel.addNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandMenu("Find") {
                Button("Find…") {
                    NotificationCenter.default.post(name: .showFindReplaceRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .findNextRequested, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find in Files…") {
                    NotificationCenter.default.post(name: .showFindInFilesRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandMenu("Tools") {
                Button("Format JSON") {
                    NotificationCenter.default.post(name: .formatJSONDocumentRequested, object: nil)
                }

                Button("Combine JSON Lines") {
                    NotificationCenter.default.post(name: .combineJSONLinesRequested, object: nil)
                }

                Button("Compare with Disk") {
                    NotificationCenter.default.post(name: .compareCurrentTabAgainstDiskRequested, object: nil)
                }

                Button("Compare Open Tabs…") {
                    NotificationCenter.default.post(name: .compareOpenTabsRequested, object: nil)
                }
            }

            CommandMenu("Help") {
                Button("Toolbar Help…") {
                    NotificationCenter.default.post(name: .showEditorHelpRequested, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)

                Button("Show Welcome Tour") {
                    NotificationCenter.default.post(name: .showWelcomeTourRequested, object: nil)
                }

                Button("Settings…") {
                    NotificationCenter.default.post(name: .showSettingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
#endif
    }

}

// MARK: - Environment Keys

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
