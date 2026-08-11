//
//  TokenKind.swift
//  SyntaxQuicklook
//
//  Token model and syntax highlighter for multiple languages.
//

import Foundation
import UniformTypeIdentifiers

enum TokenKind: Equatable {
    case keyword, type, string, number, comment, punctuation, plain
}

struct Token {
    let range: Range<String.Index>
    let kind: TokenKind
}

struct SyntaxHighlighter {
    private let swiftKeywords: Set<String> = [
        "class","struct","enum","func","let","var","if","else","guard","return","switch","case",
        "import","protocol","extension","public","internal","private","fileprivate","open","static",
        "in","for","while","repeat","break","continue","where","throws","try","catch","do","async","await","actor","nonisolated","final","override"
    ]

    private let jsKeywords: Set<String> = [
        "break","case","catch","class","const","continue","debugger","default","delete","do","else","export","extends","finally","for","function","if","import","in","instanceof","let","new","return","super","switch","this","throw","try","typeof","var","void","while","with","yield","async","await","of","null","true","false","interface","implements","public","private","protected","readonly","declare","namespace","enum","abstract","as","satisfies","keyof","unknown","never","string","number","boolean"
    ]

    private let pythonKeywords: Set<String> = [
        "and","as","assert","async","await","break","case","class","continue","def","del","elif","else","except","finally","for","from","global","if","import","in","is","lambda","match","nonlocal","not","or","pass","raise","return","try","while","with","yield","True","False","None"
    ]

    private let shellKeywords: Set<String> = [
        "case","do","done","elif","else","esac","fi","for","function","if","in","select","then","until","while"
    ]

    private let cLikeKeywords: Set<String> = [
        "auto","break","case","catch","class","const","continue","default","delete","do","else","enum","extends","final","for","func","if","import","inline","interface","namespace","new","operator","package","private","protected","public","return","static","struct","switch","template","throw","try","typedef","using","virtual","void","volatile","while","async","await","fn","impl","let","mut","match","mod","pub","trait","type","var","val","fun","go","defer","package","range","select"
    ]

    private let sqlKeywords: Set<String> = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "GROUP", "BY", "ORDER", "LIMIT", "VALUES", "INTO", "AS", "AND", "OR", "NOT", "NULL"
    ]

    private let dataLanguageKeywords: Set<String> = [
        "true", "false", "null", "include", "resource", "variable", "output", "module", "provider", "terraform", "target", "version", "name", "description"
    ]

    private let scriptingKeywords: Set<String> = [
        "def", "class", "module", "function", "sub", "local", "my", "let", "if", "else", "elsif", "elseif", "for", "foreach", "while", "until", "do", "done", "end", "return", "yield", "begin", "rescue", "ensure", "try", "catch", "throw", "import", "from", "use", "require", "package", "library", "source", "function", "param", "switch", "case", "break", "continue"
    ]

    private let configKeywords: Set<String> = [
        "server", "location", "upstream", "listen", "server_name", "proxy_pass", "include", "set", "map", "syntax", "message", "enum", "service", "rpc", "returns", "type", "interface", "query", "mutation", "subscription", "fragment"
    ]

    func highlight(_ text: String, contentType: UTType, fileExtension: String? = nil) -> [Token] {
        let ext = (fileExtension?.isEmpty == false ? fileExtension : contentType.preferredFilenameExtension)?.lowercased()
        if contentType.conforms(to: .swiftSource) || ext == "swift" {
            return highlightSwift(text)
        } else if contentType.conforms(to: .json) || ["json", "jsonc", "json5"].contains(ext) {
            return highlightJSON(text)
        } else if ext == "md" || ext == "markdown" {
            return highlightMarkdown(text)
        } else if ext == "yaml" || ext == "yml" {
            return highlightYAML(text)
        } else if ["js", "jsx", "ts", "tsx", "mjs", "cjs"].contains(ext) {
            return highlightProgramming(text, keywords: jsKeywords, lineComment: "//")
        } else if ["py", "pyi"].contains(ext) {
            return highlightProgramming(text, keywords: pythonKeywords, lineComment: "#")
        } else if ["sh", "bash", "zsh", "fish", "ps1", "psm1"].contains(ext) {
            return highlightProgramming(text, keywords: shellKeywords, lineComment: "#")
        } else if ["c", "h", "hh", "cc", "cpp", "cxx", "hpp", "m", "mm", "java", "kt", "kts", "go", "rs", "php", "phtml", "cs", "proto"].contains(ext) {
            return highlightProgramming(text, keywords: cLikeKeywords, lineComment: "//")
        } else if ["ada", "adb", "ads", "cob", "cbl", "cobol"].contains(ext) {
            return highlightProgramming(text, keywords: scriptingKeywords, lineComment: "--")
        } else if ["rb", "pl", "pm", "lua", "r"].contains(ext) {
            return highlightProgramming(text, keywords: scriptingKeywords, lineComment: "#")
        } else if ext == "sql" {
            return highlightProgramming(text, keywords: sqlKeywords, lineComment: "--")
        } else if ["toml", "hcl", "tf", "xcconfig", "ini", "env", "dotenv"].contains(ext) {
            return highlightProgramming(text, keywords: dataLanguageKeywords, lineComment: "#")
        } else if ["nix", "nginx", "conf", "vim", "graphql", "gql", "dockerfile", "makefile", "mk"].contains(ext) {
            return highlightProgramming(text, keywords: configKeywords, lineComment: "#")
        } else if ["html", "htm", "xhtml", "xml", "plist", "svg", "eex", "ee", "exp", "tmpl"].contains(ext) {
            return highlightMarkup(text)
        } else if ext == "css" {
            return highlightCSS(text)
        } else if ["tex", "rst", "eml", "log", "crash", "crashlog", "csv", "strings", "ipynb"].contains(ext) {
            return highlightProgramming(text, keywords: scriptingKeywords, lineComment: "#")
        } else if contentType.conforms(to: .plainText) {
            return [Token(range: text.startIndex..<text.endIndex, kind: .plain)]
        } else {
            return [Token(range: text.startIndex..<text.endIndex, kind: .plain)]
        }
    }

    private func highlightSwift(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var i = text.startIndex

        func consumeWhile(_ predicate: (Character) -> Bool) -> Range<String.Index> {
            let start = i
            while i < text.endIndex, predicate(text[i]) { i = text.index(after: i) }
            return start..<i
        }

        while i < text.endIndex {
            let ch = text[i]

            // Comments
            if ch == "/" {
                let next = text.index(after: i)
                if next < text.endIndex {
                    if text[next] == "/" {
                        let start = i
                        while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                        tokens.append(Token(range: start..<i, kind: .comment))
                        continue
                    } else if text[next] == "*" {
                        let start = i
                        i = text.index(after: next)
                        var depth = 1
                        while i < text.endIndex, depth > 0 {
                            if text[i] == "/" {
                                let n2 = text.index(after: i)
                                if n2 < text.endIndex, text[n2] == "*" { depth += 1; i = text.index(after: n2); continue }
                            } else if text[i] == "*" {
                                let n2 = text.index(after: i)
                                if n2 < text.endIndex, text[n2] == "/" { depth -= 1; i = text.index(after: n2); continue }
                            }
                            i = text.index(after: i)
                        }
                        tokens.append(Token(range: start..<i, kind: .comment))
                        continue
                    }
                }
            }

            // Strings
            if ch == "\"" {
                let start = i
                i = text.index(after: i)
                var escaped = false
                while i < text.endIndex {
                    let c = text[i]
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == "\"" { i = text.index(after: i); break }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .string))
                continue
            }

            // Numbers
            if ch.isNumber {
                let start = i
                _ = consumeWhile { $0.isNumber || $0 == "." }
                tokens.append(Token(range: start..<i, kind: .number))
                continue
            }

            // Identifiers / keywords / types
            if ch.isLetter || ch == "_" {
                let start = i
                _ = consumeWhile { $0.isLetter || $0.isNumber || $0 == "_" }
                let word = String(text[start..<i])
                if swiftKeywords.contains(word) {
                    tokens.append(Token(range: start..<i, kind: .keyword))
                } else if word.prefix(1).uppercased() == word.prefix(1) {
                    tokens.append(Token(range: start..<i, kind: .type))
                } else {
                    tokens.append(Token(range: start..<i, kind: .plain))
                }
                continue
            }

            // Punctuation
            if ch.isPunctuation || ch.isSymbol {
                let start = i
                i = text.index(after: i)
                tokens.append(Token(range: start..<i, kind: .punctuation))
                continue
            }

            // Whitespace and others
            let start = i
            i = text.index(after: i)
            tokens.append(Token(range: start..<i, kind: .plain))
        }

        return tokens
    }

    private func highlightJSON(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var i = text.startIndex

        func consumeWhile(_ predicate: (Character) -> Bool) -> Range<String.Index> {
            let start = i
            while i < text.endIndex, predicate(text[i]) { i = text.index(after: i) }
            return start..<i
        }

        while i < text.endIndex {
            let ch = text[i]
            if ch == "\"" {
                let start = i
                i = text.index(after: i)
                var escaped = false
                while i < text.endIndex {
                    let c = text[i]
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == "\"" { i = text.index(after: i); break }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .string))
            } else if ch.isNumber || ch == "-" {
                let start = i
                _ = consumeWhile { $0.isNumber || $0 == "." || $0 == "e" || $0 == "E" || $0 == "-" || $0 == "+" }
                tokens.append(Token(range: start..<i, kind: .number))
            } else if "{}[]:, ".contains(ch) || ch.isWhitespace {
                let start = i
                i = text.index(after: i)
                tokens.append(Token(range: start..<i, kind: .punctuation))
            } else if text[i...].hasPrefix("true") || text[i...].hasPrefix("false") || text[i...].hasPrefix("null") {
                let start = i
                let length = text[i...].hasPrefix("false") ? 5 : 4
                let end = text.index(i, offsetBy: length)
                let isBoundary = end == text.endIndex || text[end].isWhitespace || "{}[],:".contains(text[end])
                if isBoundary {
                    i = end
                    tokens.append(Token(range: start..<i, kind: .keyword))
                } else {
                    i = text.index(after: i)
                    tokens.append(Token(range: start..<i, kind: .plain))
                }
            } else {
                let start = i
                _ = consumeWhile { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
                tokens.append(Token(range: start..<i, kind: .plain))
            }
        }

        return tokens
    }

    // Simple Markdown highlighter: headings, code fences/inline code, emphasis, links, lists
    private func highlightMarkdown(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var i = text.startIndex
        var atLineStart = true

        func consumeWhile(_ predicate: (Character) -> Bool) -> Range<String.Index> {
            let start = i
            while i < text.endIndex, predicate(text[i]) { i = text.index(after: i) }
            return start..<i
        }

        func peek(_ offset: Int) -> Character? {
            var idx = i
            for _ in 0..<offset { if idx == text.endIndex { return nil }; idx = text.index(after: idx) }
            return idx < text.endIndex ? text[idx] : nil
        }

        while i < text.endIndex {
            let ch = text[i]

            // Headings starting with # at line start
            if atLineStart && ch == "#" {
                let start = i
                _ = consumeWhile { $0 == "#" || $0 == " " }
                _ = consumeWhile { $0 != "\n" }
                tokens.append(Token(range: start..<i, kind: .keyword))
                if i < text.endIndex { i = text.index(after: i) }
                atLineStart = true
                continue
            }

            // Lists at line start: -, *, + or 1.
            if atLineStart && (ch == "-" || ch == "*" || ch == "+" || ch.isNumber) {
                let start = i
                if ch.isNumber {
                    _ = consumeWhile { $0.isNumber }
                    if i < text.endIndex, text[i] == "." { i = text.index(after: i) }
                } else {
                    i = text.index(after: i)
                }
                if i < text.endIndex, text[i] == " " { i = text.index(after: i) }
                tokens.append(Token(range: start..<i, kind: .punctuation))
                atLineStart = false
                continue
            }

            // Code fence ``` ... ```
            if ch == "`", peek(1) == "`", peek(2) == "`" {
                let start = i
                i = text.index(i, offsetBy: 3)
                while i < text.endIndex {
                    if text[i] == "`", peek(1) == "`", peek(2) == "`" {
                        i = text.index(i, offsetBy: 3)
                        break
                    }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .string))
                atLineStart = (i < text.endIndex && text[text.index(before: i)] == "\n")
                continue
            }

            // Inline code `...`
            if ch == "`" {
                let start = i
                i = text.index(after: i)
                while i < text.endIndex, text[i] != "`" { i = text.index(after: i) }
                if i < text.endIndex { i = text.index(after: i) }
                tokens.append(Token(range: start..<i, kind: .string))
                atLineStart = (i < text.endIndex && text[text.index(before: i)] == "\n")
                continue
            }

            // Emphasis **bold**, *italic*, __bold__, _italic_, ~~strike~~
            if ch == "*" || ch == "_" || ch == "~" {
                let start = i
                let marker = ch
                let isDouble = (peek(1) == marker)
                if isDouble { i = text.index(i, offsetBy: 2) } else { i = text.index(after: i) }
                while i < text.endIndex {
                    if text[i] == marker {
                        if isDouble {
                            if peek(1) == marker { i = text.index(i, offsetBy: 2); break }
                        } else { i = text.index(after: i); break }
                    }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .type))
                atLineStart = (i < text.endIndex && text[text.index(before: i)] == "\n")
                continue
            }

            // Links [text](url)
            if ch == "[" {
                let start = i
                while i < text.endIndex, text[i] != ")" { i = text.index(after: i) }
                if i < text.endIndex { i = text.index(after: i) }
                tokens.append(Token(range: start..<i, kind: .type))
                atLineStart = (i < text.endIndex && text[text.index(before: i)] == "\n")
                continue
            }

            atLineStart = (ch == "\n")
            let start = i
            i = text.index(after: i)
            tokens.append(Token(range: start..<i, kind: .plain))
        }

        return tokens
    }

    private func highlightYAML(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var i = text.startIndex

        func consumeWhile(_ predicate: (Character) -> Bool) -> Range<String.Index> {
            let start = i
            while i < text.endIndex, predicate(text[i]) { i = text.index(after: i) }
            return start..<i
        }

        func isLineStart(_ index: String.Index) -> Bool {
            if index == text.startIndex { return true }
            let prev = text.index(before: index)
            return text[prev] == "\n"
        }

        while i < text.endIndex {
            let ch = text[i]

            // Comments starting with #
            if ch == "#" {
                let start = i
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                tokens.append(Token(range: start..<i, kind: .comment))
                continue
            }

            // Anchors &name and aliases *name
            if ch == "&" || ch == "*" {
                let start = i
                i = text.index(after: i)
                _ = consumeWhile { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
                tokens.append(Token(range: start..<i, kind: .type))
                continue
            }

            // Block scalars | or > at line start
            if (ch == "|" || ch == ">") && isLineStart(i) {
                let start = i
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                tokens.append(Token(range: start..<i, kind: .string))
                continue
            }

            // Quoted strings
            if ch == "\"" || ch == "'" {
                let quote = ch
                let start = i
                i = text.index(after: i)
                while i < text.endIndex {
                    let c = text[i]
                    if c == quote { i = text.index(after: i); break }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .string))
                continue
            }

            // Keys before colon at line start (skip leading spaces)
            if ch == "\n" { let start = i; i = text.index(after: i); tokens.append(Token(range: start..<i, kind: .plain)); continue }
            var j = i
            while j < text.endIndex, text[j].isWhitespace, text[j] != "\n" { j = text.index(after: j) }
            if j < text.endIndex, text[j] != "\n" {
                var k = j
                while k < text.endIndex, text[k] != ":" && text[k] != "\n" { k = text.index(after: k) }
                if k < text.endIndex, text[k] == ":" {
                    tokens.append(Token(range: j..<k, kind: .keyword))
                    tokens.append(Token(range: k..<text.index(after: k), kind: .punctuation))
                    i = text.index(after: k)
                    continue
                }
            }

            // Numbers and booleans
            if ch.isNumber || ch == "-" {
                let start = i
                _ = consumeWhile { $0.isNumber || $0 == "." || $0 == "-" }
                tokens.append(Token(range: start..<i, kind: .number))
                continue
            }

            if text[i...].lowercased().hasPrefix("true") {
                let start = i; i = text.index(i, offsetBy: 4)
                tokens.append(Token(range: start..<i, kind: .keyword)); continue
            }
            if text[i...].lowercased().hasPrefix("false") {
                let start = i; i = text.index(i, offsetBy: 5)
                tokens.append(Token(range: start..<i, kind: .keyword)); continue
            }
            if text[i...].lowercased().hasPrefix("null") {
                let start = i; i = text.index(i, offsetBy: 4)
                tokens.append(Token(range: start..<i, kind: .keyword)); continue
            }

            // Punctuation and others
            if ch.isPunctuation || ch.isSymbol {
                let start = i
                i = text.index(after: i)
                tokens.append(Token(range: start..<i, kind: .punctuation))
                continue
            }

            let start = i
            i = text.index(after: i)
            tokens.append(Token(range: start..<i, kind: .plain))
        }

        return tokens
    }

    private func highlightJavaScript(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var i = text.startIndex

        func consumeWhile(_ predicate: (Character) -> Bool) -> Range<String.Index> {
            let start = i
            while i < text.endIndex, predicate(text[i]) { i = text.index(after: i) }
            return start..<i
        }

        func peek(_ offset: Int) -> Character? {
            var idx = i
            for _ in 0..<offset { if idx == text.endIndex { return nil }; idx = text.index(after: idx) }
            return idx < text.endIndex ? text[idx] : nil
        }

        while i < text.endIndex {
            let ch = text[i]

            // Regex literal /.../flags (heuristic): only if next isn't / or * and we can find a closing /
            if ch == "/" {
                let n = peek(1)
                if n != "/" && n != "*" {
                    let start = i
                    i = text.index(after: i)
                    var escaped = false
                    var found = false
                    while i < text.endIndex {
                        let c = text[i]
                        if escaped { escaped = false }
                        else if c == "\\" { escaped = true }
                        else if c == "/" { found = true; i = text.index(after: i); break }
                        i = text.index(after: i)
                    }
                    if found {
                        _ = consumeWhile { $0.isLetter }
                        tokens.append(Token(range: start..<i, kind: .string))
                        continue
                    } else {
                        i = start
                    }
                }
            }

            // Line or block comments
            if ch == "/" {
                let next = text.index(after: i)
                if next < text.endIndex {
                    if text[next] == "/" {
                        let start = i
                        while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                        tokens.append(Token(range: start..<i, kind: .comment))
                        continue
                    } else if text[next] == "*" {
                        let start = i
                        i = text.index(after: next)
                        while i < text.endIndex {
                            if text[i] == "*" {
                                let n2 = text.index(after: i)
                                if n2 < text.endIndex, text[n2] == "/" { i = text.index(after: n2); break }
                            }
                            i = text.index(after: i)
                        }
                        tokens.append(Token(range: start..<i, kind: .comment))
                        continue
                    }
                }
            }

            // Strings: ' ', " ", template ` `
            if ch == "\"" || ch == "'" {
                let quote = ch
                let start = i
                i = text.index(after: i)
                var escaped = false
                while i < text.endIndex {
                    let c = text[i]
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == quote { i = text.index(after: i); break }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .string))
                continue
            }
            if ch == "`" {
                let start = i
                i = text.index(after: i)
                while i < text.endIndex {
                    if text[i] == "`" { i = text.index(after: i); break }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .string))
                continue
            }

            // Numbers
            if ch.isNumber {
                let start = i
                _ = consumeWhile { $0.isNumber || $0 == "." }
                tokens.append(Token(range: start..<i, kind: .number))
                continue
            }

            // Identifiers / keywords
            if ch.isLetter || ch == "_" || ch == "$" {
                let start = i
                _ = consumeWhile { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
                let word = String(text[start..<i])
                if jsKeywords.contains(word) {
                    tokens.append(Token(range: start..<i, kind: .keyword))
                } else {
                    tokens.append(Token(range: start..<i, kind: .plain))
                }
                continue
            }

            // Punctuation
            if ch.isPunctuation || ch.isSymbol {
                let start = i
                i = text.index(after: i)
                tokens.append(Token(range: start..<i, kind: .punctuation))
                continue
            }

            // Whitespace and others
            let start = i
            i = text.index(after: i)
            tokens.append(Token(range: start..<i, kind: .plain))
        }

        return tokens
    }

    private func highlightProgramming(
        _ text: String,
        keywords: Set<String>,
        lineComment: String,
        offset: String.Index? = nil,
        in source: String? = nil
    ) -> [Token] {
        var tokens: [Token] = []
        var i = text.startIndex

        func consumeWhile(_ predicate: (Character) -> Bool) -> Range<String.Index> {
            let start = i
            while i < text.endIndex, predicate(text[i]) { i = text.index(after: i) }
            return start..<i
        }

        func hasPrefix(_ prefix: String) -> Bool {
            text[i...].hasPrefix(prefix)
        }

        while i < text.endIndex {
            let ch = text[i]

            if hasPrefix(lineComment) {
                let start = i
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                tokens.append(Token(range: start..<i, kind: .comment))
                continue
            }

            if ch == "/", text.index(after: i) < text.endIndex, text[text.index(after: i)] == "*" {
                let start = i
                i = text.index(i, offsetBy: 2)
                while i < text.endIndex {
                    if text[i] == "*" {
                        let next = text.index(after: i)
                        if next < text.endIndex, text[next] == "/" {
                            i = text.index(after: next)
                            break
                        }
                    }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .comment))
                continue
            }

            if ch == "\"" || ch == "'" || ch == "`" {
                let quote = ch
                let start = i
                i = text.index(after: i)
                var escaped = false
                while i < text.endIndex {
                    let current = text[i]
                    if escaped {
                        escaped = false
                    } else if current == "\\" {
                        escaped = true
                    } else if current == quote {
                        i = text.index(after: i)
                        break
                    }
                    i = text.index(after: i)
                }
                tokens.append(Token(range: start..<i, kind: .string))
                continue
            }

            if ch.isNumber {
                let start = i
                _ = consumeWhile { $0.isNumber || $0 == "." || $0 == "_" }
                tokens.append(Token(range: start..<i, kind: .number))
                continue
            }

            if ch.isLetter || ch == "_" || ch == "$" {
                let start = i
                _ = consumeWhile { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
                let word = String(text[start..<i])
                if keywords.contains(word) {
                    tokens.append(Token(range: start..<i, kind: .keyword))
                } else if word.first?.isUppercase == true {
                    tokens.append(Token(range: start..<i, kind: .type))
                } else {
                    tokens.append(Token(range: start..<i, kind: .plain))
                }
                continue
            }

            let start = i
            i = text.index(after: i)
            tokens.append(Token(range: start..<i, kind: ch.isPunctuation || ch.isSymbol ? .punctuation : .plain))
        }

        guard let offset, let source else { return tokens }
        return tokens.map { Token(range: sourceRange($0.range, local: text, offset: offset, in: source), kind: $0.kind) }
    }

    private func highlightMarkup(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var i = text.startIndex

        while i < text.endIndex {
            if text[i...].hasPrefix("<!--") {
                let start = i
                while i < text.endIndex, !text[i...].hasPrefix("-->") { i = text.index(after: i) }
                if i < text.endIndex { i = text.index(i, offsetBy: 3) }
                tokens.append(Token(range: start..<i, kind: .comment))
                continue
            }

            if text[i...].lowercased().hasPrefix("<style") {
                let contentStart = i
                guard let close = text[contentStart...].range(of: ">") else {
                    i = text.endIndex
                    continue
                }
                let bodyStart = close.upperBound
                guard let endTag = text[bodyStart...].range(of: "</style", options: [.caseInsensitive]) else {
                    tokens.append(contentsOf: highlightCSS(String(text[bodyStart...]), offset: bodyStart, in: text))
                    i = text.endIndex
                    continue
                }
                tokens.append(contentsOf: highlightCSS(String(text[bodyStart..<endTag.lowerBound]), offset: bodyStart, in: text))
                i = endTag.lowerBound
                continue
            }

            if text[i...].lowercased().hasPrefix("<script") {
                let contentStart = i
                guard let close = text[contentStart...].range(of: ">") else {
                    i = text.endIndex
                    continue
                }
                let bodyStart = close.upperBound
                guard let endTag = text[bodyStart...].range(of: "</script", options: [.caseInsensitive]) else {
                    tokens.append(contentsOf: highlightProgramming(String(text[bodyStart...]), keywords: jsKeywords, lineComment: "//", offset: bodyStart, in: text))
                    i = text.endIndex
                    continue
                }
                tokens.append(contentsOf: highlightProgramming(String(text[bodyStart..<endTag.lowerBound]), keywords: jsKeywords, lineComment: "//", offset: bodyStart, in: text))
                i = endTag.lowerBound
                continue
            }

            if text[i] == "<" {
                let tagStart = i
                var quote: Character?
                while i < text.endIndex {
                    let current = text[i]
                    if let activeQuote = quote {
                        if current == activeQuote { quote = nil }
                    } else if current == "\"" || current == "'" {
                        quote = current
                    } else if current == ">" {
                        i = text.index(after: i)
                        break
                    }
                    i = text.index(after: i)
                }
                tokens.append(contentsOf: highlightTag(text[tagStart..<i], offset: tagStart, in: text))
                continue
            }

            let start = i
            i = text.index(after: i)
            tokens.append(Token(range: start..<i, kind: .plain))
        }

        return tokens
    }

    private func highlightTag(_ tag: Substring, offset: String.Index, in source: String) -> [Token] {
        let tagText = String(tag)
        var tokens: [Token] = []
        var index = tagText.startIndex
        var isFirstName = true

        while index < tagText.endIndex {
            let character = tagText[index]
            if character == "\"" || character == "'" {
                let start = index
                let quote = character
                index = tagText.index(after: index)
                while index < tagText.endIndex, tagText[index] != quote { index = tagText.index(after: index) }
                if index < tagText.endIndex { index = tagText.index(after: index) }
                tokens.append(Token(range: sourceRange(start..<index, local: tagText, offset: offset, in: source), kind: .string))
            } else if character.isLetter || character == "_" || character == ":" {
                let start = index
                index = tagText.index(after: index)
                while index < tagText.endIndex, tagText[index].isLetter || tagText[index].isNumber || tagText[index] == "-" || tagText[index] == "_" || tagText[index] == ":" {
                    index = tagText.index(after: index)
                }
                let kind: TokenKind = isFirstName ? .type : .keyword
                isFirstName = false
                tokens.append(Token(range: sourceRange(start..<index, local: tagText, offset: offset, in: source), kind: kind))
            } else {
                let start = index
                index = tagText.index(after: index)
                tokens.append(Token(range: sourceRange(start..<index, local: tagText, offset: offset, in: source), kind: character.isPunctuation || character.isSymbol ? .punctuation : .plain))
            }
        }
        return tokens
    }

    private func highlightCSS(_ text: String, offset: String.Index? = nil, in source: String? = nil) -> [Token] {
        let base = offset ?? text.startIndex
        let original = source ?? text
        var tokens: [Token] = []
        var index = text.startIndex
        var declarationDepth = 0

        func range(_ local: Range<String.Index>) -> Range<String.Index> {
            sourceRange(local, local: text, offset: base, in: original)
        }

        while index < text.endIndex {
            if text[index...].hasPrefix("/*") {
                let start = index
                index = text.index(index, offsetBy: 2)
                while index < text.endIndex, !text[index...].hasPrefix("*/") { index = text.index(after: index) }
                if index < text.endIndex { index = text.index(index, offsetBy: 2) }
                tokens.append(Token(range: range(start..<index), kind: .comment))
                continue
            }
            let character = text[index]
            if character == "\"" || character == "'" {
                let start = index
                let quote = character
                index = text.index(after: index)
                var escaped = false
                while index < text.endIndex {
                    let current = text[index]
                    if escaped { escaped = false }
                    else if current == "\\" { escaped = true }
                    else if current == quote { index = text.index(after: index); break }
                    index = text.index(after: index)
                }
                tokens.append(Token(range: range(start..<index), kind: .string))
            } else if character.isNumber {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, text[index].isNumber || text[index] == "." || text[index].isLetter || text[index] == "%" {
                    index = text.index(after: index)
                }
                tokens.append(Token(range: range(start..<index), kind: .number))
            } else if character == "@" {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, text[index].isLetter || text[index] == "-" { index = text.index(after: index) }
                tokens.append(Token(range: range(start..<index), kind: .keyword))
            } else if character.isLetter || character == "-" || character == "_" {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, text[index].isLetter || text[index].isNumber || text[index] == "-" || text[index] == "_" { index = text.index(after: index) }
                let word = text[start..<index]
                var lookahead = index
                while lookahead < text.endIndex, text[lookahead].isWhitespace { lookahead = text.index(after: lookahead) }
                let kind: TokenKind = declarationDepth > 0 && lookahead < text.endIndex && text[lookahead] == ":" ? .keyword : (word.first == "-" ? .type : .plain)
                tokens.append(Token(range: range(start..<index), kind: kind))
            } else {
                let start = index
                index = text.index(after: index)
                if character == "{" { declarationDepth += 1 }
                if character == "}" { declarationDepth = max(0, declarationDepth - 1) }
                tokens.append(Token(range: range(start..<index), kind: character.isPunctuation || character.isSymbol ? .punctuation : .plain))
            }
        }
        return tokens
    }

    private func sourceRange(_ range: Range<String.Index>, local: String, offset: String.Index, in source: String) -> Range<String.Index> {
        let startOffset = range.lowerBound.utf16Offset(in: local)
        let endOffset = range.upperBound.utf16Offset(in: local)
        let start = source.index(offset, offsetBy: startOffset)
        let length = endOffset - startOffset
        let end = source.index(start, offsetBy: length)
        return start..<end
    }
}
