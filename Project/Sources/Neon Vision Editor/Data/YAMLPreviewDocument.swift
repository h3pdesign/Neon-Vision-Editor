import Foundation

/// A source preview, not a YAML decoder: comments, tags, and original spelling survive.
nonisolated struct YAMLPreviewDocument: Sendable {
    static let maximumBytes = 16 * 1_024 * 1_024
    let pages: [String]
    private let pageTokens: [[Token]]

    private struct Token: Sendable {
        var range: NSRange
        let kind: String
    }

    static func supports(extension fileExtension: String?, language: String) -> Bool {
        ["yaml", "yml"].contains(fileExtension?.lowercased() ?? "") ||
        ["yaml", "yml"].contains(language.lowercased())
    }

    static func prepare(_ source: String) throws -> Self {
        guard source.utf8.count <= maximumBytes else {
            throw JSONPreviewDocument.Failure(message: "YAML preview supports up to 16 MB. The source remains available in the editor.")
        }
        var pages: [String] = []
        var pageOffsets = [0]
        var start = source.startIndex
        var index = start
        var scalars = 0
        var lines = 0
        var utf16Offset = 0
        // Bound even a single enormous line, without losing or splitting Unicode scalars.
        while index < source.endIndex {
            try Task.checkCancellation()
            if source.unicodeScalars[index] == "\n" { lines += 1 }
            utf16Offset += source.unicodeScalars[index].value > 0xFFFF ? 2 : 1
            source.unicodeScalars.formIndex(after: &index)
            scalars += 1
            if lines >= 200 || scalars >= 16_384 {
                pages.append(String(source[start..<index]))
                pageOffsets.append(utf16Offset)
                start = index
                scalars = 0
                lines = 0
            }
        }
        if start < source.endIndex || pages.isEmpty { pages.append(String(source[start...])) }
        var pageTokens = Array(repeating: [Token](), count: pages.count)
        var page = 0
        try lex(source) { range, kind in
            var offset = range.location
            while offset < NSMaxRange(range) {
                while page + 1 < pages.count, offset >= pageOffsets[page + 1] { page += 1 }
                let end = min(NSMaxRange(range), page + 1 < pages.count ? pageOffsets[page + 1] : utf16Offset)
                pageTokens[page].append(Token(range: NSRange(location: offset - pageOffsets[page], length: end - offset), kind: kind))
                offset = end
            }
        }
        return Self(pages: pages, pageTokens: pageTokens)
    }

    func html(forPage page: Int) throws -> String {
        try Self.render(pages[page], tokens: pageTokens[page])
    }

    static func html(for source: String) throws -> String {
        var tokens: [Token] = []
        try lex(source) { tokens.append(Token(range: $0, kind: $1)) }
        return try render(source, tokens: tokens)
    }

    /// Lex the original stream before splitting display pages. Page boundaries
    /// must not turn scalar contents into keys, comments, or implicit values.
    private static func lex(_ source: String, emit: (NSRange, String) -> Void) throws {
        let text = source as NSString
        let number = try NSRegularExpression(pattern: #"^[+-]?(?:[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|\.(?:inf|Inf|INF|nan|NaN|NAN))$"#)
        func space(_ c: unichar) -> Bool { c == 32 || c == 9 }
        func separated(after index: Int, end: Int) -> Bool {
            index + 1 == end || space(text.character(at: index + 1))
        }
        func hasBlockContinuation(after lineEnd: Int, parentIndent: Int) throws -> Bool {
            var next = lineEnd
            while next < text.length {
                try Task.checkCancellation()
                var end = 0
                var contentEnd = 0
                text.getLineStart(nil, end: &end, contentsEnd: &contentEnd, for: NSRange(location: next, length: 0))
                var first = next
                while first < contentEnd, text.character(at: first) == 32 {
                    if first % 1_024 == 0 { try Task.checkCancellation() }
                    first += 1
                }
                if first < contentEnd, text.character(at: first) != 35 { return first - next > parentIndent }
                next = end
            }
            return false
        }
        func hasFlowContinuation(after lineEnd: Int) throws -> Bool {
            var next = lineEnd
            while next < text.length {
                if next % 1_024 == 0 { try Task.checkCancellation() }
                let c = text.character(at: next)
                if c == 35 {
                    text.getLineStart(nil, end: &next, contentsEnd: nil, for: NSRange(location: next, length: 0))
                } else if space(c) || c == 10 || c == 13 { next += 1 }
                else { return ![44, 93, 125].contains(c) }
            }
            return false
        }
        var quote: unichar?
        var block: (parent: Int, indent: Int?)?
        var plainIndent: Int?
        var flowDepth = 0
        var flowPlain = false
        var lineStart = 0
        while lineStart < text.length {
            try Task.checkCancellation()
            var lineEnd = 0
            var contentEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentEnd, for: NSRange(location: lineStart, length: 0))
            var start = lineStart
            while start < contentEnd, text.character(at: start) == 32 {
                if start % 1_024 == 0 { try Task.checkCancellation() }
                start += 1
            }
            let indent = start - lineStart
            defer { lineStart = lineEnd }

            if var scalar = block {
                if start == contentEnd {
                    emit(NSRange(location: lineStart, length: lineEnd - lineStart), "string")
                    continue
                }
                if scalar.indent == nil, indent > scalar.parent { scalar.indent = indent; block = scalar }
                if let required = scalar.indent, indent >= required {
                    emit(NSRange(location: lineStart, length: lineEnd - lineStart), "string")
                    continue
                }
                block = nil
            }
            if quote == nil, let parent = plainIndent {
                if start == contentEnd { continue }
                if text.character(at: start) == 35 {
                    emit(NSRange(location: start, length: contentEnd - start), "comment")
                    continue
                }
                if indent > parent, flowDepth == 0 {
                    var end = start
                    while end < contentEnd {
                        if end % 1_024 == 0 { try Task.checkCancellation() }
                        if text.character(at: end) == 35, space(text.character(at: end - 1)) { break }
                        end += 1
                    }
                    emit(NSRange(location: lineStart, length: end - lineStart), "string")
                    if end < contentEnd { emit(NSRange(location: end, length: contentEnd - end), "comment") }
                    continue
                }
                plainIndent = nil
            }

            var index = quote == nil ? start : lineStart
            var nodeIndent = indent
            while index < contentEnd {
                try Task.checkCancellation()
                let c = text.character(at: index)
                if quote != nil || (!flowPlain && (c == 34 || c == 39)) {
                    let tokenStart = index
                    if quote == nil { quote = c; index += 1 }
                    while index < contentEnd {
                        if index % 1_024 == 0 { try Task.checkCancellation() }
                        let current = text.character(at: index)
                        if quote == 34, current == 92 {
                            index = min(contentEnd, index + 2)
                        } else if current == quote {
                            index += 1
                            if quote == 39, index < contentEnd, text.character(at: index) == 39 {
                                index += 1
                            } else {
                                quote = nil
                                break
                            }
                        } else { index += 1 }
                    }
                    emit(NSRange(location: tokenStart, length: index - tokenStart), "string")
                    continue
                }
                if space(c) { index += 1; continue }
                if c == 35 {
                    emit(NSRange(location: index, length: contentEnd - index), "comment")
                    break
                }
                if c == 91 || c == 123 { flowDepth += 1; index += 1; continue }
                if flowDepth > 0, c == 93 || c == 125 || c == 44 {
                    if c != 44 { flowDepth -= 1 }
                    flowPlain = false
                    index += 1
                    continue
                }
                if (c == 58 && (flowDepth > 0 || separated(after: index, end: contentEnd))) ||
                    ((c == 45 || c == 63) && separated(after: index, end: contentEnd)) {
                    index += 1
                    continue
                }
                let tokenStart = index
                if c == 38 || c == 42 || c == 33 || (c == 37 && index == lineStart) {
                    while index < contentEnd, !space(text.character(at: index)),
                          ![44, 91, 93, 123, 125].contains(text.character(at: index)) {
                        if index % 1_024 == 0 { try Task.checkCancellation() }
                        index += 1
                    }
                    emit(NSRange(location: tokenStart, length: index - tokenStart), "meta")
                    continue
                }
                if flowDepth == 0, c == 124 || c == 62 {
                    index += 1
                    var explicitIndent: Int?
                    var chomping = false
                    while index < contentEnd {
                        let indicator = text.character(at: index)
                        if (49...57).contains(indicator), explicitIndent == nil {
                            explicitIndent = Int(indicator - 48)
                        } else if (indicator == 43 || indicator == 45), !chomping {
                            chomping = true
                        } else { break }
                        index += 1
                    }
                    if index == contentEnd || space(text.character(at: index)) {
                        emit(NSRange(location: tokenStart, length: index - tokenStart), "meta")
                        block = (nodeIndent, explicitIndent.map { nodeIndent + $0 })
                        continue
                    }
                    index = tokenStart
                }
                // A plain scalar is one token: words inside it are not booleans
                // or numbers, and quotes/# without separation are literal text.
                while index < contentEnd {
                    if index % 1_024 == 0 { try Task.checkCancellation() }
                    let current = text.character(at: index)
                    if current == 35, index > tokenStart, space(text.character(at: index - 1)) { break }
                    if current == 58, separated(after: index, end: contentEnd) ||
                        (flowDepth > 0 && index + 1 < contentEnd && [44, 91, 93, 123, 125].contains(text.character(at: index + 1))) { break }
                    if flowDepth > 0, [44, 91, 93, 123, 125].contains(current) { break }
                    index += 1
                }
                var end = index
                while end > tokenStart, space(text.character(at: end - 1)) { end -= 1 }
                guard end > tokenStart else { index += 1; continue }
                let range = NSRange(location: tokenStart, length: end - tokenStart)
                let value = text.substring(with: range)
                let isKey = index < contentEnd && text.character(at: index) == 58
                var kind: String
                if isKey {
                    kind = "key"
                    nodeIndent = tokenStart - lineStart
                } else if ["---", "..."].contains(value), tokenStart == lineStart {
                    kind = "meta"
                    plainIndent = nil
                } else if flowPlain {
                    kind = "string"
                } else if ["true", "True", "TRUE", "false", "False", "FALSE", "null", "Null", "NULL", "~"].contains(value) {
                    kind = "atom"
                } else if number.firstMatch(in: value, range: NSRange(location: 0, length: range.length)) != nil {
                    kind = "number"
                } else {
                    kind = "string"
                }
                if flowDepth == 0, kind == "atom" || kind == "number",
                   try hasBlockContinuation(after: lineEnd, parentIndent: indent) {
                    kind = "string"
                }
                flowPlain = try !isKey && flowDepth > 0 &&
                    (index == contentEnd || text.character(at: index) == 35) &&
                    hasFlowContinuation(after: lineEnd)
                if flowPlain { kind = "string" }
                emit(range, kind)
                if !isKey, kind != "meta", flowDepth == 0 { plainIndent = indent }
            }
        }
    }

    private static func render(_ source: String, tokens: [Token]) throws -> String {
        let text = source as NSString
        var output = ""
        var end = 0
        for token in tokens {
            try Task.checkCancellation()
            output += ContentView.escapedHTML(text.substring(with: NSRange(location: end, length: token.range.location - end)))
            output += "<span class=\"\(token.kind)\">\(ContentView.escapedHTML(text.substring(with: token.range)))</span>"
            end = NSMaxRange(token.range)
        }
        output += ContentView.escapedHTML(text.substring(from: end))
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <style>
        :root { color-scheme: light dark; }
        body { margin: 0; padding: 16px; color: #202124; background: transparent; }
        pre { margin: 0; font: 14px/1.6 ui-monospace, monospace; tab-size: 4; white-space: pre-wrap; overflow-wrap: anywhere; }
        .key { color: #174b96; } .string { color: #146338; } .comment { color: #62646a; }
        .atom, .meta { color: #854700; } .number { color: #7134a2; }
        @media (prefers-color-scheme: dark) {
          body { color: #ececf0; } .key { color: #80baff; } .string { color: #85d6a5; }
          .comment { color: #aaaeb8; } .atom, .meta { color: #ffc078; } .number { color: #cda3ff; }
        }
        </style></head><body><pre aria-label="YAML source"><code>\(output)</code></pre></body></html>
        """
    }
}
