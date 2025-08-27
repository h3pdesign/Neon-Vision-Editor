import SwiftUI
import Highlightr
import UniformTypeIdentifiers
import Combine
import SwiftData
import AppKit

// MARK: - ContentView
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: ViewModel
    @State private var showSidebar: Bool = true
    @State private var selectedTOCItem: String? = nil
    
    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            ForEach(viewModel.tabs, id: \.id) { tab in
                VStack {
                    HStack(spacing: 0) {
                        if showSidebar {
                            SidebarView(content: tab.content, language: tab.language, selectedTOCItem: $selectedTOCItem)
                        }
                        CustomTextEditor(text: Binding(
                            get: { tab.content },
                            set: { tab.content = $0 }
                        ), language: Binding(
                            get: { tab.language },
                            set: { tab.language = $0 }
                        ), highlightr: HighlightrViewModel().highlightr)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(minWidth: 1000, minHeight: 600)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
                    .toolbar {
                        ToolbarItemGroup {
                            HStack(spacing: 10) {
                                Picker("", selection: Binding(
                                    get: { tab.language },
                                    set: { tab.language = $0 }
                                )) {
                                    ForEach(["HTML", "C", "Swift", "Python", "C++", "Java", "Bash", "JSON", "Markdown"], id: \.self) { lang in
                                        Text(lang).tag(lang.lowercased())
                                    }
                                }
                                .labelsHidden()
                                .onChange(of: tab.language) { _, newValue in
                                    NotificationCenter.default.post(name: .languageChanged, object: newValue)
                                }
                                Button(action: { showSidebar.toggle() }) {
                                    Image(systemName: "sidebar.left")
                                }
                                .buttonStyle(.borderless)
                                Button(action: { openFile(tab) }) {
                                    Image(systemName: "folder.badge.plus")
                                }
                                .buttonStyle(.borderless)
                                Button(action: { saveFile(tab) }) {
                                    Image(systemName: "floppydisk")
                                }
                                .buttonStyle(.borderless)
                                Button(action: { saveAsFile(tab) }) {
                                    Image(systemName: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderless)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .tabItem {
                    Text(tab.name)
                }
                .tag(tab as Tab?)
            }
        }
        .tabViewStyle(.automatic) // Enables native macOS tabbing
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
    }
    
    func openFile(_ tab: Tab) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.text, .sourceCode, UTType.html, UTType.cSource, UTType.swiftSource, UTType.pythonScript, UTType("public.shell-script")!, UTType("public.markdown")!]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let language = languageMap[url.pathExtension.lowercased()] ?? "plaintext"
            tab.content = content
            tab.language = language
            tab.name = url.lastPathComponent
            if let window = NSApplication.shared.windows.first {
                window.title = tab.name
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    window.title = tab.name
                }
            }
        } catch {
            print("Error opening file: \(error)")
        }
    }
    
    func saveFile(_ tab: Tab) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text, .sourceCode, UTType.html, UTType.cSource, UTType.swiftSource, UTType.pythonScript, UTType("public.shell-script")!, UTType("public.markdown")!]
        savePanel.nameFieldStringValue = tab.name
        
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try tab.content.write(to: url, atomically: true, encoding: .utf8)
            try viewModel.saveTab(tab)
            tab.name = url.lastPathComponent
            if let window = NSApplication.shared.windows.first {
                window.title = tab.name
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    window.title = tab.name
                }
            }
            print("Successfully saved file to: \(url.path)")
        } catch {
            print("Error saving file: \(error)")
        }
    }
    
    func saveAsFile(_ tab: Tab) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text, .sourceCode, UTType.html, UTType.cSource, UTType.swiftSource, UTType.pythonScript, UTType("public.shell-script")!, UTType("public.markdown")!]
        savePanel.nameFieldStringValue = tab.name
        
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try tab.content.write(to: url, atomically: true, encoding: .utf8)
            try viewModel.saveTab(tab)
            tab.name = url.lastPathComponent
            if let window = NSApplication.shared.windows.first {
                window.title = tab.name
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    window.title = tab.name
                }
            }
            print("Successfully saved as file to: \(url.path)")
        } catch {
            print("Error saving as file: \(error)")
        }
    }
    
    let languageMap: [String: String] = [
        "html": "html", "htm": "html",
        "c": "c", "h": "c",
        "swift": "swift",
        "py": "python",
        "cpp": "cpp",
        "java": "java",
        "sh": "bash",
        "json": "json",
        "md": "markdown", "markdown": "markdown"
    ]
}

// MARK: - SidebarView
struct SidebarView: View {
    let content: String
    let language: String
    @Binding var selectedTOCItem: String?
    
    var body: some View {
        List(generateTableOfContents(), id: \.self, selection: $selectedTOCItem) { item in
            Text(item)
                .foregroundColor(.gray)
                .onTapGesture {
                    selectedTOCItem = item
                    if let lineNumber = lineNumber(for: item) {
                        NotificationCenter.default.post(name: .moveCursorToLine, object: lineNumber)
                    }
                }
        }
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .listStyle(.sidebar)
    }
    
    func generateTableOfContents() -> [String] {
        if content.isEmpty {
            return ["No content"]
        }
        switch language.lowercased() {
        case "markdown":
            return content.components(separatedBy: .newlines)
                .filter { $0.hasPrefix("#") }
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression) }
        case "swift", "c", "cpp", "java", "python":
            return content.components(separatedBy: .newlines)
                .filter { $0.contains("func") || $0.contains("def") || $0.contains("class") }
                .map { line in
                    let components = line.components(separatedBy: .whitespaces)
                    return components.last { !$0.isEmpty && !["func", "def", "class"].contains($0) } ?? line
                }
        default:
            return ["No table of contents available for \(language)"]
        }
    }
    
    func lineNumber(for tocItem: String) -> Int? {
        if content.isEmpty {
            return nil
        }
        let lines = content.components(separatedBy: .newlines)
        return lines.firstIndex { $0.contains(tocItem) }
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
        textView.font = NSFont(name: "SFMono-Regular", size: 12.0) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        
        let appearance = NSAppearance.currentDrawing()
        if appearance.name == .darkAqua {
            textView.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.85)
            textView.textColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.85)
        } else {
            textView.backgroundColor = NSColor(red: 1, green: 1, blue: 1, alpha: 0.85)
            textView.textColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0.85)
        }
        
        textView.delegate = context.coordinator
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { notification in
            guard let newLanguage = notification.object as? String else { return }
            language = newLanguage
            textView.string = text
            if let highlightedText = highlightr.highlight(text, as: newLanguage == "markdown" ? "md" : newLanguage) {
                textStorage.setAttributedString(highlightedText)
            }
            textStorage.language = newLanguage == "markdown" ? "md" : newLanguage
        }
        
        NotificationCenter.default.addObserver(forName: .moveCursorToLine, object: nil, queue: .main) { notification in
            guard let lineNumber = notification.object as? Int else { return }
            textView.scrollToLine(lineNumber)
            textView.setSelectedRange(NSRange(location: textView.lineStartIndex(at: lineNumber) ?? 0, length: 0))
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
        guard let textView = nsView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        let textStorage = textView.textStorage as! CodeAttributedString
        textStorage.beginEditing()
        if let highlightedText = highlightr.highlight(text, as: language == "markdown" ? "md" : language) {
            textStorage.setAttributedString(highlightedText)
        }
        textStorage.endEditing()
        textStorage.language = language == "markdown" ? "md" : language
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CustomTextEditor
        
        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Extensions
extension NSTextView {
    func lineStartIndex(at lineNumber: Int) -> Int? {
        guard lineNumber >= 0, lineNumber < string.components(separatedBy: .newlines).count else { return nil }
        let lines = string.components(separatedBy: .newlines)
        var position = 0
        for i in 0...lineNumber where i < lines.count {
            position += lines[i].count + 1
        }
        return position > string.count ? nil : position
    }
    
    func scrollToLine(_ lineNumber: Int) {
        guard let startIndex = lineStartIndex(at: lineNumber) else { return }
        guard let glyphRange = layoutManager?.glyphRange(forCharacterRange: NSRange(location: startIndex, length: 0), actualCharacterRange: nil) else { return }
        scrollRangeToVisible(glyphRange)
    }
}

extension Notification.Name {
    static let moveCursorToLine = Notification.Name("moveCursorToLine")
    static let languageChanged = Notification.Name("languageChanged")
}