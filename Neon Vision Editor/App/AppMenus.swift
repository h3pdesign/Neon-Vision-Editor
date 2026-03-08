#if os(macOS)
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

struct NeonVisionMacAppCommands: Commands {
    let activeEditorViewModel: () -> EditorViewModel
    let hasActiveEditorWindow: () -> Bool
    let openNewWindow: () -> Void
    let openAIDiagnosticsWindow: () -> Void
    let postWindowCommand: (_ name: Notification.Name, _ object: Any?) -> Void
    let isUpdaterEnabled: Bool

    @Binding var useAppleIntelligence: Bool
    @Binding var appleAIStatus: String
    @Binding var appleAIRoundTripMS: Double?
    @Binding var showGrokError: Bool
    @Binding var grokErrorMessage: String

    private static let languageOptions = [
        "swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby",
        "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html",
        "expressionengine", "css", "c", "cpp", "csharp", "objective-c", "json", "xml", "yaml",
        "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "bash", "zsh", "powershell",
        "standard", "plain"
    ]

    private var appleAIStatusMenuLabel: String {
        if appleAIStatus.contains("Ready") { return "AI: Ready" }
        if appleAIStatus.contains("Checking") { return "AI: Checking" }
        if appleAIStatus.contains("Unavailable") { return "AI: Unavailable" }
        if appleAIStatus.contains("Error") { return "AI: Error" }
        return "AI: Status"
    }

    @CommandsBuilder
    var body: some Commands {
        appSettingsCommands
        fileCommands
        languageCommands
        aiCommands
        viewCommands
        findCommands
        editorCommands
        toolsCommands
        diagnosticsCommands
    }

    private var hasSelectedTab: Bool {
        activeEditorViewModel().selectedTab != nil
    }

    private func post(_ name: Notification.Name, object: Any? = nil) {
        postWindowCommand(name, object)
    }

    @CommandsBuilder
    private var appSettingsCommands: some Commands {
        CommandGroup(before: .appSettings) {
            if isUpdaterEnabled {
                Button("Check for Updates…") {
                    post(.showUpdaterRequested, object: true)
                }
                Divider()
            }
        }
    }

    @CommandsBuilder
    private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                activeEditorViewModel().addNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Open File…") {
                activeEditorViewModel().openFile()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Folder…") {
                post(.openProjectFolderRequested)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                let current = activeEditorViewModel()
                if let tab = current.selectedTab {
                    current.saveFile(tabID: tab.id)
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!hasSelectedTab)

            Button("Save As…") {
                let current = activeEditorViewModel()
                if let tab = current.selectedTab {
                    current.saveFileAs(tabID: tab.id)
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!hasSelectedTab)

            Button("Rename") {
                let current = activeEditorViewModel()
                current.showingRename = true
                current.renameText = current.selectedTab?.name ?? "Untitled"
            }
            .disabled(!hasSelectedTab)

            Divider()

            Button("Close Tab") {
                post(.closeSelectedTabRequested)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(!hasActiveEditorWindow() || !hasSelectedTab)
        }
    }

    @CommandsBuilder
    private var languageCommands: some Commands {
        CommandMenu("Language") {
            ForEach(Self.languageOptions, id: \.self) { language in
                Button(languageLabel(for: language)) {
                    let current = activeEditorViewModel()
                    if let tab = current.selectedTab {
                        current.updateTabLanguage(tabID: tab.id, language: language)
                    }
                }
                .disabled(!hasSelectedTab)
            }
        }
    }

    @CommandsBuilder
    private var aiCommands: some Commands {
        CommandMenu("AI") {
            Button("API Settings…") {
                post(.showAPISettingsRequested)
            }
        }
    }

    @CommandsBuilder
    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Sidebar") {
                post(.toggleSidebarRequested)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Toggle Project Structure Sidebar") {
                post(.toggleProjectStructureSidebarRequested)
            }

            Button("Brain Dump Mode") {
                post(.toggleBrainDumpModeRequested)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Toggle Translucent Window Background") {
                let next = !UserDefaults.standard.bool(forKey: "EnableTranslucentWindow")
                UserDefaults.standard.set(next, forKey: "EnableTranslucentWindow")
                post(.toggleTranslucencyRequested, object: next)
            }

            Divider()

            Button {
                post(.showWelcomeTourRequested)
            } label: {
                Label("Show Welcome Tour", systemImage: "sparkles.rectangle.stack")
            }
        }
    }

    @CommandsBuilder
    private var findCommands: some Commands {
        CommandMenu("Find") {
            Button("Find…") {
                post(.showFindReplaceRequested)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find Next") {
                post(.findNextRequested)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("Find in Files…") {
                post(.showFindInFilesRequested)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }

    @CommandsBuilder
    private var editorCommands: some Commands {
        CommandMenu("Editor") {
            Button("Quick Open…") {
                post(.showQuickSwitcherRequested)
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Clear Editor") {
                post(.clearEditorRequested)
            }

            Button("Add Next Match") {
                post(.addNextMatchRequested)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!hasSelectedTab)

            Divider()

            Button("Toggle Vim Mode") {
                post(.toggleVimModeRequested)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
    }

    @CommandsBuilder
    private var toolsCommands: some Commands {
        CommandMenu("Tools") {
            Button("Suggest Code") {
                suggestCode()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!hasSelectedTab)

            Toggle("Use Apple Intelligence", isOn: $useAppleIntelligence)
        }
    }

    @CommandsBuilder
    private var diagnosticsCommands: some Commands {
        CommandMenu("Diag") {
            Text(appleAIStatusMenuLabel)
            Divider()

            Button("Open AI Activity Log") {
                openAIDiagnosticsWindow()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Inspect Whitespace Scalars at Caret") {
                post(.inspectWhitespaceScalarsRequested)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Divider()

            Button("Run AI Check") {
                runAICheck()
            }

            if let roundTripMS = appleAIRoundTripMS {
                Text(String(format: "RTT: %.1f ms", roundTripMS))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func runAICheck() {
        Task {
            AIActivityLog.record("Manual AI health check started.", source: "Diag")
            #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
            do {
                let start = Date()
                _ = try await AppleFM.appleFMHealthCheck()
                let end = Date()
                appleAIStatus = "Apple Intelligence: Ready"
                appleAIRoundTripMS = end.timeIntervalSince(start) * 1000.0
                AIActivityLog.record(
                    "AI health check succeeded (\(String(format: "%.1f", appleAIRoundTripMS ?? 0)) ms).",
                    source: "Diag"
                )
            } catch {
                appleAIStatus = "Apple Intelligence: Error — \(error.localizedDescription)"
                appleAIRoundTripMS = nil
                AIActivityLog.record(
                    "AI health check failed: \(error.localizedDescription)",
                    level: .error,
                    source: "Diag"
                )
            }
            #else
            appleAIStatus = "Apple Intelligence: Unavailable (build without USE_FOUNDATION_MODELS)"
            appleAIRoundTripMS = nil
            AIActivityLog.record(
                "AI health check unavailable (built without USE_FOUNDATION_MODELS).",
                level: .warning,
                source: "Diag"
            )
            #endif
        }
    }

    private func suggestCode() {
        Task {
            let current = activeEditorViewModel()
            guard let tab = current.selectedTab else { return }

            let contentPrefix = String(tab.content.prefix(1000))
            let prompt = "Suggest improvements for this \(tab.language) code: \(contentPrefix)"

            AIActivityLog.record("Suggest Code requested for tab '\(tab.name)'.", source: "Suggest")

            let grokToken = SecureTokenStore.token(for: .grok)
            let openAIToken = SecureTokenStore.token(for: .openAI)
            let geminiToken = SecureTokenStore.token(for: .gemini)
            let anthropicToken = SecureTokenStore.token(for: .anthropic)

            var providerLabel = "Unknown"
            let client: AIClient? = {
                #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                if useAppleIntelligence {
                    providerLabel = "Apple Intelligence"
                    return AIClientFactory.makeClient(for: .appleIntelligence)
                }
                #endif
                if !grokToken.isEmpty {
                    providerLabel = "Grok"
                    return AIClientFactory.makeClient(for: .grok, grokAPITokenProvider: { grokToken })
                }
                if !openAIToken.isEmpty {
                    providerLabel = "OpenAI"
                    return AIClientFactory.makeClient(for: .openAI, openAIKeyProvider: { openAIToken })
                }
                if !geminiToken.isEmpty {
                    providerLabel = "Gemini"
                    return AIClientFactory.makeClient(for: .gemini, geminiKeyProvider: { geminiToken })
                }
                if !anthropicToken.isEmpty {
                    providerLabel = "Anthropic"
                    return AIClientFactory.makeClient(for: .anthropic, anthropicKeyProvider: { anthropicToken })
                }
                #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
                providerLabel = "Apple Intelligence (fallback)"
                return AIClientFactory.makeClient(for: .appleIntelligence)
                #else
                return nil
                #endif
            }()

            guard let client else {
                let message = "No AI provider configured."
                grokErrorMessage = message
                showGrokError = true
                AIActivityLog.record(message, level: .error, source: "Suggest")
                return
            }

            AIActivityLog.record("Suggest Code using \(providerLabel).", source: "Suggest")
            var aggregated = ""
            for await chunk in client.streamSuggestions(prompt: prompt) {
                aggregated += chunk
            }
            let trimmed = aggregated.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                AIActivityLog.record(
                    "Suggest Code returned an empty response from \(providerLabel).",
                    level: .warning,
                    source: "Suggest"
                )
                return
            }

            current.updateTabContent(
                tabID: tab.id,
                content: tab.content + "\n\n// AI Suggestion:\n" + aggregated
            )
            AIActivityLog.record("Suggest Code completed (\(aggregated.count) chars).", source: "Suggest")
        }
    }

    private func languageLabel(for language: String) -> String {
        switch language {
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
        default: return language.capitalized
        }
    }
}
#endif
