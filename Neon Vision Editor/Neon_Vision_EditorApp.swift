import SwiftUI
import SwiftData

@main
struct Neon_Vision_EditorApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Tab.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, modelContainer.mainContext)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    let context = try? ModelContainer(for: Tab.self).mainContext
                    let newTab = Tab(name: "Untitled \(Int.random(in: 1...1000))")
                    context?.insert(newTab)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }
}
