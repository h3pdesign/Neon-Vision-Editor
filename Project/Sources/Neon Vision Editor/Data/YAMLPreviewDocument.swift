import Foundation

/// A source preview, not a YAML decoder: comments, tags, and original spelling survive.
nonisolated struct YAMLPreviewDocument: Sendable {
    static let maximumBytes = 16 * 1_024 * 1_024
    let pages: [String]

    static func supports(extension fileExtension: String?, language: String) -> Bool {
        ["yaml", "yml"].contains(fileExtension?.lowercased() ?? "") ||
        ["yaml", "yml"].contains(language.lowercased())
    }

    static func prepare(_ source: String) throws -> Self {
        guard source.utf8.count <= maximumBytes else {
            throw JSONPreviewDocument.Failure(message: "YAML preview supports up to 16 MB. The source remains available in the editor.")
        }
        var pages: [String] = []
        var start = source.startIndex
        var index = start
        var scalars = 0
        var lines = 0
        // Bound even a single enormous line, without losing or splitting Unicode scalars.
        while index < source.endIndex {
            try Task.checkCancellation()
            if source.unicodeScalars[index] == "\n" { lines += 1 }
            source.unicodeScalars.formIndex(after: &index)
            scalars += 1
            if lines >= 200 || scalars >= 16_384 {
                pages.append(String(source[start..<index]))
                start = index
                scalars = 0
                lines = 0
            }
        }
        if start < source.endIndex || pages.isEmpty { pages.append(String(source[start...])) }
        return Self(pages: pages)
    }

    static func html(for source: String) throws -> String {
        // Match raw source before escaping: HTML entities must never become YAML tokens.
        let patterns: [(String, String)] = [
            (#"\"(?:[^\"\\]|\\.)*\"|'(?:[^']|'')*'"#, "string"),
            (#"(?<!\S)#.*$"#, "comment"),
            (#"[\w.-]+(?=:[ \t\r\n]|:$)"#, "key"),
            (#"(?<![\w.-])(?:true|false|null|yes|no|on|off|~)(?![\w.-])"#, "atom"),
            (#"(?<![\w.-])-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?(?![\w.-])"#, "number"),
            (#"[&*!][A-Za-z0-9_./:-]+|^---$|^\.\.\.$|(?<!\S)[|>][-+]?(?=[ \t]*(?:#|$))"#, "meta")
        ]
        let regex = try NSRegularExpression(pattern: patterns.map { "(\($0.0))" }.joined(separator: "|"), options: [.anchorsMatchLines])
        let text = source as NSString
        var output = ""
        var end = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: text.length)) {
            try Task.checkCancellation()
            output += ContentView.escapedHTML(text.substring(with: NSRange(location: end, length: match.range.location - end)))
            let token = patterns.indices.first { match.range(at: $0 + 1).location != NSNotFound }!
            output += "<span class=\"\(patterns[token].1)\">\(ContentView.escapedHTML(text.substring(with: match.range)))</span>"
            end = NSMaxRange(match.range)
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
