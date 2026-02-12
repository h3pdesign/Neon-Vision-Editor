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

    #if os(macOS)
    private var appleAIStatusMenuLabel: String {
        if appleAIStatus.contains("Ready") { return "AI: Ready" }
        if appleAIStatus.contains("Checking") { return "AI: Checking" }
        if appleAIStatus.contains("Unavailable") { return "AI: Unavailable" }
        if appleAIStatus.contains("Error") { return "AI: Error" }
        return "AI: Status"
    }
    #endif

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

        WindowGroup("New Window", id: "blank-window") {
            DetachedWindowContentView(
                supportPurchaseManager: supportPurchaseManager,
                showGrokError: $showGrokError,
                grokErrorMessage: $grokErrorMessage
            )
        }
        .defaultSize(width: 1000, height: 600)
        .handlesExternalEvents(matching: [])

        
        WindowGroup("Settings", id: "settings") {
            NeonSettingsView()
                .environmentObject(supportPurchaseManager)
                .background(NonRestorableWindow())
        }
        .defaultSize(width: 860, height: 620)

        WindowGroup("Console Log", id: "console-log") {
            ConsoleLogWindow()
                .background(NonRestorableWindow())
        }
        .defaultSize(width: 900, height: 600)

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openWindow(id: "blank-window")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Tab") {
                    activeEditorViewModel.addNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Open File...") {
                    activeEditorViewModel.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Menu("Open Recent") {
                    if recentFilesManager.recentFiles.isEmpty {
                        Text("No Recent Files")
                            .disabled(true)
                    } else {
                        let displayNames = recentFilesManager.uniqueDisplayNames()
                        ForEach(recentFilesManager.recentFiles, id: \.self) { url in
                            Button(displayNames[url] ?? url.lastPathComponent) {
                                activeEditorViewModel.openFile(url: url)
                            }
                        }
                        
                        Divider()
                        
                        Button("Clear Menu") {
                            recentFilesManager.clearRecentFiles()
                        }
                    }
                }
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    let current = activeEditorViewModel
                    if let tab = current.selectedTab {
                        current.saveFile(tab: tab)
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(activeEditorViewModel.selectedTab == nil)

                Button("Save As...") {
                    let current = activeEditorViewModel
                    if let tab = current.selectedTab {
                        current.saveFileAs(tab: tab)
                    }
                }
                .disabled(activeEditorViewModel.selectedTab == nil)

                Button("Rename") {
                    let current = activeEditorViewModel
                    current.showingRename = true
                    current.renameText = current.selectedTab?.name ?? "Untitled"
                }
                .disabled(activeEditorViewModel.selectedTab == nil)

                Divider()

                Button("Close Tab") {
                    let current = activeEditorViewModel
                    if let tab = current.selectedTab {
                        current.closeTab(tab: tab)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(activeEditorViewModel.selectedTab == nil)
            }

            CommandMenu("Language") {
                ForEach(["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "css", "c", "cpp", "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "bash", "zsh", "powershell", "standard", "plain"], id: \.self) { lang in
                    let label: String = {
                        switch lang {
                        case "php": return "PHP"
                        case "cobol": return "COBOL"
                        case "dotenv": return "Dotenv"
                        case "proto": return "Proto"
                        case "graphql": return "GraphQL"
                        case "rst": return "reStructuredText"
                        case "nginx": return "Nginx"
                        case "objective-c": return "Objective-C"
                        case "csharp": return "C#"
                        case "c": return "C"
                        case "cpp": return "C++"
                        case "json": return "JSON"
                        case "xml": return "XML"
                        case "yaml": return "YAML"
                        case "toml": return "TOML"
                        case "csv": return "CSV"
                        case "ini": return "INI"
                        case "sql": return "SQL"
                        case "vim": return "Vim"
                        case "log": return "Log"
                        case "ipynb": return "Jupyter Notebook"
                        case "html": return "HTML"
                        case "css": return "CSS"
                        case "standard": return "Standard"
                        default: return lang.capitalized
                        }
                    }()
                    Button(label) {
                        let current = activeEditorViewModel
                        if let tab = current.selectedTab {
                            current.updateTabLanguage(tab: tab, language: lang)
                        }
                    }
                    .disabled(activeEditorViewModel.selectedTab == nil)
                }
            }

            CommandMenu("AI") {
                Button("API Settings…") {
                    postWindowCommand(.showAPISettingsRequested)
                }

                Divider()

                Button("Use Apple Intelligence") {
                    postWindowCommand(.selectAIModelRequested, object: AIModel.appleIntelligence.rawValue)
                }
                Button("Use Grok") {
                    postWindowCommand(.selectAIModelRequested, object: AIModel.grok.rawValue)
                }
                Button("Use OpenAI") {
                    postWindowCommand(.selectAIModelRequested, object: AIModel.openAI.rawValue)
                }
                Button("Use Gemini") {
                    postWindowCommand(.selectAIModelRequested, object: AIModel.gemini.rawValue)
                }
                Button("Use Anthropic") {
                    postWindowCommand(.selectAIModelRequested, object: AIModel.anthropic.rawValue)
                }
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    postWindowCommand(.toggleSidebarRequested)
                }
                    .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Toggle Project Structure Sidebar") {
                    postWindowCommand(.toggleProjectStructureSidebarRequested)
                }

                Button("Brain Dump Mode") {
                    postWindowCommand(.toggleBrainDumpModeRequested)
                }
                    .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Toggle Translucent Window Background") {
                    let next = !UserDefaults.standard.bool(forKey: "EnableTranslucentWindow")
                    UserDefaults.standard.set(next, forKey: "EnableTranslucentWindow")
                    postWindowCommand(.toggleTranslucencyRequested, object: next)
                }

                Divider()

                Button("Show Welcome Tour") {
                    postWindowCommand(.showWelcomeTourRequested)
                }
            }

            CommandMenu("Editor") {
                Button("Quick Open…") {
                    postWindowCommand(.showQuickSwitcherRequested)
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Clear Editor") {
                    postWindowCommand(.clearEditorRequested)
                }

                Button("Find & Replace") {
                    postWindowCommand(.showFindReplaceRequested)
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Toggle Vim Mode") {
                    postWindowCommand(.toggleVimModeRequested)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }

            CommandMenu("Tools") {
                Button("Suggest Code") {
                    Task {
                        let current = activeEditorViewModel
                        if let tab = current.selectedTab {
                            let contentPrefix = String(tab.content.prefix(1000))
                            let prompt = "Suggest improvements for this \(tab.language) code: \(contentPrefix)"

                            let grokToken = SecureTokenStore.token(for: .grok)
                            let openAIToken = SecureTokenStore.token(for: .openAI)
                            let geminiToken = SecureTokenStore.token(for: .gemini)
                            let anthropicToken = SecureTokenStore.token(for: .anthropic)

                            let client: AIClient? = {
                                #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                                if useAppleIntelligence {
                                    return AIClientFactory.makeClient(for: AIModel.appleIntelligence)
                                }
                                #endif
                                if !grokToken.isEmpty { return AIClientFactory.makeClient(for: .grok, grokAPITokenProvider: { grokToken }) }
                                if !openAIToken.isEmpty { return AIClientFactory.makeClient(for: .openAI, openAIKeyProvider: { openAIToken }) }
                                if !geminiToken.isEmpty { return AIClientFactory.makeClient(for: .gemini, geminiKeyProvider: { geminiToken }) }
                                if !anthropicToken.isEmpty { return AIClientFactory.makeClient(for: .anthropic, anthropicKeyProvider: { anthropicToken }) }
                                #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                                return AIClientFactory.makeClient(for: .appleIntelligence)
                                #else
                                return nil
                                #endif
                            }()

                            guard let client else { grokErrorMessage = "No AI provider configured."; showGrokError = true; return }

                            var aggregated = ""
                            for await chunk in client.streamSuggestions(prompt: prompt) { aggregated += chunk }

                            current.updateTabContent(tab: tab, content: tab.content + "\n\n// AI Suggestion:\n" + aggregated)
                        }
                    }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(activeEditorViewModel.selectedTab == nil)

                Toggle("Use Apple Intelligence", isOn: $useAppleIntelligence)
            }

            CommandMenu("Diag") {
                Button("Show Console Log") {
                    openWindow(id: "console-log")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                
                Divider()
                
                Text(appleAIStatusMenuLabel)
                Divider()
                Button("Inspect Whitespace Scalars at Caret") {
                    postWindowCommand(.inspectWhitespaceScalarsRequested)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Divider()
                Button("Run AI Check") {
                    Task {
                        AppLogger.shared.info("Running Apple Intelligence health check...", category: "AI")
                        #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                        AppleFM.isEnabled = true
                        do {
                            let start = Date()
                            _ = try await AppleFM.appleFMHealthCheck()
                            let end = Date()
                            appleAIStatus = "Apple Intelligence: Ready"
                            appleAIRoundTripMS = end.timeIntervalSince(start) * 1000.0
                            AppLogger.shared.info("Apple Intelligence health check passed (RTT: \(String(format: "%.1f", appleAIRoundTripMS!))ms)", category: "AI")
                        } catch {
                            appleAIStatus = "Apple Intelligence: Error — \(error.localizedDescription)"
                            appleAIRoundTripMS = nil
                            AppLogger.shared.error("Apple Intelligence health check failed: \(error.localizedDescription)", category: "AI")
                        }
                        #else
                        appleAIStatus = "Apple Intelligence: Unavailable (build without USE_FOUNDATION_MODELS)"
                        appleAIRoundTripMS = nil
                        AppLogger.shared.warning("Apple Intelligence not available in this build", category: "AI")
                        #endif
                    }
                }

                if let ms = appleAIRoundTripMS {
                    Text(String(format: "RTT: %.1f ms", ms))
                        .foregroundStyle(.secondary)
                }
            }
        }
#else
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(supportPurchaseManager)
                .environment(\.showGrokError, $showGrokError)
                .environment(\.grokErrorMessage, $grokErrorMessage)
        }
#endif
    }

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
