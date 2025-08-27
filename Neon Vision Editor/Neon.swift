import SwiftUI
import SwiftData

@main
struct Neon_Vision_EditorApp: App {
    let container: ModelContainer
    @StateObject private var viewModel = ViewModel()
    @State private var showCloseAlert = false
    @State private var unsavedTabs: [Tab] = []
    
    init() {
        do {
            container = try ModelContainer(for: Tab.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, container.mainContext)
                .environmentObject(viewModel)
                .frame(minWidth: 1000, minHeight: 600)
                .alert(isPresented: $showCloseAlert) {
                    Alert(
                        title: Text("Save Changes?"),
                        message: Text("You have unsaved changes. Do you want to save them?"),
                        primaryButton: .default(Text("Save All")) {
                            saveAllTabs()
                        },
                        secondaryButton: .destructive(Text("Discard")) {
                            discardUnsaved()
                        },
                        tertiaryButton: .cancel()
                    )
                }
        }
        .defaultSize(width: 1000, height: 600)
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    viewModel.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        .onChange(of: viewModel.tabs) { _, _ in
            unsavedTabs = viewModel.tabs.filter { !$0.content.isEmpty }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            if !unsavedTabs.isEmpty {
                showCloseAlert = true
            }
        }
    }
    
    private func saveAllTabs() {
        for tab in unsavedTabs {
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = tab.name
            if savePanel.runModal() == .OK, let url = savePanel.url {
                do {
                    try tab.content.write(to: url, atomically: true, encoding: .utf8)
                    try viewModel.saveTab(tab)
                } catch {
                    print("Error saving tab: \(error)")
                }
            }
        }
        unsavedTabs.removeAll()
    }
    
    private func discardUnsaved() {
        viewModel.discardUnsaved()
        unsavedTabs.removeAll()
    }
}

// MARK: - ViewModel
@Observable
class ViewModel {
    var tabs: [Tab] = []
    var selectedTab: Tab?
    var modelContext: ModelContext?
    
    func setModelContext(_ context: ModelContext) {
        modelContext = context
        if tabs.isEmpty {
            addTab()
        }
    }
    
    func addTab() {
        let newTab = Tab()
        tabs.append(newTab)
        selectedTab = newTab
        if let window = NSApplication.shared.windows.first {
            window.title = newTab.name
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                window.title = newTab.name
            }
        }
    }
    
    func removeTab(_ tab: Tab) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.remove(at: index)
            selectedTab = tabs.last
            if let window = NSApplication.shared.windows.first {
                window.title = selectedTab?.name ?? "Note"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    window.title = selectedTab?.name ?? "Note"
                }
            }
        }
    }
    
    func saveTab(_ tab: Tab) throws {
        guard let context = modelContext else { throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model context"]) }
        do {
            try context.save()
            if let existingItem = try context.fetch(FetchDescriptor<Tab>(sortBy: [SortDescriptor(\Tab.name)]))
                .first(where: { $0.name == tab.name }) {
                existingItem.content = tab.content
                existingItem.language = tab.language
            } else {
                context.insert(tab)
            }
        } catch {
            throw error
        }
    }
    
    func discardUnsaved() {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<Tab>()
            let allTabs = try context.fetch(descriptor)
            for tab in allTabs {
                context.delete(tab)
            }
            try context.save()
            tabs.removeAll()
            addTab()
        } catch {
            print("Error discarding unsaved tabs: \(error)")
        }
    }
}