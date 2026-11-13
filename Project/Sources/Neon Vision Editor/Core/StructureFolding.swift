import Foundation

/// The structure that can be folded in a document: JSON objects and arrays,
/// or XML elements, comments, and CDATA sections.
nonisolated enum StructureFoldSyntax: Sendable, Equatable {
    case json
    case xml

    static func forLanguage(_ language: String) -> StructureFoldSyntax? {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "json", "jsonc", "json5", "ipynb", "geojson":
            return .json
        case "xml", "plist", "svg", "xsd", "xsl", "xslt":
            return .xml
        default:
            return nil
        }
    }
}

/// A folded region in document coordinates. The header line stays visible,
/// lines `headerLine + 1 ..< endLine` are hidden, and the closing line stays
/// visible, so the closing bracket or tag still reads below the header.
nonisolated struct StructureFold: Equatable, Sendable {
    var headerLine: Int
    var endLine: Int
    /// UTF-16 offset of the first hidden line's start.
    var hiddenStartUTF16: Int
    /// UTF-16 offset of the closing line's start.
    var hiddenEndUTF16: Int

    var hiddenLineCount: Int { endLine - headerLine - 1 }
    var hiddenUTF16Length: Int { hiddenEndUTF16 - hiddenStartUTF16 }
}

/// A candidate region found by a structure scan: the line of the opener and
/// the line of its matching closer.
nonisolated struct StructureFoldRegion: Equatable, Sendable {
    let headerLine: Int
    let endLine: Int
    let hiddenStartUTF16: Int
    let hiddenEndUTF16: Int
    let depth: Int

    var fold: StructureFold {
        StructureFold(headerLine: headerLine, endLine: endLine,
                      hiddenStartUTF16: hiddenStartUTF16, hiddenEndUTF16: hiddenEndUTF16)
    }
}

/// A byte-level tokenizer for structure delimiters. Every delimiter is ASCII,
/// so UTF-8 multi-byte sequences can never be mistaken for one.
nonisolated struct StructureFoldTokenizer {
    enum Event: Equatable {
        case open
        case close
    }

    private enum Mode: Equatable {
        case code
        // JSON
        case string
        case stringEscape
        case lineComment
        case blockComment
        // XML
        case tagStart
        case markupStart(matched: Int)
        case openTag(quote: UInt8?)
        case closeTag
        case declaration(quote: UInt8?)
        case processingInstruction
        case comment
        case cdata
    }

    let syntax: StructureFoldSyntax
    private var mode: Mode = .code
    private var previous: UInt8 = 0
    private var beforePrevious: UInt8 = 0
    private var markupIsCDATA = false

    init(syntax: StructureFoldSyntax) {
        self.syntax = syntax
    }

    private static let commentPrefix = Array("!--".utf8)
    private static let cdataPrefix = Array("![CDATA[".utf8)

    /// Consumes one byte and reports a structure that opens or closes there.
    mutating func consume(_ byte: UInt8) -> Event? {
        defer {
            beforePrevious = previous
            previous = byte
        }
        switch syntax {
        case .json: return consumeJSON(byte)
        case .xml: return consumeXML(byte)
        }
    }

    private mutating func consumeJSON(_ byte: UInt8) -> Event? {
        switch mode {
        case .string:
            if byte == 0x5C { mode = .stringEscape } // backslash
            else if byte == 0x22 || byte == 0x0A { mode = .code } // a line break ends a broken string
            return nil
        case .stringEscape:
            mode = .string
            return nil
        case .lineComment:
            if byte == 0x0A { mode = .code }
            return nil
        case .blockComment:
            if byte == 0x2F && previous == 0x2A { mode = .code; return nil } // */
            return nil
        default:
            switch byte {
            case 0x22: mode = .string
            case 0x2F where previous == 0x2F: mode = .lineComment
            case 0x2A where previous == 0x2F: mode = .blockComment
            case 0x7B, 0x5B: return .open // { [
            case 0x7D, 0x5D: return .close // } ]
            default: break
            }
            return nil
        }
    }

    private mutating func consumeXML(_ byte: UInt8) -> Event? {
        switch mode {
        case .code:
            if byte == 0x3C { mode = .tagStart } // <
            return nil
        case .tagStart:
            switch byte {
            case 0x2F: mode = .closeTag; return nil // </
            case 0x3F: mode = .processingInstruction; return nil // <?
            case 0x21: mode = .markupStart(matched: 1); return nil // <!
            case 0x3C: mode = .tagStart; return nil
            case 0x20, 0x09, 0x0A, 0x0D, 0x3E: mode = .code; return nil // not a tag
            default: mode = .openTag(quote: nil); return nil
            }
        case .markupStart(let matched):
            // After "<!": a comment ("<!--"), a CDATA section, or a declaration.
            if matched == 1 {
                if byte == 0x2D { markupIsCDATA = false }
                else if byte == 0x5B { markupIsCDATA = true }
                else { mode = .declaration(quote: nil); return consumeDeclaration(byte, quote: nil) }
            }
            let target = markupIsCDATA ? Self.cdataPrefix : Self.commentPrefix
            guard matched < target.count, byte == target[matched] else {
                mode = .declaration(quote: nil)
                return consumeDeclaration(byte, quote: nil)
            }
            if matched + 1 == target.count {
                mode = markupIsCDATA ? .cdata : .comment
                return .open
            }
            mode = .markupStart(matched: matched + 1)
            return nil
        case .openTag(let quote):
            if let quote {
                if byte == quote { mode = .openTag(quote: nil) }
                return nil
            }
            switch byte {
            case 0x22, 0x27: mode = .openTag(quote: byte)
            case 0x3E: // >
                mode = .code
                return previous == 0x2F ? nil : .open // "/>" closes itself
            default: break
            }
            return nil
        case .closeTag:
            if byte == 0x3E { mode = .code; return .close }
            return nil
        case .declaration(let quote):
            return consumeDeclaration(byte, quote: quote)
        case .processingInstruction:
            if byte == 0x3E && previous == 0x3F { mode = .code }
            return nil
        case .comment:
            if byte == 0x3E && previous == 0x2D && beforePrevious == 0x2D { mode = .code; return .close }
            return nil
        case .cdata:
            if byte == 0x3E && previous == 0x5D && beforePrevious == 0x5D { mode = .code; return .close }
            return nil
        default:
            mode = .code
            return nil
        }
    }

    private mutating func consumeDeclaration(_ byte: UInt8, quote: UInt8?) -> Event? {
        if let quote {
            if byte == quote { mode = .declaration(quote: nil) }
            return nil
        }
        switch byte {
        case 0x22, 0x27: mode = .declaration(quote: byte)
        case 0x3E: mode = .code
        default: break
        }
        return nil
    }
}

nonisolated enum StructureFoldScanner {
    /// Lines longer than this never show a fold control; a minified line has
    /// nothing to hide below it.
    static let maximumHeaderLineUTF16Length = 20_000

    /// True when `line` opens a structure that it does not close, so the line
    /// can start a fold. This only reads the line, so it is cheap enough for
    /// every visible row.
    static func lineOpensStructure(_ line: String, syntax: StructureFoldSyntax) -> Bool {
        guard line.utf16.count <= maximumHeaderLineUTF16Length else { return false }
        var tokenizer = StructureFoldTokenizer(syntax: syntax)
        var unmatched = 0
        for byte in line.utf8 {
            switch tokenizer.consume(byte) {
            case .open: unmatched += 1
            case .close: unmatched = max(0, unmatched - 1)
            case nil: break
            }
        }
        return unmatched > 0
    }

    /// Finds the fold that starts on `headerLine`: the outermost structure the
    /// line opens without closing, through the line holding its closer.
    static func region(
        startingAt headerLine: Int,
        in document: any EditorDocument,
        syntax: StructureFoldSyntax
    ) throws -> StructureFoldRegion? {
        guard headerLine >= 0, headerLine + 2 < document.lineCount else { return nil }
        let start = try document.viewport(aroundLine: headerLine, maximumByteCount: 8, maximumLineCount: 1)
        guard start.lineRange.lowerBound == headerLine else { return nil }
        var tokenizer = StructureFoldTokenizer(syntax: syntax)
        var offset = start.startByteOffset
        var line = headerLine
        var unmatched = 0
        var openedOnHeader = false
        var closingLine: Int?
        scan: while true {
            let chunk = try document.textChunk(startByteOffset: offset, maximumByteCount: 256 * 1024)
            guard chunk.byteCount > 0 else { break }
            offset += chunk.byteCount
            var text = chunk.text
            let done: Bool = text.withUTF8 { bytes in
                for byte in bytes {
                    if byte == 0x0A {
                        if line == headerLine {
                            openedOnHeader = unmatched > 0
                            if !openedOnHeader { return true }
                        }
                        line += 1
                    }
                    switch tokenizer.consume(byte) {
                    case .open:
                        unmatched += 1
                    case .close:
                        guard unmatched > 0 else { continue }
                        unmatched -= 1
                        if unmatched == 0, line > headerLine {
                            closingLine = line
                            return true
                        }
                    case nil:
                        break
                    }
                }
                return false
            }
            if done { break scan }
        }
        guard openedOnHeader, let endLine = closingLine, endLine > headerLine + 1 else { return nil }
        let hiddenStart = try document.viewport(aroundLine: headerLine + 1, maximumByteCount: 8, maximumLineCount: 1)
        let hiddenEnd = try document.viewport(aroundLine: endLine, maximumByteCount: 8, maximumLineCount: 1)
        return StructureFoldRegion(
            headerLine: headerLine,
            endLine: endLine,
            hiddenStartUTF16: hiddenStart.startUTF16Offset,
            hiddenEndUTF16: hiddenEnd.startUTF16Offset,
            depth: 0
        )
    }

    /// Every multi-line region in the document, one per header line (the
    /// outermost when a line opens several). One pass; UTF-16 offsets are
    /// counted from the decoded bytes, so no per-region lookups are needed.
    static func allRegions(
        in document: any EditorDocument,
        syntax: StructureFoldSyntax
    ) throws -> [StructureFoldRegion] {
        struct Open {
            let line: Int
            let depth: Int
            var nextLineStartUTF16: Int?
        }
        var tokenizer = StructureFoldTokenizer(syntax: syntax)
        var stack: [Open] = []
        var byHeader: [Int: StructureFoldRegion] = [:]
        var offset = 0
        var utf16 = 0
        var line = 0
        var lineStartUTF16 = 0
        while true {
            try Task.checkCancellation()
            let chunk = try document.textChunk(startByteOffset: offset, maximumByteCount: 256 * 1024)
            guard chunk.byteCount > 0 else { break }
            offset += chunk.byteCount
            var text = chunk.text
            text.withUTF8 { bytes in
                for byte in bytes {
                    // UTF-16 length of each scalar, counted at its lead byte.
                    if byte & 0xC0 != 0x80 { utf16 += byte >= 0xF0 ? 2 : 1 }
                    if byte == 0x0A {
                        line += 1
                        lineStartUTF16 = utf16
                        var index = stack.count - 1
                        while index >= 0, stack[index].line == line - 1, stack[index].nextLineStartUTF16 == nil {
                            stack[index].nextLineStartUTF16 = utf16
                            index -= 1
                        }
                    }
                    switch tokenizer.consume(byte) {
                    case .open:
                        stack.append(Open(line: line, depth: stack.count, nextLineStartUTF16: nil))
                    case .close:
                        guard let open = stack.popLast() else { continue }
                        guard line > open.line + 1, let hiddenStart = open.nextLineStartUTF16 else { continue }
                        let region = StructureFoldRegion(
                            headerLine: open.line, endLine: line,
                            hiddenStartUTF16: hiddenStart, hiddenEndUTF16: lineStartUTF16,
                            depth: open.depth
                        )
                        if let existing = byHeader[open.line], existing.endLine >= line { continue }
                        byHeader[open.line] = region
                    case nil:
                        break
                    }
                }
            }
        }
        return byHeader.values.sorted { $0.headerLine < $1.headerLine }
    }
}

/// The folds of one editor and the mapping between document coordinates and
/// the folded view, where hidden lines are absent. Every lookup is a binary
/// search over the visible (outermost) folds.
nonisolated final class StructureFoldModel {
    private(set) var folds: [StructureFold] = []
    private(set) var visibleFolds: [StructureFold] = []
    private var hiddenUTF16Before: [Int] = [0]
    private var hiddenLinesBefore: [Int] = [0]

    var isEmpty: Bool { folds.isEmpty }
    var hiddenUTF16Count: Int { hiddenUTF16Before[hiddenUTF16Before.count - 1] }
    var hiddenLineCount: Int { hiddenLinesBefore[hiddenLinesBefore.count - 1] }

    func setFolds(_ folds: [StructureFold]) {
        self.folds = folds.filter { $0.hiddenLineCount > 0 && $0.hiddenUTF16Length > 0 }
        rebuild()
    }

    func add(_ fold: StructureFold) {
        guard fold.hiddenLineCount > 0, fold.hiddenUTF16Length > 0 else { return }
        folds.removeAll { $0.headerLine == fold.headerLine }
        folds.append(fold)
        rebuild()
    }

    func removeAll() {
        guard !folds.isEmpty else { return }
        folds.removeAll()
        rebuild()
    }

    @discardableResult
    func removeFold(headerLine: Int) -> Bool {
        let count = folds.count
        folds.removeAll { $0.headerLine == headerLine }
        guard folds.count != count else { return false }
        rebuild()
        return true
    }

    /// The visible fold whose header is `line` (document coordinates).
    func visibleFold(headerLine line: Int) -> StructureFold? {
        var low = 0
        var high = visibleFolds.count
        while low < high {
            let middle = (low + high) / 2
            if visibleFolds[middle].headerLine < line { low = middle + 1 } else { high = middle }
        }
        return low < visibleFolds.count && visibleFolds[low].headerLine == line ? visibleFolds[low] : nil
    }

    /// Removes every fold that hides part of `range` or would be cut by an
    /// edit there, so the text becomes visible. Returns true when any opened.
    @discardableResult
    func reveal(_ range: NSRange) -> Bool {
        let start = range.location
        let end = NSMaxRange(range)
        let count = folds.count
        folds.removeAll { fold in
            range.length == 0
                ? start >= fold.hiddenStartUTF16 && start < fold.hiddenEndUTF16
                : start < fold.hiddenEndUTF16 && end > fold.hiddenStartUTF16
        }
        guard folds.count != count else { return false }
        rebuild()
        return true
    }

    /// Removes every fold that hides part of `line`.
    @discardableResult
    func reveal(line: Int) -> Bool {
        let count = folds.count
        folds.removeAll { line > $0.headerLine && line < $0.endLine }
        guard folds.count != count else { return false }
        rebuild()
        return true
    }

    /// Keeps folds consistent with an edit of `range` (document coordinates).
    /// Folds before the edit stay, folds after it move, and a fold the edit
    /// touches is removed so nothing stays hidden in an unexpected place.
    func applyEdit(range: NSRange, replacementUTF16Length: Int, lineDelta: Int) {
        guard !folds.isEmpty else { return }
        let start = range.location
        let end = NSMaxRange(range)
        let delta = replacementUTF16Length - range.length
        var changed = false
        folds = folds.compactMap { fold in
            if start >= fold.hiddenEndUTF16 { return fold }
            if end < fold.hiddenStartUTF16 {
                guard delta != 0 || lineDelta != 0 else { return fold }
                changed = true
                return StructureFold(
                    headerLine: fold.headerLine + lineDelta,
                    endLine: fold.endLine + lineDelta,
                    hiddenStartUTF16: fold.hiddenStartUTF16 + delta,
                    hiddenEndUTF16: fold.hiddenEndUTF16 + delta
                )
            }
            changed = true
            return nil
        }
        if changed { rebuild() }
    }

    // MARK: Coordinate mapping

    func foldedOffset(forDocumentOffset offset: Int) -> Int {
        let passed = countVisibleFolds { $0.hiddenEndUTF16 <= offset }
        if passed < visibleFolds.count, visibleFolds[passed].hiddenStartUTF16 <= offset {
            return visibleFolds[passed].hiddenStartUTF16 - hiddenUTF16Before[passed]
        }
        return offset - hiddenUTF16Before[passed]
    }

    /// A folded offset at a fold's closing line start maps past the hidden
    /// lines; with `beforeHiddenText` it maps to the first hidden line start.
    func documentOffset(forFoldedOffset offset: Int, beforeHiddenText: Bool = false) -> Int {
        var low = 0
        var high = visibleFolds.count
        while low < high {
            let middle = (low + high) / 2
            let junction = visibleFolds[middle].hiddenStartUTF16 - hiddenUTF16Before[middle]
            if beforeHiddenText ? junction < offset : junction <= offset { low = middle + 1 } else { high = middle }
        }
        return offset + hiddenUTF16Before[low]
    }

    /// The document range for a folded range: the start maps past hidden
    /// text, the end before it, so a range that ends at a closing line does
    /// not take the hidden lines with it.
    func documentRange(forFoldedRange range: NSRange) -> NSRange {
        let start = documentOffset(forFoldedOffset: range.location)
        guard range.length > 0 else { return NSRange(location: start, length: 0) }
        let end = max(start, documentOffset(forFoldedOffset: NSMaxRange(range), beforeHiddenText: true))
        return NSRange(location: start, length: end - start)
    }

    func foldedRange(forDocumentRange range: NSRange) -> NSRange {
        let start = foldedOffset(forDocumentOffset: range.location)
        let end = foldedOffset(forDocumentOffset: NSMaxRange(range))
        return NSRange(location: start, length: max(0, end - start))
    }

    /// True when the folded range spans a fold, so editing it would also
    /// replace the hidden lines.
    func foldedRangeSpansHiddenText(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        let mapped = documentRange(forFoldedRange: range)
        return visibleFolds.contains {
            $0.hiddenStartUTF16 >= mapped.location && $0.hiddenEndUTF16 <= NSMaxRange(mapped)
        }
    }

    func foldedLine(forDocumentLine line: Int) -> Int {
        let passed = countVisibleFolds { $0.endLine <= line }
        if passed < visibleFolds.count, visibleFolds[passed].headerLine < line {
            return visibleFolds[passed].headerLine - hiddenLinesBefore[passed]
        }
        return line - hiddenLinesBefore[passed]
    }

    func documentLine(forFoldedLine line: Int) -> Int {
        var low = 0
        var high = visibleFolds.count
        while low < high {
            let middle = (low + high) / 2
            let closingLine = visibleFolds[middle].endLine - hiddenLinesBefore[middle + 1]
            if closingLine <= line { low = middle + 1 } else { high = middle }
        }
        return line + hiddenLinesBefore[low]
    }

    /// Visible folds whose hidden text starts in `range` (document UTF-16).
    func visibleFolds(startingIn range: Range<Int>) -> ArraySlice<StructureFold> {
        let lower = countVisibleFolds { $0.hiddenStartUTF16 < range.lowerBound }
        let upper = countVisibleFolds { $0.hiddenStartUTF16 < range.upperBound }
        return visibleFolds[lower..<max(lower, upper)]
    }

    private func countVisibleFolds(where precedes: (StructureFold) -> Bool) -> Int {
        var low = 0
        var high = visibleFolds.count
        while low < high {
            let middle = (low + high) / 2
            if precedes(visibleFolds[middle]) { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private func rebuild() {
        folds.sort { $0.hiddenStartUTF16 < $1.hiddenStartUTF16 }
        visibleFolds.removeAll(keepingCapacity: true)
        for fold in folds {
            if let last = visibleFolds.last, fold.hiddenStartUTF16 < last.hiddenEndUTF16 { continue }
            visibleFolds.append(fold)
        }
        hiddenUTF16Before = [0]
        hiddenLinesBefore = [0]
        hiddenUTF16Before.reserveCapacity(visibleFolds.count + 1)
        hiddenLinesBefore.reserveCapacity(visibleFolds.count + 1)
        for fold in visibleFolds {
            hiddenUTF16Before.append(hiddenUTF16Before[hiddenUTF16Before.count - 1] + fold.hiddenUTF16Length)
            hiddenLinesBefore.append(hiddenLinesBefore[hiddenLinesBefore.count - 1] + fold.hiddenLineCount)
        }
    }
}

/// Presents a document with its folded lines removed. The editor works in
/// these folded coordinates; reads and edits map to the underlying document.
/// Byte offsets stay those of the underlying document, so byte-based context
/// scans are not offered while folds exist; folding is limited to JSON and
/// XML, which do not use them.
nonisolated final class FoldedEditorDocument: EditorDocument {
    enum Error: Swift.Error {
        case unsupportedWhileFolded
    }

    let base: any EditorDocument
    let model: StructureFoldModel

    init(base: any EditorDocument, model: StructureFoldModel) {
        self.base = base
        self.model = model
    }

    var storageKind: EditorDocumentStorageKind { base.storageKind }
    var utf16Length: Int { max(0, base.utf16Length - model.hiddenUTF16Count) }
    var isDirty: Bool { base.isDirty }
    var supportsBoundedWindows: Bool { base.supportsBoundedWindows }
    var lineCount: Int { max(1, base.lineCount - model.hiddenLineCount) }

    func makeViewportReader() -> EditorDocumentViewportReader? { nil }

    func position(atUTF16Offset offset: Int) throws -> (line: Int, column: Int) {
        let position = try base.position(atUTF16Offset: model.documentOffset(forFoldedOffset: offset))
        return (model.foldedLine(forDocumentLine: position.line), position.column)
    }

    func textChunk(startByteOffset: Int, maximumByteCount: Int) throws -> (text: String, byteCount: Int) {
        throw Error.unsupportedWhileFolded
    }

    /// Text of a folded range, including any lines it spans that are folded,
    /// so copying a selection across a fold copies the hidden lines too.
    func text(inUTF16Range range: NSRange) throws -> String {
        try base.text(inUTF16Range: model.documentRange(forFoldedRange: range))
    }

    func string() -> String { base.string() }

    func replace(range: NSRange, with replacement: String) throws {
        try replace(utf16Range: range, with: replacement)
    }

    func replace(utf16Range range: NSRange, with replacement: String) throws {
        let documentRange = model.documentRange(forFoldedRange: range)
        let lineDelta = try Self.lineDelta(in: base, replacing: documentRange, with: replacement)
        try base.replace(utf16Range: documentRange, with: replacement)
        model.applyEdit(range: documentRange, replacementUTF16Length: replacement.utf16.count, lineDelta: lineDelta)
    }

    func replaceAll(with text: String) throws {
        try base.replaceAll(with: text)
        model.removeAll()
    }

    func markClean() { base.markClean() }

    func replace(in viewport: EditorDocumentViewport, utf16Range: NSRange, with replacement: String) throws {
        try replace(
            utf16Range: NSRange(location: viewport.startUTF16Offset + utf16Range.location, length: utf16Range.length),
            with: replacement
        )
    }

    /// Change in line count when `range` of `document` becomes `replacement`.
    static func lineDelta(in document: any EditorDocument, replacing range: NSRange, with replacement: String) throws -> Int {
        let removed = range.length == 0 ? 0 : try document.position(atUTF16Offset: NSMaxRange(range)).line
            - document.position(atUTF16Offset: range.location).line
        var inserted = 0
        for unit in replacement.utf16 where unit == 10 { inserted += 1 }
        return inserted - removed
    }

    func viewport(containingUTF16Offset offset: Int, maximumByteCount: Int, maximumLineCount: Int) throws -> EditorDocumentViewport {
        let line = try position(atUTF16Offset: offset).line
        let window = try viewport(aroundLine: line, maximumByteCount: maximumByteCount, maximumLineCount: maximumLineCount)
        if offset >= window.startUTF16Offset && offset <= window.startUTF16Offset + window.text.utf16.count {
            return window
        }
        // A line longer than the budget: the underlying window stays inside
        // that one visible line, so only its coordinates move.
        let underlying = try base.viewport(
            containingUTF16Offset: model.documentOffset(forFoldedOffset: offset),
            maximumByteCount: maximumByteCount,
            maximumLineCount: maximumLineCount
        )
        return shifted(underlying)
    }

    func viewport(aroundLine line: Int, maximumByteCount: Int, maximumLineCount: Int) throws -> EditorDocumentViewport {
        let count = lineCount
        let center = min(max(0, line), count - 1)
        var lineBudget = max(1, min(maximumLineCount, count))
        while true {
            let first = max(0, min(center - lineBudget / 2, count - lineBudget))
            let last = min(count - 1, first + lineBudget - 1)
            if let window = try stitchedViewport(firstLine: first, lastLine: last, maximumByteCount: maximumByteCount) {
                return window
            }
            guard lineBudget > 1 else { break }
            lineBudget = max(1, lineBudget / 2)
        }
        let underlying = try base.viewport(
            aroundLine: model.documentLine(forFoldedLine: center),
            maximumByteCount: maximumByteCount,
            maximumLineCount: 1
        )
        return shifted(underlying)
    }

    /// Reads folded lines `first...last` from the visible parts of the
    /// document, or nil when they exceed the byte budget.
    private func stitchedViewport(firstLine: Int, lastLine: Int, maximumByteCount: Int) throws -> EditorDocumentViewport? {
        let documentFirst = model.documentLine(forFoldedLine: firstLine)
        let documentAfterLast = model.documentLine(forFoldedLine: lastLine) + 1
        let startProbe = try base.viewport(aroundLine: documentFirst, maximumByteCount: 8, maximumLineCount: 1)
        let start = startProbe.startUTF16Offset
        let end = documentAfterLast >= base.lineCount
            ? base.utf16Length
            : try base.viewport(aroundLine: documentAfterLast, maximumByteCount: 8, maximumLineCount: 1).startUTF16Offset
        let hidden = model.visibleFolds(startingIn: start..<max(start, end))
        let visibleLength = (end - start) - hidden.reduce(0) { $0 + $1.hiddenUTF16Length }
        // UTF-16 units approximate the byte budget; JSON and XML are mostly
        // ASCII, and an oversized single line falls back to the bounded read.
        guard visibleLength <= maximumByteCount else { return nil }
        var text = ""
        text.reserveCapacity(visibleLength)
        var cursor = start
        for fold in hidden {
            text += try base.text(inUTF16Range: NSRange(location: cursor, length: fold.hiddenStartUTF16 - cursor))
            cursor = fold.hiddenEndUTF16
        }
        text += try base.text(inUTF16Range: NSRange(location: cursor, length: max(0, end - cursor)))
        return EditorDocumentViewport(
            text: text,
            startByteOffset: startProbe.startByteOffset,
            startUTF16Offset: model.foldedOffset(forDocumentOffset: start),
            lineRange: firstLine...lastLine,
            generation: startProbe.generation
        )
    }

    private func shifted(_ viewport: EditorDocumentViewport) -> EditorDocumentViewport {
        let firstLine = model.foldedLine(forDocumentLine: viewport.lineRange.lowerBound)
        let lastLine = model.foldedLine(forDocumentLine: viewport.lineRange.upperBound)
        return EditorDocumentViewport(
            text: viewport.text,
            startByteOffset: viewport.startByteOffset,
            startUTF16Offset: model.foldedOffset(forDocumentOffset: viewport.startUTF16Offset),
            lineRange: firstLine...max(firstLine, lastLine),
            generation: viewport.generation,
            startColumnUTF16: viewport.startColumnUTF16
        )
    }
}
