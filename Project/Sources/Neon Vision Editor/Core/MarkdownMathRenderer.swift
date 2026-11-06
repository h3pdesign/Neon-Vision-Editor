import Foundation
import JavaScriptCore

/// Render bundled KaTeX in JavaScriptCore, not in the document's WebView.
/// Preview, copied HTML and PDF export all receive the same inert markup.
nonisolated enum MarkdownMathRenderer {
    private static let engine = NVELock<JSValue?>({
        guard let url = Bundle.main.url(forResource: "katex.min", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { return nil }
        context.evaluateScript(script)
        return context.objectForKeyedSubscript("katex")?.objectForKeyedSubscript("renderToString")
    }())

    static func render(_ source: String, display: Bool) -> String {
        engine.withLock { function in
            let options: [String: Any] = [
                "displayMode": display, "throwOnError": false, "trust": false,
                "strict": "ignore", "maxExpand": 1000, "maxSize": 20
            ]
            guard let function, !function.isUndefined,
                  let result = function.call(withArguments: [source, options]),
                  !result.isUndefined, let html = result.toString() else {
                return "<code class=\"math-error\" title=\"Formula renderer unavailable\">\(escape(source))</code>"
            }
            return html
        }
    }

    private static let bundledCSS: String = {
        guard let url = Bundle.main.url(forResource: "katex.min", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return css + """

        .markdown-math-display { max-width: 100%; overflow-x: auto; padding: 0.25em 0; }
        .markdown-math-display .katex-display { margin: 0.6em 0; }
        .katex-display { overflow-x: auto; overflow-y: hidden; padding: 0.2em 0; }
        """
    }()

    static func stylesheet(for body: String) -> String {
        body.contains("class=\"katex") ? bundledCSS : ""
    }

    struct ProtectedInline {
        let text: String
        let replacements: [(token: String, source: String, original: String, display: Bool)]

        func restoring(in html: String) -> String {
            replacements.reduce(html) {
                $0.replacingOccurrences(of: $1.token, with: MarkdownMathRenderer.render($1.source, display: $1.display))
            }
        }

        func restoringSource(in text: String) -> String {
            replacements.reduce(text) { $0.replacingOccurrences(of: $1.token, with: $1.original) }
        }
    }

    /// Protect formulas before Markdown emphasis, links and HTML escaping run.
    /// Code, image markup, link destinations and HTML attributes remain literal.
    static func protectInline(in text: String) -> ProtectedInline {
        guard text.contains("$") || text.contains(#"\("#) || text.contains(#"\["#) else {
            return ProtectedInline(text: text, replacements: [])
        }
        var output = ""
        var replacements: [(token: String, source: String, original: String, display: Bool)] = []
        let prefix = "NVEMATH\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))TOKEN"
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            var literalEnd: String.Index?
            if text[index] == "`", !isEscaped(index, in: text) {
                let fence = String(rest.prefix(while: { $0 == "`" }))
                let start = text.index(index, offsetBy: fence.count)
                literalEnd = text.range(of: fence, range: start..<text.endIndex)?.upperBound
                    ?? start
            } else if text[index] == "<", let end = rest.firstIndex(of: ">") {
                literalEnd = text.index(after: end)
            } else if rest.hasPrefix("https://") || rest.hasPrefix("http://") {
                literalEnd = rest.firstIndex(where: { $0.isWhitespace || $0 == "<" || $0 == ">" })
                    ?? text.endIndex
            } else if rest.hasPrefix("!["), let end = rest.firstIndex(of: ")") {
                literalEnd = text.index(after: end)
            } else if text[index] == "(", index > text.startIndex,
                      text[text.index(before: index)] == "]", let end = rest.firstIndex(of: ")") {
                literalEnd = text.index(after: end)
            }
            if let literalEnd {
                output += text[index..<literalEnd]
                index = literalEnd
                continue
            }

            let delimiter: (open: String, close: String, display: Bool)?
            if isEscaped(index, in: text) {
                delimiter = nil
            } else if rest.hasPrefix("$$") {
                delimiter = ("$$", "$$", true)
            } else if rest.hasPrefix("$") {
                delimiter = ("$", "$", false)
            } else if rest.hasPrefix(#"\("#) {
                delimiter = (#"\("#, #"\)"#, false)
            } else if rest.hasPrefix(#"\["#) {
                delimiter = (#"\["#, #"\]"#, true)
            } else {
                delimiter = nil
            }
            if let delimiter {
                let start = text.index(index, offsetBy: delimiter.open.count)
                if let end = closingDelimiter(delimiter.close, in: text, after: start) {
                    let source = String(text[start..<end.lowerBound])
                    let followedByDigit = end.upperBound < text.endIndex && text[end.upperBound].isNumber
                    let balancedPadding = source.first?.isWhitespace == source.last?.isWhitespace
                    if !source.trimmingCharacters(in: .whitespaces).isEmpty,
                       !source.contains("\n"),
                       !(delimiter.open == "$" && (followedByDigit || !balancedPadding)) {
                        let token = "\(prefix)\(replacements.count)END"
                        replacements.append((token, source, String(text[index..<end.upperBound]), delimiter.display))
                        output += token
                        index = end.upperBound
                        continue
                    }
                }
                // Consume the entire opener, so an unmatched $$ is not re-read as $.
                output += delimiter.open
                index = start
                continue
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return ProtectedInline(text: output, replacements: replacements)
    }

    static func displayBlock(in lines: [String], at index: Int, quoted: Bool) -> (source: String, nextLine: Int)? {
        func content(_ line: String) -> String? {
            var value = line.trimmingCharacters(in: .whitespaces)
            if quoted {
                guard value.hasPrefix(">") else { return nil }
                value = value.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            return value
        }
        guard let first = content(lines[index]) else { return nil }
        let opener: String
        let closer: String
        if first.hasPrefix("$$") { opener = "$$"; closer = "$$" }
        else if first.hasPrefix(#"\["#) { opener = #"\["#; closer = #"\]"# }
        else { return nil }

        var body = String(first.dropFirst(opener.count))
        var lineIndex = index
        while true {
            if let end = closingDelimiter(closer, in: body, after: body.startIndex) {
                guard body[end.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                let source = String(body[..<end.lowerBound])
                guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return (source, lineIndex + 1)
            }
            lineIndex += 1
            guard lineIndex < lines.count, let next = content(lines[lineIndex]) else { return nil }
            body += "\n" + next
        }
    }

    private static func closingDelimiter(_ delimiter: String, in text: String,
                                         after start: String.Index) -> Range<String.Index>? {
        var cursor = start
        while let range = text.range(of: delimiter, range: cursor..<text.endIndex) {
            if !isEscaped(range.lowerBound, in: text) { return range }
            cursor = range.upperBound
        }
        return nil
    }

    private static func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var cursor = index
        var count = 0
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            guard text[cursor] == "\\" else { break }
            count += 1
        }
        return count % 2 == 1
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
