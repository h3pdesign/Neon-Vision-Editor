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
    @StateObject private var viewModel = EditorViewModel()
    @ObservedObject var supportPurchaseManager: SupportPurchaseManager
    @ObservedObject var appUpdateManager: AppUpdateManager
    @Binding var showGrokError: Bool
    @Binding var grokErrorMessage: String

    var body: some View {
        ContentView()
            .environmentObject(viewModel)
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
    @StateObject private var viewModel = EditorViewModel()
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

    #if os(macOS)
    private var appleAIStatusMenuLabel: String {
        if appleAIStatus.contains("Ready") { return "AI: Ready" }
        if appleAIStatus.contains("Checking") { return "AI: Checking" }
        if appleAIStatus.contains("Unavailable") { return "AI: Unavailable" }
        if appleAIStatus.contains("Error") { return "AI: Error" }
        return "AI: Status"
    }
    #endif

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
                    } catch {
                        appleAIStatus = "Apple Intelligence: Error — \(error.localizedDescription)"
                        appleAIRoundTripMS = nil
                    }
                    #else
                    appleAIStatus = "Apple Intelligence: Unavailable (build without USE_FOUNDATION_MODELS)"
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

        .commands {
            CommandGroup(replacing: .appSettings) {
                if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
                    Button("Check for Updates…") {
                        postWindowCommand(.showUpdaterRequested, object: true)
                    }
                }

                Divider()

                Button("Settings…") {
                    postWindowCommand(.showSettingsRequested)
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
                .keyboardShortcut("s", modifiers: [.command, .shift])
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
                ForEach(["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "bash", "zsh", "powershell", "standard", "plain"], id: \.self) { lang in
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
                        case "expressionengine": return "ExpressionEngine"
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

                            let client: AIClient? = {
                                #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                                if useAppleIntelligence {
                                    return AIClientFactory.makeClient(for: AIModel.appleIntelligence)
                                }
                                #endif
                                if !grokToken.isEmpty { return AIClientFactory.makeClient(for: .grok, grokAPITokenProvider: { grokToken }) }
                                if !openAIToken.isEmpty { return AIClientFactory.makeClient(for: .openAI, openAIKeyProvider: { openAIToken }) }
                                if !geminiToken.isEmpty { return AIClientFactory.makeClient(for: .gemini, geminiKeyProvider: { geminiToken }) }
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
                Text(appleAIStatusMenuLabel)
                Divider()
                Button("Inspect Whitespace Scalars at Caret") {
                    postWindowCommand(.inspectWhitespaceScalarsRequested)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Divider()
                Button("Run AI Check") {
                    Task {
                        #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                        do {
                            let start = Date()
                            _ = try await AppleFM.appleFMHealthCheck()
                            let end = Date()
                            appleAIStatus = "Apple Intelligence: Ready"
                            appleAIRoundTripMS = end.timeIntervalSince(start) * 1000.0
                        } catch {
                            appleAIStatus = "Apple Intelligence: Error — \(error.localizedDescription)"
                            appleAIRoundTripMS = nil
                        }
                        #else
                        appleAIStatus = "Apple Intelligence: Unavailable (build without USE_FOUNDATION_MODELS)"
                        appleAIRoundTripMS = nil
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

    private func showSettingsWindow() {
        #if os(macOS)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
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
