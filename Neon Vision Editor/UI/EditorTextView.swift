import SwiftUI
import Foundation
import OSLog

private let syntaxHighlightSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "SyntaxHighlight")

#if os(macOS)
private extension Notification.Name {
    static let editorPointerInteraction = Notification.Name("NeonEditorPointerInteraction")
}
#endif

private enum EditorRuntimeLimits {
    // Above this, keep editing responsive by skipping regex-heavy syntax passes.
    static let syntaxMinimalUTF16Length = 1_200_000
    static let htmlFastProfileUTF16Length = 250_000
    static let csvFastProfileUTF16Length = 180_000
    static let scopeComputationMaxUTF16Length = 300_000
    static let cursorRehighlightMaxUTF16Length = 220_000
    static let nonImmediateHighlightMaxUTF16Length = 220_000
    static let bindingDebounceUTF16Length = 250_000
    static let bindingDebounceDelay: TimeInterval = 0.18
}

struct EditorTextMutation {
    let documentID: UUID
    let range: NSRange
    let replacement: String
}

#if os(macOS)
private func replaceTextPreservingSelectionAndFocus(
    _ textView: NSTextView,
    with newText: String,
    preserveViewport: Bool = true
) {
    let previousSelection = textView.selectedRange()
    let hadFocus = (textView.window?.firstResponder as? NSTextView) === textView
    _ = preserveViewport
    textView.string = newText
    let length = (newText as NSString).length
    let safeLocation = min(max(0, previousSelection.location), length)
    let safeLength = min(max(0, previousSelection.length), max(0, length - safeLocation))
    textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
    if hadFocus {
        textView.window?.makeFirstResponder(textView)
    }
}
#endif

private enum EmmetExpander {
    struct Node {
        var tag: String
        var id: String?
        var classes: [String]
        var count: Int
        var children: [Node]
    }

    private static let allowedChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.#>+*-_")
    private static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]

    static func expansionIfPossible(in text: String, cursorUTF16Location: Int, language: String) -> (range: NSRange, expansion: String, caretOffset: Int)? {
        guard language == "html" || language == "php" else { return nil }
        if language == "php" && !isHTMLContextInPHP(text: text, cursorUTF16Location: cursorUTF16Location) {
            return nil
        }

        let ns = text as NSString
        let clamped = min(max(0, cursorUTF16Location), ns.length)
        guard let range = abbreviationRange(in: ns, cursor: clamped), range.length > 0 else { return nil }
        let raw = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("<"), !raw.contains("> ") else { return nil }
        guard let nodes = parseChain(raw), !nodes.isEmpty else { return nil }
        let indent = leadingIndentationForLine(in: ns, at: range.location)
        let rendered = render(nodes: nodes, indent: indent, level: 0)
        if let first = rendered.range(of: "></") {
            let caretUTF16 = rendered[..<first.lowerBound].utf16.count + 1
            return (range, rendered, caretUTF16)
        }
        return (range, rendered, rendered.utf16.count)
    }

    private static func abbreviationRange(in text: NSString, cursor: Int) -> NSRange? {
        guard text.length > 0, cursor > 0 else { return nil }
        var start = cursor
        while start > 0 {
            let scalar = text.character(at: start - 1)
            guard let uni = UnicodeScalar(scalar), allowedChars.contains(uni) else { break }
            start -= 1
        }
        guard start < cursor else { return nil }
        return NSRange(location: start, length: cursor - start)
    }

    private static func leadingIndentationForLine(in text: NSString, at location: Int) -> String {
        let lineRange = text.lineRange(for: NSRange(location: max(0, min(location, text.length)), length: 0))
        let line = text.substring(with: lineRange)
        return String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func isHTMLContextInPHP(text: String, cursorUTF16Location: Int) -> Bool {
        let ns = text as NSString
        let clamped = min(max(0, cursorUTF16Location), ns.length)
        let search = NSRange(location: 0, length: clamped)
        let openRanges = [
            ns.range(of: "<?php", options: .backwards, range: search),
            ns.range(of: "<?=", options: .backwards, range: search),
            ns.range(of: "<?", options: .backwards, range: search)
        ]
        let latestOpen = openRanges.compactMap { $0.location == NSNotFound ? nil : $0.location }.max() ?? -1
        let latestCloseRange = ns.range(of: "?>", options: .backwards, range: search)
        let latestClose = latestCloseRange.location
        return latestOpen == -1 || (latestClose != NSNotFound && latestClose > latestOpen)
    }

    private static func parseChain(_ raw: String) -> [Node]? {
        let hierarchyParts = raw.split(separator: ">", omittingEmptySubsequences: false).map(String.init)
        guard !hierarchyParts.isEmpty else { return nil }

        var levels: [[Node]] = []
        for part in hierarchyParts {
            let siblings = part.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            var levelNodes: [Node] = []
            for sibling in siblings {
                guard let node = parseNode(sibling), !node.tag.isEmpty else { return nil }
                levelNodes.append(node)
            }
            guard !levelNodes.isEmpty else { return nil }
            levels.append(levelNodes)
        }

        for level in stride(from: levels.count - 2, through: 0, by: -1) {
            let children = levels[level + 1]
            for idx in levels[level].indices {
                levels[level][idx].children = children
            }
        }
        return levels.first
    }

    private static func parseNode(_ token: String) -> Node? {
        let source = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        var count = 1
        var core = source
        if let star = source.lastIndex(of: "*") {
            let multiplier = String(source[source.index(after: star)...])
            if let n = Int(multiplier), n > 0 {
                count = n
                core = String(source[..<star])
            }
        }

        var tag = ""
        var id: String?
        var classes: [String] = []
        var i = core.startIndex
        while i < core.endIndex {
            let ch = core[i]
            if ch == "." || ch == "#" { break }
            tag.append(ch)
            i = core.index(after: i)
        }
        if tag.isEmpty { tag = "div" }

        while i < core.endIndex {
            let marker = core[i]
            guard marker == "." || marker == "#" else { return nil }
            i = core.index(after: i)
            var value = ""
            while i < core.endIndex {
                let c = core[i]
                if c == "." || c == "#" { break }
                value.append(c)
                i = core.index(after: i)
            }
            guard !value.isEmpty else { return nil }
            if marker == "#" { id = value } else { classes.append(value) }
        }

        return Node(tag: tag, id: id, classes: classes, count: count, children: [])
    }

    private static func render(nodes: [Node], indent: String, level: Int) -> String {
        nodes.map { render(node: $0, indent: indent, level: level) }.joined(separator: "\n")
    }

    private static func render(node: Node, indent: String, level: Int) -> String {
        var lines: [String] = []
        for _ in 0..<max(1, node.count) {
            let pad = indent + String(repeating: "    ", count: level)
            let attrs = attributes(for: node)
            if node.children.isEmpty {
                if voidTags.contains(node.tag.lowercased()) {
                    lines.append("\(pad)<\(node.tag)\(attrs)>")
                } else {
                    lines.append("\(pad)<\(node.tag)\(attrs)></\(node.tag)>")
                }
            } else {
                lines.append("\(pad)<\(node.tag)\(attrs)>")
                lines.append(render(nodes: node.children, indent: indent, level: level + 1))
                lines.append("\(pad)</\(node.tag)>")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func attributes(for node: Node) -> String {
        var attrs: [String] = []
        if let id = node.id { attrs.append("id=\"\(id)\"") }
        if !node.classes.isEmpty { attrs.append("class=\"\(node.classes.joined(separator: " "))\"") }
        return attrs.isEmpty ? "" : " " + attrs.joined(separator: " ")
    }
}

///MARK: - Paste Notifications
extension Notification.Name {
    static let pastedFileURL = Notification.Name("pastedFileURL")
}

///MARK: - Scope Match Models
// Bracket-based scope data used for highlighting and guide rendering.
private struct BracketScopeMatch {
    let openRange: NSRange
    let closeRange: NSRange
    let scopeRange: NSRange?
    let guideMarkerRanges: [NSRange]
}

// Indentation-based scope data used for Python/YAML style highlighting.
private struct IndentationScopeMatch {
    let scopeRange: NSRange
    let guideMarkerRanges: [NSRange]
}

///MARK: - Bracket/Indent Scope Helpers
private func matchingOpeningBracket(for closing: unichar) -> unichar? {
    switch UnicodeScalar(closing) {
    case "}": return unichar(UnicodeScalar("{").value)
    case "]": return unichar(UnicodeScalar("[").value)
    case ")": return unichar(UnicodeScalar("(").value)
    default: return nil
    }
}

private func matchingClosingBracket(for opening: unichar) -> unichar? {
    switch UnicodeScalar(opening) {
    case "{": return unichar(UnicodeScalar("}").value)
    case "[": return unichar(UnicodeScalar("]").value)
    case "(": return unichar(UnicodeScalar(")").value)
    default: return nil
    }
}

private func isBracket(_ c: unichar) -> Bool {
    matchesAny(c, ["{", "}", "[", "]", "(", ")"])
}

private func matchesAny(_ c: unichar, _ chars: [Character]) -> Bool {
    guard let scalar = UnicodeScalar(c) else { return false }
    return chars.contains(Character(scalar))
}

private func computeBracketScopeMatch(text: String, caretLocation: Int) -> BracketScopeMatch? {
    let ns = text as NSString
    let length = ns.length
    guard length > 0 else { return nil }

    func matchFrom(start: Int) -> BracketScopeMatch? {
        guard start >= 0 && start < length else { return nil }
        let startChar = ns.character(at: start)
        let openIndex: Int
        let closeIndex: Int

        if let wantedClose = matchingClosingBracket(for: startChar) {
            var depth = 0
            var found: Int?
            for i in start..<length {
                let c = ns.character(at: i)
                if c == startChar { depth += 1 }
                if c == wantedClose {
                    depth -= 1
                    if depth == 0 {
                        found = i
                        break
                    }
                }
            }
            guard let found else { return nil }
            openIndex = start
            closeIndex = found
        } else if let wantedOpen = matchingOpeningBracket(for: startChar) {
            var depth = 0
            var found: Int?
            var i = start
            while i >= 0 {
                let c = ns.character(at: i)
                if c == startChar { depth += 1 }
                if c == wantedOpen {
                    depth -= 1
                    if depth == 0 {
                        found = i
                        break
                    }
                }
                i -= 1
            }
            guard let found else { return nil }
            openIndex = found
            closeIndex = start
        } else {
            return nil
        }

        let openRange = NSRange(location: openIndex, length: 1)
        let closeRange = NSRange(location: closeIndex, length: 1)
        let scopeLength = max(0, closeIndex - openIndex - 1)
        let scopeRange: NSRange? = scopeLength > 0 ? NSRange(location: openIndex + 1, length: scopeLength) : nil

        let openLineRange = ns.lineRange(for: NSRange(location: openIndex, length: 0))
        let closeLineRange = ns.lineRange(for: NSRange(location: closeIndex, length: 0))
        let column = openIndex - openLineRange.location

        var markers: [NSRange] = []
        var lineStart = openLineRange.location
        while lineStart <= closeLineRange.location && lineStart < length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineEndExcludingNewline = lineRange.location + max(0, lineRange.length - 1)
            if lineEndExcludingNewline > lineRange.location {
                let markerLoc = min(lineRange.location + column, lineEndExcludingNewline - 1)
                if markerLoc >= lineRange.location && markerLoc < lineEndExcludingNewline {
                    markers.append(NSRange(location: markerLoc, length: 1))
                }
            }
            let nextLineStart = lineRange.location + lineRange.length
            if nextLineStart <= lineStart { break }
            lineStart = nextLineStart
        }

        return BracketScopeMatch(
            openRange: openRange,
            closeRange: closeRange,
            scopeRange: scopeRange,
            guideMarkerRanges: markers
        )
    }

    let safeCaret = max(0, min(caretLocation, length))
    var probeIndices: [Int] = [safeCaret]
    if safeCaret > 0 { probeIndices.append(safeCaret - 1) }

    var candidateIndices: [Int] = []
    var seenCandidates = Set<Int>()
    func addCandidate(_ index: Int) {
        guard index >= 0 && index < length else { return }
        if seenCandidates.insert(index).inserted {
            candidateIndices.append(index)
        }
    }
    for idx in probeIndices where idx >= 0 && idx < length {
        if isBracket(ns.character(at: idx)) {
            addCandidate(idx)
        }
    }

    // If caret is not directly on a bracket, find the nearest enclosing opening
    // bracket whose matching close still contains the caret.
    var stack: [Int] = []
    if safeCaret > 0 {
        for i in 0..<safeCaret {
            let c = ns.character(at: i)
            if matchingClosingBracket(for: c) != nil {
                stack.append(i)
                continue
            }
            if let wantedOpen = matchingOpeningBracket(for: c), let last = stack.last, ns.character(at: last) == wantedOpen {
                stack.removeLast()
            }
        }
    }
    while let candidate = stack.popLast() {
        let c = ns.character(at: candidate)
        guard let wantedClose = matchingClosingBracket(for: c) else { continue }
        var depth = 0
        var foundClose: Int?
        for i in candidate..<length {
            let current = ns.character(at: i)
            if current == c { depth += 1 }
            if current == wantedClose {
                depth -= 1
                if depth == 0 {
                    foundClose = i
                    break
                }
            }
        }
        if let close = foundClose, safeCaret >= candidate && safeCaret <= close {
            addCandidate(candidate)
        }
    }

    // Add all brackets by nearest distance so we still find a valid scope even if
    // early candidates are unmatched (e.g. bracket chars inside strings/comments).
    let allBracketIndices = (0..<length).filter { isBracket(ns.character(at: $0)) }
    let sortedByDistance = allBracketIndices.sorted { abs($0 - safeCaret) < abs($1 - safeCaret) }
    for idx in sortedByDistance {
        addCandidate(idx)
    }

    for candidate in candidateIndices {
        if let match = matchFrom(start: candidate) {
            return match
        }
    }
    return nil
}

private func supportsIndentationScopes(language: String) -> Bool {
    let lang = language.lowercased()
    return lang == "python" || lang == "yaml" || lang == "yml"
}

private func computeIndentationScopeMatch(text: String, caretLocation: Int) -> IndentationScopeMatch? {
    let ns = text as NSString
    let length = ns.length
    guard length > 0 else { return nil }

    struct LineInfo {
        let range: NSRange
        let contentEnd: Int
        let indent: Int?
    }

    func lineIndent(_ lineRange: NSRange) -> Int? {
        guard lineRange.length > 0 else { return nil }
        let line = ns.substring(with: lineRange)
        var indent = 0
        var sawContent = false
        for ch in line {
            if ch == " " {
                indent += 1
                continue
            }
            if ch == "\t" {
                indent += 4
                continue
            }
            if ch == "\n" || ch == "\r" {
                continue
            }
            sawContent = true
            break
        }
        return sawContent ? indent : nil
    }

    var lines: [LineInfo] = []
    var lineStart = 0
    while lineStart < length {
        let lr = ns.lineRange(for: NSRange(location: lineStart, length: 0))
        let contentEnd = lr.location + max(0, lr.length - 1)
        lines.append(LineInfo(range: lr, contentEnd: contentEnd, indent: lineIndent(lr)))
        let next = lr.location + lr.length
        if next <= lineStart { break }
        lineStart = next
    }
    guard !lines.isEmpty else { return nil }

    let safeCaret = max(0, min(caretLocation, max(0, length - 1)))
    guard let caretLineIndex = lines.firstIndex(where: { NSLocationInRange(safeCaret, $0.range) }) else { return nil }

    var blockStart = caretLineIndex
    var baseIndent: Int? = lines[caretLineIndex].indent

    // If caret is on a block header line (e.g. Python ":"), use the next indented line.
    if baseIndent == nil || baseIndent == 0 {
        let currentLine = ns.substring(with: lines[caretLineIndex].range).trimmingCharacters(in: .whitespacesAndNewlines)
        if currentLine.hasSuffix(":") {
            var next = caretLineIndex + 1
            while next < lines.count {
                if let nextIndent = lines[next].indent, nextIndent > 0 {
                    baseIndent = nextIndent
                    blockStart = next
                    break
                }
                next += 1
            }
        }
    }

    guard let indentLevel = baseIndent, indentLevel > 0 else { return nil }

    var start = blockStart
    while start > 0 {
        let prev = lines[start - 1]
        guard let prevIndent = prev.indent else {
            start -= 1
            continue
        }
        if prevIndent >= indentLevel {
            start -= 1
            continue
        }
        break
    }

    var end = blockStart
    var idx = blockStart + 1
    while idx < lines.count {
        let info = lines[idx]
        if let infoIndent = info.indent {
            if infoIndent < indentLevel { break }
            end = idx
            idx += 1
            continue
        }
        // Keep blank lines inside the current block.
        end = idx
        idx += 1
    }

    let startLoc = lines[start].range.location
    let endLoc = lines[end].contentEnd
    guard endLoc > startLoc else { return nil }

    var guideMarkers: [NSRange] = []
    for i in start...end {
        let info = lines[i]
        guard info.contentEnd > info.range.location else { continue }
        guard let infoIndent = info.indent, infoIndent >= indentLevel else { continue }
        let marker = min(info.range.location + max(0, indentLevel - 1), info.contentEnd - 1)
        if marker >= info.range.location && marker < info.contentEnd {
            guideMarkers.append(NSRange(location: marker, length: 1))
        }
    }

    return IndentationScopeMatch(
        scopeRange: NSRange(location: startLoc, length: endLoc - startLoc),
        guideMarkerRanges: guideMarkers
    )
}

private func isValidRange(_ range: NSRange, utf16Length: Int) -> Bool {
    guard range.location != NSNotFound, range.length >= 0, range.location >= 0 else { return false }
    return NSMaxRange(range) <= utf16Length
}

private func fastSyntaxColorRanges(
    language: String,
    profile: SyntaxPatternProfile,
    text: NSString,
    in range: NSRange,
    colors: SyntaxColors
) -> [(NSRange, Color)]? {
    let lower = language.lowercased()
    if profile == .csvFast || (profile == .full && lower == "csv" && range.length >= 180_000) {
        let rangeEnd = NSMaxRange(range)
        var out: [(NSRange, Color)] = []
        var i = range.location
        while i < rangeEnd {
            let ch = text.character(at: i)
            if ch == 34 { // "
                let start = i
                i += 1
                while i < rangeEnd {
                    let c = text.character(at: i)
                    if c == 34 {
                        if i + 1 < rangeEnd && text.character(at: i + 1) == 34 {
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    i += 1
                }
                out.append((NSRange(location: start, length: max(0, i - start)), colors.string))
                continue
            }
            if ch == 44 { // ,
                out.append((NSRange(location: i, length: 1), colors.property))
            }
            i += 1
        }
        return out
    }

    if profile == .htmlFast && (lower == "html" || lower == "xml") {
        let rangeEnd = NSMaxRange(range)
        var out: [(NSRange, Color)] = []
        var i = range.location
        while i < rangeEnd {
            let ch = text.character(at: i)
            if ch == 60 { // <
                let start = i
                i += 1
                while i < rangeEnd && text.character(at: i) != 62 { // >
                    i += 1
                }
                if i < rangeEnd && text.character(at: i) == 62 { i += 1 }
                out.append((NSRange(location: start, length: max(0, i - start)), colors.tag))
                continue
            }
            if ch == 34 { // "
                let start = i
                i += 1
                while i < rangeEnd && text.character(at: i) != 34 {
                    i += 1
                }
                if i < rangeEnd { i += 1 }
                out.append((NSRange(location: start, length: max(0, i - start)), colors.string))
                continue
            }
            i += 1
        }
        return out
    }
    return nil
}

#if os(macOS)
import AppKit

private struct TextViewObserverToken: @unchecked Sendable {
    let raw: NSObjectProtocol
}

final class AcceptingTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }
    private let vimModeDefaultsKey = "EditorVimModeEnabled"
    private let vimInterceptionDefaultsKey = "EditorVimInterceptionEnabled"
    private var isVimInsertMode: Bool = true
    private var vimObservers: [TextViewObserverToken] = []
    private var activityObservers: [TextViewObserverToken] = []
    private var didConfigureVimMode: Bool = false
    private var didApplyDeepInvisibleDisable: Bool = false
    private var defaultsObserver: TextViewObserverToken?
    private let dropReadChunkSize = 64 * 1024
    fileprivate var isApplyingDroppedContent: Bool = false
    private var inlineSuggestion: String?
    private var inlineSuggestionLocation: Int?
    private var inlineSuggestionView: NSTextField?
    fileprivate var isApplyingInlineSuggestion: Bool = false
    fileprivate var recentlyAcceptedInlineSuggestion: Bool = false
    fileprivate var isApplyingPaste: Bool = false
    var autoIndentEnabled: Bool = true
    var autoCloseBracketsEnabled: Bool = true
    var emmetLanguage: String = "plain"
    var indentStyle: String = "spaces"
    var indentWidth: Int = 4
    var highlightCurrentLine: Bool = true
    private let editorInsetX: CGFloat = 12

    // We want the caret at the *start* of the paste.
    private var pendingPasteCaretLocation: Int?

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver.raw)
        }
        for observer in activityObservers {
            NotificationCenter.default.removeObserver(observer.raw)
        }
        for observer in vimObservers {
            NotificationCenter.default.removeObserver(observer.raw)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !didConfigureVimMode {
            configureVimMode()
            didConfigureVimMode = true
        }
        configureActivityObservers()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
        textContainerInset = NSSize(width: editorInsetX, height: 12)
        if defaultsObserver == nil {
            defaultsObserver = TextViewObserverToken(raw: NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.forceDisableInvisibleGlyphRendering(deep: true)
                }
            })
        }
        forceDisableInvisibleGlyphRendering(deep: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Keep invisibles/control markers hard-disabled even during inactive-window redraw passes.
        forceDisableInvisibleGlyphRendering()
        super.draw(dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        cancelPendingPasteCaretEnforcement()
        clearInlineSuggestion()
        NotificationCenter.default.post(name: .editorPointerInteraction, object: self)
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains([.shift, .option]) {
            let delta = event.scrollingDeltaY
            if abs(delta) > 0.1 {
                let step: Double = delta > 0 ? 1 : -1
                NotificationCenter.default.post(name: .zoomEditorFontRequested, object: step)
                return
            }
        }
        cancelPendingPasteCaretEnforcement()
        super.scrollWheel(with: event)
        updateInlineSuggestionPosition()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome, UserDefaults.standard.bool(forKey: vimModeDefaultsKey) {
            // Re-enter NORMAL whenever Vim mode is active.
            isVimInsertMode = false
            postVimModeState()
        }
        return didBecome
    }

    override func layout() {
        super.layout()
        updateInlineSuggestionPosition()
        forceDisableInvisibleGlyphRendering()
    }

    ///MARK: - Drag and Drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        let canReadFileURL = pb.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
        let canReadPlainText = pasteboardPlainString(from: pb)?.isEmpty == false
        return (canReadFileURL || canReadPlainText) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let nsurls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL],
           !nsurls.isEmpty {
            let urls = nsurls.map { $0 as URL }
            if urls.count == 1 {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls[0])
            } else {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls)
            }
            // Do not insert content; let higher-level controller open a new tab.
            return true
        }
        if let droppedString = pasteboardPlainString(from: pb), !droppedString.isEmpty {
            let sanitized = sanitizedPlainText(droppedString)
            let dropRange = insertionRangeForDrop(sender)
            isApplyingPaste = true
            if let storage = textStorage {
                storage.beginEditing()
                replaceCharacters(in: dropRange, with: sanitized)
                storage.endEditing()
            } else {
                let current = string as NSString
                if dropRange.location <= current.length &&
                    dropRange.location + dropRange.length <= current.length {
                    string = current.replacingCharacters(in: dropRange, with: sanitized)
                } else {
                    isApplyingPaste = false
                    return false
                }
            }
            isApplyingPaste = false

            NotificationCenter.default.post(name: .pastedText, object: sanitized)
            didChangeText()
            return true
        }
        return false
    }

    private func insertionRangeForDrop(_ sender: NSDraggingInfo) -> NSRange {
        let windowPoint = sender.draggingLocation
        let viewPoint = convert(windowPoint, from: nil)
        let insertionIndex = characterIndexForInsertion(at: viewPoint)
        let clamped = clampedRange(NSRange(location: insertionIndex, length: 0), forTextLength: (string as NSString).length)
        setSelectedRange(clamped)
        return clamped
    }

    private func applyDroppedContentInChunks(
        _ content: String,
        at selection: NSRange,
        fileName: String,
        largeFileMode: Bool,
        completion: @escaping (Bool, Int) -> Void
    ) {
        let nsContent = content as NSString
        let safeSelection = clampedRange(selection, forTextLength: (string as NSString).length)
        let total = nsContent.length
        if total == 0 {
            completion(true, 0)
            return
        }
        NotificationCenter.default.post(
            name: .droppedFileLoadProgress,
            object: nil,
            userInfo: [
                "fraction": 0.70,
                "fileName": "Applying file",
                "largeFileMode": largeFileMode
            ]
        )

        // Large payloads: prefer one atomic replace after yielding one runloop turn so
        // progress updates can render before the heavy text-system mutation begins.
        if total >= 300_000 {
            isApplyingDroppedContent = true
            NotificationCenter.default.post(
                name: .droppedFileLoadProgress,
                object: nil,
                userInfo: [
                    "fraction": 0.90,
                    "fileName": "Applying file",
                    "largeFileMode": largeFileMode,
                    "isDeterminate": true
                ]
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(false, 0)
                    return
                }

                let replaceSucceeded: Bool
                if let storage = self.textStorage {
                    let liveSafeSelection = self.clampedRange(safeSelection, forTextLength: storage.length)
                    self.undoManager?.disableUndoRegistration()
                    storage.beginEditing()
                    if storage.length == 0 && liveSafeSelection.location == 0 && liveSafeSelection.length == 0 {
                        storage.mutableString.setString(content)
                    } else {
                        storage.mutableString.replaceCharacters(in: liveSafeSelection, with: content)
                    }
                    storage.endEditing()
                    self.undoManager?.enableUndoRegistration()
                    replaceSucceeded = true
                } else {
                    let current = self.string as NSString
                    if safeSelection.location <= current.length &&
                        safeSelection.location + safeSelection.length <= current.length {
                        let replaced = current.replacingCharacters(in: safeSelection, with: content)
                        self.string = replaced
                        replaceSucceeded = true
                    } else {
                        replaceSucceeded = false
                    }
                }

                self.isApplyingDroppedContent = false
                NotificationCenter.default.post(
                    name: .droppedFileLoadProgress,
                    object: nil,
                    userInfo: [
                        "fraction": replaceSucceeded ? 1.0 : 0.0,
                        "fileName": replaceSucceeded ? "Reading file" : "Import failed",
                        "largeFileMode": largeFileMode,
                        "isDeterminate": true
                    ]
                )
                completion(replaceSucceeded, replaceSucceeded ? total : 0)
            }
            return
        }

        let replaceSucceeded: Bool
        if let storage = textStorage {
            undoManager?.disableUndoRegistration()
            storage.beginEditing()
            storage.mutableString.replaceCharacters(in: safeSelection, with: content)
            storage.endEditing()
            undoManager?.enableUndoRegistration()
            replaceSucceeded = true
        } else {
            // Fallback for environments where textStorage is temporarily unavailable.
            let current = string as NSString
            if safeSelection.location <= current.length &&
                safeSelection.location + safeSelection.length <= current.length {
                let replaced = current.replacingCharacters(in: safeSelection, with: content)
                string = replaced
                replaceSucceeded = true
            } else {
                replaceSucceeded = false
            }
        }

        NotificationCenter.default.post(
            name: .droppedFileLoadProgress,
            object: nil,
            userInfo: [
                "fraction": replaceSucceeded ? 1.0 : 0.0,
                "fileName": replaceSucceeded ? "Reading file" : "Import failed",
                "largeFileMode": largeFileMode
            ]
        )

        completion(replaceSucceeded, replaceSucceeded ? total : 0)
    }

    private func clampedSelectionRange() -> NSRange {
        clampedRange(selectedRange(), forTextLength: (string as NSString).length)
    }

    private func clampedRange(_ range: NSRange, forTextLength length: Int) -> NSRange {
        guard length >= 0 else { return NSRange(location: 0, length: 0) }
        if range.location == NSNotFound {
            return NSRange(location: length, length: 0)
        }
        let safeLocation = min(max(0, range.location), length)
        let maxLen = max(0, length - safeLocation)
        let safeLength = min(max(0, range.length), maxLen)
        return NSRange(location: safeLocation, length: safeLength)
    }

    private func readDroppedFileData(
        at url: URL,
        totalBytes: Int64,
        progress: @escaping (Double) -> Void
    ) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var data = Data()
            if totalBytes > 0, totalBytes <= Int64(Int.max) {
                data.reserveCapacity(Int(totalBytes))
            }

            var loadedBytes: Int64 = 0
            var lastReported: Double = -1

            while true {
                let chunk = try handle.read(upToCount: dropReadChunkSize) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
                loadedBytes += Int64(chunk.count)

                if totalBytes > 0 {
                    let fraction = min(1.0, Double(loadedBytes) / Double(totalBytes))
                    if fraction - lastReported >= 0.02 || fraction >= 1.0 {
                        lastReported = fraction
                        DispatchQueue.main.async {
                            progress(fraction)
                        }
                    }
                }
            }

            if totalBytes > 0, lastReported < 1.0 {
                DispatchQueue.main.async {
                    progress(1.0)
                }
            }
            return data
        } catch {
            // Fallback path for URLs/FileHandle edge cases in sandboxed drag-drop.
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            DispatchQueue.main.async {
                progress(1.0)
            }
            return data
        }
    }

    private func decodeDroppedFileText(_ data: Data, fileURL: URL) -> String {
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .isoLatin1]
        for encoding in encodings {
            if let decoded = String(data: data, encoding: encoding) {
                return Self.sanitizePlainText(decoded)
            }
        }
        if let fallback = try? String(contentsOf: fileURL, encoding: .utf8) {
            return Self.sanitizePlainText(fallback)
        }
        return Self.sanitizePlainText(String(decoding: data, as: UTF8.self))
    }

    ///MARK: - Typing Helpers
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if !isApplyingInlineSuggestion {
            clearInlineSuggestion()
        }
        guard let s = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let sanitized = sanitizedPlainText(s)

        // Ensure invisibles off after insertion
        self.layoutManager?.showsInvisibleCharacters = false
        self.layoutManager?.showsControlCharacters = false

        // Auto-indent by copying leading whitespace
        if sanitized == "\n" && autoIndentEnabled {
            let ns = (string as NSString)
            let sel = selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let currentLine = ns.substring(with: NSRange(
                location: lineRange.location,
                length: max(0, sel.location - lineRange.location)
            ))
            let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
            super.insertText("\n" + indent, replacementRange: replacementRange)
            return
        }

        // Auto-close common bracket/quote pairs
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"]
        if autoCloseBracketsEnabled, let closing = pairs[sanitized] {
            let sel = selectedRange()
            super.insertText(sanitized + closing, replacementRange: replacementRange)
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }

        super.insertText(sanitized, replacementRange: replacementRange)
    }

    static func sanitizePlainText(_ input: String) -> String {
        // Reuse model-level sanitizer to keep all text paths consistent.
        EditorTextSanitizer.sanitize(input)
    }

    private static func containsGlyphArtifacts(_ input: String) -> Bool {
        for scalar in input.unicodeScalars {
            let value = scalar.value
            if value == 0x2581 || (0x2400...0x243F).contains(value) {
                return true
            }
        }
        return false
    }

    private func sanitizedPlainText(_ input: String) -> String {
        Self.sanitizePlainText(input)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 { // Tab
            if acceptInlineSuggestion() {
                return
            }
        }
        // Safety default: bypass Vim interception unless explicitly enabled.
        if !UserDefaults.standard.bool(forKey: vimInterceptionDefaultsKey) {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            super.keyDown(with: event)
            return
        }

        let vimModeEnabled = UserDefaults.standard.bool(forKey: vimModeDefaultsKey)
        guard vimModeEnabled else {
            super.keyDown(with: event)
            return
        }

        if !isVimInsertMode {
            let key = event.charactersIgnoringModifiers ?? ""
            switch key {
            case "h":
                moveLeft(nil)
            case "j":
                moveDown(nil)
            case "k":
                moveUp(nil)
            case "l":
                moveRight(nil)
            case "w":
                moveWordForward(nil)
            case "b":
                moveWordBackward(nil)
            case "0":
                moveToBeginningOfLine(nil)
            case "$":
                moveToEndOfLine(nil)
            case "x":
                deleteForward(nil)
            case "p":
                paste(nil)
            case "i":
                isVimInsertMode = true
                postVimModeState()
            case "a":
                moveRight(nil)
                isVimInsertMode = true
                postVimModeState()
            case "\u{1B}":
                break
            default:
                break
            }
            return
        }

        // Escape exits insert mode.
        if event.keyCode == 53 || event.characters == "\u{1B}" {
            isVimInsertMode = false
            postVimModeState()
            return
        }

        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        if acceptInlineSuggestion() {
            return
        }
        if let expansion = EmmetExpander.expansionIfPossible(
            in: string,
            cursorUTF16Location: selectedRange().location,
            language: emmetLanguage
        ) {
            textStorage?.beginEditing()
            replaceCharacters(in: expansion.range, with: expansion.expansion)
            textStorage?.endEditing()
            let caretLocation = expansion.range.location + expansion.caretOffset
            setSelectedRange(NSRange(location: caretLocation, length: 0))
            didChangeText()
            return
        }
        // Keep Tab insertion deterministic and avoid platform-level invisible glyph rendering.
        let insertion: String
        if indentStyle == "tabs" {
            insertion = "\t"
        } else {
            insertion = String(repeating: " ", count: max(1, indentWidth))
        }
        super.insertText(sanitizedPlainText(insertion), replacementRange: selectedRange())
        forceDisableInvisibleGlyphRendering()
    }

    // Paste: capture insertion point and enforce caret position after paste across async updates.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let nsurls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL],
           !nsurls.isEmpty {
            let urls = nsurls.map { $0 as URL }
            if urls.count == 1 {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls[0])
            } else {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls)
            }
            return
        }
        if let urls = fileURLsFromPasteboard(pasteboard), !urls.isEmpty {
            if urls.count == 1 {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls[0])
            } else {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls)
            }
            return
        }
        // Keep caret anchored at the current insertion location while paste async work settles.
        pendingPasteCaretLocation = selectedRange().location

        if let raw = pasteboardPlainString(from: pasteboard), !raw.isEmpty {
            if let pathURL = fileURLFromString(raw) {
                NotificationCenter.default.post(name: .pastedFileURL, object: pathURL)
                return
            }
            let sanitized = sanitizedPlainText(raw)
            isApplyingPaste = true
            textStorage?.beginEditing()
            replaceCharacters(in: selectedRange(), with: sanitized)
            textStorage?.endEditing()
            isApplyingPaste = false

            // Ensure invisibles are off after paste
            self.layoutManager?.showsInvisibleCharacters = false
            self.layoutManager?.showsControlCharacters = false

            NotificationCenter.default.post(name: .pastedText, object: sanitized)
            didChangeText()

            schedulePasteCaretEnforcement()
            return
        }

        isApplyingPaste = true
        super.paste(sender)
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingPaste = false

            // Ensure invisibles are off after async paste
            self?.layoutManager?.showsInvisibleCharacters = false
            self?.layoutManager?.showsControlCharacters = false
        }

        // Enforce caret after paste (multiple ticks beats late selection changes)
        schedulePasteCaretEnforcement()
    }

    private func pasteboardPlainString(from pasteboard: NSPasteboard) -> String? {
        if let raw = pasteboard.string(forType: .string), !raw.isEmpty {
            return raw
        }
        if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [NSString],
           let first = strings.first,
           first.length > 0 {
            return first as String
        }
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ),
           !attributed.string.isEmpty {
            return attributed.string
        }
        return nil
    }

    private func fileURLsFromPasteboard(_ pasteboard: NSPasteboard) -> [URL]? {
        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return [url]
        }
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let list = pasteboard.propertyList(forType: filenamesType) as? [String] {
            let urls = list.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty { return urls }
        }
        return nil
    }

    private func fileURLFromString(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Plain paths (with spaces or ~)
        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
        return nil
    }

    override func didChangeText() {
        super.didChangeText()
        forceDisableInvisibleGlyphRendering(deep: true)
        if let storage = textStorage {
            let raw = storage.string
            if Self.containsGlyphArtifacts(raw) {
                let sanitized = Self.sanitizePlainText(raw)
                let sel = selectedRange()
                storage.beginEditing()
                storage.replaceCharacters(in: NSRange(location: 0, length: (raw as NSString).length), with: sanitized)
                storage.endEditing()
                setSelectedRange(NSRange(location: min(sel.location, (sanitized as NSString).length), length: 0))
            }
        }
        if !isApplyingInlineSuggestion {
            clearInlineSuggestion()
        }
        // Pasting triggers didChangeText; schedule enforcement again.
        schedulePasteCaretEnforcement()
    }

    private func forceDisableInvisibleGlyphRendering(deep: Bool = false) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "NSShowAllInvisibles") || defaults.bool(forKey: "NSShowControlCharacters") {
            defaults.set(false, forKey: "NSShowAllInvisibles")
            defaults.set(false, forKey: "NSShowControlCharacters")
        }
        layoutManager?.showsInvisibleCharacters = false
        layoutManager?.showsControlCharacters = false

        guard deep, !didApplyDeepInvisibleDisable else { return }
        didApplyDeepInvisibleDisable = true

        let selectors = [
            "setShowsInvisibleCharacters:",
            "setShowsControlCharacters:",
            "setDisplaysInvisibleCharacters:",
            "setDisplaysControlCharacters:"
        ]
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            let value = NSNumber(value: false)
            if responds(to: selector) {
                _ = perform(selector, with: value)
            }
            if let lm = layoutManager, lm.responds(to: selector) {
                _ = lm.perform(selector, with: value)
            }
        }
        if #available(macOS 12.0, *) {
            if let tlm = value(forKey: "textLayoutManager") as? NSObject {
                for selectorName in selectors {
                    let selector = NSSelectorFromString(selectorName)
                    if tlm.responds(to: selector) {
                        _ = tlm.perform(selector, with: NSNumber(value: false))
                    }
                }
            }
        }
    }

    private func configureActivityObservers() {
        guard activityObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification
        ]
        for name in names {
            let token = TextViewObserverToken(raw: center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notif in
                guard let self else { return }
                if let targetWindow = notif.object as? NSWindow, targetWindow != self.window {
                    return
                }
                self.forceDisableInvisibleGlyphRendering(deep: true)
            })
            activityObservers.append(token)
        }
    }

    func showInlineSuggestion(_ suggestion: String, at location: Int) {
        guard !suggestion.isEmpty else {
            clearInlineSuggestion()
            return
        }
        inlineSuggestion = suggestion
        inlineSuggestionLocation = location
        if inlineSuggestionView == nil {
            let label = NSTextField(labelWithString: suggestion)
            label.isBezeled = false
            label.isEditable = false
            label.isSelectable = false
            label.drawsBackground = false
            label.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.6)
            label.font = font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            label.lineBreakMode = .byClipping
            label.maximumNumberOfLines = 1
            inlineSuggestionView = label
            addSubview(label)
        } else {
            inlineSuggestionView?.stringValue = suggestion
            inlineSuggestionView?.font = font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }
        updateInlineSuggestionPosition()
    }

    func clearInlineSuggestion() {
        inlineSuggestion = nil
        inlineSuggestionLocation = nil
        inlineSuggestionView?.removeFromSuperview()
        inlineSuggestionView = nil
    }

    private func acceptInlineSuggestion() -> Bool {
        guard let suggestion = inlineSuggestion,
              let loc = inlineSuggestionLocation else { return false }
        let sanitizedSuggestion = sanitizedPlainText(suggestion)
        guard !sanitizedSuggestion.isEmpty else {
            clearInlineSuggestion()
            return false
        }
        let sel = selectedRange()
        guard sel.length == 0, sel.location == loc else {
            clearInlineSuggestion()
            return false
        }
        isApplyingInlineSuggestion = true
        textStorage?.replaceCharacters(in: NSRange(location: loc, length: 0), with: sanitizedSuggestion)
        setSelectedRange(NSRange(location: loc + (sanitizedSuggestion as NSString).length, length: 0))
        isApplyingInlineSuggestion = false
        recentlyAcceptedInlineSuggestion = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.recentlyAcceptedInlineSuggestion = false
        }
        clearInlineSuggestion()
        return true
    }

    private func updateInlineSuggestionPosition() {
        guard let suggestion = inlineSuggestion,
              let loc = inlineSuggestionLocation,
              let label = inlineSuggestionView,
              let window else { return }
        let sel = selectedRange()
        if sel.location != loc || sel.length != 0 {
            clearInlineSuggestion()
            return
        }
        let rectInScreen = firstRect(forCharacterRange: NSRange(location: loc, length: 0), actualRange: nil)
        let rectInWindow = window.convertFromScreen(rectInScreen)
        let rectInView = convert(rectInWindow, from: nil)
        label.stringValue = suggestion
        label.sizeToFit()
        label.frame.origin = NSPoint(x: rectInView.origin.x, y: rectInView.origin.y)
    }

    // Re-apply the desired caret position over multiple runloop ticks to beat late layout/async work.
    private func schedulePasteCaretEnforcement() {
        guard pendingPasteCaretLocation != nil else { return }

        // Cancel previously queued enforcement to avoid spamming
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyPendingPasteCaret), object: nil)

        // Run next turn
        perform(#selector(applyPendingPasteCaret), with: nil, afterDelay: 0)

        // Run again next runloop tick (beats "snap back" from late async work)
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingPasteCaret()
        }

        // Run once more with a tiny delay (beats slower async highlight passes)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.applyPendingPasteCaret()
        }
    }

    private func cancelPendingPasteCaretEnforcement() {
        pendingPasteCaretLocation = nil
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyPendingPasteCaret), object: nil)
    }

    @objc private func applyPendingPasteCaret() {
        guard let desired = pendingPasteCaretLocation else { return }

        let length = (string as NSString).length
        let loc = min(max(0, desired), length)
        let range = NSRange(location: loc, length: 0)

        // Set caret and keep it visible
        setSelectedRange(range)

        if let container = textContainer {
            layoutManager?.ensureLayout(for: container)
        }
        scrollRangeToVisible(range)

        // Important: clear only after we've enforced at least once.
        // The delayed calls will no-op once this is nil.
        pendingPasteCaretLocation = nil
    }

    private func postVimModeState() {
        NotificationCenter.default.post(
            name: .vimModeStateDidChange,
            object: nil,
            userInfo: ["insertMode": isVimInsertMode]
        )
    }

    private func insertBracketHelperToken(_ token: String) {
        guard isEditable else { return }
        clearInlineSuggestion()
        let selection = selectedRange()

        let pairMap: [String: (String, String)] = [
            "()": ("(", ")"),
            "{}": ("{", "}"),
            "[]": ("[", "]"),
            "\"\"": ("\"", "\""),
            "''": ("'", "'")
        ]

        if let pair = pairMap[token] {
            let insertion = pair.0 + pair.1
            textStorage?.replaceCharacters(in: selection, with: insertion)
            setSelectedRange(NSRange(location: selection.location + (pair.0 as NSString).length, length: 0))
            didChangeText()
            return
        }

        textStorage?.replaceCharacters(in: selection, with: token)
        setSelectedRange(NSRange(location: selection.location + (token as NSString).length, length: 0))
        didChangeText()
    }

    private func scalarName(for value: UInt32) -> String {
        switch value {
        case 0x20: return "SPACE"
        case 0x09: return "TAB"
        case 0x0A: return "LF"
        case 0x0D: return "CR"
        case 0x2581: return "LOWER_ONE_EIGHTH_BLOCK"
        default: return "U+\(String(format: "%04X", value))"
        }
    }

    private func inspectWhitespaceScalarsAtCaret() {
        let ns = string as NSString
        let length = ns.length
        let caret = min(max(selectedRange().location, 0), max(length - 1, 0))
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let line = ns.substring(with: lineRange)
        let lineOneBased = ns.substring(to: lineRange.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        var counts: [UInt32: Int] = [:]
        for scalar in line.unicodeScalars {
            let value = scalar.value
            let isWhitespace = scalar.properties.generalCategory == .spaceSeparator || value == 0x20 || value == 0x09
            let isLineBreak = value == 0x0A || value == 0x0D
            let isControlPicture = (0x2400...0x243F).contains(value)
            let isLowBlock = value == 0x2581
            if isWhitespace || isLineBreak || isControlPicture || isLowBlock {
                counts[value, default: 0] += 1
            }
        }

        let header = "Line \(lineOneBased) at UTF16@\(selectedRange().location), whitespace scalars:"
        let body: String
        if counts.isEmpty {
            body = "none detected"
        } else {
            let rows = counts.keys.sorted().map { key in
                "\(scalarName(for: key)) x\(counts[key] ?? 0)"
            }
            body = rows.joined(separator: ", ")
        }

        let windowNumber = window?.windowNumber ?? -1
        NotificationCenter.default.post(
            name: .whitespaceScalarInspectionResult,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.windowNumber: windowNumber,
                EditorCommandUserInfo.inspectionMessage: "\(header)\n\(body)"
            ]
        )
    }

    private func configureVimMode() {
        // Vim enabled starts in NORMAL; disabled uses regular insert typing.
        isVimInsertMode = !UserDefaults.standard.bool(forKey: vimModeDefaultsKey)
        postVimModeState()

        let observerRaw = NotificationCenter.default.addObserver(
            forName: .toggleVimModeRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Enter NORMAL when Vim mode is enabled; INSERT when disabled.
                let enabled = UserDefaults.standard.bool(forKey: self.vimModeDefaultsKey)
                self.isVimInsertMode = !enabled
                self.postVimModeState()
            }
        }
        let observer = TextViewObserverToken(raw: observerRaw)
        vimObservers.append(observer)

        let inspectorObserverRaw = NotificationCenter.default.addObserver(
            forName: .inspectWhitespaceScalarsRequested,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            if let target = notif.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
               let own = self.window?.windowNumber,
               target != own {
                return
            }
            self.inspectWhitespaceScalarsAtCaret()
        }
        let inspectorObserver = TextViewObserverToken(raw: inspectorObserverRaw)
        vimObservers.append(inspectorObserver)

        let bracketHelperObserverRaw = NotificationCenter.default.addObserver(
            forName: .insertBracketHelperTokenRequested,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            if let target = notif.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
               let own = self.window?.windowNumber,
               target != own {
                return
            }
            guard let token = notif.userInfo?[EditorCommandUserInfo.bracketToken] as? String else { return }
            self.insertBracketHelperToken(token)
        }
        let bracketHelperObserver = TextViewObserverToken(raw: bracketHelperObserverRaw)
        vimObservers.append(bracketHelperObserver)
    }

    private func trimTrailingWhitespaceIfEnabled() {
        let enabled = UserDefaults.standard.bool(forKey: "SettingsTrimTrailingWhitespace")
        guard enabled else { return }
        let original = self.string
        let lines = original.components(separatedBy: .newlines)
        var changed = false
        let trimmedLines = lines.map { line -> String in
            let trimmed = line.replacingOccurrences(of: #"[\t\x20]+$"#, with: "", options: .regularExpression)
            if trimmed != line { changed = true }
            return trimmed
        }
        guard changed else { return }
        let newString = trimmedLines.joined(separator: "\n")
        let oldSelected = self.selectedRange()
        self.textStorage?.beginEditing()
        self.string = newString
        self.textStorage?.endEditing()
        let newLoc = min(oldSelected.location, (newString as NSString).length)
        self.setSelectedRange(NSRange(location: newLoc, length: 0))
        self.didChangeText()
    }

}

// NSViewRepresentable wrapper around NSTextView to integrate with SwiftUI.
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    let documentID: UUID?
    let language: String
    let colorScheme: ColorScheme
    let fontSize: CGFloat
    @Binding var isLineWrapEnabled: Bool
    let isLargeFileMode: Bool
    let translucentBackgroundEnabled: Bool
    let showKeyboardAccessoryBar: Bool
    let showLineNumbers: Bool
    let showInvisibleCharacters: Bool
    let highlightCurrentLine: Bool
    let highlightMatchingBrackets: Bool
    let showScopeGuides: Bool
    let highlightScopeBackground: Bool
    let indentStyle: String
    let indentWidth: Int
    let autoIndentEnabled: Bool
    let autoCloseBracketsEnabled: Bool
    let highlightRefreshToken: Int
    let isTabLoadingContent: Bool
    let onTextMutation: ((EditorTextMutation) -> Void)?

    private var fontName: String {
        UserDefaults.standard.string(forKey: "SettingsEditorFontName") ?? ""
    }

    private var useSystemFont: Bool {
        UserDefaults.standard.bool(forKey: "SettingsUseSystemFont")
    }

    private var lineHeightMultiple: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "SettingsLineHeight")
        return CGFloat(stored > 0 ? stored : 1.0)
    }

    // Toggle soft-wrapping by adjusting text container sizing and scroller visibility.
    private func applyWrapMode(isWrapped: Bool, textView: NSTextView, scrollView: NSScrollView) {
        if isWrapped {
            // Wrap: track the text view width, no horizontal scrolling
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.heightTracksTextView = false
            scrollView.hasHorizontalScroller = false
            // Ensure the container width matches the visible content width right now
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

        // Keep wrap-mode flips lightweight; avoid forcing a full invalidation pass.
        if let container = textView.textContainer, let lm = textView.layoutManager {
            lm.ensureLayout(for: container)
        }
    }

    private func resolvedFont() -> NSFont {
        if useSystemFont {
            return NSFont.systemFont(ofSize: fontSize)
        }
        if let named = NSFont(name: fontName, size: fontSize) {
            return named
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = max(0.9, lineHeightMultiple)
        return style
    }

    private func effectiveBaseTextColor() -> NSColor {
        if colorScheme == .light && !translucentBackgroundEnabled {
            return NSColor.textColor
        }
        let theme = currentEditorTheme(colorScheme: colorScheme)
        return NSColor(theme.text)
    }

    private func applyInvisibleCharacterPreference(_ textView: NSTextView) {
        // Hard-disable invisible/control glyph rendering in editor text.
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "NSShowAllInvisibles")
        defaults.set(false, forKey: "NSShowControlCharacters")
        defaults.set(false, forKey: "SettingsShowInvisibleCharacters")
        textView.layoutManager?.showsInvisibleCharacters = false
        textView.layoutManager?.showsControlCharacters = false
        let value = NSNumber(value: false)
        let selectors = [
            "setShowsInvisibleCharacters:",
            "setShowsControlCharacters:",
            "setDisplaysInvisibleCharacters:",
            "setDisplaysControlCharacters:"
        ]
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            if textView.responds(to: selector) {
                let enabled = selectorName.contains("ControlCharacters") ? NSNumber(value: false) : value
                textView.perform(selector, with: enabled)
            }
            if let layoutManager = textView.layoutManager, layoutManager.responds(to: selector) {
                let enabled = selectorName.contains("ControlCharacters") ? NSNumber(value: false) : value
                _ = layoutManager.perform(selector, with: enabled)
            }
        }
        if #available(macOS 12.0, *) {
            if let tlm = textView.value(forKey: "textLayoutManager") as? NSObject {
                for selectorName in selectors {
                    let selector = NSSelectorFromString(selectorName)
                    if tlm.responds(to: selector) {
                        let enabled = selectorName.contains("ControlCharacters") ? NSNumber(value: false) : value
                        _ = tlm.perform(selector, with: enabled)
                    }
                }
            }
        }
    }

    private func sanitizedForExternalSet(_ input: String) -> String {
        let nsLength = (input as NSString).length
        if nsLength > 300_000 {
            if !input.contains("\0") && !input.contains("\r") {
                return input
            }
            return input
                .replacingOccurrences(of: "\0", with: "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }
        return AcceptingTextView.sanitizePlainText(input)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Build scroll view and text view
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = AcceptingTextView(frame: .zero)
        textView.identifier = NSUserInterfaceItemIdentifier("NeonEditorTextView")
        // Configure editing behavior and visuals
        textView.isEditable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.usesInspectorBar = false
        textView.usesFontPanel = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = resolvedFont()

        // Apply visibility preference from Settings (off by default).
        applyInvisibleCharacterPreference(textView)
        textView.textStorage?.beginEditing()
        if let storage = textView.textStorage {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.removeAttribute(.underlineStyle, range: fullRange)
            storage.removeAttribute(.strikethroughStyle, range: fullRange)
        }
        textView.textStorage?.endEditing()

        let theme = currentEditorTheme(colorScheme: colorScheme)
        if translucentBackgroundEnabled {
            textView.backgroundColor = .clear
            textView.drawsBackground = false
        } else {
            let bg = (colorScheme == .light) ? NSColor.textBackgroundColor : NSColor(theme.background)
            textView.backgroundColor = bg
            textView.drawsBackground = true
        }

        // Use NSRulerView line numbering (v0.4.4-beta behavior).
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isSelectable = true
        textView.allowsUndo = true
        let baseTextColor = effectiveBaseTextColor()
        textView.textColor = baseTextColor
        textView.insertionPointColor = (colorScheme == .light && !translucentBackgroundEnabled) ? NSColor.labelColor : NSColor(theme.cursor)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(theme.selection)
        ]
        textView.usesInspectorBar = false
        textView.usesFontPanel = false
        textView.layoutManager?.allowsNonContiguousLayout = true
        // Keep a fixed left gutter gap so content never visually collides with line numbers.
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.lineFragmentPadding = 4

        // Keep horizontal rulers disabled; vertical ruler is dedicated to line numbers.
        textView.usesRuler = true
        textView.isRulerVisible = showLineNumbers
        scrollView.hasHorizontalRuler = false
        scrollView.horizontalRulerView = nil
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers
        scrollView.verticalRulerView = showLineNumbers ? LineNumberRulerView(textView: textView) : nil

        applyInvisibleCharacterPreference(textView)
        textView.autoIndentEnabled = autoIndentEnabled
        textView.autoCloseBracketsEnabled = autoCloseBracketsEnabled
        textView.emmetLanguage = language
        textView.indentStyle = indentStyle
        textView.indentWidth = indentWidth
        textView.highlightCurrentLine = highlightCurrentLine

        // Disable smart substitutions/detections that can interfere with selection when recoloring
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.registerForDraggedTypes([.fileURL, .URL])

        // Embed the text view in the scroll view
        scrollView.documentView = textView

        // Configure the text view delegate
        textView.delegate = context.coordinator

        // Apply wrapping and seed initial content
        applyWrapMode(isWrapped: isLineWrapEnabled && !isLargeFileMode, textView: textView, scrollView: scrollView)

        // Seed initial text (strip control pictures when invisibles are hidden)
        let seeded = sanitizedForExternalSet(text)
        textView.string = seeded
        if seeded != text {
            // Keep binding clean of control-picture glyphs.
            DispatchQueue.main.async {
                if self.text != seeded {
                    self.text = seeded
                }
            }
        }
        context.coordinator.scheduleHighlightIfNeeded(currentText: text, immediate: true)

        // Keep container width in sync when the scroll view resizes (coalesced and guarded in coordinator).
        context.coordinator.installWrapResizeObserver(for: textView, scrollView: scrollView)

        context.coordinator.textView = textView
        return scrollView
    }

    // Keep NSTextView in sync with SwiftUI state and schedule highlighting when needed.
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            var needsLayoutRefresh = false
            var didChangeRulerConfiguration = false
            textView.isEditable = true
            textView.isSelectable = true
            let acceptingView = textView as? AcceptingTextView
            let isDropApplyInFlight = acceptingView?.isApplyingDroppedContent ?? false
            context.coordinator.installWrapResizeObserver(for: textView, scrollView: nsView)
            let didSwitchDocument = context.coordinator.lastDocumentID != documentID
            let didFinishTabLoad = (context.coordinator.lastTabLoadingContent == true) && !isTabLoadingContent
            let isInteractionSuppressed = context.coordinator.isInInteractionSuppressionWindow()
            if didSwitchDocument {
                context.coordinator.lastDocumentID = documentID
                context.coordinator.cancelPendingBindingSync()
                context.coordinator.clearPendingTextMutation()
                context.coordinator.invalidateHighlightCache()
            }
            context.coordinator.lastTabLoadingContent = isTabLoadingContent

            // Sanitize and avoid publishing binding during update
            let target = sanitizedForExternalSet(text)
            if textView.string != target {
                let hasFocus = (textView.window?.firstResponder as? NSTextView) === textView
                let shouldPreferEditorBuffer = hasFocus && !isTabLoadingContent && !didSwitchDocument && !didFinishTabLoad
                if shouldPreferEditorBuffer || isInteractionSuppressed {
                    context.coordinator.syncBindingTextImmediately(textView.string)
                } else {
                    context.coordinator.cancelPendingBindingSync()
                    replaceTextPreservingSelectionAndFocus(
                        textView,
                        with: target,
                        preserveViewport: !didSwitchDocument
                    )
                    needsLayoutRefresh = true
                    context.coordinator.invalidateHighlightCache()
                    DispatchQueue.main.async {
                        if self.text != target {
                            self.text = target
                        }
                    }
                }
            }

            let targetFont = resolvedFont()
            let currentFont = textView.font
            let fontChanged = currentFont?.fontName != targetFont.fontName ||
                abs((currentFont?.pointSize ?? -1) - targetFont.pointSize) > 0.001
            if fontChanged {
                textView.font = targetFont
                needsLayoutRefresh = true
                context.coordinator.invalidateHighlightCache()
            }
            if textView.textContainerInset.width != 6 || textView.textContainerInset.height != 8 {
                textView.textContainerInset = NSSize(width: 6, height: 8)
                needsLayoutRefresh = true
            }
            if textView.textContainer?.lineFragmentPadding != 4 {
                textView.textContainer?.lineFragmentPadding = 4
                needsLayoutRefresh = true
            }
            let style = paragraphStyle()
            let currentLineHeight = textView.defaultParagraphStyle?.lineHeightMultiple ?? 1.0
            if abs(currentLineHeight - style.lineHeightMultiple) > 0.0001 {
                textView.defaultParagraphStyle = style
                textView.typingAttributes[.paragraphStyle] = style
                needsLayoutRefresh = true
                let nsLen = (textView.string as NSString).length
                if nsLen <= 200_000, let storage = textView.textStorage {
                    storage.beginEditing()
                    storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: nsLen))
                    storage.endEditing()
                }
            }

            // Defensive sanitize pass only for smaller documents to avoid heavy full-buffer scans.
            let currentLength = (textView.string as NSString).length
            if currentLength <= 300_000 {
                let sanitized = AcceptingTextView.sanitizePlainText(textView.string)
                if sanitized != textView.string, !isInteractionSuppressed {
                    replaceTextPreservingSelectionAndFocus(
                        textView,
                        with: sanitized,
                        preserveViewport: !didSwitchDocument
                    )
                    needsLayoutRefresh = true
                    context.coordinator.invalidateHighlightCache()
                    DispatchQueue.main.async {
                        if self.text != sanitized {
                            self.text = sanitized
                        }
                    }
                }
            }

            let theme = currentEditorTheme(colorScheme: colorScheme)

            let effectiveHighlightCurrentLine = highlightCurrentLine
            let effectiveWrap = (isLineWrapEnabled && !isLargeFileMode)

            // Background color adjustments for translucency
            if translucentBackgroundEnabled {
                nsView.drawsBackground = false
                textView.backgroundColor = .clear
                textView.drawsBackground = false
            } else {
                nsView.drawsBackground = false
                let bg = (colorScheme == .light) ? NSColor.textBackgroundColor : NSColor(theme.background)
                textView.backgroundColor = bg
                textView.drawsBackground = true
            }
            let baseTextColor = effectiveBaseTextColor()
            let caretColor = (colorScheme == .light && !translucentBackgroundEnabled) ? NSColor.labelColor : NSColor(theme.cursor)
            if textView.insertionPointColor != caretColor {
                textView.insertionPointColor = caretColor
            }
            textView.typingAttributes[.foregroundColor] = baseTextColor
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor(theme.selection)
            ]
            let showLineNumbersByDefault = showLineNumbers
            if textView.usesRuler != showLineNumbersByDefault {
                textView.usesRuler = showLineNumbersByDefault
                didChangeRulerConfiguration = true
            }
            if textView.isRulerVisible != showLineNumbersByDefault {
                textView.isRulerVisible = showLineNumbersByDefault
                didChangeRulerConfiguration = true
            }
            if nsView.hasHorizontalRuler {
                nsView.hasHorizontalRuler = false
                didChangeRulerConfiguration = true
            }
            if nsView.horizontalRulerView != nil {
                nsView.horizontalRulerView = nil
                didChangeRulerConfiguration = true
            }
            if nsView.hasVerticalRuler != showLineNumbersByDefault {
                nsView.hasVerticalRuler = showLineNumbersByDefault
                didChangeRulerConfiguration = true
            }
            if nsView.rulersVisible != showLineNumbersByDefault {
                nsView.rulersVisible = showLineNumbersByDefault
                didChangeRulerConfiguration = true
            }
            if showLineNumbersByDefault {
                if !(nsView.verticalRulerView is LineNumberRulerView) {
                    nsView.verticalRulerView = LineNumberRulerView(textView: textView)
                    didChangeRulerConfiguration = true
                }
            } else {
                if nsView.verticalRulerView != nil {
                    nsView.verticalRulerView = nil
                    didChangeRulerConfiguration = true
                }
            }

            // Re-apply invisible-character visibility preference after style updates.
            applyInvisibleCharacterPreference(textView)

            // Keep the text container width in sync & relayout
            acceptingView?.autoIndentEnabled = autoIndentEnabled
            acceptingView?.autoCloseBracketsEnabled = autoCloseBracketsEnabled
            acceptingView?.emmetLanguage = language
            acceptingView?.indentStyle = indentStyle
            acceptingView?.indentWidth = indentWidth
            acceptingView?.highlightCurrentLine = effectiveHighlightCurrentLine
            if context.coordinator.lastAppliedWrapMode != effectiveWrap {
                applyWrapMode(isWrapped: effectiveWrap, textView: textView, scrollView: nsView)
                context.coordinator.lastAppliedWrapMode = effectiveWrap
                needsLayoutRefresh = true
            }

            if didChangeRulerConfiguration {
                context.coordinator.scheduleDeferredRulerTile(for: nsView)
            }
            if needsLayoutRefresh, let container = textView.textContainer {
                context.coordinator.scheduleDeferredEnsureLayout(for: textView, container: container)
            }

            // Only schedule highlight if needed (e.g., language/color scheme changes or external text updates)
            context.coordinator.parent = self

            if !isDropApplyInFlight {
                let shouldSchedule = context.coordinator.shouldScheduleHighlightFromUpdate(
                    currentText: textView.string,
                    language: language,
                    colorScheme: colorScheme,
                    lineHeightValue: lineHeightMultiple,
                    token: highlightRefreshToken,
                    translucencyEnabled: translucentBackgroundEnabled
                )
                if shouldSchedule {
                    context.coordinator.scheduleHighlightIfNeeded()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }


    // Coordinator: NSTextViewDelegate that bridges NSText changes to SwiftUI and manages highlighting.
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        weak var textView: NSTextView?

        // Background queue + debouncer for regex-based highlighting
        private let highlightQueue = DispatchQueue(label: "NeonVision.SyntaxHighlight", qos: .userInitiated)
        // Snapshots of last highlighted state to avoid redundant work
        private var pendingHighlight: DispatchWorkItem?
        private var lastHighlightedText: String = ""
        private var lastLanguage: String?
        private var lastColorScheme: ColorScheme?
        var lastLineHeight: CGFloat?
        private var lastHighlightToken: Int = 0
        private var lastSelectionLocation: Int = -1
        private var lastTranslucencyEnabled: Bool?
        private var isApplyingHighlight = false
        private var highlightGeneration: Int = 0
        private var pendingEditedRange: NSRange?
        private var pendingBindingSync: DispatchWorkItem?
        private var pendingTextMutation: (range: NSRange, replacement: String)?
        private var pendingDeferredRulerTile = false
        private var pendingDeferredLayoutEnsure = false
        private var wrapResizeObserver: TextViewObserverToken?
        private weak var observedWrapContentView: NSClipView?
        private var lastObservedWrapContentWidth: CGFloat = -1
        private var interactionSuppressionDeadline: TimeInterval = 0
        var lastAppliedWrapMode: Bool?
        var lastDocumentID: UUID?
        var lastTabLoadingContent: Bool?
        var hasPendingBindingSync: Bool { pendingBindingSync != nil }

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(moveToLine(_:)), name: .moveCursorToLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(moveToRange(_:)), name: .moveCursorToRange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handlePointerInteraction(_:)), name: .editorPointerInteraction, object: nil)
        }

        deinit {
            if let wrapResizeObserver {
                NotificationCenter.default.removeObserver(wrapResizeObserver.raw)
            }
            NotificationCenter.default.removeObserver(self)
        }

        func invalidateHighlightCache() {
            lastHighlightedText = ""
            lastLanguage = nil
            lastColorScheme = nil
            lastLineHeight = nil
            lastHighlightToken = 0
            lastSelectionLocation = -1
            lastTranslucencyEnabled = nil
        }

        private func syncBindingText(_ text: String, immediate: Bool = false) {
            if parent.isTabLoadingContent {
                return
            }
            pendingBindingSync?.cancel()
            pendingBindingSync = nil
            if immediate || (text as NSString).length < EditorRuntimeLimits.bindingDebounceUTF16Length {
                parent.text = text
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingBindingSync = nil
                if self.textView?.string == text {
                    self.parent.text = text
                }
            }
            pendingBindingSync = work
            DispatchQueue.main.asyncAfter(deadline: .now() + EditorRuntimeLimits.bindingDebounceDelay, execute: work)
        }

        func cancelPendingBindingSync() {
            pendingBindingSync?.cancel()
            pendingBindingSync = nil
        }

        func clearPendingTextMutation() {
            pendingTextMutation = nil
        }

        private func debugViewportTrace(_ source: String, textView: NSTextView? = nil) {
#if DEBUG
            let tv = textView ?? self.textView
            let sel = tv?.selectedRange().location ?? -1
            let origin = tv?.enclosingScrollView?.contentView.bounds.origin ?? .zero
            print("[ViewportTrace] \(source) wrap=\(parent.isLineWrapEnabled) sel=\(sel) origin=(\(Int(origin.x)),\(Int(origin.y)))")
#endif
        }

        private func noteRecentInteraction(source: String, duration: TimeInterval = 0.24) {
            let now = ProcessInfo.processInfo.systemUptime
            interactionSuppressionDeadline = max(interactionSuppressionDeadline, now + duration)
            pendingHighlight?.cancel()
            pendingHighlight = nil
            highlightGeneration &+= 1
            debugViewportTrace("interaction:\(source)")
        }

        func isInInteractionSuppressionWindow() -> Bool {
            ProcessInfo.processInfo.systemUptime < interactionSuppressionDeadline
        }

        func shouldScheduleHighlightFromUpdate(
            currentText: String,
            language: String,
            colorScheme: ColorScheme,
            lineHeightValue: CGFloat,
            token: Int,
            translucencyEnabled: Bool
        ) -> Bool {
            if isInInteractionSuppressionWindow() {
                return false
            }
            if parent.isLargeFileMode {
                return false
            }
            return !(currentText == lastHighlightedText &&
                     language == lastLanguage &&
                     colorScheme == lastColorScheme &&
                     abs((lastLineHeight ?? lineHeightValue) - lineHeightValue) <= 0.0001 &&
                     token == lastHighlightToken &&
                     translucencyEnabled == lastTranslucencyEnabled)
        }

        func installWrapResizeObserver(for textView: NSTextView, scrollView: NSScrollView) {
            guard observedWrapContentView !== scrollView.contentView else { return }
            if let wrapResizeObserver {
                NotificationCenter.default.removeObserver(wrapResizeObserver.raw)
            }
            observedWrapContentView = scrollView.contentView
            lastObservedWrapContentWidth = -1
            let tokenRaw = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak textView, weak scrollView] _ in
                guard let self, let tv = textView, let sv = scrollView else { return }
                guard tv.textContainer?.widthTracksTextView == true else { return }
                let targetWidth = sv.contentSize.width
                guard targetWidth > 0 else { return }
                if abs(self.lastObservedWrapContentWidth - targetWidth) <= 0.5 {
                    return
                }
                self.lastObservedWrapContentWidth = targetWidth
                let currentWidth = tv.textContainer?.containerSize.width ?? 0
                guard abs(currentWidth - targetWidth) > 0.5 else { return }
                tv.textContainer?.containerSize.width = targetWidth
                self.debugViewportTrace("wrapWidthChanged", textView: tv)
            }
            wrapResizeObserver = TextViewObserverToken(raw: tokenRaw)
        }

        @objc private func handlePointerInteraction(_ notification: Notification) {
            guard let interactedTextView = notification.object as? NSTextView else { return }
            guard let activeTextView = textView, interactedTextView === activeTextView else { return }
            noteRecentInteraction(source: "mouseDown")
        }

        func scheduleDeferredRulerTile(for scrollView: NSScrollView) {
            guard !pendingDeferredRulerTile else { return }
            pendingDeferredRulerTile = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self else { return }
                self.pendingDeferredRulerTile = false
                scrollView?.tile()
            }
        }

        func scheduleDeferredEnsureLayout(for textView: NSTextView, container: NSTextContainer) {
            guard !pendingDeferredLayoutEnsure else { return }
            pendingDeferredLayoutEnsure = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.pendingDeferredLayoutEnsure = false
                guard let textView else { return }
                textView.layoutManager?.ensureLayout(for: container)
            }
        }

        func syncBindingTextImmediately(_ text: String) {
            syncBindingText(text, immediate: true)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !parent.isTabLoadingContent,
                  parent.documentID != nil,
                  let replacementString else {
                pendingTextMutation = nil
                return true
            }
            pendingTextMutation = (
                range: affectedCharRange,
                replacement: AcceptingTextView.sanitizePlainText(replacementString)
            )
            return true
        }

        func scheduleHighlightIfNeeded(currentText: String? = nil, immediate: Bool = false) {
            guard textView != nil else { return }

            // Query NSApp.modalWindow on the main thread to avoid thread-check warnings
            let isModalPresented: Bool = {
                if Thread.isMainThread {
                    return NSApp.modalWindow != nil
                } else {
                    var result = false
                    DispatchQueue.main.sync { result = (NSApp.modalWindow != nil) }
                    return result
                }
            }()

            if isModalPresented {
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
            let lineHeightValue: CGFloat = parent.lineHeightMultiple
            let token = parent.highlightRefreshToken
            let translucencyEnabled = parent.translucentBackgroundEnabled
            let selectionLocation: Int = {
                if Thread.isMainThread {
                    return textView?.selectedRange().location ?? 0
                }
                var result = 0
                DispatchQueue.main.sync {
                    result = textView?.selectedRange().location ?? 0
                }
                return result
            }()
            let text: String = {
                if let currentText = currentText {
                    return currentText
                }

                if Thread.isMainThread {
                    return textView?.string ?? ""
                }

                var result = ""
                DispatchQueue.main.sync {
                    result = textView?.string ?? ""
                }
                return result
            }()

            if !immediate && isInInteractionSuppressionWindow() {
                lastSelectionLocation = selectionLocation
                debugViewportTrace("highlightSuppressedInteraction")
                return
            }

            if parent.isLargeFileMode {
                self.lastHighlightedText = text
                self.lastLanguage = lang
                self.lastColorScheme = scheme
                self.lastLineHeight = lineHeightValue
                self.lastHighlightToken = token
                self.lastSelectionLocation = selectionLocation
                self.lastTranslucencyEnabled = self.parent.translucentBackgroundEnabled
                return
            }
            let textLength = (text as NSString).length
            if textLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length {
                self.lastHighlightedText = text
                self.lastLanguage = lang
                self.lastColorScheme = scheme
                self.lastLineHeight = lineHeightValue
                self.lastHighlightToken = token
                self.lastSelectionLocation = selectionLocation
                self.lastTranslucencyEnabled = self.parent.translucentBackgroundEnabled
                return
            }

            if text == lastHighlightedText &&
                lastLanguage == lang &&
                lastColorScheme == scheme &&
                lastLineHeight == lineHeightValue &&
                lastHighlightToken == token &&
                lastSelectionLocation == selectionLocation &&
                lastTranslucencyEnabled == translucencyEnabled {
                return
            }
            let styleStateUnchanged = lang == lastLanguage &&
                scheme == lastColorScheme &&
                lastLineHeight == lineHeightValue &&
                lastHighlightToken == token &&
                lastTranslucencyEnabled == translucencyEnabled
            let selectionOnlyChange = text == lastHighlightedText &&
                styleStateUnchanged &&
                lastSelectionLocation != selectionLocation
            if selectionOnlyChange && (parent.isLineWrapEnabled || textLength >= EditorRuntimeLimits.cursorRehighlightMaxUTF16Length) {
                // Avoid running stale highlight work that can re-apply an outdated viewport in wrapped mode.
                pendingHighlight?.cancel()
                pendingHighlight = nil
                highlightGeneration &+= 1
                lastSelectionLocation = selectionLocation
                return
            }
            let incrementalRange: NSRange? = {
                guard token == lastHighlightToken,
                      lang == lastLanguage,
                      scheme == lastColorScheme,
                      !immediate,
                      text.utf16.count < 120_000,
                      let edit = pendingEditedRange else { return nil }
                return expandedHighlightRange(around: edit, in: text as NSString)
            }()
            pendingEditedRange = nil
            let shouldRunImmediate = immediate || lastHighlightedText.isEmpty || lastHighlightToken != token
            highlightGeneration &+= 1
            let generation = highlightGeneration
            rehighlight(token: token, generation: generation, immediate: shouldRunImmediate, targetRange: incrementalRange)
        }

        private func expandedHighlightRange(around range: NSRange, in text: NSString, maxUTF16Padding: Int = 6000) -> NSRange {
            let start = max(0, range.location - maxUTF16Padding)
            let end = min(text.length, NSMaxRange(range) + maxUTF16Padding)
            let startLine = text.lineRange(for: NSRange(location: start, length: 0)).location
            let endAnchor = max(startLine, min(text.length - 1, max(0, end - 1)))
            let endLine = NSMaxRange(text.lineRange(for: NSRange(location: endAnchor, length: 0)))
            return NSRange(location: startLine, length: max(0, endLine - startLine))
        }

        private func preferredHighlightRange(
            in textView: NSTextView,
            text: NSString,
            explicitRange: NSRange?,
            immediate: Bool
        ) -> NSRange {
            let fullRange = NSRange(location: 0, length: text.length)
            if let explicitRange {
                return explicitRange
            }
            // For very large buffers, prioritize visible content while typing.
            guard text.length >= 100_000 else { return fullRange }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return fullRange }
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
            let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
            guard visibleCharacterRange.length > 0 else { return fullRange }
            return expandedHighlightRange(around: visibleCharacterRange, in: text, maxUTF16Padding: 12_000)
        }

        func rehighlight(token: Int, generation: Int, immediate: Bool = false, targetRange: NSRange? = nil) {
            if !Thread.isMainThread {
                DispatchQueue.main.async { [weak self] in
                    self?.rehighlight(token: token, generation: generation, immediate: immediate, targetRange: targetRange)
                }
                return
            }
            guard let textView = textView else { return }
            // Snapshot current state
            let textSnapshot = textView.string
            let language = parent.language
            let scheme = parent.colorScheme
            let lineHeightValue: CGFloat = parent.lineHeightMultiple
            let selected = textView.selectedRange()
            let theme = currentEditorTheme(colorScheme: scheme)
            let nsText = textSnapshot as NSString
            let syntaxProfile: SyntaxPatternProfile = {
                let lower = language.lowercased()
                if lower == "html" && nsText.length >= EditorRuntimeLimits.htmlFastProfileUTF16Length {
                    return .htmlFast
                }
                if lower == "csv" && nsText.length >= EditorRuntimeLimits.csvFastProfileUTF16Length {
                    return .csvFast
                }
                return .full
            }()
            let colors = SyntaxColors(
                keyword: theme.syntax.keyword,
                string: theme.syntax.string,
                number: theme.syntax.number,
                comment: theme.syntax.comment,
                attribute: theme.syntax.attribute,
                variable: theme.syntax.variable,
                def: theme.syntax.def,
                property: theme.syntax.property,
                meta: theme.syntax.meta,
                tag: theme.syntax.tag,
                atom: theme.syntax.atom,
                builtin: theme.syntax.builtin,
                type: theme.syntax.type
            )
            let patterns = getSyntaxPatterns(for: language, colors: colors, profile: syntaxProfile)
            let fullRange = NSRange(location: 0, length: nsText.length)
            let applyRange = preferredHighlightRange(
                in: textView,
                text: nsText,
                explicitRange: targetRange,
                immediate: immediate
            )

            // Cancel any in-flight work
            pendingHighlight?.cancel()

            let work = DispatchWorkItem { [weak self] in
                let interval = syntaxHighlightSignposter.beginInterval("rehighlight_macos")
                // Compute matches off the main thread
                var coloredRanges: [(NSRange, Color)] = []
                if let fastRanges = fastSyntaxColorRanges(
                    language: language,
                    profile: syntaxProfile,
                    text: nsText,
                    in: applyRange,
                    colors: colors
                ) {
                    coloredRanges = fastRanges
                } else {
                    for (pattern, color) in patterns {
                        guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                        let matches = regex.matches(in: textSnapshot, range: applyRange)
                        for match in matches {
                            coloredRanges.append((match.range, color))
                        }
                    }
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let tv = self.textView else {
                        syntaxHighlightSignposter.endInterval("rehighlight_macos", interval)
                        return
                    }
                    defer { syntaxHighlightSignposter.endInterval("rehighlight_macos", interval) }
                    guard generation == self.highlightGeneration else { return }
                    // Discard if text changed since we started
                    guard tv.string == textSnapshot else { return }
                    let baseColor = self.parent.effectiveBaseTextColor()
                    let priorSelectedRange = tv.selectedRange()
                    let selectionBeforeApply = priorSelectedRange
                    self.isApplyingHighlight = true
                    defer { self.isApplyingHighlight = false }

                    tv.textStorage?.beginEditing()
                    tv.textStorage?.removeAttribute(.foregroundColor, range: applyRange)
                    tv.textStorage?.removeAttribute(.backgroundColor, range: applyRange)
                    tv.textStorage?.removeAttribute(.underlineStyle, range: applyRange)
                    tv.textStorage?.addAttribute(.foregroundColor, value: baseColor, range: applyRange)
                    // Apply colored ranges
                    for (range, color) in coloredRanges {
                        tv.textStorage?.addAttribute(.foregroundColor, value: NSColor(color), range: range)
                    }

                    let nsTextMain = textSnapshot as NSString
                    let selectedLocation = min(max(0, selected.location), max(0, fullRange.length))
                    let wantsBracketTokens = self.parent.highlightMatchingBrackets
                    let wantsScopeBackground = self.parent.highlightScopeBackground
                    let wantsScopeGuides = self.parent.showScopeGuides && !self.parent.isLineWrapEnabled && self.parent.language.lowercased() != "swift"
                    let needsScopeComputation = (wantsBracketTokens || wantsScopeBackground || wantsScopeGuides)
                        && nsTextMain.length < EditorRuntimeLimits.scopeComputationMaxUTF16Length
                    let bracketMatch = needsScopeComputation ? computeBracketScopeMatch(text: textSnapshot, caretLocation: selectedLocation) : nil
                    let indentationMatch: IndentationScopeMatch? = {
                        guard needsScopeComputation, supportsIndentationScopes(language: self.parent.language) else { return nil }
                        return computeIndentationScopeMatch(text: textSnapshot, caretLocation: selectedLocation)
                    }()

                    if wantsBracketTokens, let match = bracketMatch {
                        let textLength = fullRange.length
                        let tokenColor = NSColor.systemOrange
                        if isValidRange(match.openRange, utf16Length: textLength) {
                            tv.textStorage?.addAttribute(.foregroundColor, value: tokenColor, range: match.openRange)
                            tv.textStorage?.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.openRange)
                            tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.22), range: match.openRange)
                        }
                        if isValidRange(match.closeRange, utf16Length: textLength) {
                            tv.textStorage?.addAttribute(.foregroundColor, value: tokenColor, range: match.closeRange)
                            tv.textStorage?.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.closeRange)
                            tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.22), range: match.closeRange)
                        }
                    }

                    if wantsScopeBackground || wantsScopeGuides {
                        let textLength = fullRange.length
                        let scopeRange = bracketMatch?.scopeRange ?? indentationMatch?.scopeRange
                        let guideRanges = bracketMatch?.guideMarkerRanges ?? indentationMatch?.guideMarkerRanges ?? []

                        if wantsScopeBackground, let scope = scopeRange, isValidRange(scope, utf16Length: textLength) {
                            tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.18), range: scope)
                        }

                        if wantsScopeGuides {
                            for marker in guideRanges {
                                if isValidRange(marker, utf16Length: textLength) {
                                    tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.36), range: marker)
                                }
                            }
                        }
                    }

                    if self.parent.highlightCurrentLine {
                        let caret = NSRange(location: selectedLocation, length: 0)
                        let lineRange = nsTextMain.lineRange(for: caret)
                        tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.12), range: lineRange)
                    }
                    tv.textStorage?.endEditing()
                    let textLength = (tv.string as NSString).length
                    let safeLocation = min(max(0, priorSelectedRange.location), textLength)
                    let safeLength = min(max(0, priorSelectedRange.length), max(0, textLength - safeLocation))
                    let safeRange = NSRange(location: safeLocation, length: safeLength)
                    let currentRange = tv.selectedRange()
                    let selectionUnchangedDuringApply =
                        currentRange.location == selectionBeforeApply.location &&
                        currentRange.length == selectionBeforeApply.length
                    if selectionUnchangedDuringApply &&
                        (currentRange.location != safeRange.location || currentRange.length != safeRange.length) {
                        tv.setSelectedRange(safeRange)
                    }
                    tv.typingAttributes[.foregroundColor] = baseColor

                    self.parent.applyInvisibleCharacterPreference(tv)

                    // Update last highlighted state
                    self.lastHighlightedText = textSnapshot
                    self.lastLanguage = language
                    self.lastColorScheme = scheme
                    self.lastLineHeight = lineHeightValue
                    self.lastHighlightToken = token
                    self.lastSelectionLocation = selectedLocation
                    self.lastTranslucencyEnabled = self.parent.translucentBackgroundEnabled
                }
            }

            pendingHighlight = work
            // Run immediately on first paint/explicit refresh, debounce while typing.
            if immediate {
                highlightQueue.async(execute: work)
            } else {
                let delay: TimeInterval
                if targetRange != nil {
                    delay = 0.08
                } else if textSnapshot.utf16.count >= 120_000 {
                    delay = 0.22
                } else {
                    delay = 0.12
                }
                highlightQueue.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if let accepting = textView as? AcceptingTextView, accepting.isApplyingDroppedContent {
                // Drop-import chunking mutates storage many times; defer expensive binding/highlight work
                // until the final didChangeText emitted after import completion.
                return
            }
            let currentText = textView.string
            let currentLength = (currentText as NSString).length
            let sanitized: String
            if currentLength > 300_000 {
                // Fast path while editing very large files.
                if currentText.contains("\0") || currentText.contains("\r") {
                    sanitized = currentText
                        .replacingOccurrences(of: "\0", with: "")
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                } else {
                    sanitized = currentText
                }
            } else {
                sanitized = AcceptingTextView.sanitizePlainText(currentText)
            }
            if sanitized != currentText {
                pendingTextMutation = nil
                replaceTextPreservingSelectionAndFocus(textView, with: sanitized)
            }
            let normalizedStyle = NSMutableParagraphStyle()
            normalizedStyle.lineHeightMultiple = max(0.9, parent.lineHeightMultiple)
            textView.defaultParagraphStyle = normalizedStyle
            textView.typingAttributes[.paragraphStyle] = normalizedStyle
            if let storage = textView.textStorage {
                let len = storage.length
                if len <= 200_000 {
                    storage.beginEditing()
                    storage.addAttribute(.paragraphStyle, value: normalizedStyle, range: NSRange(location: 0, length: len))
                    storage.endEditing()
                }
            }
            let didApplyIncrementalMutation = applyPendingTextMutationIfPossible()
            if !didApplyIncrementalMutation {
                syncBindingText(sanitized)
            }
            parent.applyInvisibleCharacterPreference(textView)
            if let accepting = textView as? AcceptingTextView, accepting.isApplyingPaste {
                parent.applyInvisibleCharacterPreference(textView)
                let snapshot = textView.string
                highlightQueue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    DispatchQueue.main.async {
                        self?.syncBindingText(snapshot, immediate: true)
                        self?.scheduleHighlightIfNeeded(currentText: snapshot)
                    }
                }
                return
            }
            parent.applyInvisibleCharacterPreference(textView)
            // Update SwiftUI binding, caret status, and rehighlight.
            let nsText = textView.string as NSString
            let caretLocation = min(nsText.length, textView.selectedRange().location)
            pendingEditedRange = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))
            updateCaretStatusAndHighlight(triggerHighlight: false)
            scheduleHighlightIfNeeded(currentText: sanitized)
        }

        private func applyPendingTextMutationIfPossible() -> Bool {
            defer { pendingTextMutation = nil }
            guard !parent.isTabLoadingContent,
                  let pendingTextMutation,
                  let documentID = parent.documentID,
                  let onTextMutation = parent.onTextMutation else {
                return false
            }
            onTextMutation(
                EditorTextMutation(
                    documentID: documentID,
                    range: pendingTextMutation.range,
                    replacement: pendingTextMutation.replacement
                )
            )
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if isApplyingHighlight { return }
            if let tv = notification.object as? AcceptingTextView {
                tv.clearInlineSuggestion()
                if let eventType = tv.window?.currentEvent?.type,
                   eventType == .leftMouseDown || eventType == .leftMouseDragged || eventType == .leftMouseUp {
                    noteRecentInteraction(source: "selection")
                }
            }
            updateCaretStatusAndHighlight(triggerHighlight: !parent.isLineWrapEnabled)
        }

        // Compute (line, column), broadcast, and highlight the current line.
        private func updateCaretStatusAndHighlight(triggerHighlight: Bool = true) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let location = sel.location
            if parent.isLargeFileMode || ns.length > 300_000 {
                NotificationCenter.default.post(
                    name: .caretPositionDidChange,
                    object: nil,
                    userInfo: ["line": 0, "column": location]
                )
                return
            }
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
            if triggerHighlight {
                // For very large files, avoid immediate full caret-triggered passes to keep UI responsive.
                let immediateHighlight = ns.length < 200_000
                scheduleHighlightIfNeeded(currentText: tv.string, immediate: immediateHighlight)
            }
        }

        @objc func moveToLine(_ notification: Notification) {
            if let targetWindow = notification.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
               let ownWindow = textView?.window?.windowNumber,
               targetWindow != ownWindow {
                return
            }
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
                if let textContainer = tv.textContainer {
                    tv.layoutManager?.ensureLayout(for: textContainer)
                }
                tv.setSelectedRange(NSRange(location: location, length: 0))
                tv.scrollRangeToVisible(NSRange(location: location, length: 0))

                self.scheduleHighlightIfNeeded(currentText: tv.string, immediate: true)
            }
        }

        @objc func moveToRange(_ notification: Notification) {
            if let targetWindow = notification.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
               let ownWindow = textView?.window?.windowNumber,
               targetWindow != ownWindow {
                return
            }
            guard let textView = textView else { return }
            guard let location = notification.userInfo?[EditorCommandUserInfo.rangeLocation] as? Int,
                  let length = notification.userInfo?[EditorCommandUserInfo.rangeLength] as? Int else { return }
            let textLength = (textView.string as NSString).length
            guard location >= 0, length >= 0, location + length <= textLength else { return }

            let range = NSRange(location: location, length: length)
            pendingHighlight?.cancel()
            textView.window?.makeFirstResponder(textView)
            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            scheduleHighlightIfNeeded(currentText: textView.string, immediate: true)
        }
    }
}
#else
import UIKit

final class EditorInputTextView: UITextView {
    private final class BracketAccessoryHostView: UIView {
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: 46)
        }
    }

    private let bracketTokens: [String] = ["(", ")", "{", "}", "[", "]", "<", ">", "'", "\"", "`", "()", "{}", "[]", "\"\"", "''"]

    private lazy var bracketAccessoryView: UIView = {
        let host = BracketAccessoryHostView()
        host.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        host.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        for token in bracketTokens {
            let button = UIButton(type: .system)
            button.setTitle(token, for: .normal)
            button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
            button.accessibilityIdentifier = token
            if #available(iOS 15.0, *) {
                var config = button.configuration ?? .plain()
                config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                button.configuration = config
            } else {
                button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            }
            button.layer.cornerRadius = 8
            button.layer.masksToBounds = true
            button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
            button.addTarget(self, action: #selector(insertBracketToken(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        host.addSubview(scroll)
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            host.heightAnchor.constraint(equalToConstant: 46),

            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: host.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -6),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        return host
    }()
    private var isBracketAccessoryVisible: Bool = true

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        inputAccessoryView = bracketAccessoryView
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        inputAccessoryView = bracketAccessoryView
    }

    func setBracketAccessoryVisible(_ visible: Bool) {
        guard isBracketAccessoryVisible != visible else { return }
        isBracketAccessoryVisible = visible
        inputAccessoryView = visible ? bracketAccessoryView : nil
        if isFirstResponder {
            reloadInputViews()
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return isEditable && (UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs)
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        // Force plain-text fallback so simulator/device paste remains reliable
        // even when the pasteboard advertises rich content first.
        if let raw = UIPasteboard.general.string, !raw.isEmpty {
            let sanitized = EditorTextSanitizer.sanitize(raw)
            if let selection = selectedTextRange {
                replace(selection, withText: sanitized)
            } else {
                insertText(sanitized)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.selectedRange = NSRange(location: 0, length: 0)
                self.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
            return
        }
        super.paste(sender)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.selectedRange = NSRange(location: 0, length: 0)
            self.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }

    @objc private func insertBracketToken(_ sender: UIButton) {
        guard isEditable, let token = sender.accessibilityIdentifier else { return }
        becomeFirstResponder()

        let selection = selectedRange
        if let pair = pairForToken(token) {
            textStorage.replaceCharacters(in: selection, with: pair.open + pair.close)
            selectedRange = NSRange(location: selection.location + pair.open.count, length: 0)
            delegate?.textViewDidChange?(self)
            return
        }

        textStorage.replaceCharacters(in: selection, with: token)
        selectedRange = NSRange(location: selection.location + token.count, length: 0)
        delegate?.textViewDidChange?(self)
    }

    private func pairForToken(_ token: String) -> (open: String, close: String)? {
        switch token {
        case "()": return ("(", ")")
        case "{}": return ("{", "}")
        case "[]": return ("[", "]")
        case "\"\"": return ("\"", "\"")
        case "''": return ("'", "'")
        default: return nil
        }
    }
}

final class LineNumberGutterView: UIView {
    weak var textView: UITextView?
    var lineStarts: [Int] = [0]
    var font: UIFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    var textColor: UIColor = .secondaryLabel

    override func draw(_ rect: CGRect) {
        guard let textView else { return }
        let layoutManager = textView.layoutManager
        guard !lineStarts.isEmpty else { return }

        let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size).insetBy(dx: 0, dy: -80)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textView.textContainer)
        if glyphRange.length == 0 { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let rightPadding: CGFloat = 6
        let textContainerTop = textView.textContainerInset.top
        let contentOffsetY = textView.contentOffset.y

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, glyphRange, _ in
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            let lineNumber = self.lineNumberForCharacterIndex(charIndex) + 1
            let drawY = usedRect.minY + textContainerTop - contentOffsetY
            let drawRect = CGRect(x: 0, y: drawY, width: self.bounds.width - rightPadding, height: usedRect.height)
            NSString(string: String(lineNumber)).draw(in: drawRect, withAttributes: attrs)
        }
    }

    private func lineNumberForCharacterIndex(_ index: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= index {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return max(0, min(high, lineStarts.count - 1))
    }
}

final class LineNumberedTextViewContainer: UIView {
    let lineNumberView = LineNumberGutterView()
    let textView = EditorInputTextView()
    private var lineNumberWidthConstraint: NSLayoutConstraint?
    private var cachedLineStarts: [Int] = [0]
    private var cachedFontPointSize: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    private func configureViews() {
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        lineNumberView.textView = textView

        lineNumberView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.65)
        lineNumberView.textColor = .secondaryLabel
        lineNumberView.isUserInteractionEnabled = false

        textView.contentInsetAdjustmentBehavior = .never
        textView.keyboardDismissMode = .onDrag
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.6)

        addSubview(lineNumberView)
        addSubview(divider)
        addSubview(textView)

        NSLayoutConstraint.activate([
            lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberView.topAnchor.constraint(equalTo: topAnchor),
            lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            textView.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let widthConstraint = lineNumberView.widthAnchor.constraint(equalToConstant: 46)
        widthConstraint.isActive = true
        lineNumberWidthConstraint = widthConstraint
    }

    func updateLineNumbers(for text: String, fontSize: CGFloat) {
        let numberFont = UIFont.monospacedDigitSystemFont(ofSize: max(11, fontSize - 1), weight: .regular)
        if abs(cachedFontPointSize - numberFont.pointSize) > 0.01 {
            lineNumberView.font = numberFont
            cachedFontPointSize = numberFont.pointSize
        }
        let lineStarts = lineStartOffsets(for: text)
        if lineStarts != cachedLineStarts {
            cachedLineStarts = lineStarts
            lineNumberView.lineStarts = lineStarts
        }
        let lineCount = max(1, lineStarts.count)
        let digits = max(2, String(lineCount).count)
        let glyphWidth = NSString(string: "8").size(withAttributes: [.font: numberFont]).width
        let targetWidth = ceil((glyphWidth * CGFloat(digits)) + 14)
        if abs((lineNumberWidthConstraint?.constant ?? 46) - targetWidth) > 0.5 {
            lineNumberWidthConstraint?.constant = targetWidth
            setNeedsLayout()
            layoutIfNeeded()
        }
        lineNumberView.setNeedsDisplay()
    }

    private func lineStartOffsets(for text: String) -> [Int] {
        var starts: [Int] = [0]
        let utf16 = text.utf16
        starts.reserveCapacity(max(32, utf16.count / 24))
        var idx = 0
        for codeUnit in utf16 {
            idx += 1
            if codeUnit == 10 { // '\n'
                starts.append(idx)
            }
        }
        return starts
    }
}

struct CustomTextEditor: UIViewRepresentable {
    @Binding var text: String
    let documentID: UUID?
    let language: String
    let colorScheme: ColorScheme
    let fontSize: CGFloat
    @Binding var isLineWrapEnabled: Bool
    let isLargeFileMode: Bool
    let translucentBackgroundEnabled: Bool
    let showKeyboardAccessoryBar: Bool
    let showLineNumbers: Bool
    let showInvisibleCharacters: Bool
    let highlightCurrentLine: Bool
    let highlightMatchingBrackets: Bool
    let showScopeGuides: Bool
    let highlightScopeBackground: Bool
    let indentStyle: String
    let indentWidth: Int
    let autoIndentEnabled: Bool
    let autoCloseBracketsEnabled: Bool
    let highlightRefreshToken: Int
    let isTabLoadingContent: Bool
    let onTextMutation: ((EditorTextMutation) -> Void)?

    private var fontName: String {
        UserDefaults.standard.string(forKey: "SettingsEditorFontName") ?? ""
    }

    private var useSystemFont: Bool {
        UserDefaults.standard.bool(forKey: "SettingsUseSystemFont")
    }

    private var lineHeightMultiple: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "SettingsLineHeight")
        return CGFloat(stored > 0 ? stored : 1.0)
    }

    private func resolvedUIFont(size: CGFloat? = nil) -> UIFont {
        let targetSize = size ?? fontSize
        if useSystemFont {
            return UIFont.systemFont(ofSize: targetSize)
        }
        if let named = UIFont(name: fontName, size: targetSize) {
            return named
        }
        return UIFont.monospacedSystemFont(ofSize: targetSize, weight: .regular)
    }

    func makeUIView(context: Context) -> LineNumberedTextViewContainer {
        let container = LineNumberedTextViewContainer()
        let textView = container.textView
        let theme = currentEditorTheme(colorScheme: colorScheme)

        textView.delegate = context.coordinator
        let initialFont = resolvedUIFont()
        textView.font = initialFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = max(0.9, lineHeightMultiple)
        let baseColor = UIColor(theme.text)
        var typing = textView.typingAttributes
        typing[.paragraphStyle] = paragraphStyle
        typing[.foregroundColor] = baseColor
        typing[.font] = textView.font ?? initialFont
        textView.typingAttributes = typing
        textView.text = text
        if text.count <= 200_000 {
            textView.textStorage.beginEditing()
            textView.textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: textView.textStorage.length))
            textView.textStorage.endEditing()
        }
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.backgroundColor = translucentBackgroundEnabled ? .clear : .systemBackground
        textView.setBracketAccessoryVisible(showKeyboardAccessoryBar)
        let shouldWrapText = isLineWrapEnabled && !isLargeFileMode
        let desiredLineBreakMode: NSLineBreakMode = shouldWrapText ? .byWordWrapping : .byClipping
        if textView.textContainer.lineBreakMode != desiredLineBreakMode
            || textView.textContainer.widthTracksTextView != shouldWrapText {
            let priorOffset = textView.contentOffset
            textView.textContainer.lineBreakMode = desiredLineBreakMode
            textView.textContainer.widthTracksTextView = shouldWrapText
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            let inset = textView.adjustedContentInset
            let minY = -inset.top
            let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)
            let clampedY = min(max(priorOffset.y, minY), maxY)
            textView.setContentOffset(CGPoint(x: priorOffset.x, y: clampedY), animated: false)
        }

        if isLargeFileMode || !showLineNumbers {
            container.lineNumberView.isHidden = true
        } else {
            container.lineNumberView.isHidden = false
            container.updateLineNumbers(for: text, fontSize: fontSize)
        }
        context.coordinator.container = container
        context.coordinator.textView = textView
        context.coordinator.scheduleHighlightIfNeeded(currentText: text, immediate: true)
        return container
    }

    func updateUIView(_ uiView: LineNumberedTextViewContainer, context: Context) {
        let textView = uiView.textView
        context.coordinator.parent = self
        let didSwitchDocument = context.coordinator.lastDocumentID != documentID
        let didFinishTabLoad = (context.coordinator.lastTabLoadingContent == true) && !isTabLoadingContent
        if didSwitchDocument {
            context.coordinator.lastDocumentID = documentID
            context.coordinator.cancelPendingBindingSync()
            context.coordinator.clearPendingTextMutation()
            context.coordinator.invalidateHighlightCache()
        }
        context.coordinator.lastTabLoadingContent = isTabLoadingContent
        if textView.text != text {
            let shouldPreferEditorBuffer = textView.isFirstResponder && !isTabLoadingContent && !didSwitchDocument && !didFinishTabLoad
            if shouldPreferEditorBuffer {
                context.coordinator.syncBindingTextImmediately(textView.text)
            } else {
                context.coordinator.cancelPendingBindingSync()
                let priorSelection = textView.selectedRange
                let priorOffset = textView.contentOffset
                textView.text = text
                let length = (textView.text as NSString).length
                let clampedLocation = min(priorSelection.location, length)
                let clampedLength = min(priorSelection.length, max(0, length - clampedLocation))
                textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
                textView.setContentOffset(priorOffset, animated: false)
            }
        }
        let targetFont = resolvedUIFont()
        if textView.font?.fontName != targetFont.fontName || textView.font?.pointSize != targetFont.pointSize {
            textView.font = targetFont
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = max(0.9, lineHeightMultiple)
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        if context.coordinator.lastLineHeight != lineHeightMultiple {
            let len = textView.textStorage.length
            if len > 0 && len <= 200_000 {
                textView.textStorage.beginEditing()
                textView.textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: len))
                textView.textStorage.endEditing()
            }
            context.coordinator.lastLineHeight = lineHeightMultiple
        }
        let theme = currentEditorTheme(colorScheme: colorScheme)
        let baseColor = UIColor(theme.text)
        textView.tintColor = UIColor(theme.cursor)
        textView.backgroundColor = translucentBackgroundEnabled ? .clear : UIColor(theme.background)
        textView.setBracketAccessoryVisible(showKeyboardAccessoryBar)
        let shouldWrapText = isLineWrapEnabled && !isLargeFileMode
        let desiredLineBreakMode: NSLineBreakMode = shouldWrapText ? .byWordWrapping : .byClipping
        if textView.textContainer.lineBreakMode != desiredLineBreakMode
            || textView.textContainer.widthTracksTextView != shouldWrapText {
            let priorOffset = textView.contentOffset
            textView.textContainer.lineBreakMode = desiredLineBreakMode
            textView.textContainer.widthTracksTextView = shouldWrapText
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            let inset = textView.adjustedContentInset
            let minY = -inset.top
            let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)
            let clampedY = min(max(priorOffset.y, minY), maxY)
            textView.setContentOffset(CGPoint(x: priorOffset.x, y: clampedY), animated: false)
        }
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.keyboardDismissMode = .onDrag
        textView.typingAttributes[.foregroundColor] = baseColor
        if isLargeFileMode || !showLineNumbers {
            uiView.lineNumberView.isHidden = true
        } else {
            uiView.lineNumberView.isHidden = false
            uiView.updateLineNumbers(for: text, fontSize: fontSize)
        }
        context.coordinator.syncLineNumberScroll()
        context.coordinator.scheduleHighlightIfNeeded(currentText: text)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CustomTextEditor
        weak var container: LineNumberedTextViewContainer?
        weak var textView: EditorInputTextView?
        private let highlightQueue = DispatchQueue(label: "NeonVision.iOS.SyntaxHighlight", qos: .userInitiated)
        private var pendingHighlight: DispatchWorkItem?
        private var pendingBindingSync: DispatchWorkItem?
        private var pendingTextMutation: (range: NSRange, replacement: String)?
        private var lastHighlightedText: String = ""
        private var lastLanguage: String?
        private var lastColorScheme: ColorScheme?
        var lastLineHeight: CGFloat?
        private var lastHighlightToken: Int = 0
        private var lastSelectionLocation: Int = -1
        private var lastTranslucencyEnabled: Bool?
        private var isApplyingHighlight = false
        private var highlightGeneration: Int = 0
        var lastDocumentID: UUID?
        var lastTabLoadingContent: Bool?
        var hasPendingBindingSync: Bool { pendingBindingSync != nil }

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(moveToLine(_:)), name: .moveCursorToLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(moveToRange(_:)), name: .moveCursorToRange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(updateKeyboardAccessoryVisibility(_:)), name: .keyboardAccessoryBarVisibilityChanged, object: nil)
        }

        deinit {
            pendingBindingSync?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        private func shouldRenderLineNumbers() -> Bool {
            guard let lineView = container?.lineNumberView else { return false }
            return parent.showLineNumbers && !parent.isLargeFileMode && !lineView.isHidden
        }

        func invalidateHighlightCache() {
            lastHighlightedText = ""
            lastLanguage = nil
            lastColorScheme = nil
            lastLineHeight = nil
            lastHighlightToken = 0
            lastSelectionLocation = -1
            lastTranslucencyEnabled = nil
        }

        private func syncBindingText(_ text: String, immediate: Bool = false) {
            if parent.isTabLoadingContent {
                return
            }
            pendingBindingSync?.cancel()
            pendingBindingSync = nil
            if immediate || (text as NSString).length < EditorRuntimeLimits.bindingDebounceUTF16Length {
                parent.text = text
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingBindingSync = nil
                if self.textView?.text == text {
                    self.parent.text = text
                }
            }
            pendingBindingSync = work
            DispatchQueue.main.asyncAfter(deadline: .now() + EditorRuntimeLimits.bindingDebounceDelay, execute: work)
        }

        func cancelPendingBindingSync() {
            pendingBindingSync?.cancel()
            pendingBindingSync = nil
        }

        func clearPendingTextMutation() {
            pendingTextMutation = nil
        }

        func syncBindingTextImmediately(_ text: String) {
            syncBindingText(text, immediate: true)
        }

        private func setPendingTextMutation(range: NSRange, replacement: String) {
            guard !parent.isTabLoadingContent, parent.documentID != nil else {
                pendingTextMutation = nil
                return
            }
            pendingTextMutation = (range: range, replacement: replacement)
        }

        private func applyPendingTextMutationIfPossible() -> Bool {
            defer { pendingTextMutation = nil }
            guard !parent.isTabLoadingContent,
                  let pendingTextMutation,
                  let documentID = parent.documentID,
                  let onTextMutation = parent.onTextMutation else {
                return false
            }
            onTextMutation(
                EditorTextMutation(
                    documentID: documentID,
                    range: pendingTextMutation.range,
                    replacement: pendingTextMutation.replacement
                )
            )
            return true
        }

        @objc private func updateKeyboardAccessoryVisibility(_ notification: Notification) {
            guard let textView else { return }
            let isVisible: Bool
            if let explicit = notification.object as? Bool {
                isVisible = explicit
            } else {
                isVisible = UserDefaults.standard.object(forKey: "SettingsShowKeyboardAccessoryBarIOS") as? Bool ?? false
            }
            textView.setBracketAccessoryVisible(isVisible)
            if isVisible && !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            textView.reloadInputViews()
        }

        @objc private func moveToRange(_ notification: Notification) {
            guard let textView else { return }
            guard let location = notification.userInfo?[EditorCommandUserInfo.rangeLocation] as? Int,
                  let length = notification.userInfo?[EditorCommandUserInfo.rangeLength] as? Int else { return }
            let textLength = (textView.text as NSString?)?.length ?? 0
            guard location >= 0, length >= 0, location + length <= textLength else { return }
            let range = NSRange(location: location, length: length)
            textView.becomeFirstResponder()
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
        }

        @objc private func moveToLine(_ notification: Notification) {
            guard let lineOneBased = notification.object as? Int, lineOneBased > 0 else { return }
            guard let textView else { return }
            let nsText = (textView.text ?? "") as NSString
            guard nsText.length > 0 else { return }

            let lineFragments = (textView.text ?? "").components(separatedBy: .newlines)
            let clampedLineIndex = max(1, min(lineOneBased, lineFragments.count)) - 1
            var location = 0
            if clampedLineIndex > 0 {
                for i in 0..<clampedLineIndex {
                    location += (lineFragments[i] as NSString).length + 1
                }
            }
            location = max(0, min(location, nsText.length))
            let target = NSRange(location: location, length: 0)
            textView.becomeFirstResponder()
            textView.selectedRange = target
            textView.scrollRangeToVisible(target)
            scheduleHighlightIfNeeded(currentText: textView.text ?? "", immediate: true)
        }

        func scheduleHighlightIfNeeded(currentText: String? = nil, immediate: Bool = false) {
            guard let textView else { return }
            let text = currentText ?? textView.text ?? ""
            let lang = parent.language
            let scheme = parent.colorScheme
            let lineHeight = parent.lineHeightMultiple
            let token = parent.highlightRefreshToken
            let translucencyEnabled = parent.translucentBackgroundEnabled
            let selectionLocation = textView.selectedRange.location

            if parent.isLargeFileMode {
                lastHighlightedText = text
                lastLanguage = lang
                lastColorScheme = scheme
                lastLineHeight = lineHeight
                lastHighlightToken = token
                lastSelectionLocation = selectionLocation
                lastTranslucencyEnabled = translucencyEnabled
                return
            }
            let textLength = (text as NSString).length
            if textLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length {
                lastHighlightedText = text
                lastLanguage = lang
                lastColorScheme = scheme
                lastLineHeight = lineHeight
                lastHighlightToken = token
                lastSelectionLocation = selectionLocation
                lastTranslucencyEnabled = translucencyEnabled
                return
            }

            if text == lastHighlightedText &&
                lang == lastLanguage &&
                scheme == lastColorScheme &&
                lineHeight == lastLineHeight &&
                lastHighlightToken == token &&
                lastSelectionLocation == selectionLocation &&
                lastTranslucencyEnabled == translucencyEnabled {
                return
            }

            let styleStateUnchanged = lang == lastLanguage &&
                scheme == lastColorScheme &&
                lineHeight == lastLineHeight &&
                lastHighlightToken == token &&
                lastTranslucencyEnabled == translucencyEnabled
            let selectionOnlyChange = text == lastHighlightedText &&
                styleStateUnchanged &&
                lastSelectionLocation != selectionLocation
            if selectionOnlyChange && parent.isLineWrapEnabled {
                pendingHighlight?.cancel()
                pendingHighlight = nil
                lastSelectionLocation = selectionLocation
                return
            }
            if selectionOnlyChange && textLength >= EditorRuntimeLimits.cursorRehighlightMaxUTF16Length {
                lastSelectionLocation = selectionLocation
                return
            }

            pendingHighlight?.cancel()
            highlightGeneration &+= 1
            let generation = highlightGeneration
            let applyRange = preferredHighlightRange(textView: textView, text: text as NSString, immediate: immediate)
            let work = DispatchWorkItem { [weak self] in
                self?.rehighlight(
                    text: text,
                    language: lang,
                    colorScheme: scheme,
                    token: token,
                    generation: generation,
                    applyRange: applyRange
                )
            }
            pendingHighlight = work
            let allowImmediate = textLength < EditorRuntimeLimits.nonImmediateHighlightMaxUTF16Length
            if (immediate || lastHighlightedText.isEmpty || lastHighlightToken != token) && allowImmediate {
                highlightQueue.async(execute: work)
            } else {
                let delay: TimeInterval
                if text.utf16.count >= 120_000 {
                    delay = 0.24
                } else if text.utf16.count >= 80_000 {
                    delay = 0.18
                } else {
                    delay = 0.1
                }
                highlightQueue.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }

        private func expandedRange(around range: NSRange, in text: NSString, maxUTF16Padding: Int = 8000) -> NSRange {
            let start = max(0, range.location - maxUTF16Padding)
            let end = min(text.length, NSMaxRange(range) + maxUTF16Padding)
            let startLine = text.lineRange(for: NSRange(location: start, length: 0)).location
            let endAnchor = max(startLine, min(text.length - 1, max(0, end - 1)))
            let endLine = NSMaxRange(text.lineRange(for: NSRange(location: endAnchor, length: 0)))
            return NSRange(location: startLine, length: max(0, endLine - startLine))
        }

        private func preferredHighlightRange(
            textView: UITextView,
            text: NSString,
            immediate: Bool
        ) -> NSRange {
            let fullRange = NSRange(location: 0, length: text.length)
            // Keep syntax matching focused on visible content for very large buffers.
            guard text.length >= 100_000 else { return fullRange }
            let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size).insetBy(dx: 0, dy: -80)
            let glyphRange = textView.layoutManager.glyphRange(forBoundingRect: visibleRect, in: textView.textContainer)
            let charRange = textView.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.length > 0 else { return fullRange }
            return expandedRange(around: charRange, in: text, maxUTF16Padding: 12_000)
        }

        private func rehighlight(
            text: String,
            language: String,
            colorScheme: ColorScheme,
            token: Int,
            generation: Int,
            applyRange: NSRange
        ) {
            let interval = syntaxHighlightSignposter.beginInterval("rehighlight_ios")
            defer { syntaxHighlightSignposter.endInterval("rehighlight_ios", interval) }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let theme = currentEditorTheme(colorScheme: colorScheme)
            let baseColor = UIColor(theme.text)
            let baseFont: UIFont
            if parent.useSystemFont {
                baseFont = UIFont.systemFont(ofSize: parent.fontSize)
            } else if let named = UIFont(name: parent.fontName, size: parent.fontSize) {
                baseFont = named
            } else {
                baseFont = UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            }

            let colors = SyntaxColors(
                keyword: theme.syntax.keyword,
                string: theme.syntax.string,
                number: theme.syntax.number,
                comment: theme.syntax.comment,
                attribute: theme.syntax.attribute,
                variable: theme.syntax.variable,
                def: theme.syntax.def,
                property: theme.syntax.property,
                meta: theme.syntax.meta,
                tag: theme.syntax.tag,
                atom: theme.syntax.atom,
                builtin: theme.syntax.builtin,
                type: theme.syntax.type
            )
            let syntaxProfile: SyntaxPatternProfile = {
                let lower = language.lowercased()
                if lower == "html" && nsText.length >= EditorRuntimeLimits.htmlFastProfileUTF16Length {
                    return .htmlFast
                }
                if lower == "csv" && nsText.length >= EditorRuntimeLimits.csvFastProfileUTF16Length {
                    return .csvFast
                }
                return .full
            }()
            let patterns = getSyntaxPatterns(for: language, colors: colors, profile: syntaxProfile)
            var coloredRanges: [(NSRange, UIColor)] = []

            if let fastRanges = fastSyntaxColorRanges(
                language: language,
                profile: syntaxProfile,
                text: nsText,
                in: applyRange,
                colors: colors
            ) {
                for (range, color) in fastRanges {
                    guard isValidRange(range, utf16Length: fullRange.length) else { continue }
                    coloredRanges.append((range, UIColor(color)))
                }
            } else {
                for (pattern, color) in patterns {
                    guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                    let matches = regex.matches(in: text, range: applyRange)
                    let uiColor = UIColor(color)
                    for match in matches {
                        guard isValidRange(match.range, utf16Length: fullRange.length) else { continue }
                        coloredRanges.append((match.range, uiColor))
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView else { return }
                guard generation == self.highlightGeneration else { return }
                guard textView.text == text else { return }
                let selectedRange = textView.selectedRange
                let priorOffset = textView.contentOffset
                let wasFirstResponder = textView.isFirstResponder
                self.isApplyingHighlight = true
                textView.textStorage.beginEditing()
                textView.textStorage.removeAttribute(.foregroundColor, range: applyRange)
                textView.textStorage.removeAttribute(.backgroundColor, range: applyRange)
                textView.textStorage.removeAttribute(.underlineStyle, range: applyRange)
                textView.textStorage.addAttribute(.foregroundColor, value: baseColor, range: applyRange)
                textView.textStorage.addAttribute(.font, value: baseFont, range: applyRange)
                for (range, color) in coloredRanges {
                    textView.textStorage.addAttribute(.foregroundColor, value: color, range: range)
                }
                let wantsBracketTokens = self.parent.highlightMatchingBrackets
                let wantsScopeBackground = self.parent.highlightScopeBackground
                let wantsScopeGuides = self.parent.showScopeGuides && !self.parent.isLineWrapEnabled && self.parent.language.lowercased() != "swift"
                let needsScopeComputation = (wantsBracketTokens || wantsScopeBackground || wantsScopeGuides)
                    && nsText.length < EditorRuntimeLimits.scopeComputationMaxUTF16Length
                let bracketMatch = needsScopeComputation ? computeBracketScopeMatch(text: text, caretLocation: selectedRange.location) : nil
                let indentationMatch: IndentationScopeMatch? = {
                    guard needsScopeComputation, supportsIndentationScopes(language: self.parent.language) else { return nil }
                    return computeIndentationScopeMatch(text: text, caretLocation: selectedRange.location)
                }()

                if wantsBracketTokens, let match = bracketMatch {
                    let textLength = fullRange.length
                    if isValidRange(match.openRange, utf16Length: textLength) {
                        textView.textStorage.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: match.openRange)
                        textView.textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.openRange)
                        textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemOrange.withAlphaComponent(0.22), range: match.openRange)
                    }
                    if isValidRange(match.closeRange, utf16Length: textLength) {
                        textView.textStorage.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: match.closeRange)
                        textView.textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.closeRange)
                        textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemOrange.withAlphaComponent(0.22), range: match.closeRange)
                    }
                }

                if wantsScopeBackground || wantsScopeGuides {
                    let textLength = fullRange.length
                    let scopeRange = bracketMatch?.scopeRange ?? indentationMatch?.scopeRange
                    let guideRanges = bracketMatch?.guideMarkerRanges ?? indentationMatch?.guideMarkerRanges ?? []

                    if wantsScopeBackground, let scope = scopeRange, isValidRange(scope, utf16Length: textLength) {
                        textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemOrange.withAlphaComponent(0.18), range: scope)
                    }
                    if wantsScopeGuides {
                        for marker in guideRanges {
                            if isValidRange(marker, utf16Length: textLength) {
                                textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemBlue.withAlphaComponent(0.36), range: marker)
                            }
                        }
                    }
                }
                if self.parent.highlightCurrentLine {
                    let ns = text as NSString
                    let lineRange = ns.lineRange(for: selectedRange)
                    textView.textStorage.addAttribute(.backgroundColor, value: UIColor.secondarySystemFill, range: lineRange)
                }
                textView.textStorage.endEditing()
                textView.selectedRange = selectedRange
                if wasFirstResponder {
                    textView.setContentOffset(priorOffset, animated: false)
                }
                textView.typingAttributes = [
                    .foregroundColor: baseColor,
                    .font: baseFont
                ]
                self.isApplyingHighlight = false
                self.lastHighlightedText = text
                self.lastLanguage = language
                self.lastColorScheme = colorScheme
                self.lastLineHeight = self.parent.lineHeightMultiple
                self.lastHighlightToken = token
                self.lastSelectionLocation = selectedRange.location
                self.lastTranslucencyEnabled = self.parent.translucentBackgroundEnabled
                if self.shouldRenderLineNumbers() {
                    self.container?.updateLineNumbers(for: text, fontSize: self.parent.fontSize)
                    self.syncLineNumberScroll()
                }
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            let didApplyIncrementalMutation = applyPendingTextMutationIfPossible()
            if !didApplyIncrementalMutation {
                syncBindingText(textView.text)
            }
            if shouldRenderLineNumbers() {
                container?.updateLineNumbers(for: textView.text, fontSize: parent.fontSize)
            }
            scheduleHighlightIfNeeded(currentText: textView.text)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            let nsLength = (textView.text as NSString?)?.length ?? 0
            let immediateHighlight = nsLength < 200_000
            scheduleHighlightIfNeeded(currentText: textView.text, immediate: immediateHighlight)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\t" {
                if let expansion = EmmetExpander.expansionIfPossible(
                    in: textView.text ?? "",
                    cursorUTF16Location: range.location,
                    language: parent.language
                ) {
                    setPendingTextMutation(range: expansion.range, replacement: expansion.expansion)
                    textView.textStorage.replaceCharacters(in: expansion.range, with: expansion.expansion)
                    let caretLocation = expansion.range.location + expansion.caretOffset
                    textView.selectedRange = NSRange(location: caretLocation, length: 0)
                    textViewDidChange(textView)
                    return false
                }
                let insertion: String
                if parent.indentStyle == "tabs" {
                    insertion = "\t"
                } else {
                    insertion = String(repeating: " ", count: max(1, parent.indentWidth))
                }
                setPendingTextMutation(range: range, replacement: insertion)
                textView.textStorage.replaceCharacters(in: range, with: insertion)
                textView.selectedRange = NSRange(location: range.location + insertion.count, length: 0)
                textViewDidChange(textView)
                return false
            }

            if text == "\n", parent.autoIndentEnabled {
                let ns = textView.text as NSString
                let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let currentLine = ns.substring(with: NSRange(
                    location: lineRange.location,
                    length: max(0, range.location - lineRange.location)
                ))
                let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
                let normalized = normalizedIndentation(String(indent))
                let replacement = "\n" + normalized
                setPendingTextMutation(range: range, replacement: replacement)
                textView.textStorage.replaceCharacters(in: range, with: replacement)
                textView.selectedRange = NSRange(location: range.location + replacement.count, length: 0)
                textViewDidChange(textView)
                return false
            }

            if parent.autoCloseBracketsEnabled, text.count == 1 {
                let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"]
                if let closing = pairs[text] {
                    let insertion = text + closing
                    setPendingTextMutation(range: range, replacement: insertion)
                    textView.textStorage.replaceCharacters(in: range, with: insertion)
                    textView.selectedRange = NSRange(location: range.location + 1, length: 0)
                    textViewDidChange(textView)
                    return false
                }
            }

            setPendingTextMutation(range: range, replacement: text)
            return true
        }

        private func normalizedIndentation(_ indent: String) -> String {
            let width = max(1, parent.indentWidth)
            switch parent.indentStyle {
            case "tabs":
                let spacesCount = indent.filter { $0 == " " }.count
                let tabsCount = indent.filter { $0 == "\t" }.count
                let totalSpaces = spacesCount + (tabsCount * width)
                let tabs = String(repeating: "\t", count: totalSpaces / width)
                let leftover = String(repeating: " ", count: totalSpaces % width)
                return tabs + leftover
            default:
                let tabsCount = indent.filter { $0 == "\t" }.count
                let spacesCount = indent.filter { $0 == " " }.count
                let totalSpaces = spacesCount + (tabsCount * width)
                return String(repeating: " ", count: totalSpaces)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncLineNumberScroll()
        }

        func syncLineNumberScroll() {
            guard shouldRenderLineNumbers() else { return }
            container?.lineNumberView.setNeedsDisplay()
        }
    }
}
#endif
