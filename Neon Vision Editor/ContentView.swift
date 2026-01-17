// Simplified: Single-document editor without tabs; removed AIModel references and fixed compile errors
import SwiftUI
import AppKit

enum AIModel: String, CaseIterable, Identifiable {
    case appleIntelligence
    case grok
    var id: String { rawValue }
}

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

    // Fallback single-document state in case the view model doesn't expose one
    @State private var selectedModel: AIModel = .appleIntelligence
    @State private var singleContent: String = ""
    @State private var singleLanguage: String = "swift"
    @State private var caretStatus: String = "Ln 1, Col 1"
    @State private var editorFontSize: CGFloat = 14

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            editorView
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 600)
        .frame(minWidth: 600, minHeight: 400)
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
            SidebarView(content: currentContent,
                        language: currentLanguage)
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 600)
                .animation(.spring(), value: viewModel.showSidebar)
                .safeAreaInset(edge: .bottom) {
                    Divider()
                }
        }
    }

    private var currentContentBinding: Binding<String> {
        if let tab = viewModel.selectedTab {
            return Binding(
                get: { tab.content },
                set: { newValue in viewModel.updateTabContent(tab: tab, content: newValue) }
            )
        } else {
            return $singleContent
        }
    }

    private var currentLanguageBinding: Binding<String> {
        if let selectedID = viewModel.selectedTabID, let idx = viewModel.tabs.firstIndex(where: { $0.id == selectedID }) {
            return Binding(
                get: { viewModel.tabs[idx].language },
                set: { newValue in viewModel.tabs[idx].language = newValue }
            )
        } else {
            return $singleLanguage
        }
    }

    private var currentContent: String { currentContentBinding.wrappedValue }
    private var currentLanguage: String { currentLanguageBinding.wrappedValue }

    @ViewBuilder
    private var editorView: some View {
        VStack(spacing: 0) {
            // Single editor (no TabView)
            CustomTextEditor(
                text: currentContentBinding,
                language: currentLanguage,
                colorScheme: colorScheme,
                fontSize: editorFontSize,
                isLineWrapEnabled: $viewModel.isLineWrapEnabled
            )
            .frame(maxWidth: viewModel.isBrainDumpMode ? 800 : .infinity)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, viewModel.isBrainDumpMode ? 100 : 0)
            .padding(.vertical, viewModel.isBrainDumpMode ? 40 : 0)

            if !viewModel.isBrainDumpMode {
                wordCountView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .caretPositionDidChange)) { notif in
            if let line = notif.userInfo?["line"] as? Int, let col = notif.userInfo?["column"] as? Int {
                caretStatus = "Ln \(line), Col \(col)"
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Picker("AI Model", selection: $selectedModel) {
                        Text("Apple Intelligence").tag(AIModel.appleIntelligence)
                        Text("Grok").tag(AIModel.grok)
                    }
                    .labelsHidden()
                    .controlSize(.large)
                    .frame(width: 170)
                    .padding(.vertical, 2)

                    Picker("Language", selection: currentLanguageBinding) {
                        ForEach(["swift", "python", "javascript", "html", "css", "c", "cpp", "json", "markdown"], id: \.self) { lang in
                            Text(lang.capitalized).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.large)
                    .frame(width: 140)
                    .padding(.vertical, 2)

                    Divider()
                    Button(action: { editorFontSize = max(8, editorFontSize - 1) }) {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .help("Decrease Font Size")
                    Button(action: { editorFontSize = min(48, editorFontSize + 1) }) {
                        Image(systemName: "textformat.size.larger")
                    }
                    .help("Increase Font Size")
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                Button(action: { viewModel.openFile() }) {
                    Image(systemName: "folder")
                }
                Button(action: {
                    if let tab = viewModel.selectedTab { viewModel.saveFile(tab: tab) }
                }) {
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
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
    }
    @ViewBuilder
    private var wordCountView: some View {
        HStack {
            Spacer()
            Text("\(caretStatus) • Words: \(viewModel.wordCount(for: currentContent))")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
                .padding(.trailing, 16)
        }
    }
}

struct SidebarView: View {
    let content: String
    let language: String
    @State private var selectedTOCItem: String?

    var body: some View {
        List(generateTableOfContents(), id: \.self, selection: $selectedTOCItem) { item in
            Button(action: {
                // Expect item format: "... (Line N)"
                if let startRange = item.range(of: "(Line "),
                   let endRange = item.range(of: ")", range: startRange.upperBound..<item.endIndex) {
                    let numberStr = item[startRange.upperBound..<endRange.lowerBound]
                    if let lineOneBased = Int(numberStr.trimmingCharacters(in: .whitespaces)), lineOneBased > 0 {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .moveCursorToLine, object: lineOneBased)
                        }
                    }
                }
            }) {
                Text(item)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .tag(item)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selectedTOCItem) { oldValue, newValue in
            guard let item = newValue else { return }
            if let startRange = item.range(of: "(Line "),
               let endRange = item.range(of: ")", range: startRange.upperBound..<item.endIndex) {
                let numberStr = item[startRange.upperBound..<endRange.lowerBound]
                if let lineOneBased = Int(numberStr.trimmingCharacters(in: .whitespaces)), lineOneBased > 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .moveCursorToLine, object: lineOneBased)
                    }
                }
            }
        }
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
}

final class AcceptingTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let s = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        if s == "\n" {
            // Auto-indent: copy leading whitespace from current line
            let ns = (string as NSString)
            let sel = selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let currentLine = ns.substring(with: NSRange(location: lineRange.location, length: sel.location - lineRange.location))
            let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
            super.insertText("\n" + indent, replacementRange: replacementRange)
            return
        }
        // Bracket/quote pairing
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"]
        if let closing = pairs[s] {
            let sel = selectedRange()
            super.insertText(s + closing, replacementRange: replacementRange)
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }
}

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    let language: String
    let colorScheme: ColorScheme
    let fontSize: CGFloat
    @Binding var isLineWrapEnabled: Bool

    private func applyWrapMode(isWrapped: Bool, textView: NSTextView, scrollView: NSScrollView) {
        if isWrapped {
            // Wrap: track the text view width, no horizontal scrolling
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.heightTracksTextView = false
            scrollView.hasHorizontalScroller = false
            // Ensure the container width matches the visible content width
            let contentWidth = scrollView.contentSize.width
            let width = contentWidth > 0 ? contentWidth : scrollView.frame.size.width
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            // No wrap: allow horizontal expansion and horizontal scrolling
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.heightTracksTextView = false
            scrollView.hasHorizontalScroller = true
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Use AppKit's factory to get a correctly configured scrollable plain text editor
        let scrollView = NSTextView.scrollablePlainDocumentContentTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Configure the text view
        textView.isEditable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = true
        textView.isAutomaticTextCompletionEnabled = false

        // Disable smart substitutions/detections that can interfere with selection when recoloring
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.delegate = context.coordinator

        // Add line number ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)

        // Apply wrapping mode configuration
        applyWrapMode(isWrapped: isLineWrapEnabled, textView: textView, scrollView: scrollView)

        // Seed initial text
        textView.string = text
        DispatchQueue.main.async { [weak scrollView, weak textView] in
            guard let sv = scrollView, let tv = textView else { return }
            sv.window?.makeFirstResponder(tv)
        }
        context.coordinator.scheduleHighlightIfNeeded(currentText: text)

        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak textView, weak scrollView] _ in
            guard let tv = textView, let sv = scrollView else { return }
            if tv.textContainer?.widthTracksTextView == true {
                tv.textContainer?.containerSize.width = sv.contentSize.width
                if let container = tv.textContainer {
                    tv.layoutManager?.ensureLayout(for: container)
                }
            }
        }

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                textView.string = text
            }
            if textView.font?.pointSize != fontSize {
                textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
            // Keep the text container width in sync & relayout
            applyWrapMode(isWrapped: isLineWrapEnabled, textView: textView, scrollView: nsView)
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.invalidateIntrinsicContentSize()
            // Only schedule highlight if needed (e.g., language/color scheme changes or external text updates)
            context.coordinator.scheduleHighlightIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        weak var textView: NSTextView?

        private let highlightQueue = DispatchQueue(label: "NeonVision.SyntaxHighlight", qos: .userInitiated)
        private var pendingHighlight: DispatchWorkItem?
        private var lastHighlightedText: String = ""
        private var lastLanguage: String?
        private var lastColorScheme: ColorScheme?

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(moveToLine(_:)), name: .moveCursorToLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(streamSuggestion(_:)), name: .streamSuggestion, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func scheduleHighlightIfNeeded(currentText: String? = nil) {
            guard textView != nil else { return }
            // Defer highlighting while a modal panel is presented (e.g., NSSavePanel)
            if NSApp.modalWindow != nil {
                pendingHighlight?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.scheduleHighlightIfNeeded(currentText: currentText)
                }
                pendingHighlight = work
                highlightQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
                return
            }

            let lang = parent.language
            let scheme = parent.colorScheme
            let text = currentText ?? textView?.string ?? ""
            if text == lastHighlightedText && lastLanguage == lang && lastColorScheme == scheme {
                return
            }
            rehighlight()
        }

        func rehighlight() {
            guard let textView = textView else { return }
            // Snapshot current state
            let textSnapshot = textView.string
            let language = parent.language
            let scheme = parent.colorScheme
            let selected = textView.selectedRange()
            let colors = SyntaxColors.fromVibrantLightTheme(colorScheme: scheme)
            let patterns = getSyntaxPatterns(for: language, colors: colors)

            // Cancel any in-flight work
            pendingHighlight?.cancel()

            let work = DispatchWorkItem { [weak self] in
                // Compute matches off the main thread
                let nsText = textSnapshot as NSString
                let fullRange = NSRange(location: 0, length: nsText.length)
                var coloredRanges: [(NSRange, Color)] = []
                for (pattern, color) in patterns {
                    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                    let matches = regex.matches(in: textSnapshot, range: fullRange)
                    for match in matches {
                        coloredRanges.append((match.range, color))
                    }
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let tv = self.textView else { return }
                    // Discard if text changed since we started
                    guard tv.string == textSnapshot else { return }

                    tv.textStorage?.beginEditing()
                    // Clear previous coloring and apply base color
                    tv.textStorage?.removeAttribute(.foregroundColor, range: fullRange)
                    tv.textStorage?.addAttribute(.foregroundColor, value: tv.textColor ?? NSColor.labelColor, range: fullRange)
                    // Apply colored ranges
                    for (range, color) in coloredRanges {
                        tv.textStorage?.addAttribute(.foregroundColor, value: NSColor(color), range: range)
                    }
                    tv.textStorage?.endEditing()

                    // Restore selection only if it hasn't changed since we started
                    if NSEqualRanges(tv.selectedRange(), selected) {
                        tv.setSelectedRange(selected)
                    }

                    // Update last highlighted state
                    self.lastHighlightedText = textSnapshot
                    self.lastLanguage = language
                    self.lastColorScheme = scheme
                }
            }

            pendingHighlight = work
            // Debounce slightly to avoid thrashing while typing
            highlightQueue.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateCaretStatusAndHighlight()
            scheduleHighlightIfNeeded(currentText: parent.text)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateCaretStatusAndHighlight()
        }

        private func updateCaretStatusAndHighlight() {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let location = sel.location
            let prefix = ns.substring(to: min(location, ns.length))
            let line = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let col: Int = {
                if let lastNL = prefix.lastIndex(of: "\n") {
                    return prefix.distance(from: lastNL, to: prefix.endIndex) - 1
                } else {
                    return prefix.count
                }
            }()
            NotificationCenter.default.post(name: .caretPositionDidChange, object: nil, userInfo: ["line": line, "column": col])

            // Highlight current line
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let fullRange = NSRange(location: 0, length: ns.length)
            tv.textStorage?.beginEditing()
            tv.textStorage?.removeAttribute(.backgroundColor, range: fullRange)
            tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.12), range: lineRange)
            tv.textStorage?.endEditing()
        }

        @objc func moveToLine(_ notification: Notification) {
            guard let lineOneBased = notification.object as? Int,
                  let textView = textView else { return }

            // If there's no text, nothing to do
            let currentText = textView.string
            guard !currentText.isEmpty else { return }

            // Cancel any in-flight highlight to prevent it from restoring an old selection
            pendingHighlight?.cancel()

            // Work with NSString/UTF-16 indices to match NSTextView expectations
            let ns = currentText as NSString
            let totalLength = ns.length

            // Clamp target line to available line count (1-based input)
            let linesArray = currentText.components(separatedBy: .newlines)
            let clampedLineIndex = max(1, min(lineOneBased, linesArray.count)) - 1 // 0-based index

            // Compute the UTF-16 location by summing UTF-16 lengths of preceding lines + newline characters
            var location = 0
            if clampedLineIndex > 0 {
                for i in 0..<(clampedLineIndex) {
                    let lineNSString = linesArray[i] as NSString
                    location += lineNSString.length
                    // Add one for the newline that separates lines, as components(separatedBy:) drops separators
                    location += 1
                }
            }
            // Safety clamp
            location = max(0, min(location, totalLength))

            // Move caret and scroll into view on the main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tv = self.textView else { return }
                tv.window?.makeFirstResponder(tv)
                // Ensure layout is up-to-date before scrolling
                if let container = tv.textContainer {
                    tv.layoutManager?.ensureLayout(for: container)
                }
                tv.setSelectedRange(NSRange(location: location, length: 0))
                tv.scrollRangeToVisible(NSRange(location: location, length: 0))

                // Stronger highlight for the entire target line
                let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
                let fullRange = NSRange(location: 0, length: totalLength)
                tv.textStorage?.beginEditing()
                tv.textStorage?.removeAttribute(.backgroundColor, range: fullRange)
                tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.18), range: lineRange)
                tv.textStorage?.endEditing()
            }
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
    }
}

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let textColor = NSColor.secondaryLabelColor
    private let inset: CGFloat = 4

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 44
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: scrollView?.contentView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let ctx = NSString(string: tv.string)
        let visibleGlyphRange = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
        var lineNumber = 1
        if visibleGlyphRange.location > 0 {
            let charIndex = lm.characterIndexForGlyph(at: visibleGlyphRange.location)
            let prefix = ctx.substring(to: charIndex)
            lineNumber = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        }
        var glyphIndex = visibleGlyphRange.location
        while glyphIndex < visibleGlyphRange.upperBound {
            var effectiveRange = NSRange(location: 0, length: 0)
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange, withoutAdditionalLayout: true)
            let y = (lineRect.minY - tv.visibleRect.origin.y) + 2 - tv.textContainerInset.height
            let numberString = "\(lineNumber)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let size = numberString.size(withAttributes: attributes)
            let drawPoint = NSPoint(x: bounds.maxX - size.width - inset, y: y)
            numberString.draw(at: drawPoint, withAttributes: attributes)
            glyphIndex = effectiveRange.upperBound
            lineNumber += 1
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
            // Keywords (extended to include `import`)
            "\\b(func|struct|class|enum|protocol|extension|if|else|for|while|switch|case|default|guard|defer|throw|try|catch|return|init|deinit|import)\\b": colors.keyword,

            // Strings and Characters
            "\"[^\"]*\"": colors.string,
            "'[^'\\](?:\\.[^'\\])*'": colors.string,

            // Numbers
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,

            // Comments (single and multi-line)
            "//.*": colors.comment,
            "/\\*([^*]|(\\*+[^*/]))*\\*+/": colors.comment,

            // Documentation markup (triple slash and doc blocks)
            "(?m)^(///).*$": colors.comment,
            "/\\*\\*([\\s\\S]*?)\\*+/": colors.comment,
            // Documentation keywords inside docs (e.g., - Parameter:, - Returns:)
            "(?m)\\-\\s*(Parameter|Parameters|Returns|Throws|Note|Warning|See\\salso)\\s*:": colors.meta,

            // Marks / TODO / FIXME
            "(?m)//\\s*(MARK|TODO|FIXME)\\s*:.*$": colors.meta,

            // URLs
            "https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+": colors.atom,
            "file://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+": colors.atom,

            // Preprocessor statements (conditionals and directives)
            "(?m)^#(if|elseif|else|endif|warning|error|available)\\b.*$": colors.keyword,

            // Attributes like @available, @MainActor, etc.
            "@\\w+": colors.attribute,

            // Variable declarations
            "\\b(var|let)\\b": colors.variable,

            // Common Swift types
            "\\b(String|Int|Double|Bool)\\b": colors.type,

            // Regex literals and components (Swift /…/)
            "/[^/\\n]*/": colors.builtin, // whole regex literal
            "\\(\\?<([A-Za-z_][A-Za-z0-9_]*)>": colors.def, // named capture start (?<name>
            "\\[[^\\]]*\\]": colors.property, // character classes
            "[|*+?]": colors.meta, // regex operators

            // Common SwiftUI property names like `body`
            "\\bbody\\b": colors.property,
            // Project-specific identifier you mentioned: `viewModel`
            "\\bviewModel\\b": colors.property
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
    static let caretPositionDidChange = Notification.Name("caretPositionDidChange")
}

