//
//  Neon_Vision_EditorApp.swift
//  Neon Vision Editor
//
//  Created by Hilthart Pedersen on 25.08.25.
//

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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
