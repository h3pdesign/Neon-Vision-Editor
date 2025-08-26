// Neon_Vision_EditorApp.swift
import SwiftUI
import SwiftData

@main
struct Neon_Vision_EditorApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @StateObject private var viewModel = ContentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 600) // Increased width for sidebar
                .environmentObject(viewModel)
                .background(Color.clear)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open…") {
                    viewModel.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Save…") {
                    viewModel.saveFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                Button("New Tab") {
                    viewModel.addNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
