import SwiftUI
import SwiftData

@main
struct Neon_Vision_EditorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: Item.self) // Configure the model container for the Item schema
        }
    }
}
