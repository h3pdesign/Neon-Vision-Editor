import SwiftUI
import Highlightr
import UniformTypeIdentifiers
import Combine
import SwiftData
import AppKit

// MARK: - ContentViewModel
class ContentViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var selectedLanguage: String = "swift"
    @Published var tabs: [Item] = []
    @Published var selectedTab: Item? = nil
    @Published var showSidebar = true
    @Published var selectedTOCItem: String? // Track selected table of contents item
    
    let languages: [String] = ["HTML", "C", "Swift", "Python", "C++", "Java", "Bash", "JSON", "Markdown"]
    let languageMap: [String: String] = [
        "html": "html",
        "htm": "html",
        "c": "c",
        "h": "c",
        "swift": "swift",
        "py": "python",
        "cpp": "cpp",
        "java": "java",
        "sh": "bash",
        "json": "json",
        "md": "markdown",
        "markdown": "markdown"
    ]
    
    private var modelContext: ModelContext?
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadTabs()
    }
    
    func openFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.text, .sourceCode, UTType.html, UTType.cSource, UTType.swiftSource, UTType.pythonScript, UTType("public.shell-script")!, UTType("public.markdown")!]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let lang = languageMap[url.pathExtension.lowercased()] ?? "plaintext"
                selectedLanguage = lang
                let newItem = Item(name: url.lastPathComponent, content: content, language: selectedLanguage)
                tabs.append(newItem)
                selectedTab = newItem
                saveToSwiftData(url.lastPathComponent)
            } catch {
                print("Error opening file: \(error)")
            }
        }
    }
    
    func saveFile() {
        guard let selectedItem = selectedTab else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text, .sourceCode, UTType.html, UTType.cSource, UTType.swiftSource, UTType.pythonScript, UTType("public.shell-script")!, UTType("public.markdown")!]
        savePanel.nameFieldStringValue = selectedItem.name
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try selectedItem.content.write(to: url, atomically: true, encoding: .utf8)
                saveToSwiftData(selectedItem.name)
            } catch {
                print("Error saving file: \(error)")
            }
        }
    }
    
    func saveAsFile() {
        guard let selectedItem = selectedTab else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text, .sourceCode, UTType.html, UTType.cSource, UTType.swiftSource, UTType.pythonScript, UTType("public.shell-script")!, UTType("public.markdown")!]
        savePanel.nameFieldStringValue = selectedItem.name
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try selectedItem.content.write(to: url, atomically: true, encoding: .utf8)
                saveToSwiftData(selectedItem.name)
            } catch {
                print("Error saving as file: \(error)")
            }
        }
    }
    
    func addNewTab() {
        let newItem = Item(name: "Note", content: "", language: selectedLanguage)
        tabs.append(newItem)
        selectedTab = newItem
        saveToSwiftData(newItem.name)
    }
    
    func removeTab(_ item: Item) {
        if let index = tabs.firstIndex(of: item) {
            tabs.remove(at: index)
            if selectedTab == item {
                selectedTab = tabs.last ?? nil
            }
            if let context = modelContext {
                do {
                    try context.save()
                    context.delete(item)
                } catch {
                    print("Failed to delete from SwiftData: \(error)")
                }
            }
        }
    }
    
    func updateContent(_ content: String) {
        if let selectedItem = selectedTab {
            selectedItem.content = content
            saveToSwiftData(selectedItem.name)
            print("ViewModel updated content to: \(content)")
        }
    }
    
    func updateLanguage(_ language: String) {
        if let selectedItem = selectedTab {
            selectedItem.language = language
            saveToSwiftData(selectedItem.name)
        }
    }
    
    private func saveToSwiftData(_ name: String) {
        if let selectedItem = selectedTab, let context = modelContext {
            do {
                try context.save()
                if let existingItem = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name)]))
                    .first(where: { $0.name == name }) {
                    existingItem.content = selectedItem.content
                    existingItem.language = selectedItem.language
                } else {
                    context.insert(selectedItem)
                }
            } catch {
                print("Failed to save to SwiftData: \(error)")
            }
        }
    }
    
    func loadTabs() {
        if let context = modelContext {
            do {
                let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name)])
                tabs = try context.fetch(descriptor)
                if let firstTab = tabs.first {
                    selectedTab = firstTab
                } else {
                    addNewTab()
                }
            } catch {
                print("Failed to load tabs: \(error)")
                addNewTab()
            }
        } else {
            addNewTab()
        }
    }
    
    func toggleSidebar() {
        showSidebar = !showSidebar
    }
    
    // Generate table of contents based on selected language and content
    func generateTableOfContents() -> [String] {
        guard let selectedItem = selectedTab, !selectedItem.content.isEmpty else { return ["No content"] }
        
        switch selectedItem.language.lowercased() {
        case "markdown":
            return selectedItem.content.components(separatedBy: .newlines)
                .filter { $0.hasPrefix("#") }
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression) }
        case "swift", "c", "cpp", "java", "python":
            return selectedItem.content.components(separatedBy: .newlines)
                .filter { $0.contains("func") || $0.contains("def") || $0.contains("class") }
                .map { line in
                    let components = line.components(separatedBy: .whitespaces)
                    return components.last { !$0.isEmpty && !["func", "def", "class"].contains($0) } ?? line
                }
        default:
            return ["No table of contents available for \(selectedItem.language)"]
        }
    }
    
    // Find line number for a given TOC item
    func lineNumber(for tocItem: String) -> Int? {
        guard let selectedItem = selectedTab, !selectedItem.content.isEmpty else { return nil }
        let lines = selectedItem.content.components(separatedBy: .newlines)
        return lines.firstIndex { $0.contains(tocItem) }
    }
}

// MARK: - SidebarView
struct SidebarView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        List(viewModel.generateTableOfContents(), id: \.self, selection: $viewModel.selectedTOCItem) { item in
            Text(item)
                .foregroundColor(Color.gray)
                .onTapGesture {
                    viewModel.selectedTOCItem = item
                    if let lineNumber = viewModel.lineNumber(for: item) {
                        NotificationCenter.default.post(name: .moveCursorToLine, object: lineNumber)
                    }
                }
        }
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .listStyle(SidebarListStyle())
        .frame(minHeight: 0)
    }
}

// MARK: - ContentView
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ContentViewModel()
    
    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            ForEach(viewModel.tabs, id: \.id) { tab in
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if viewModel.showSidebar {
                            SidebarView(viewModel: viewModel)
                        }
                        VStack(spacing: 0) {
                            CustomTextEditor(text: Binding(
                                get: { tab.content },
                                set: { viewModel.updateContent($0) }
                            ), language: $viewModel.selectedLanguage, highlightr: HighlightrViewModel().highlightr)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .tabItem {
                    Text(tab.name)
                }
                .tag(tab as Item?)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 10) {
                    Text("Neon Vision Editor")
                        .foregroundColor(.white)
                    Picker("", selection: $viewModel.selectedLanguage) {
                        ForEach(viewModel.languages, id: \.self) { lang in
                            Text(lang).tag(lang.lowercased())
                        }
                    }
                    .labelsHidden()
                    Button(action: viewModel.toggleSidebar) {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.borderless)
                    Button(action: viewModel.openFile) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    Button(action: viewModel.saveFile) {
                        Image(systemName: "floppydisk")
                    }
                    .buttonStyle(.borderless)
                    Button(action: viewModel.saveAsFile) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    Button(action: viewModel.addNewTab) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(8)
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            print("ContentView appeared, loading tabs. Tabs count: \(viewModel.tabs.count)")
            viewModel.loadTabs()
            print("After load, tabs count: \(viewModel.tabs.count), selectedTab: \(String(describing: viewModel.selectedTab))")
        }
    }
}

// MARK: - CustomTextEditor
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var language: String
    let highlightr: Highlightr
    
    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = CodeAttributedString(highlightr: highlightr)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85)
        textView.textColor = NSColor.gray
        textView.delegate = context.coordinator
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add observer for cursor movement
        NotificationCenter.default.addObserver(forName: .moveCursorToLine, object: nil, queue: .main) { notification in
            if let lineNumber = notification.object as? Int {
                textView.scrollToLine(lineNumber)
                textView.setSelectedRange(NSRange(location: textView.lineStartIndex(at: lineNumber) ?? 0, length: 0))
            }
        }
        
        DispatchQueue.main.async {
            textView.string = text
            textStorage.beginEditing()
            if let highlightedText = highlightr.highlight(text, as: language == "markdown" ? "md" : language) {
                textStorage.setAttributedString(highlightedText)
            }
            textStorage.endEditing()
            textStorage.language = language == "markdown" ? "md" : language
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView, textView.string != text {
            textView.string = text
            let textStorage = textView.textStorage as! CodeAttributedString
            textStorage.beginEditing()
            if let highlightedText = highlightr.highlight(text, as: language == "markdown" ? "md" : language) {
                textStorage.setAttributedString(highlightedText)
            }
            textStorage.endEditing()
            textStorage.language = language == "markdown" ? "md" : language
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        
        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
            }
        }
    }
}

// MARK: - Extensions
extension NSTextView {
    func lineStartIndex(at lineNumber: Int) -> Int? {
        guard lineNumber >= 0, lineNumber < string.components(separatedBy: .newlines).count else { return nil }
        let lines = string.components(separatedBy: .newlines)
        var position = 0
        for i in 0...lineNumber {
            if i < lines.count {
                position += lines[i].count + 1 // +1 for newline
            }
        }
        return position > string.count ? nil : position
    }
    
    func scrollToLine(_ lineNumber: Int) {
        guard let startIndex = lineStartIndex(at: lineNumber) else { return }
        let glyphRange = layoutManager?.glyphRange(forCharacterRange: NSRange(location: startIndex, length: 0), actualCharacterRange: nil)
        if let glyphRange = glyphRange {
            scrollRangeToVisible(glyphRange)
        }
    }
}

extension Notification.Name {
    static let moveCursorToLine = Notification.Name("moveCursorToLine")
}

// MARK: - HighlightrViewModel
class HighlightrViewModel {
    let highlightr: Highlightr = {
        if let h = Highlightr() {
            h.setTheme(to: "vs2015")
            return h
        } else {
            fatalError("Highlightr initialization failed. Ensure the package is correctly added via Swift Package Manager.")
        }
    }()
}
