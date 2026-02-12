//
//  AppMenus.swift
//  Neon Vision Editor
//
//  Created by Warren Postma on 2026-02-11.
//  Main menu functionality from the main app unit.

import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Language Menu Commands

#if os(macOS)
struct LanguageMenuCommands: Commands {
    let activeEditorViewModel: EditorViewModel
    
    var body: some Commands {
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
                    if let tab = activeEditorViewModel.selectedTab {
                        activeEditorViewModel.updateTabLanguage(tab: tab, language: lang)
                    }
                }
                .disabled(activeEditorViewModel.selectedTab == nil)
            }
        }
    }
}
#endif

// MARK: - App Menu Commands

#if os(macOS)
struct AppMenuCommands {
    let activeEditorViewModel: EditorViewModel
    let recentFilesManager: RecentFilesManager
    let supportPurchaseManager: SupportPurchaseManager
    let openWindow: OpenWindowAction
    
    @Binding var useAppleIntelligence: Bool
    @Binding var showGrokError: Bool
    @Binding var grokErrorMessage: String
    @Binding var appleAIStatus: String
    @Binding var appleAIRoundTripMS: Double?
    
    private var activeWindowNumber: Int? {
        NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber
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
    
    var appleAIStatusMenuLabel: String {
        if appleAIStatus.contains("Ready") { return "AI: Ready" }
        if appleAIStatus.contains("Checking") { return "AI: Checking" }
        if appleAIStatus.contains("Unavailable") { return "AI: Unavailable" }
        if appleAIStatus.contains("Error") { return "AI: Error" }
        return "AI: Status"
    }
    
    // MARK: - Command Builders
    
    @CommandsBuilder
    var allCommands: some Commands {
        settingsCommands
        fileCommands
        findCommands
        LanguageMenuCommands(activeEditorViewModel: activeEditorViewModel)
        aiCommands
        viewCommands
        editorCommands
        toolsCommands
        diagCommands
    }
    
    @CommandsBuilder
    private var settingsCommands: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
    
    @CommandsBuilder
    private var fileCommands: some Commands {
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
            
            Button("Open Folder...") {
                postWindowCommand(.openProjectFolderRequested)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            
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
    }
    
    @CommandsBuilder
    private var findCommands: some Commands {
        CommandMenu("Find") {
            Button("Find & Replace") {
                postWindowCommand(.showFindReplaceRequested)
            }
            .keyboardShortcut("f", modifiers: .command)
            
            Button("Find in Folders...") {
                postWindowCommand(.showFindInFoldersRequested)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
    
    @CommandsBuilder
    private var aiCommands: some Commands {
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
    }
    
    @CommandsBuilder
    private var viewCommands: some Commands {
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
    }
    
    @CommandsBuilder
    private var editorCommands: some Commands {
        CommandMenu("Editor") {
            Button("Quick Open…") {
                postWindowCommand(.showQuickSwitcherRequested)
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Clear Editor") {
                postWindowCommand(.clearEditorRequested)
            }

            Divider()

            Button("Toggle Vim Mode") {
                postWindowCommand(.toggleVimModeRequested)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
    }
    
    @CommandsBuilder
    private var toolsCommands: some Commands {
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
   
        EmptyCommands()
    }
    
    @CommandsBuilder
    private var diagCommands: some Commands {
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
}
#endif


