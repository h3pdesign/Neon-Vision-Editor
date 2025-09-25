import SwiftUI
import SwiftData
import UniformTypeIdentifiers

class EditorViewModel: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedTab: Tab?
    @Published var showSidebar: Bool = true

    func addNewTab(context: ModelContext) {
        let newTab = Tab(name: "New Tab \(tabs.count + 1)", content: "", language: "swift")
        tabs.append(newTab)
        context.insert(newTab)
        selectedTab = newTab
        try? context.save()
    }

    func openFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.text, .sourceCode, .swiftSource, .pythonScript, .javaScript, .html, .css, .cSource, .cppSource, .json, .markdown]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let language = languageMap[url.pathExtension.lowercased()] ?? "plaintext"
            let newTab = Tab(name: url.lastPathComponent, content: content, language: language, fileURL: url)
            tabs.append(newTab)
            selectedTab = newTab
            if let context = try? ModelContext(ModelContainer(for: Tab.self)) {
                context.insert(newTab)
                try? context.save()
            }
        } catch {
            print("Error opening file: \(error)")
        }
    }

    func saveFile(tab: Tab) {
        if let url = tab.fileURL {
            do {
                try tab.content.write(to: url, atomically: true, encoding: .utf8)
                print("Saved to \(url.path)")
            } catch {
                print("Error saving file: \(error)")
            }
        } else {
            saveFileAs(tab: tab)
        }
    }

    func saveFileAs(tab: Tab) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text, .sourceCode, .swiftSource, .pythonScript, .javaScript, .html, .css, .cSource, .cppSource, .json, .markdown]
        savePanel.nameFieldStringValue = tab.name

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try tab.content.write(to: url, atomically: true, encoding: .utf8)
            tab.fileURL = url
            tab.name = url.lastPathComponent
            if let context = try? ModelContext(ModelContainer(for: Tab.self)) {
                try? context.save()
            }
            print("Saved as \(url.path)")
        } catch {
            print("Error saving file: \(error)")
        }
    }

    let languageMap: [String: String] = [
        "swift": "swift", "py": "python", "js": "javascript", "html": "html", "css": "css",
        "c": "c", "cpp": "cpp", "json": "json", "md": "markdown"
    ]
}