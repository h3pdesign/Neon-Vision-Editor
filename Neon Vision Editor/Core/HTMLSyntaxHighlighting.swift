import Foundation
import SwiftUI

/// Lexical context is independent of the theme and survives line/viewport boundaries.
nonisolated struct HTMLSyntaxState: Equatable, Sendable {
    enum Phase: Sendable { case text, tagName, tag, attributeName, afterAttribute, beforeValue, value, comment, rawText, css }
    var phase: Phase = .text
    var tagName = ""
    var attributeName = ""
    var closingTag = false
    var valueQuote: UInt16 = 0
    var css = CSSSyntaxState()
}

nonisolated struct CSSSyntaxState: Equatable, Sendable {
    var comment = false
    var quote: UInt16 = 0
    var escaped = false
}

/// A scanner rather than overlapping regex passes: comments and strings own their
/// contents, and HTML attribute delimiters always take precedence over embedded CSS.
nonisolated enum HTMLSyntaxHighlighter {
    static func ranges(
        in text: NSString, range: NSRange, state: inout HTMLSyntaxState,
        colors: SyntaxColors, emitColors: Bool = true
    ) -> [(NSRange, Color)] {
        guard isSyntaxHighlightRangeValid(range, utf16Length: text.length) else { return [] }
        var output: [(NSRange, Color)] = []
        let end = NSMaxRange(range)
        var i = range.location
        func append(_ start: Int, _ finish: Int, _ color: Color) {
            guard emitColors, finish > start else { return }
            if let last = output.last, last.1 == color, NSMaxRange(last.0) == start {
                output[output.count - 1].0.length += finish - start
            } else { output.append((NSRange(location: start, length: finish - start), color)) }
        }
        func matches(_ value: String, at index: Int, insensitive: Bool = false) -> Bool {
            let length = value.utf16.count
            guard index + length <= end else { return false }
            return text.compare(value, options: insensitive ? [.caseInsensitive] : [], range: NSRange(location: index, length: length)) == .orderedSame
        }
        func name(_ ch: UInt16) -> Bool {
            (65...90).contains(ch) || (97...122).contains(ch) || (48...57).contains(ch) || [45, 46, 58, 95, 33].contains(ch)
        }
        func whitespace(_ ch: UInt16) -> Bool { [9, 10, 12, 13, 32].contains(ch) }
        func isRawClose(at index: Int) -> Bool {
            let token = "</" + state.tagName
            guard matches(token, at: index, insensitive: true), index + token.utf16.count < end else { return false }
            let next = text.character(at: index + token.utf16.count)
            return whitespace(next) || next == 62 || next == 47
        }
        while i < end {
            let ch = text.character(at: i)
            let start = i
            switch state.phase {
            case .text:
                if matches("<!--", at: i) {
                    state.phase = .comment
                    i += 4
                    append(start, i, colors.comment)
                } else if ch == 60 {
                    state.phase = .tagName
                    state.tagName = ""
                    state.closingTag = false
                    i += 1
                    append(start, i, colors.tag)
                } else if ch == 38,
                          let match = cachedSyntaxRegex(pattern: #"&(?:#\d+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);"#)?.firstMatch(in: text as String, options: [.anchored], range: NSRange(location: i, length: min(34, end - i))) {
                    i = NSMaxRange(match.range)
                    append(start, i, colors.atom)
                } else { i += 1 }
            case .comment:
                if matches("-->", at: i) { i += 3; state.phase = .text }
                else { i += 1 }
                append(start, i, colors.comment)
            case .tagName:
                if ch == 47 && state.tagName.isEmpty { state.closingTag = true; i += 1 }
                else if name(ch) {
                    if state.tagName.utf16.count < 16 { state.tagName += String(UnicodeScalar(ch)!).lowercased() }
                    i += 1
                } else { state.phase = .tag }
                append(start, i, state.tagName.hasPrefix("!") ? colors.meta : colors.tag)
            case .tag:
                if ch == 62 {
                    i += 1
                    if !state.closingTag && state.tagName == "style" { state.phase = .css; state.css = CSSSyntaxState() }
                    else if !state.closingTag && ["script", "textarea", "title"].contains(state.tagName) { state.phase = .rawText }
                    else { state.phase = .text }
                } else if whitespace(ch) || ch == 47 { i += 1 }
                else if name(ch) { state.attributeName = ""; state.phase = .attributeName }
                else { i += 1 }
                append(start, i, colors.tag)
            case .attributeName:
                if name(ch) {
                    if state.attributeName.utf16.count < 16 { state.attributeName += String(UnicodeScalar(ch)!).lowercased() }
                    i += 1
                    append(start, i, colors.property)
                } else { state.phase = .afterAttribute }
            case .afterAttribute:
                if whitespace(ch) { i += 1 }
                else if ch == 61 { i += 1; state.phase = .beforeValue }
                else { state.phase = .tag }
                append(start, i, colors.tag)
            case .beforeValue:
                if whitespace(ch) { i += 1 }
                else {
                    state.valueQuote = ch == 34 || ch == 39 ? ch : 0
                    state.css = CSSSyntaxState()
                    state.phase = .value
                    if state.valueQuote != 0 { i += 1; append(start, i, colors.string) }
                }
            case .value:
                if (state.valueQuote != 0 && ch == state.valueQuote) || (state.valueQuote == 0 && (whitespace(ch) || ch == 62)) {
                    if state.valueQuote != 0 { i += 1; append(start, i, colors.string) }
                    state.phase = .tag
                } else {
                    while i < end {
                        let c = text.character(at: i)
                        if state.valueQuote != 0 ? c == state.valueQuote : (whitespace(c) || c == 62) { break }
                        i += 1
                    }
                    if state.attributeName == "style" {
                        output += cssRanges(in: text, range: NSRange(location: start, length: i - start), state: &state.css, colors: colors, emitColors: emitColors)
                    } else { append(start, i, colors.string) }
                }
            case .css, .rawText:
                if ch == 60 && isRawClose(at: i) {
                    state.phase = .tagName
                    state.tagName = ""
                    state.closingTag = false
                    i += 1
                    append(start, i, colors.tag)
                } else {
                    i += 1
                    while i < end && !(text.character(at: i) == 60 && isRawClose(at: i)) { i += 1 }
                    if state.phase == .css {
                        output += cssRanges(in: text, range: NSRange(location: start, length: i - start), state: &state.css, colors: colors, emitColors: emitColors)
                    }
                }
            }
        }
        return output
    }

    static func cssRanges(in text: NSString, range: NSRange, state: inout CSSSyntaxState, colors: SyntaxColors, emitColors: Bool = true) -> [(NSRange, Color)] {
        var output: [(NSRange, Color)] = []
        let end = NSMaxRange(range)
        var i = range.location
        var plainStart = i
        func append(_ start: Int, _ finish: Int, _ color: Color) {
            guard emitColors, finish > start else { return }
            if let last = output.last, last.1 == color, NSMaxRange(last.0) == start {
                output[output.count - 1].0.length += finish - start
            } else { output.append((NSRange(location: start, length: finish - start), color)) }
        }
        func plain(_ finish: Int) {
            guard emitColors, finish > plainStart else { return }
            let patterns: [(String, Color)] = [
                (#"@[A-Za-z-]+\b|!important\b"#, colors.keyword),
                (#"[.#][A-Za-z_][A-Za-z0-9_-]*(?=\s*\{)"#, colors.tag),
                (#"(?<![A-Za-z0-9_-])(?:--[A-Za-z_][A-Za-z0-9_-]*|[A-Za-z-]+)(?=\s*:)"#, colors.property),
                (#"\b(?:var|calc|min|max|clamp|rgb|rgba|hsl|hsla|linear-gradient|radial-gradient|url)\s*\("#, colors.builtin),
                (#"(?<![\w.#-])(?:#[0-9A-Fa-f]{3,8}\b|[+-]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][+-]?\d+)?(?:%|[A-Za-z]+)?)(?![\w-])"#, colors.number)
            ]
            for (pattern, color) in patterns {
                guard let regex = cachedSyntaxRegex(pattern: pattern) else { continue }
                for match in regex.matches(in: text as String, range: NSRange(location: plainStart, length: finish - plainStart)) {
                    output.append((match.range, color))
                }
            }
        }
        while i < end {
            let ch = text.character(at: i)
            if state.comment {
                let start = i
                while i < end {
                    if text.character(at: i) == 42 && i + 1 < end && text.character(at: i + 1) == 47 {
                        i += 2; state.comment = false; break
                    }
                    i += 1
                }
                append(start, i, colors.comment)
                plainStart = i
            } else if state.quote != 0 {
                let start = i
                while i < end {
                    let c = text.character(at: i)
                    i += 1
                    if state.escaped { state.escaped = false }
                    else if c == 92 { state.escaped = true }
                    else if c == state.quote { state.quote = 0; break }
                    else if c == 10 || c == 13 { state.quote = 0; break }
                }
                append(start, i, colors.string)
                plainStart = i
            } else if ch == 47 && i + 1 < end && text.character(at: i + 1) == 42 {
                plain(i); state.comment = true; append(i, i + 2, colors.comment); i += 2; plainStart = i
            } else if ch == 34 || ch == 39 {
                plain(i); state.quote = ch; append(i, i + 1, colors.string); i += 1; plainStart = i
            } else { i += 1 }
        }
        plain(end)
        return output
    }

    /// Retain short delimiters at an artificial read boundary. Names themselves
    /// are accumulated by the scanner, so even an extremely long line is bounded.
    static func safePrefixLength(_ text: NSString) -> Int {
        var cut = max(0, text.length - 32)
        let searchStart = max(0, cut - 16)
        for index in searchStart..<cut where text.character(at: index) == 60 { cut = index; break }
        while cut > 0 && [45, 47, 42].contains(text.character(at: cut - 1)) && text.length - cut < 64 { cut -= 1 }
        // Never split a UTF-16 surrogate pair.
        if cut > 0 && (0xD800...0xDBFF).contains(text.character(at: cut - 1)) { cut -= 1 }
        return cut
    }
}
