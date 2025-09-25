import SwiftUI

@main
struct NeonVisionEditorApp: App {
    @StateObject private var viewModel = EditorViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 600, minHeight: 400)
                .background(.ultraThinMaterial)
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
                Button("Suggest Code with Grok") {
                    Task {
                        let client = GrokAPIClient(apiKey: "your-xai-api-key")  // Replace with your actual xAI API key from https://x.ai/api
                        if let tab = viewModel.selectedTab {
                            let prompt = "Suggest improvements for this \(tab.language) code: \(tab.content.prefix(1000))"
                            do {
                                let suggestion = try await client.generateText(prompt: prompt, maxTokens: 200)
                                // Append suggestion to the current content
                                viewModel.updateTabContent(tab: tab, content: tab.content + "\n\n// Grok Suggestion:\n" + suggestion)
                            } catch {
                                print("Grok API error: \(error)")
                                // Optional: Show an alert or sheet for the error
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
