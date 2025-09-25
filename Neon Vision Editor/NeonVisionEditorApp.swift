import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: EditorViewModel?
    var modelContext: ModelContext?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel = viewModel, let modelContext = modelContext else {
            return .terminateNow
        }

        for tab in viewModel.tabs {
            if !tab.content.isEmpty && tab.fileURL == nil {
                let alert = NSAlert()
                alert.messageText = "Save changes to \"\(tab.name)\" before quitting?"
                alert.informativeText = "Your changes will be lost if you don't save them."
                alert.addButton(withTitle: "Save")
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Don't Save")
                alert.alertStyle = .warning

                switch alert.runModal() {
                case .alertFirstButtonReturn: // Save
                    viewModel.saveFileAs(tab: tab)
                case .alertSecondButtonReturn: // Cancel
                    return .terminateCancel
                case .alertThirdButtonReturn: // Don't Save
                    break
                default:
                    break
                }
            }
        }

        // Clear all tabs on quit
        for tab in viewModel.tabs {
            modelContext.delete(tab)
        }
        try? modelContext.save()

        return .terminateNow
    }
}

@main
struct NeonVisionEditorApp: App {
    @StateObject private var viewModel = EditorViewModel()
    @State private var appDelegate = AppDelegate()
    @State private var modelContainer: ModelContainer?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environment(\.modelContext, modelContainer?.mainContext ?? ModelContext(ModelContainer(for: Tab.self)))
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear {
                    if modelContainer == nil {
                        do {
                            let container = try ModelContainer(for: Tab.self)
                            modelContainer = container
                            appDelegate.viewModel = viewModel
                            appDelegate.modelContext = container.mainContext
                            NSApplication.shared.delegate = appDelegate
                        } catch {
                            print("Failed to create ModelContainer: \(error)")
                        }
                    }
                }
        }
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    if let context = modelContainer?.mainContext {
                        viewModel.addNewTab(context: context)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            CommandMenu("File") {
                Button("Open File...") {
                    viewModel.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save") {
                    if let selectedTab = viewModel.selectedTab {
                        viewModel.saveFile(tab: selectedTab)
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(viewModel.selectedTab == nil)

                Button("Save As...") {
                    if let selectedTab = viewModel.selectedTab {
                        viewModel.saveFileAs(tab: selectedTab)
                    }
                }
                .disabled(viewModel.selectedTab == nil)
            }

            CommandMenu("View") {
                Button(viewModel.showSidebar ? "Hide Sidebar" : "Show Sidebar") {
                    viewModel.showSidebar.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}
