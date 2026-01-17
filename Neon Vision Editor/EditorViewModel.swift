import SwiftUI
import Combine
import UniformTypeIdentifiers

struct TabData: Identifiable {
    let id = UUID()
    var name: String
    var content: String
    var language: String
    var fileURL: URL?
}

@MainActor
class EditorViewModel: ObservableObject {
    @Published var tabs: [TabData] = []
    @Published var selectedTabID: UUID?
    @Published var showSidebar: Bool = true
    @Published var isBrainDumpMode: Bool = false
    @Published var showingRename: Bool = false
    @Published var renameText: String = ""
    @Published var isLineWrapEnabled: Bool = true
    
    var selectedTab: TabData? {
        get { tabs.first(where: { $0.id == selectedTabID }) }
        set { selectedTabID = newValue?.id }
    }
    
    private let languageMap: [String: String] = [
        "swift": "swift",
        "py": "python",
        "js": "javascript",
        "html": "html",
        "css": "css",
        "c": "c",
        "cpp": "cpp",
        "h": "c",
        "json": "json",
        "md": "markdown"
    ]
    
    init() {
        addNewTab()
    }
    
    func addNewTab() {
        let newTab = TabData(name: "Untitled \(tabs.count + 1)", content: "", language: "swift", fileURL: nil)
        tabs.append(newTab)
        selectedTabID = newTab.id
    }
    
    func renameTab(tab: TabData, newName: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].name = newName
        }
    }
    
    func updateTabContent(tab: TabData, content: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].content = content
        }
    }
    
    func updateTabLanguage(tab: TabData, language: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].language = language
        }
    }
    
    func closeTab(tab: TabData) {
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty {
            addNewTab()
        } else if selectedTabID == tab.id {
            selectedTabID = tabs.first?.id
        }
    }
    
    func saveFile(tab: TabData) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let url = tabs[index].fileURL {
            do {
                try tabs[index].content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Error saving file: \(error)")
            }
        } else {
            saveFileAs(tab: tab)
        }
    }
    
    func saveFileAs(tab: TabData) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tabs[index].name
        panel.allowedContentTypes = [.text, .swiftSource, .pythonScript, .javaScript, .html, .css, .cSource, .json, UTType(importedAs: "public.markdown")]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try tabs[index].content.write(to: url, atomically: true, encoding: .utf8)
                tabs[index].fileURL = url
                tabs[index].name = url.lastPathComponent
            } catch {
                print("Error saving file: \(error)")
            }
        }
    }
    
    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, .sourceCode, .swiftSource, .pythonScript, .javaScript, .html, .css, .cSource, .json, UTType(importedAs: "public.markdown")]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let newTab = TabData(name: url.lastPathComponent,
                                     content: content,
                                     language: languageMap[url.pathExtension.lowercased()] ?? "swift",
                                     fileURL: url)
                tabs.append(newTab)
                selectedTabID = newTab.id
            } catch {
                print("Error opening file: \(error)")
            }
        }
    }
    
    func wordCount(for text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }
}
