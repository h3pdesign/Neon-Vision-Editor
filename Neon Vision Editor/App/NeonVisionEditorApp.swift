import SwiftUI
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif
#if os(macOS)
import AppKit
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

    @MainActor
    private func flushPendingURLs(into viewModel: EditorViewModel) {
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        urls.forEach { viewModel.openFile(url: $0) }
    }
}

private struct DetachedWindowContentView: View {
    @StateObject private var viewModel = EditorViewModel()
    @ObservedObject var supportPurchaseManager: SupportPurchaseManager
    @Binding var showGrokError: Bool
    @Binding var grokErrorMessage: String

    var body: some View {
        ContentView()
            .environmentObject(viewModel)
            .environmentObject(supportPurchaseManager)
            .environment(\.showGrokError, $showGrokError)
            .environment(\.grokErrorMessage, $grokErrorMessage)
            .frame(minWidth: 600, minHeight: 400)
    }
}
#endif

@main
struct NeonVisionEditorApp: App {
    @StateObject private var viewModel = EditorViewModel()
    @StateObject private var supportPurchaseManager = SupportPurchaseManager()
    @StateObject private var recentFilesManager = RecentFilesManager.shared
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var useAppleIntelligence: Bool = true
    @State private var appleAIStatus: String = "Apple Intelligence: Checking…"
    @State private var appleAIRoundTripMS: Double? = nil
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    @State private var showGrokError: Bool = false
    @State private var grokErrorMessage: String = ""

    init() {
        let defaults = UserDefaults.standard
        SecureTokenStore.migrateLegacyUserDefaultsTokens()
        // Safety reset: avoid stale NORMAL-mode state making editor appear non-editable.
        defaults.set(false, forKey: "EditorVimModeEnabled")
        // Force-disable invisible/control character rendering.
        defaults.set(false, forKey: "NSShowAllInvisibles")
        defaults.set(false, forKey: "NSShowControlCharacters")
        defaults.set(false, forKey: "SettingsShowInvisibleCharacters")
        // Default editor behavior:
        // - keep line numbers on
        // - keep style/space visualization toggles off unless user enables them in Settings
        defaults.register(defaults: [
            "SettingsShowLineNumbers": true,
            "SettingsHighlightCurrentLine": false,
            "SettingsLineWrapEnabled": false,
            "SettingsShowInvisibleCharacters": false,
            "SettingsIndentStyle": "spaces",
            "SettingsIndentWidth": 4,
            "SettingsAutoIndent": true,
            "SettingsAutoCloseBrackets": false,
            "SettingsTrimTrailingWhitespace": false,
            "SettingsTrimWhitespaceForSyntaxDetection": false,
            "SettingsCompletionEnabled": false,
            "SettingsCompletionFromDocument": false,
            "SettingsCompletionFromSyntax": false
        ])
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
        macOSScenes
        #else
        iOSScenes
        #endif
    }
    
    #if os(macOS)
    // MARK: - macOS Scenes
    @SceneBuilder
    private var macOSScenes: some Scene {
        mainWindowGroup
        blankWindowGroup
        settingsWindowGroup
        consoleLogWindowGroup
    }
    
    @SceneBuilder
    private var mainWindowGroup: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(supportPurchaseManager)
                .onAppear { 
                    appDelegate.viewModel = viewModel
                    
                    // Clean up recent files that no longer exist
                    recentFilesManager.cleanupDeletedFiles()
                    
                    // Diagnostic: Check Foundation Models availability
                    #if USE_FOUNDATION_MODELS
                    print("✅ USE_FOUNDATION_MODELS flag is defined")
                    #else
                    print("❌ USE_FOUNDATION_MODELS flag is NOT defined")
                    #endif
                    
                    #if canImport(FoundationModels)
                    print("✅ FoundationModels can be imported")
                    #else
                    print("❌ FoundationModels CANNOT be imported")
                    #endif
                    
                    AppLogger.shared.info("Neon Vision Editor launched", category: "App")
                }
                .environment(\.showGrokError, $showGrokError)
                .environment(\.grokErrorMessage, $grokErrorMessage)
                .frame(minWidth: 600, minHeight: 400)
                .task {
                    #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                    AppleFM.isEnabled = true
                    AppLogger.shared.info("Checking Apple Intelligence availability...", category: "AI")
                    do {
                        let start = Date()
                        _ = try await AppleFM.appleFMHealthCheck()
                        let end = Date()
                        appleAIStatus = "Apple Intelligence: Ready"
                        appleAIRoundTripMS = end.timeIntervalSince(start) * 1000.0
                        AppLogger.shared.info("Apple Intelligence ready (RTT: \(String(format: "%.1f", appleAIRoundTripMS!))ms)", category: "AI")
                    } catch {
                        appleAIStatus = "Apple Intelligence: Error — \(error.localizedDescription)"
                        appleAIRoundTripMS = nil
                        AppLogger.shared.error("Apple Intelligence error: \(error.localizedDescription)", category: "AI")
                    }
                    #else
                    appleAIStatus = "Apple Intelligence: Unavailable (build without USE_FOUNDATION_MODELS)"
                    AppLogger.shared.warning("Apple Intelligence not available in this build", category: "AI")
                    #endif
                }
        }
        .defaultSize(width: 1000, height: 600)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            appCommands
        }
    }
    
    @SceneBuilder
    private var blankWindowGroup: some Scene {
        WindowGroup("New Window", id: "blank-window") {
            DetachedWindowContentView(
                supportPurchaseManager: supportPurchaseManager,
                showGrokError: $showGrokError,
                grokErrorMessage: $grokErrorMessage
            )
        }
        .defaultSize(width: 1000, height: 600)
        .handlesExternalEvents(matching: [])
    }
    
    @SceneBuilder
    private var settingsWindowGroup: some Scene {
        WindowGroup("Settings", id: "settings") {
            NeonSettingsView()
                .environmentObject(supportPurchaseManager)
                .background(NonRestorableWindow())
        }
        .defaultSize(width: 860, height: 620)
    }
    
    @SceneBuilder
    private var consoleLogWindowGroup: some Scene {
        WindowGroup("Console Log", id: "console-log") {
            ConsoleLogWindow()
                .background(NonRestorableWindow())
        }
        .defaultSize(width: 900, height: 600)
    }
    
    // MARK: - Commands
    @CommandsBuilder
    private var appCommands: some Commands {
        AppMenuCommands(
            activeEditorViewModel: activeEditorViewModel,
            recentFilesManager: recentFilesManager,
            supportPurchaseManager: supportPurchaseManager,
            openWindow: openWindow,
            useAppleIntelligence: $useAppleIntelligence,
            showGrokError: $showGrokError,
            grokErrorMessage: $grokErrorMessage,
            appleAIStatus: $appleAIStatus,
            appleAIRoundTripMS: $appleAIRoundTripMS
        ).allCommands
    }
    #else
    // MARK: - iOS Scenes
    @SceneBuilder
    private var iOSScenes: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(supportPurchaseManager)
                .environment(\.showGrokError, $showGrokError)
                .environment(\.grokErrorMessage, $grokErrorMessage)
        }
    }
    #endif

    private func showSettingsWindow() {
        #if os(macOS)
        openWindow(id: "settings")
        #endif
    }
}

#if os(macOS)
private struct NonRestorableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isRestorable = false
                window.identifier = nil
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.isRestorable = false
                window.identifier = nil
            }
        }
    }
}
#endif

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
