// FIXES APPLIED: Consistent rename and content persistence for tab creation and language updates
import SwiftUI
import AppKit

// Extension to calculate string width
extension String {
    func width(usingFont font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        let size = (self as NSString).size(withAttributes: attributes)
        return size.width
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showGrokError) private var showGrokError
    @Environment(\.grokErrorMessage) private var grokErrorMessage
    @Environment(\.selectedAIModel) private var selectedAIModel
    
    @State private var singleContent: String = ""
    @State private var singleLanguage: String = "swift"
    
    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            editorView
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(.ultraThinMaterial)
        .overlay(.ultraThinMaterial.opacity(0.2)) // Fallback for liquidGlassEffect
        .sheet(isPresented: $viewModel.showingRename) {
            renameSheet
        }
        .alert("AI Error", isPresented: showGrokError) {
            Button("OK") { }
        } message: {
            Text(grokErrorMessage.wrappedValue)
        }
        .navigationTitle("NeonVision Editor")
    }
    
    @ViewBuilder
    private var sidebarView: some View {
        if viewModel.showSidebar && !viewModel.isBrainDumpMode {
            SidebarView(content: (viewModel.selectedTab?.content ?? singleContent),
                       language: (viewModel.selectedTab?.language ?? singleLanguage))
                .frame(minWidth: 200, idealWidth: 250)
                .background(.ultraThinMaterial)
                .overlay(.ultraThinMaterial.opacity(0.2))
                .animation(.spring(), value: viewModel.showSidebar)
                .safeAreaInset(edge: .bottom) {
                    Divider()
                }
        }
    }
    
    @ViewBuilder
    private var editorView: some View {
        VStack(spacing: 0) {
            tabViewContent
            if !viewModel.isBrainDumpMode {
                wordCountView
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Language", selection: Binding(
                    get: {
                        viewModel.selectedTab?.language ?? singleLanguage
                    },
                    set: { newLang in
                        if let selectedID = viewModel.selectedTabID, let idx = viewModel.tabs.firstIndex(where: { $0.id == selectedID }) {
                            viewModel.tabs[idx].language = newLang
                        } else {
                            singleLanguage = newLang
                        }
                    }
                )) {
                    ForEach(["swift", "python", "javascript", "html", "css", "c", "cpp", "json", "markdown"], id: \.self) { lang in
                        Text(lang.capitalized).tag(lang)
                    }
                }
                .frame(width: 150)
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("AI Model", selection: selectedAIModel) {
                    Text("Apple Intelligence").tag(AIModel.appleIntelligence)
                    Text("Grok").tag(AIModel.grok)
                }
                .frame(width: 150)
            }
            ToolbarItemGroup(placement: .automatic) {
                Button(action: { viewModel.openFile() }) {
                    Image(systemName: "folder")
                }
                Button(action: { if let tab = viewModel.selectedTab { viewModel.saveFile(tab: tab) } }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(viewModel.selectedTab == nil)
                Button(action: { viewModel.showSidebar.toggle() }) {
                    Image(systemName: viewModel.showSidebar ? "sidebar.left" : "sidebar.right")
                }
                Button(action: { viewModel.isBrainDumpMode.toggle() }) {
                    Image(systemName: "note.text")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Added to expand editorView
    }
    
    @ViewBuilder
    private var tabViewContent: some View {
        VStack(spacing: 0) {
            CustomTextEditor(
                text: Binding(
                    get: {
                        if let selID = viewModel.selectedTabID, let tab = viewModel.tabs.first(where: { $0.id == selID }) {
                            return tab.content
                        } else {
                            return singleContent
                        }
                    },
                    set: { newValue in
                        if let selID = viewModel.selectedTabID, let tab = viewModel.tabs.first(where: { $0.id == selID }) {
                            viewModel.updateTabContent(tab: tab, content: newValue)
                        } else {
                            singleContent = newValue
                        }
                    }
                ),
                language: viewModel.selectedTab?.language ?? singleLanguage,
                colorScheme: colorScheme
            )
            .frame(maxWidth: viewModel.isBrainDumpMode ? 800 : .infinity)
            .padding(viewModel.isBrainDumpMode ? .horizontal : [], 100)
        }
    }
    
    @ViewBuilder
    private var wordCountView: some View {
        HStack {
            Spacer()
            Text("Words: \(viewModel.wordCount(for: viewModel.selectedTab?.content ?? ""))")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
                .padding(.trailing, 16)
        }
    }
    
    @ViewBuilder
    private var renameSheet: some View {
        VStack {
            Text("Rename Tab")
                .font(.headline)
            TextField("Name", text: $viewModel.renameText)
                .textFieldStyle(.roundedBorder)
                .padding()
            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.showingRename = false
                }
                .buttonStyle(.bordered)

                Button("OK") {
                    // Ensure we have a selected tab; if not, select the first available tab
                    if viewModel.selectedTab == nil, let first = viewModel.tabs.first {
                        viewModel.selectedTabID = first.id
                    }
                    if let tab = viewModel.selectedTab {
                        if viewModel.selectedTabID != tab.id {
                            viewModel.selectedTabID = tab.id
                        }
                        viewModel.renameTab(tab: tab, newName: viewModel.renameText)
                    }
                    viewModel.showingRename = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.renameText.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 12)
        .interactiveDismissDisabled(false)
        .allowsHitTesting(true)
    }
}

struct SidebarView: View {
    let content: String
    let language: String
    @State private var selectedTOCItem: String?
    
    var body: some View {
        List(generateTableOfContents(), id: \.self, selection: $selectedTOCItem) { item in
            Text(item)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .onTapGesture {
                    if let lineNumber = lineNumber(for: item) {
                        NotificationCenter.default.post(name: .moveCursorToLine, object: lineNumber)
                    }
                }
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    func generateTableOfContents() -> [String] {
        guard !content.isEmpty else { return ["No content available"] }
        let lines = content.components(separatedBy: .newlines)
        var toc: [String] = []
        
        switch language {
        case "swift":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("func ") || trimmed.hasPrefix("struct ") ||
                   trimmed.hasPrefix("class ") || trimmed.hasPrefix("enum ") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "python":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "javascript":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("function ") || trimmed.hasPrefix("class ") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "c", "cpp":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("(") && !trimmed.contains(";") && (trimmed.hasPrefix("void ") || trimmed.hasPrefix("int ") || trimmed.hasPrefix("float ") || trimmed.hasPrefix("double ") || trimmed.hasPrefix("char ") || trimmed.contains("{")) {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "html", "css", "json", "markdown":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && (trimmed.hasPrefix("#") || trimmed.hasPrefix("<h")) {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        default:
            return ["Unsupported language"]
        }
        
        return toc.isEmpty ? ["No headers found"] : toc
    }
    
    func lineNumber(for item: String) -> Int? {
        let lines = content.components(separatedBy: .newlines)
        return lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == item.components(separatedBy: " (Line").first }
    }
}

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    let language: String
    let colorScheme: ColorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        // Use AppKit's factory to get a properly configured scroll view + text view
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        // Configure text view
        textView.isEditable = true
        textView.isRulerVisible = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textColor = .labelColor

        // Plain text configuration and initial value
        textView.isRichText = false
        textView.usesRuler = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.string = self.text

        // Disable smart replacements/spell checking for code
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Sizing behavior: allow vertical growth and wrap to width
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.postsFrameChangedNotifications = true

        if let container = textView.textContainer {
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            container.widthTracksTextView = true
            container.heightTracksTextView = false
        }

        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear

        // Keep container width in sync with scroll view size changes
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(context.coordinator.scrollViewBoundsDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)

        // Coordinator and notifications
        textView.delegate = context.coordinator
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(context.coordinator.updateTextContainerSize), name: NSView.frameDidChangeNotification, object: textView)
        context.coordinator.textView = textView

        // Apply initial syntax highlighting
        context.coordinator.applySyntaxHighlighting()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            // Only push SwiftUI -> AppKit when the source of truth changed
            if textView.string != self.text {
                textView.string = self.text
                context.coordinator.applySyntaxHighlighting()
            }
            // Do not write back here. Coordinator's textDidChange handles AppKit -> SwiftUI updates.
            
            if let container = textView.textContainer {
                let width = nsView.contentSize.width
                if container.containerSize.width != width {
                    container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
                    container.widthTracksTextView = true
                }
            }
            textView.invalidateIntrinsicContentSize()
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        weak var textView: NSTextView?
        
        init(_ parent: CustomTextEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(moveToLine(_:)), name: .moveCursorToLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(streamSuggestion(_:)), name: .streamSuggestion, object: nil)
        }
        
        @objc func moveToLine(_ notification: Notification) {
            guard let lineNumber = notification.object as? Int,
                  let textView = textView,
                  !parent.text.isEmpty else { return }
            
            let lines = parent.text.components(separatedBy: .newlines)
            guard lineNumber >= 0 && lineNumber < lines.count else { return }
            
            let lineStart = lines[0..<lineNumber].joined(separator: "\n").count + (lineNumber > 0 ? 1 : 0)
            textView.setSelectedRange(NSRange(location: lineStart, length: 0))
            textView.scrollRangeToVisible(NSRange(location: lineStart, length: 0))
        }
        
        @objc func streamSuggestion(_ notification: Notification) {
            guard let stream = notification.object as? AsyncStream<String>,
                  let textView = textView else { return }
            
            Task {
                for await chunk in stream {
                    textView.textStorage?.append(NSAttributedString(string: chunk))
                    textView.scrollToEndOfDocument(nil)
                    parent.text = textView.string
                }
            }
        }
        
        @objc func updateTextContainerSize() {
            if let tv = textView, let sv = tv.enclosingScrollView {
                tv.textContainer?.containerSize = NSSize(width: sv.contentSize.width, height: .greatestFiniteMagnitude)
                tv.textContainer?.widthTracksTextView = true
            }
        }
        
        @objc func scrollViewBoundsDidChange(_ notification: Notification) {
            if let tv = textView, let sv = tv.enclosingScrollView {
                tv.textContainer?.containerSize = NSSize(width: sv.contentSize.width, height: .greatestFiniteMagnitude)
                tv.textContainer?.widthTracksTextView = true
                tv.invalidateIntrinsicContentSize()
                tv.layoutManager?.ensureLayout(for: tv.textContainer!)
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            
            if let container = textView.textContainer, let scrollView = textView.enclosingScrollView {
                container.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
                container.widthTracksTextView = true
                textView.invalidateIntrinsicContentSize()
                textView.layoutManager?.ensureLayout(for: container)
            }
            
            applySyntaxHighlighting()
        }
        
        func applySyntaxHighlighting() {
            guard let textView = textView else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            // Replace the line below with adaptive label color instead of removing attribute
            textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            let colors = SyntaxColors.fromVibrantLightTheme(colorScheme: parent.colorScheme)
            let patterns = getSyntaxPatterns(for: parent.language, colors: colors)
            for (pattern, color) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                let matches = regex.matches(in: textView.string, range: fullRange)
                for match in matches {
                    textView.textStorage?.addAttribute(.foregroundColor, value: NSColor(color), range: match.range)
                }
            }
        }
    }
}

struct SyntaxColors {
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let attribute: Color
    let variable: Color
    let def: Color
    let property: Color
    let meta: Color
    let tag: Color
    let atom: Color
    let builtin: Color
    let type: Color
    
    static func fromVibrantLightTheme(colorScheme: ColorScheme) -> SyntaxColors {
        let baseColors: [String: (light: Color, dark: Color)] = [
            "keyword": (light: Color(red: 251/255, green: 0/255, blue: 186/255), dark: Color(red: 251/255, green: 0/255, blue: 186/255)),
            "string": (light: Color(red: 190/255, green: 0/255, blue: 255/255), dark: Color(red: 190/255, green: 0/255, blue: 255/255)),
            "number": (light: Color(red: 28/255, green: 0/255, blue: 207/255), dark: Color(red: 28/255, green: 0/255, blue: 207/255)),
            "comment": (light: Color(red: 93/255, green: 108/255, blue: 121/255), dark: Color(red: 150/255, green: 160/255, blue: 170/255)),
            "attribute": (light: Color(red: 57/255, green: 0/255, blue: 255/255), dark: Color(red: 57/255, green: 0/255, blue: 255/255)),
            "variable": (light: Color(red: 19/255, green: 0/255, blue: 255/255), dark: Color(red: 19/255, green: 0/255, blue: 255/255)),
            "def": (light: Color(red: 29/255, green: 196/255, blue: 83/255), dark: Color(red: 29/255, green: 196/255, blue: 83/255)),
            "property": (light: Color(red: 29/255, green: 196/255, blue: 83/255), dark: Color(red: 29/255, green: 0/255, blue: 160/255)),
            "meta": (light: Color(red: 255/255, green: 16/255, blue: 0/255), dark: Color(red: 255/255, green: 16/255, blue: 0/255)),
            "tag": (light: Color(red: 170/255, green: 0/255, blue: 160/255), dark: Color(red: 170/255, green: 0/255, blue: 160/255)),
            "atom": (light: Color(red: 28/255, green: 0/255, blue: 207/255), dark: Color(red: 28/255, green: 0/255, blue: 207/255)),
            "builtin": (light: Color(red: 255/255, green: 130/255, blue: 0/255), dark: Color(red: 255/255, green: 130/255, blue: 0/255)),
            "type": (light: Color(red: 170/255, green: 0/255, blue: 160/255), dark: Color(red: 170/255, green: 0/255, blue: 160/255))
        ]
        
        return SyntaxColors(
            keyword: colorScheme == .dark ? baseColors["keyword"]!.dark : baseColors["keyword"]!.light,
            string: colorScheme == .dark ? baseColors["string"]!.dark : baseColors["string"]!.light,
            number: colorScheme == .dark ? baseColors["number"]!.dark : baseColors["number"]!.light,
            comment: colorScheme == .dark ? baseColors["comment"]!.dark : baseColors["comment"]!.light,
            attribute: colorScheme == .dark ? baseColors["attribute"]!.dark : baseColors["attribute"]!.light,
            variable: colorScheme == .dark ? baseColors["variable"]!.dark : baseColors["variable"]!.light,
            def: colorScheme == .dark ? baseColors["def"]!.dark : baseColors["def"]!.light,
            property: colorScheme == .dark ? baseColors["property"]!.dark : baseColors["property"]!.light,
            meta: colorScheme == .dark ? baseColors["meta"]!.dark : baseColors["meta"]!.light,
            tag: colorScheme == .dark ? baseColors["tag"]!.dark : baseColors["tag"]!.light,
            atom: colorScheme == .dark ? baseColors["atom"]!.dark : baseColors["atom"]!.light,
            builtin: colorScheme == .dark ? baseColors["builtin"]!.dark : baseColors["builtin"]!.light,
            type: colorScheme == .dark ? baseColors["type"]!.dark : baseColors["type"]!.light
        )
    }
}

func getSyntaxPatterns(for language: String, colors: SyntaxColors) -> [String: Color] {
    switch language {
    case "swift":
        return [
            "\\b(func|struct|class|enum|protocol|extension|if|else|for|while|switch|case|default|guard|defer|throw|try|catch|return|init|deinit)\\b": colors.keyword,
            "\"[^\"]*\"": colors.string,
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,
            "//.*": colors.comment,
            "/\\*([^*]|(\\*+[^*/]))*\\*+/": colors.comment,
            "@\\w+": colors.attribute,
            "\\b(var|let)\\b": colors.variable,
            "\\b(String|Int|Double|Bool)\\b": colors.type
        ]
    case "python":
        return [
            "\\b(def|class|if|else|for|while|try|except|with|as|import|from)\\b": colors.keyword,
            "\\b(int|str|float|bool|list|dict)\\b": colors.type,
            "\"[^\"]*\"|'[^']*'": colors.string,
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,
            "#.*": colors.comment
        ]
    case "javascript":
        return [
            "\\b(function|var|let|const|if|else|for|while|do|try|catch)\\b": colors.keyword,
            "\\b(Number|String|Boolean|Object|Array)\\b": colors.type,
            "\"[^\"]*\"|'[^']*'|\\`[^\\`]*\\`": colors.string,
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,
            "//.*|/\\*([^*]|(\\*+[^*/]))*\\*+/": colors.comment
        ]
    case "html":
        return ["<[^>]+>": colors.tag]
    case "css":
        return ["\\b([a-zA-Z-]+\\s*:\\s*[^;]+;)": colors.property]
    case "c", "cpp":
        return [
            "\\b(int|float|double|char|void|if|else|for|while|do|switch|case|return)\\b": colors.keyword,
            "\\b(int|float|double|char)\\b": colors.type,
            "\"[^\"]*\"": colors.string,
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,
            "//.*|/\\*([^*]|(\\*+[^*/]))*\\*+/": colors.comment
        ]
    case "json":
        return [
            "\"[^\"]+\"\\s*:": colors.property,
            "\"[^\"]*\"": colors.string,
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,
            "\\b(true|false|null)\\b": colors.keyword
        ]
    case "markdown":
        return [
            "^#+\\s*[^#]+": colors.keyword,
            "\\*\\*[^\\*\\*]+\\*\\*": colors.def,
            "\\_[^\\_]+\\_": colors.def
        ]
    default:
        return [:]
    }
}

extension Notification.Name {
    static let moveCursorToLine = Notification.Name("moveCursorToLine")
    static let streamSuggestion = Notification.Name("streamSuggestion")
}

