import Foundation
#if os(macOS) && !APP_STORE_BUILD
import AppKit
import Darwin

/// PTY reads are byte chunks, not independently decodable UTF-8 strings.
nonisolated final class TerminalUTF8Decoder {
    private var pending: [UInt8] = []

    func reset() { pending.removeAll(keepingCapacity: true) }

    func decode(_ data: Data) -> String {
        let bytes = pending + Array(data)
        pending.removeAll(keepingCapacity: true)
        var result = ""
        var index = 0
        while index < bytes.count {
            let first = bytes[index]
            let length: Int
            switch first {
            case 0...0x7F: length = 1
            case 0xC2...0xDF: length = 2
            case 0xE0...0xEF: length = 3
            case 0xF0...0xF4: length = 4
            default:
                result.append("\u{FFFD}")
                index += 1
                continue
            }
            let available = min(length, bytes.count - index)
            let continuationIsValid = (1..<available).allSatisfy {
                (0x80...0xBF).contains(bytes[index + $0])
            }
            guard continuationIsValid else {
                result.append("\u{FFFD}")
                index += 1
                continue
            }
            if available < length {
                pending = Array(bytes[index...]) // At most three bytes.
                break
            }
            result += String(decoding: bytes[index..<(index + length)], as: UTF8.self)
            index += length
        }
        return result
    }
}

nonisolated struct TerminalScreenPatch: @unchecked Sendable {
    let range: NSRange
    let text: NSAttributedString
}

/// A bounded primary screen and scrollback. Alternate-screen applications remain unsupported.
/// Mutated only by the session's output worker; UIKit and SwiftUI never own its cells.
nonisolated final class TerminalScreenBuffer {
    private final class Style {
        let attributes: [NSAttributedString.Key: Any]
        init(_ attributes: [NSAttributedString.Key: Any]) { self.attributes = attributes }
    }
    private struct Cell {
        var text: String
        var width: Int
        let style: Style
        var utf16Length: Int
    }
    private enum ParserState {
        case text, escape, csi, discardCSI, osc, oscEscape, stringControl, stringEscape
    }

    private let decoder = TerminalUTF8Decoder()
    private let formatter = TerminalANSIFormatter()
    private var state: ParserState = .text
    private var sequence = ""
    private var lines: [[Cell]] = [[]]
    private var rowLengths = [1]
    private var retainedLength = 1
    private var row = 0
    private var column = 0
    private var savedCursor = (row: 0, column: 0)
    private var columns = 120
    private var height = 36
    private var style: Style
    private var dirtyFromRow: Int? = 0
    private var publishedRowLengths: [Int] = []
    private var publishedLength = 0
    private let maximumUTF16Length: Int

    init(maximumUTF16Length: Int = 240_000) {
        self.maximumUTF16Length = max(1_024, maximumUTF16Length)
        style = Style(formatter.attributedText(from: " ").attributes(at: 0, effectiveRange: nil))
    }

    func resetParser() {
        decoder.reset()
        formatter.reset()
        state = .text
        sequence.removeAll(keepingCapacity: true)
        style = Style(formatter.attributedText(from: " ").attributes(at: 0, effectiveRange: nil))
    }

    func rebasePublishedState(length: Int) {
        publishedLength = length
        publishedRowLengths = []
        dirtyFromRow = 0
    }

    func reset() {
        resetParser()
        lines = [[]]
        rowLengths = [1]
        retainedLength = 1
        row = 0
        column = 0
        savedCursor = (0, 0)
        dirtyFromRow = 0
        publishedRowLengths = []
        publishedLength = 0
    }

    func resize(columns: Int, rows: Int) {
        self.columns = min(512, max(1, columns))
        height = min(256, max(1, rows))
        column = min(column, self.columns)
        // Do not reflow history on resize: it would invalidate cursor-addressed output.
    }

    func consume(_ data: Data) {
        for scalar in decoder.decode(data).unicodeScalars {
            switch state {
            case .text:
                switch scalar.value {
                case 0x1B: state = .escape
                case 0x0D: column = 0
                case 0x0A: lineFeed()
                case 0x08:
                    column = max(0, column - 1)
                    if column < lines[row].count, lines[row][column].width == 0 {
                        column = max(0, column - 1)
                    }
                case 0x09: column = min(columns, (column / 8 + 1) * 8)
                case 0x00...0x1F, 0x7F: break
                default: put(scalar)
                }
            case .escape:
                state = .text
                switch scalar {
                case "[": sequence = ""; state = .csi
                case "]": state = .osc
                case "P", "^", "_": state = .stringControl
                case "7": savedCursor = (row, column)
                case "8": restoreCursor()
                case "D": lineFeed()
                case "E": column = 0; lineFeed()
                default: break
                }
            case .csi:
                if (0x40...0x7E).contains(scalar.value) {
                    executeCSI(final: scalar)
                    state = .text
                } else if scalar.value == 0x1B {
                    state = .escape
                } else if sequence.utf8.count < 128 {
                    sequence.unicodeScalars.append(scalar)
                } else {
                    sequence = ""
                    state = .discardCSI
                }
            case .discardCSI:
                if (0x40...0x7E).contains(scalar.value) { state = .text }
                else if scalar.value == 0x1B { state = .escape }
            case .osc:
                if scalar.value == 7 { state = .text }
                else if scalar.value == 0x1B { state = .oscEscape }
            case .oscEscape:
                state = scalar == "\\" ? .text : .osc
            case .stringControl:
                if scalar.value == 0x1B { state = .stringEscape }
            case .stringEscape:
                state = scalar == "\\" ? .text : .stringControl
            }
        }
        trimHistory()
    }

    /// Return only the changed suffix of the screen, including its prior range.
    /// Progress rewrites replace a row instead of rebuilding the entire scrollback.
    func takePatch() -> TerminalScreenPatch? {
        guard let first = dirtyFromRow else { return nil }
        let start = publishedRowLengths.prefix(first).reduce(0, +)
        let output = NSMutableAttributedString()
        var lengths = Array(publishedRowLengths.prefix(first))
        for index in first..<lines.count {
            let before = output.length
            var run = ""
            var runStyle: Style?
            func flush() {
                guard !run.isEmpty, let runStyle else { return }
                output.append(NSAttributedString(string: run, attributes: runStyle.attributes))
                run = ""
            }
            for cell in lines[index] where cell.width > 0 {
                if runStyle !== cell.style { flush(); runStyle = cell.style }
                run += cell.text
            }
            flush()
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: style.attributes))
            }
            lengths.append(output.length - before)
        }
        let patch = TerminalScreenPatch(
            range: NSRange(location: start, length: publishedLength - start),
            text: NSAttributedString(attributedString: output)
        )
        publishedRowLengths = lengths
        publishedLength = start + output.length
        dirtyFromRow = nil
        return patch
    }

    private var screenTop: Int { max(0, lines.count - height) }
    private func markDirty(_ index: Int) { dirtyFromRow = min(dirtyFromRow ?? index, index) }
    private func ensureRow(_ index: Int) {
        while lines.count <= index {
            markDirty(max(0, lines.count - 1)) // The prior last row gains a newline.
            lines.append([])
            rowLengths.append(1)
            retainedLength += 1
        }
    }
    private func lineFeed() {
        row += 1
        ensureRow(row)
    }
    private func blank() -> Cell { Cell(text: " ", width: 1, style: style, utf16Length: 1) }
    private func replaceCell(at index: Int, with cell: Cell) {
        let delta = cell.utf16Length - lines[row][index].utf16Length
        lines[row][index] = cell
        rowLengths[row] += delta
        retainedLength += delta
    }
    private func clearLine(_ index: Int) {
        retainedLength -= rowLengths[index] - 1
        rowLengths[index] = 1
        lines[index] = []
        markDirty(index)
    }

    private func put(_ scalar: UnicodeScalar) {
        let isCombining = scalar.properties.generalCategory == .nonspacingMark
            || scalar.properties.generalCategory == .spacingMark
            || scalar.properties.generalCategory == .enclosingMark
            || scalar.value == 0x200D || (0xFE00...0xFE0F).contains(scalar.value)
        var previous = min(column, lines[row].count) - 1
        if previous >= 0, lines[row][previous].width == 0 { previous -= 1 }
        if previous >= 0 {
            let cell = lines[row][previous]
            let joinsEmoji = cell.text.unicodeScalars.last?.value == 0x200D
            let regionalPair = (0x1F1E6...0x1F1FF).contains(scalar.value)
                && cell.text.unicodeScalars.count == 1
                && (0x1F1E6...0x1F1FF).contains(cell.text.unicodeScalars.first!.value)
            if isCombining || joinsEmoji || regionalPair {
                lines[row][previous].text.unicodeScalars.append(scalar)
                let added = scalar.value > 0xFFFF ? 2 : 1
                lines[row][previous].utf16Length += added
                rowLengths[row] += added
                retainedLength += added
                markDirty(row)
                return
            }
        }
        if isCombining { return }
        let nativeWidth = Int(wcwidth(wchar_t(bitPattern: scalar.value)))
        let isWide = (0x1100...0x115F).contains(scalar.value)
            || (0x2E80...0xA4CF).contains(scalar.value)
            || (0xAC00...0xD7A3).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
            || (0xFE10...0xFE6F).contains(scalar.value)
            || (0xFF01...0xFF60).contains(scalar.value)
            || (0x1F000...0x1FAFF).contains(scalar.value)
            || (0x20000...0x3FFFD).contains(scalar.value)
        let width = min(columns, isWide ? 2 : max(1, nativeWidth))
        if column + width > columns { column = 0; lineFeed() }
        while lines[row].count < column + width {
            lines[row].append(blank())
            rowLengths[row] += 1
            retainedLength += 1
        }
        if lines[row][column].width == 0, column > 0 { replaceCell(at: column - 1, with: blank()) }
        if lines[row][column].width == 2, column + 1 < lines[row].count {
            replaceCell(at: column + 1, with: blank())
        }
        if width == 2, lines[row][column + 1].width == 2, column + 2 < lines[row].count {
            replaceCell(at: column + 2, with: blank())
        }
        replaceCell(at: column, with: Cell(text: String(scalar), width: width, style: style, utf16Length: scalar.value > 0xFFFF ? 2 : 1))
        if width == 2 { replaceCell(at: column + 1, with: Cell(text: "", width: 0, style: style, utf16Length: 0)) }
        column += width
        markDirty(row)
    }

    private func executeCSI(final: UnicodeScalar) {
        guard !sequence.contains("?"), !sequence.contains(":") else { return }
        let parameters = sequence.split(separator: ";", omittingEmptySubsequences: false)
        guard parameters.allSatisfy({ $0.isEmpty || $0.allSatisfy(\.isNumber) }) else { return }
        let values = parameters.map { min(100_000, Int($0) ?? 0) }
        let value = values.first ?? 0
        let amount = max(1, value)
        switch final {
        case "m":
            _ = formatter.attributedText(from: "\u{1B}[\(sequence)m")
            style = Style(formatter.attributedText(from: " ").attributes(at: 0, effectiveRange: nil))
        case "A": row = max(screenTop, row - amount)
        case "B": row = min(screenTop + height - 1, row + amount); ensureRow(row)
        case "C": column = min(columns - 1, column + amount)
        case "D": column = max(0, column - amount)
        case "E": row = min(screenTop + height - 1, row + amount); column = 0; ensureRow(row)
        case "F": row = max(screenTop, row - amount); column = 0
        case "G", "`": column = min(columns - 1, amount - 1)
        case "H", "f":
            row = screenTop + min(height - 1, amount - 1)
            column = min(columns - 1, max(1, values.count > 1 ? values[1] : 1) - 1)
            ensureRow(row)
        case "d": row = screenTop + min(height - 1, amount - 1); ensureRow(row)
        case "K": eraseLine(mode: value)
        case "J":
            guard (0...2).contains(value) else { return }
            let top = screenTop
            if value == 0 {
                eraseLine(mode: 0)
                if row + 1 < lines.count {
                    for index in (row + 1)..<lines.count { clearLine(index) }
                }
            } else if value == 1 {
                for index in top..<row { clearLine(index) }
                markDirty(top)
                eraseLine(mode: 1)
            } else {
                for index in top..<lines.count { clearLine(index) }
                markDirty(top)
            }
        case "s": savedCursor = (row, column)
        case "u": restoreCursor()
        default: break
        }
    }

    private func restoreCursor() {
        row = min(lines.count - 1, max(screenTop, savedCursor.row))
        column = min(columns - 1, savedCursor.column)
    }
    private func eraseLine(mode: Int) {
        guard (0...2).contains(mode) else { return }
        markDirty(row)
        if mode == 2 { clearLine(row); return }
        if mode == 0 {
            var start = min(column, lines[row].count)
            if start < lines[row].count, lines[row][start].width == 0 { start -= 1 }
            let removed = lines[row][start...].reduce(0) { $0 + $1.utf16Length }
            lines[row].removeSubrange(start...)
            rowLengths[row] -= removed
            retainedLength -= removed
        } else {
            let end = min(column + 1, lines[row].count)
            if end > 0 {
                for index in 0..<end { replaceCell(at: index, with: blank()) }
                if end < lines[row].count, lines[row][end].width == 0 { replaceCell(at: end, with: blank()) }
            }
        }
    }

    private func trimHistory() {
        // Both cells and UTF-16 units are bounded, including long combining sequences.
        var removed = 0
        while removed < screenTop, retainedLength > maximumUTF16Length {
            retainedLength -= rowLengths[removed]
            removed += 1
        }
        if removed > 0 {
            lines.removeFirst(removed)
            rowLengths.removeFirst(removed)
            row -= removed
            savedCursor.row = max(0, savedCursor.row - removed)
            markDirty(0)
        }
        if retainedLength > maximumUTF16Length {
            // A pathological visible screen cannot grow beyond the retained-output budget.
            // Keep complete graphemes rather than splitting a surrogate/combining sequence.
            for index in lines.indices where retainedLength > maximumUTF16Length {
                clearLine(index)
            }
        }
    }
}
#endif
