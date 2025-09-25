import SwiftUI
import AppKit // Added for NSFont and NSAttributedString

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
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            if viewModel.showSidebar && !viewModel.isBrainDumpMode {
                SidebarView(content: viewModel.selectedTab?.content ?? "",
                           language: viewModel.selectedTab?.language ?? "swift")
                    .frame(minWidth: 200)
                    .toolbar {
                        ToolbarItem {
                            Picker("Language", selection: Binding(
                                get: { viewModel.selectedTab?.language ?? "swift" },
                                set: { if let tab = viewModel.selectedTab { viewModel.updateTabLanguage(tab: tab, language: $0) }
                            })) {
                                ForEach(["swift", "python", "javascript", "html", "css", "c", "cpp", "json", "markdown"], id: \.self) { lang in
                                    Text(lang.capitalized).tag(lang)
                                }
                            }
                        }
                    }
            }
        } detail: {
            // Main Editor with Tabs
            VStack {
                if !viewModel.tabs.isEmpty {
                    TabView(selection: $viewModel.selectedTabID) {
                        ForEach(viewModel.tabs) { tab in
                            HighlightedTextEditor(
                                text: Binding(
                                    get: { tab.content },
                                    set: { viewModel.updateTabContent(tab: tab, content: $0) }
                                ),
                                language: tab.language,
                                colorScheme: colorScheme
                            )
                            .frame(maxWidth: viewModel.isBrainDumpMode ? 800 : .infinity)
                            .padding(viewModel.isBrainDumpMode ? .horizontal : [], 100)
                            .tabItem {
                                Text(tab.name + (tab.fileURL == nil && !tab.content.isEmpty ? " *" : ""))
                            }
                            .tag(tab.id)
                        }
                    }
                    
                    if !viewModel.isBrainDumpMode {
                        HStack {
                            Spacer()
                            Text("Words: \(viewModel.wordCount(for: viewModel.selectedTab?.content ?? ""))")
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                                .padding(.trailing, 8)
                        }
                    }
                } else {
                    Text("Select a tab or create a new one")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button(action: { viewModel.addNewTab(); viewModel.showingRename = true; viewModel.renameText = viewModel.selectedTab?.name ?? "Untitled" }) {
                        Image(systemName: "plus")
                    }
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
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $viewModel.showingRename) {
            VStack {
                Text("Rename Tab")
                    .font(.headline)
                TextField("Name", text: $viewModel.renameText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                HStack {
                    Button("Cancel") { viewModel.showingRename = false }
                    Button("OK") {
                        if let tab = viewModel.selectedTab {
                            viewModel.renameTab(tab: tab, newName: viewModel.renameText)
                        }
                        viewModel.showingRename = false
                    }
                    .disabled(viewModel.renameText.isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .navigationTitle(viewModel.selectedTab?.name ?? "NeonVision Editor")
    }
}

struct SidebarView: View {
    let content: String
    let language: String
    @State private var selectedTOCItem: String?
    
    var body: some View {
        List(generateTableOfContents(), id: \.self, selection: $selectedTOCItem) { item in
            Text(item)
                .foregroundColor(.secondary)
                .padding(.vertical, 2)
                .onTapGesture {
                    if let lineNumber = lineNumber(for: item) {
                        NotificationCenter.default.post(name: .moveCursorToLine, object: lineNumber)
                    }
                }
        }
        .listStyle(.sidebar)
    }
    
    func generateTableOfContents() -> [String] {
        if content.isEmpty {
            return ["No content"]
        }
        let lines = content.components(separatedBy: .newlines)
        switch language {
        case "swift":
            return lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("func") || trimmed.hasPrefix("struct") ||
                   trimmed.hasPrefix("class") || trimmed.hasPrefix("enum") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "python":
            return lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("def") || trimmed.hasPrefix("class") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "javascript":
            return lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("function") || trimmed.hasPrefix("class") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "c", "cpp":
            return lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("(") && !trimmed.contains(";") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "html", "css", "json", "markdown":
            return lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && (trimmed.hasPrefix("#") || trimmed.hasPrefix("<h")) {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        default:
            return []
        }
    }
    
    func lineNumber(for item: String) -> Int? {
        let lines = content.components(separatedBy: .newlines)
        return lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == item.components(separatedBy: " (Line").first }
    }
}

struct HighlightedTextEditor: View {
    @Binding var text: String
    let language: String
    let colorScheme: ColorScheme
    
    var body: some View {
        TextEditor(text: $text)
            .font(.custom("SF Mono", size: 13))
            .padding(10)
            .background(.ultraThinMaterial)
            .overlay(
                GeometryReader { geo in
                    HighlightOverlay(text: text, language: language, colorScheme: colorScheme)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            )
    }
}

struct HighlightOverlay: View {
    let text: String
    let language: String
    let colorScheme: ColorScheme
    
    var body: some View {
        Text(text)
            .font(.custom("SF Mono", size: 13))
            .foregroundColor(.clear)
            .overlay(
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ForEach(highlightedRanges, id: \.id) { range in
                            Text(range.text)
                                .font(.custom("SF Mono", size: 13))
                                .foregroundColor(range.color)
                                .offset(range.offset)
                        }
                    }
                }
            )
    }
    
    private var highlightedRanges: [HighlightedRange] {
        var ranges: [HighlightedRange] = []
        let colors = SyntaxColors.fromVibrantLightTheme(colorScheme: colorScheme)
        let patterns = getSyntaxPatterns(for: language, colors: colors)
        
        for (pattern, color) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
                
                for match in matches {
                    let range = match.range
                    let matchedText = nsString.substring(with: range)
                    let lines = text[..<nsString.substring(to: range.location).endIndex].components(separatedBy: .newlines)
                    let lineNumber = lines.count - 1
                    let lineStart = lines.dropLast().joined(separator: "\n").count + (lineNumber > 0 ? 1 : 0)
                    let xOffset = CGFloat(nsString.substring(with: NSRange(location: lineStart, length: range.location - lineStart)).width(usingFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)))
                    let yOffset = CGFloat(lineNumber) * 20 // Approximate line height
                    
                    ranges.append(HighlightedRange(
                        id: UUID(),
                        text: matchedText,
                        color: Color(color),
                        offset: CGSize(width: xOffset, height: yOffset)
                    ))
                }
            }
        }
        return ranges
    }
}

struct HighlightedRange: Identifiable {
    let id: UUID
    let text: String
    let color: Color
    let offset: CGSize
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
}
