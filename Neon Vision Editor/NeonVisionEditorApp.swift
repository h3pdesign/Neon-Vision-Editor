import SwiftUI
import FoundationModels

enum AIModel: String, Identifiable {
    case appleIntelligence = "Apple Intelligence"
    case grok = "Grok"
    
    var id: String { rawValue }
}

@main
struct NeonVisionEditorApp: App {
    @StateObject private var viewModel = EditorViewModel()
    @State private var showGrokError: Bool = false
    @State private var grokErrorMessage: String = ""
    @State private var selectedAIModel: AIModel = .appleIntelligence
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environment(\.showGrokError, $showGrokError)
                .environment(\.grokErrorMessage, $grokErrorMessage)
                .environment(\.selectedAIModel, $selectedAIModel)
                .frame(minWidth: 600, minHeight: 400)
                .background(.ultraThinMaterial)
                .overlay(.ultraThinMaterial.opacity(0.2)) // Fallback for liquidGlassEffect
                .task {
                    // Pre-warm Apple Intelligence model
                    let session = LanguageModelSession(model: SystemLanguageModel())
                    session.prewarm()
                }
        }
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandMenu("File") {
                Button("New Tab") {
                    viewModel.addNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("Open File...") {
                    viewModel.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("Save") {
                    if let tab = viewModel.selectedTab {
                        viewModel.saveFile(tab: tab)
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(viewModel.selectedTab == nil)
                
                Button("Save As...") {
                    if let tab = viewModel.selectedTab {
                        viewModel.saveFileAs(tab: tab)
                    }
                }
                .disabled(viewModel.selectedTab == nil)
                
                Button("Rename") {
                    viewModel.showingRename = true
                    viewModel.renameText = viewModel.selectedTab?.name ?? "Untitled"
                }
                .disabled(viewModel.selectedTab == nil)
                
                Button("Close Tab") {
                    if let tab = viewModel.selectedTab {
                        viewModel.closeTab(tab: tab)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(viewModel.selectedTab == nil)
            }
            
            CommandMenu("Language") {
                ForEach(["swift", "python", "javascript", "html", "css", "c", "cpp", "json", "markdown"], id: \.self) { lang in
                    Button(lang.capitalized) {
                        if let tab = viewModel.selectedTab {
                            viewModel.updateTabLanguage(tab: tab, language: lang)
                        }
                    }
                    .disabled(viewModel.selectedTab == nil)
                }
            }
            
            CommandMenu("View") {
                Toggle("Toggle Sidebar", isOn: $viewModel.showSidebar)
                    .keyboardShortcut("s", modifiers: [.command, .option])
                
                Toggle("Brain Dump Mode", isOn: $viewModel.isBrainDumpMode)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            
            CommandMenu("Tools") {
                Button("Suggest Code") {
                    Task {
                        if let tab = viewModel.selectedTab {
                            switch selectedAIModel {
                            case .appleIntelligence:
                                let session = LanguageModelSession(model: SystemLanguageModel())
                                let prompt = "System: Output a code suggestion for this \(tab.language) code.\nUser: \(tab.content.prefix(1000))"
                                do {
                                    let suggestion = try await session.respond(to: prompt)
                                    viewModel.updateTabContent(tab: tab, content: tab.content + "\n\n// Apple Intelligence Suggestion:\n" + suggestion.content)
                                } catch {
                                    grokErrorMessage = error.localizedDescription
                                    showGrokError = true
                                }
                            case .grok:
                                let client = GrokAPIClient(apiKey: "your-xai-api-key") // Replace with your xAI API key from https://x.ai/api
                                let prompt = "Suggest improvements for this \(tab.language) code: \(tab.content.prefix(1000))"
                                do {
                                    let suggestion = try await client.generateText(prompt: prompt, maxTokens: 200)
                                    viewModel.updateTabContent(tab: tab, content: tab.content + "\n\n// Grok Suggestion:\n" + suggestion)
                                } catch {
                                    grokErrorMessage = error.localizedDescription
                                    showGrokError = true
                                }
                            }
                        }
                    }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(viewModel.selectedTab == nil)
            }
        }
    }
}

struct ShowGrokErrorKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

struct GrokErrorMessageKey: EnvironmentKey {
    static let defaultValue: Binding<String> = .constant("")
}

struct SelectedAIModelKey: EnvironmentKey {
    static let defaultValue: Binding<AIModel> = .constant(.appleIntelligence)
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
    
    var selectedAIModel: Binding<AIModel> {
        get { self[SelectedAIModelKey.self] }
        set { self[SelectedAIModelKey.self] = newValue }
    }
}
