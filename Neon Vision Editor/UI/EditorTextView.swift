import SwiftUI
import Foundation
import OSLog

nonisolated let syntaxHighlightSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "SyntaxHighlight")

#if os(macOS)
extension Notification.Name {
    static let editorPointerInteraction = Notification.Name("NeonEditorPointerInteraction")
}
#endif

enum EditorRuntimeLimits {
    // Above this, keep editing responsive by skipping regex-heavy syntax passes.
    static let syntaxMinimalUTF16Length = 1_200_000
    static let ultraLargeResponsiveSyntaxUTF16Length = 400_000
    static let htmlFastProfileUTF16Length = 250_000
    static let csvFastProfileUTF16Length = 120_000
    static let jsonFastProfileUTF16Length = 120_000
    static let largeFileJSONVisiblePaddingUTF16 = 2_400
    static let largeFileJSONIncrementalPaddingUTF16 = 800
    nonisolated static let largeFileJSONTokenBudgetSeconds = 0.0035
    static let csvFastProfileLongLineUTF16 = 4_000
    static let csvFastProfileScanLimitUTF16 = 120_000
    static let scopeComputationMaxUTF16Length = 300_000
    static let cursorRehighlightMaxUTF16Length = 220_000
    static let nonImmediateHighlightMaxUTF16Length = 220_000
    static let bindingDebounceUTF16Length = 250_000
    static let bindingDebounceDelay: TimeInterval = 0.18
    static let bracketScopeNearestFallbackWindowUTF16 = 8_000
}

func shouldUseCSVFastProfile(_ nsText: NSString) -> Bool {
    if nsText.length >= EditorRuntimeLimits.csvFastProfileUTF16Length {
        return true
    }
    let scanLimit = min(nsText.length, EditorRuntimeLimits.csvFastProfileScanLimitUTF16)
    guard scanLimit > 0 else { return false }
    var currentLineLength = 0
    for idx in 0..<scanLimit {
        let codeUnit = nsText.character(at: idx)
        if codeUnit == 10 { // '\n'
            currentLineLength = 0
            continue
        }
        currentLineLength += 1
        if currentLineLength >= EditorRuntimeLimits.csvFastProfileLongLineUTF16 {
            return true
        }
    }
    return false
}

nonisolated func isJSONLikeLanguage(_ language: String) -> Bool {
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "json", "jsonc", "json5", "ipynb":
        return true
    default:
        return false
    }
}

func syntaxProfile(for language: String, text: NSString) -> SyntaxPatternProfile {
    let lower = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if lower == "html" && text.length >= EditorRuntimeLimits.htmlFastProfileUTF16Length {
        return .htmlFast
    }
    if lower == "csv" && shouldUseCSVFastProfile(text) {
        return .csvFast
    }
    if isJSONLikeLanguage(lower) && text.length >= EditorRuntimeLimits.jsonFastProfileUTF16Length {
        return .jsonFast
    }
    return .full
}

enum SyntaxFontEmphasis: Sendable {
    case keyword
    case comment
}

#if os(macOS)
func fontWithSymbolicTrait(_ font: NSFont, trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
    let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
    guard
          let adjustedFont = NSFont(descriptor: descriptor, size: font.pointSize) else {
        return font
    }
    return adjustedFont
}
#else
func fontWithSymbolicTrait(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
    guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)) else {
        return font
    }
    return UIFont(descriptor: descriptor, size: font.pointSize)
}
#endif

func supportsResponsiveLargeFileHighlight(language: String) -> Bool {
    isJSONLikeLanguage(language) &&
        currentLargeFileSyntaxHighlightMode() == .minimal &&
        currentLargeFileOpenMode() != .plainText
}

func supportsResponsiveLargeFileHighlight(language: String, textLength: Int) -> Bool {
    textLength <= EditorRuntimeLimits.ultraLargeResponsiveSyntaxUTF16Length &&
        supportsResponsiveLargeFileHighlight(language: language)
}

enum LargeFileSyntaxHighlightMode: String {
    case off
    case minimal
}

enum LargeFileOpenMode: String {
    case standard
    case deferred
    case plainText
}

func currentLargeFileSyntaxHighlightMode() -> LargeFileSyntaxHighlightMode {
    let raw = UserDefaults.standard.string(forKey: "SettingsLargeFileSyntaxHighlighting") ?? "minimal"
    return LargeFileSyntaxHighlightMode(rawValue: raw) ?? .minimal
}

func currentLargeFileOpenMode() -> LargeFileOpenMode {
    let raw = UserDefaults.standard.string(forKey: "SettingsLargeFileOpenMode") ?? "deferred"
    return LargeFileOpenMode(rawValue: raw) ?? .deferred
}

func shouldUseChunkedLargeFileInstall(isLargeFileMode: Bool, textLength: Int) -> Bool {
    guard isLargeFileMode else { return false }
    guard currentLargeFileOpenMode() != .standard else { return false }
    return textLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length
}

nonisolated func isJSONWhitespace(_ codeUnit: unichar) -> Bool {
    codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13
}

nonisolated func isJSONDigit(_ codeUnit: unichar) -> Bool {
    codeUnit >= 48 && codeUnit <= 57
}

nonisolated func isJSONLetter(_ codeUnit: unichar) -> Bool {
    (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122)
}

nonisolated func isJSONLiteral(_ text: NSString, range: NSRange, literal: [unichar]) -> Bool {
    guard range.length == literal.count else { return false }
    for offset in 0..<literal.count where text.character(at: range.location + offset) != literal[offset] {
        return false
    }
    return true
}

struct EditorTextMutation {
    let documentID: UUID
    let range: NSRange
    let replacement: String
}

enum LargeFileInstallRuntime {
    static let chunkUTF16 = 262_144
}

#if os(macOS)
@MainActor
func replaceTextPreservingSelectionAndFocus(
    _ textView: NSTextView,
    with newText: String,
    preserveViewport: Bool = true,
    preserveHorizontalOffset: Bool = true
) {
    let previousSelection = textView.selectedRange()
    let hadFocus = (textView.window?.firstResponder as? NSTextView) === textView
    let priorOrigin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
    let undoWasEnabled = textView.undoManager?.isUndoRegistrationEnabled ?? false
    if undoWasEnabled {
        textView.undoManager?.disableUndoRegistration()
    }
    defer {
        if undoWasEnabled {
            textView.undoManager?.enableUndoRegistration()
        }
    }
    textView.string = newText
    let length = (newText as NSString).length
    let safeLocation = min(max(0, previousSelection.location), length)
    let safeLength = min(max(0, previousSelection.length), max(0, length - safeLocation))
    textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
    if let clipView = textView.enclosingScrollView?.contentView {
        let targetOrigin: CGPoint
        if preserveViewport {
            targetOrigin = CGPoint(
                x: preserveHorizontalOffset ? priorOrigin.x : 0,
                y: priorOrigin.y
            )
        } else {
            targetOrigin = .zero
        }
        clipView.scroll(to: targetOrigin)
        textView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }
    if hadFocus {
        textView.window?.makeFirstResponder(textView)
    }
}
#endif

enum EmmetExpander {
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
    static let editorSelectionDidChange = Notification.Name("editorSelectionDidChange")
    static let editorRequestCodeSnapshotFromSelection = Notification.Name("editorRequestCodeSnapshotFromSelection")
}

///MARK: - Scope Match Models
// Bracket-based scope data used for highlighting and guide rendering.
struct BracketScopeMatch {
    let openRange: NSRange
    let closeRange: NSRange
    let scopeRange: NSRange?
    let guideMarkerRanges: [NSRange]
}

// Indentation-based scope data used for Python/YAML style highlighting.
struct IndentationScopeMatch {
    let scopeRange: NSRange
    let guideMarkerRanges: [NSRange]
}

///MARK: - Bracket/Indent Scope Helpers
func matchingOpeningBracket(for closing: unichar) -> unichar? {
    switch UnicodeScalar(closing) {
    case "}": return unichar(UnicodeScalar("{").value)
    case "]": return unichar(UnicodeScalar("[").value)
    case ")": return unichar(UnicodeScalar("(").value)
    default: return nil
    }
}

func matchingClosingBracket(for opening: unichar) -> unichar? {
    switch UnicodeScalar(opening) {
    case "{": return unichar(UnicodeScalar("}").value)
    case "[": return unichar(UnicodeScalar("]").value)
    case "(": return unichar(UnicodeScalar(")").value)
    default: return nil
    }
}

func isBracket(_ c: unichar) -> Bool {
    matchesAny(c, ["{", "}", "[", "]", "(", ")"])
}

func matchesAny(_ c: unichar, _ chars: [Character]) -> Bool {
    guard let scalar = UnicodeScalar(c) else { return false }
    return chars.contains(Character(scalar))
}

func computeBracketScopeMatch(text: String, caretLocation: Int) -> BracketScopeMatch? {
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

    // Bounded fallback keeps scope highlighting responsive in large files when
    // the caret is not directly on, or inside, a bracketed scope.
    let fallbackStart = max(0, safeCaret - EditorRuntimeLimits.bracketScopeNearestFallbackWindowUTF16)
    let fallbackEnd = min(length, safeCaret + EditorRuntimeLimits.bracketScopeNearestFallbackWindowUTF16)
    var left = safeCaret - 1
    var right = safeCaret
    while left >= fallbackStart || right < fallbackEnd {
        if left >= fallbackStart {
            if isBracket(ns.character(at: left)) {
                addCandidate(left)
            }
            left -= 1
        }
        if right < fallbackEnd {
            if isBracket(ns.character(at: right)) {
                addCandidate(right)
            }
            right += 1
        }
    }

    for candidate in candidateIndices {
        if let match = matchFrom(start: candidate) {
            return match
        }
    }
    return nil
}

func supportsIndentationScopes(language: String) -> Bool {
    let lang = language.lowercased()
    return lang == "python" || lang == "yaml" || lang == "yml"
}

func computeIndentationScopeMatch(text: String, caretLocation: Int) -> IndentationScopeMatch? {
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

func isValidRange(_ range: NSRange, utf16Length: Int) -> Bool {
    guard range.location != NSNotFound, range.length >= 0, range.location >= 0 else { return false }
    return NSMaxRange(range) <= utf16Length
}

nonisolated func fastSyntaxColorRanges(
    language: String,
    profile: SyntaxPatternProfile,
    text: NSString,
    in range: NSRange,
    colors: SyntaxColors
) -> [(NSRange, Color)]? {
    let lower = language.lowercased()
    let useCSVFastProfile: Bool = {
        switch profile {
        case .csvFast:
            return true
        case .full:
            return lower == "csv" && range.length >= 180_000
        default:
            return false
        }
    }()
    if useCSVFastProfile {
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

    if case .htmlFast = profile, lower == "html" || lower == "xml" {
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

    let useJSONScanner: Bool = {
        switch profile {
        case .full, .jsonFast:
            return isJSONLikeLanguage(lower)
        default:
            return false
        }
    }()
    if useJSONScanner {
        let rangeEnd = NSMaxRange(range)
        var out: [(NSRange, Color)] = []
        var i = range.location
        let isBudgeted: Bool = {
            if case .jsonFast = profile { return true }
            return false
        }()
        let budgetDeadline = CFAbsoluteTimeGetCurrent() + EditorRuntimeLimits.largeFileJSONTokenBudgetSeconds
        while i < rangeEnd {
            if isBudgeted && CFAbsoluteTimeGetCurrent() >= budgetDeadline {
                break
            }
            let ch = text.character(at: i)
            if isJSONWhitespace(ch) {
                i += 1
                continue
            }
            if ch == 34 { // "
                let start = i
                i += 1
                while i < rangeEnd {
                    let c = text.character(at: i)
                    if c == 92 { // \
                        i += min(2, rangeEnd - i)
                        continue
                    }
                    i += 1
                    if c == 34 {
                        break
                    }
                }
                let tokenRange = NSRange(location: start, length: max(0, i - start))
                var lookahead = i
                while lookahead < rangeEnd && isJSONWhitespace(text.character(at: lookahead)) {
                    lookahead += 1
                }
                let tokenColor = (lookahead < rangeEnd && text.character(at: lookahead) == 58)
                    ? colors.property
                    : colors.string
                out.append((tokenRange, tokenColor))
                continue
            }
            if ch == 123 || ch == 125 || ch == 91 || ch == 93 || ch == 58 || ch == 44 {
                out.append((NSRange(location: i, length: 1), colors.meta))
                i += 1
                continue
            }
            if ch == 45 || isJSONDigit(ch) {
                let start = i
                if ch == 45 {
                    i += 1
                }
                while i < rangeEnd && isJSONDigit(text.character(at: i)) {
                    i += 1
                }
                if i < rangeEnd && text.character(at: i) == 46 {
                    i += 1
                    while i < rangeEnd && isJSONDigit(text.character(at: i)) {
                        i += 1
                    }
                }
                if i < rangeEnd {
                    let exp = text.character(at: i)
                    if exp == 69 || exp == 101 {
                        i += 1
                        if i < rangeEnd {
                            let sign = text.character(at: i)
                            if sign == 43 || sign == 45 {
                                i += 1
                            }
                        }
                        while i < rangeEnd && isJSONDigit(text.character(at: i)) {
                            i += 1
                        }
                    }
                }
                if i > start {
                    out.append((NSRange(location: start, length: i - start), colors.number))
                    continue
                }
            }
            if isJSONLetter(ch) {
                let start = i
                i += 1
                while i < rangeEnd && isJSONLetter(text.character(at: i)) {
                    i += 1
                }
                let wordRange = NSRange(location: start, length: i - start)
                if isJSONLiteral(text, range: wordRange, literal: [116, 114, 117, 101]) ||
                    isJSONLiteral(text, range: wordRange, literal: [102, 97, 108, 115, 101]) ||
                    isJSONLiteral(text, range: wordRange, literal: [110, 117, 108, 108]) {
                    out.append((wordRange, colors.keyword))
                }
                continue
            }
            i += 1
        }
        return out
    }
    return nil
}

