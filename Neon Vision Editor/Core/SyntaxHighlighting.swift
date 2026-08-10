import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif



// MARK: - Regex Cache

private enum SyntaxRegexCache {
    nonisolated static let storage = NVELock<[String: NSRegularExpression]>([:])
}

/// Lets queued syntax work stop between regex passes after a newer edit wins.
/// NSRegularExpression cannot interrupt an individual match, so callers check
/// this boundary before starting the next potentially expensive pattern.
nonisolated final class SyntaxHighlightCancellationToken: @unchecked Sendable {
    private let cancelled = NVELock(false)

    func cancel() {
        cancelled.withLock { $0 = true }
    }

    var isCancelled: Bool {
        cancelled.withLock { $0 }
    }
}

// Reuse compiled regex objects across highlight passes to reduce CPU churn while typing/scrolling.
nonisolated func cachedSyntaxRegex(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
    let key = "\(options.rawValue)|\(pattern)"
    if let cached = SyntaxRegexCache.storage.withLock({ $0[key] }) {
        return cached
    }

    guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
        return nil
    }

    return SyntaxRegexCache.storage.withLock { storage in
        if let cached = storage[key] {
            return cached
        }
        storage[key] = compiled
        return compiled
    }
}

struct SyntaxColors: Sendable {
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

    static func from<T: SyntaxThemeProviding>(theme: T) -> SyntaxColors {
        theme.syntax
    }

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

        func color(_ key: String, fallback: Color) -> Color {
            guard let pair = baseColors[key] else { return fallback }
            return colorScheme == .dark ? pair.dark : pair.light
        }

        return SyntaxColors(
            keyword: color("keyword", fallback: .pink),
            string: color("string", fallback: .purple),
            number: color("number", fallback: .blue),
            comment: color("comment", fallback: .secondary),
            attribute: color("attribute", fallback: .indigo),
            variable: color("variable", fallback: .blue),
            def: color("def", fallback: .green),
            property: color("property", fallback: .green),
            meta: color("meta", fallback: .red),
            tag: color("tag", fallback: .purple),
            atom: color("atom", fallback: .blue),
            builtin: color("builtin", fallback: .orange),
            type: color("type", fallback: .purple)
        )
    }
}

/// Minimal dependency boundary so standalone syntax regression tools do not
/// need to compile the full SwiftUI theme implementation.
protocol SyntaxThemeProviding {
    var syntax: SyntaxColors { get }
}

// MARK: - Syntax Pattern Models

enum SyntaxPatternProfile: Sendable, Equatable {
    case full
    case htmlFast
    case csvFast
    case jsonFast
}

nonisolated func isSyntaxHighlightRangeValid(_ range: NSRange, utf16Length: Int) -> Bool {
    guard range.location != NSNotFound, range.length >= 0, range.location >= 0 else { return false }
    return NSMaxRange(range) <= utf16Length
}

// Kept outside the editor view so lightweight platform checks exercise the
// exact scanner used while typing in HTML and XML documents.
nonisolated func fastHTMLSyntaxColorRanges(
    text: NSString,
    in range: NSRange,
    colors: SyntaxColors
) -> [(NSRange, Color)] {
    guard isSyntaxHighlightRangeValid(range, utf16Length: text.length) else { return [] }
    let rangeEnd = NSMaxRange(range)
    var out: [(NSRange, Color)] = []
    var i = range.location

    func isWhitespace(_ codeUnit: unichar) -> Bool {
        codeUnit == 9 || codeUnit == 10 || codeUnit == 13 || codeUnit == 32
    }

    func isNameCharacter(_ codeUnit: unichar) -> Bool {
        (codeUnit >= 65 && codeUnit <= 90) ||
            (codeUnit >= 97 && codeUnit <= 122) ||
            (codeUnit >= 48 && codeUnit <= 57) ||
            codeUnit == 45 || codeUnit == 46 || codeUnit == 58 || codeUnit == 95
    }

    func hasCodeUnits(_ expected: [unichar], at location: Int) -> Bool {
        guard location >= range.location, location + expected.count <= rangeEnd else { return false }
        for offset in expected.indices where text.character(at: location + offset) != expected[offset] {
            return false
        }
        return true
    }

    func appendCSSSyntaxRanges(in cssRange: NSRange) {
        let patterns: [(String, Color)] = [
            (#"(?s)/\*.*?\*/"#, colors.comment),
            (#"(?m)@(?:charset|import|media|supports|keyframes|font-face|layer|container|property)\b"#, colors.keyword),
            (#"(?m)[.#][A-Za-z_][A-Za-z0-9_-]*(?=\s*\{)"#, colors.tag),
            (#"(?<![A-Za-z0-9_-])(?:--[A-Za-z_][A-Za-z0-9_-]*|[A-Za-z-]+)(?=\s*:)"#, colors.property),
            (#"\b(?:var|calc|min|max|clamp|rgb|rgba|hsl|hsla|linear-gradient|radial-gradient|url)\s*\("#, colors.builtin),
            (#"#[0-9A-Fa-f]{3,8}\b"#, colors.number),
            (#"\b(?:\d+(?:\.\d+)?|\.\d+)(?:%|[A-Za-z]+)?\b"#, colors.number),
            (#"!important\b"#, colors.keyword),
            (#"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"#, colors.string)
        ]
        for (pattern, color) in patterns {
            guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            for match in regex.matches(in: text as String, range: cssRange) {
                out.append((match.range, color))
            }
        }
    }

    while i < rangeEnd {
        let ch = text.character(at: i)
        if ch == 60 { // <
            if hasCodeUnits([60, 33, 45, 45], at: i) { // <!--
                let commentStart = i
                i += 4
                while i < rangeEnd && !hasCodeUnits([45, 45, 62], at: i) { // -->
                    i += 1
                }
                if i < rangeEnd {
                    i = min(rangeEnd, i + 3)
                }
                out.append((NSRange(location: commentStart, length: i - commentStart), colors.comment))
                continue
            }

            let tagStart = i
            var cursor = i + 1
            var activeQuote: unichar?
            while cursor < rangeEnd {
                let current = text.character(at: cursor)
                if let quote = activeQuote {
                    if current == quote {
                        activeQuote = nil
                    }
                } else if current == 34 || current == 39 { // " or '
                    activeQuote = current
                } else if current == 62 { // >
                    cursor += 1
                    break
                }
                cursor += 1
            }
            let tagEnd = cursor
            let tagRange = NSRange(location: tagStart, length: max(0, tagEnd - tagStart))
            let isDeclaration = tagStart + 1 < rangeEnd && text.character(at: tagStart + 1) == 33 // !
            out.append((tagRange, isDeclaration ? colors.meta : colors.tag))

            var token = tagStart + 1
            if token < tagEnd && text.character(at: token) == 47 { // /
                token += 1
            }
            while token < tagEnd && isWhitespace(text.character(at: token)) {
                token += 1
            }
            while token < tagEnd && isNameCharacter(text.character(at: token)) {
                token += 1
            }
            let tagNameRange = NSRange(location: tagStart + 1, length: max(0, token - tagStart - 1))
            let tagName = tagNameRange.length > 0
                ? text.substring(with: tagNameRange).lowercased()
                : ""

            while token < tagEnd {
                while token < tagEnd {
                    let current = text.character(at: token)
                    if isWhitespace(current) || current == 47 {
                        token += 1
                    } else {
                        break
                    }
                }
                guard token < tagEnd, text.character(at: token) != 62 else { break }

                let attributeStart = token
                while token < tagEnd && isNameCharacter(text.character(at: token)) {
                    token += 1
                }
                guard token > attributeStart else {
                    token += 1
                    continue
                }
                out.append((
                    NSRange(location: attributeStart, length: token - attributeStart),
                    colors.property
                ))

                while token < tagEnd && isWhitespace(text.character(at: token)) {
                    token += 1
                }
                guard token < tagEnd && text.character(at: token) == 61 else { continue } // =
                token += 1
                while token < tagEnd && isWhitespace(text.character(at: token)) {
                    token += 1
                }
                guard token < tagEnd else { break }

                let valueStart = token
                let quote = text.character(at: token)
                if quote == 34 || quote == 39 {
                    token += 1
                    while token < tagEnd && text.character(at: token) != quote {
                        token += 1
                    }
                    if token < tagEnd {
                        token += 1
                    }
                } else {
                    while token < tagEnd {
                        let current = text.character(at: token)
                        if isWhitespace(current) || current == 62 {
                            break
                        }
                        token += 1
                    }
                }
                if token > valueStart {
                    out.append((NSRange(location: valueStart, length: token - valueStart), colors.string))
                }
            }

            if tagName == "style", tagStart + 1 < rangeEnd, text.character(at: tagStart + 1) != 47 {
                let styleStart = tagEnd
                let remainingRange = NSRange(location: styleStart, length: rangeEnd - styleStart)
                let closingStyle = cachedSyntaxRegex(pattern: #"(?i)</style\s*>"#)?.firstMatch(
                    in: text as String,
                    range: remainingRange
                )
                let styleEnd = closingStyle?.range.location ?? rangeEnd
                if styleEnd > styleStart {
                    appendCSSSyntaxRanges(in: NSRange(location: styleStart, length: styleEnd - styleStart))
                }
                i = styleEnd
                continue
            }

            i = tagEnd
            continue
        }
        if ch == 38 { // &
            let entityStart = i
            var cursor = i + 1
            while cursor < rangeEnd && cursor - entityStart <= 32 {
                let current = text.character(at: cursor)
                if current == 59 { // ;
                    cursor += 1
                    out.append((NSRange(location: entityStart, length: cursor - entityStart), colors.atom))
                    break
                }
                if isWhitespace(current) || current == 60 || current == 62 {
                    break
                }
                cursor += 1
            }
        }
        i += 1
    }
    return out
}

#if os(macOS)
@MainActor
@discardableResult
func applyMacSyntaxForegroundColors(
    to textView: NSTextView,
    in range: NSRange,
    coloredRanges: [(NSRange, Color)]
) -> Bool {
    guard let layoutManager = textView.layoutManager,
          let storage = textView.textStorage,
          isSyntaxHighlightRangeValid(range, utf16Length: storage.length) else {
        return false
    }

    layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
    for (tokenRange, color) in coloredRanges {
        guard isSyntaxHighlightRangeValid(tokenRange, utf16Length: storage.length) else { continue }
        layoutManager.addTemporaryAttribute(
            .foregroundColor,
            value: NSColor(color),
            forCharacterRange: tokenRange
        )
    }
    layoutManager.invalidateDisplay(forCharacterRange: range)
    textView.needsDisplay = true
    return true
}
#endif

struct SyntaxEmphasisPatterns: Sendable {
    let keyword: [String]
    let comment: [String]
    let link: [String]
    let markdownHeading: [String]
}

private nonisolated func canonicalSyntaxLanguage(_ language: String) -> String {
    let normalized = language
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    switch normalized {
    case "py", "python3":
        return "python"
    case "js", "mjs", "cjs":
        return "javascript"
    case "ts", "tsx":
        return "typescript"
    case "htm", "xhtml":
        return "html"
    case "ee", "expression-engine", "expression_engine":
        return "expressionengine"
    case "latex", "bibtex":
        return "tex"
    case "yml":
        return "yaml"
    default:
        return normalized
    }
}

nonisolated func isHTMLLikeSyntaxLanguage(_ language: String) -> Bool {
    canonicalSyntaxLanguage(language) == "html"
}

// MARK: - Syntax Emphasis Profiles

func syntaxEmphasisPatterns(
    for language: String,
    profile: SyntaxPatternProfile = .full
) -> SyntaxEmphasisPatterns {
    switch canonicalSyntaxLanguage(language) {
    case "swift":
        return SyntaxEmphasisPatterns(
            keyword: [
                "\\b(func|struct|class|enum|protocol|extension|actor|if|else|for|while|switch|case|default|guard|defer|throw|try|catch|return|init|deinit|import|typealias|associatedtype|where|public|private|fileprivate|internal|open|static|mutating|nonmutating|inout|async|await|throws|rethrows)\\b",
                "(?m)^#(if|elseif|else|endif|warning|error|available)\\b.*$"
            ],
            comment: [
                "//.*",
                "/\\*([^*]|(\\*+[^*/]))*\\*+/",
                "(?m)^(///).*$",
                "/\\*\\*([\\s\\S]*?)\\*+/"
            ],
            link: [
                "https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+",
                "file://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"
            ],
            markdownHeading: []
        )
    case "ada":
        return SyntaxEmphasisPatterns(
            keyword: [#"(?i)\b(abort|abs|abstract|accept|access|aliased|all|and|array|at|begin|body|case|constant|declare|delay|delta|digits|do|else|elsif|end|entry|exception|exit|for|function|generic|goto|if|in|interface|is|limited|loop|mod|new|not|null|of|or|others|out|overriding|package|pragma|private|procedure|protected|raise|range|record|rem|renames|requeue|return|reverse|select|separate|subtype|synchronized|tagged|task|terminate|then|type|until|use|when|while|with|xor)\b"#],
            comment: [#"(?m)--.*$"#],
            link: [],
            markdownHeading: []
        )
    case "python":
        return SyntaxEmphasisPatterns(
            keyword: ["\\b(def|class|if|else|elif|for|while|try|except|with|as|import|from|return|yield|async|await)\\b"],
            comment: ["#.*"],
            link: [],
            markdownHeading: []
        )
    case "javascript":
        return SyntaxEmphasisPatterns(
            keyword: ["\\b(function|var|let|const|if|else|for|while|do|try|catch|finally|return|class|extends|new|import|export|async|await)\\b"],
            comment: ["//.*|/\\*([^*]|(\\*+[^*/]))*\\*+/"],
            link: [],
            markdownHeading: []
        )
    case "php":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(function|class|interface|trait|namespace|use|public|private|protected|static|final|abstract|if|else|elseif|for|foreach|while|do|switch|case|default|return|try|catch|throw|new|echo)\b"#],
            comment: [#"//.*|#.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "expressionengine":
        return SyntaxEmphasisPatterns(
            keyword: [#"\{if(?::elseif)?\b[^}]*\}|\{\/if\}|\{:else\}"#],
            comment: [#"\{!--[\s\S]*?--\}"#],
            link: [],
            markdownHeading: []
        )
    case "html":
        return SyntaxEmphasisPatterns(
            keyword: [],
            comment: profile == .htmlFast ? [] : [],
            link: [],
            markdownHeading: []
        )
    case "css":
        return SyntaxEmphasisPatterns(keyword: [], comment: [], link: [], markdownHeading: [])
    case "c", "cpp":
        return SyntaxEmphasisPatterns(
            keyword: ["\\b(int|float|double|char|void|if|else|for|while|do|switch|case|return)\\b"],
            comment: ["//.*|/\\*([^*]|(\\*+[^*/]))*\\*+/"],
            link: [],
            markdownHeading: []
        )
    case "json":
        return SyntaxEmphasisPatterns(keyword: [#"\b(true|false|null)\b"#], comment: [], link: [], markdownHeading: [])
    case "markdown":
        return SyntaxEmphasisPatterns(
            keyword: [
                #"(?m)^```[A-Za-z0-9_-]*\s*$|(?m)^~~~[A-Za-z0-9_-]*\s*$"#,
                #"(?m)^\s*[-*+]\s+\[[ xX]\]\s+.*$"#,
                #"(?m)^\s*[-*+]\s+.*$|(?m)^\s*\d+\.\s+.*$"#
            ],
            comment: [
                #"(?m)^\s{0,3}>\s?.*$"#,
                #"(?s)<!--.*?-->"#
            ],
            link: [
                #"!\[[^\]\n]*\]\([^)]+\)"#,
                #"\[[^\]]+\]\([^)]+\)"#,
                #"(?m)^\s{0,3}\[[^\]\n]+\]:\s+\S+.*$"#,
                #"<https?://[^>\s]+>"#,
                #"https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"#
            ],
            markdownHeading: [
                #"(?m)^\s{0,3}#{1,6}\s+.*$"#,
                #"(?m)^\s{0,3}(=+|-+)\s*$"#
            ]
        )
    case "tex":
        return SyntaxEmphasisPatterns(
            keyword: [#"\\[A-Za-z@]+(\*?)"#],
            comment: [#"(?m)%.*$"#],
            link: [],
            markdownHeading: []
        )
    case "bash":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|in|select|until|time)\b"#],
            comment: [#"#.*"#],
            link: [],
            markdownHeading: []
        )
    case "zsh":
        return SyntaxEmphasisPatterns(
            keyword: ["\\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|in|autoload|typeset|setopt|unsetopt)\\b"],
            comment: ["#.*"],
            link: [],
            markdownHeading: []
        )
    case "powershell":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(function|param|if|else|elseif|foreach|for|while|switch|break|continue|return|try|catch|finally)\b"#],
            comment: [#"#.*"#],
            link: [],
            markdownHeading: []
        )
    case "java":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(class|interface|enum|public|private|protected|static|final|void|int|double|float|boolean|new|return|if|else|for|while|switch|case)\b"#],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "kotlin":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(class|object|fun|val|var|when|if|else|for|while|return|import|package|interface)\b"#],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "go":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(package|import|func|var|const|type|struct|interface|if|else|for|switch|case|return|go|defer)\b"#],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "ruby":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(def|class|module|if|else|elsif|end|do|while|until|case|when|begin|rescue|ensure|return)\b"#],
            comment: [#"#.*"#],
            link: [],
            markdownHeading: []
        )
    case "rust":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(fn|let|mut|struct|enum|impl|trait|pub|use|mod|if|else|match|loop|while|for|return)\b"#],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "typescript":
        return SyntaxEmphasisPatterns(
            keyword: [
                #"\b(function|class|interface|type|enum|const|let|var|if|else|for|while|do|try|catch|finally|return|extends|implements|import|export|from|as|async|await|new|throw|switch|case|default|break|continue|in|of|instanceof|typeof|void|delete|yield|public|private|protected|readonly|static|abstract|declare|namespace|module|keyof|infer|is|satisfies|asserts|constructor|override|get|set)\b"#,
                #"@[A-Za-z_$][A-Za-z0-9_$]*"#
            ],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "objective-c":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(if|else|for|while|switch|case|return)\b"#],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "sql":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(SELECT|INSERT|UPDATE|DELETE|CREATE|TABLE|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|GROUP|BY|ORDER|LIMIT|VALUES|INTO)\b"#],
            comment: [#"--.*"#],
            link: [],
            markdownHeading: []
        )
    case "xml":
        return SyntaxEmphasisPatterns(keyword: [], comment: [], link: [], markdownHeading: [])
    case "yaml":
        return SyntaxEmphasisPatterns(
            keyword: [#"(?m)^(\s*)-\s"#, #"\b(true|false|null|yes|no|on|off)\b"#],
            comment: [#"(?m)#.*$"#],
            link: [],
            markdownHeading: []
        )
    case "toml":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(true|false)\b"#],
            comment: [#"(?m)#.*$"#],
            link: [],
            markdownHeading: []
        )
    case "nix":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(assert|else|if|in|inherit|let|or|rec|then|with|true|false|null)\b"#],
            comment: [#"(?m)#.*$|(?s)/\*.*?\*/"#],
            link: [#"https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"#],
            markdownHeading: []
        )
    case "eml":
        return SyntaxEmphasisPatterns(
            keyword: [#"(?mi)^(from|to|cc|bcc|subject|date|message-id|reply-to|sender|mime-version|content-type|content-transfer-encoding|content-disposition|received|return-path|authentication-results):"#],
            comment: [#"(?m)^>.*$"#],
            link: [
                #"https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"#,
                #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#
            ],
            markdownHeading: []
        )
    case "csv":
        return SyntaxEmphasisPatterns(keyword: [], comment: [], link: [], markdownHeading: [])
    case "ini":
        return SyntaxEmphasisPatterns(keyword: [], comment: ["^;.*$"], link: [], markdownHeading: [])
    case "vim":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(set|let|if|endif|for|endfor|while|endwhile|function|endfunction|command|autocmd|syntax|highlight|nnoremap|inoremap|vnoremap|map|nmap|imap|vmap)\b"#],
            comment: [#"^\s*\".*$"#],
            link: [],
            markdownHeading: []
        )
    case "log":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(ERROR|ERR|FATAL|WARN|WARNING|INFO|DEBUG|TRACE)\b"#],
            comment: [],
            link: [#"https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"#],
            markdownHeading: []
        )
    case "crashlog":
        return SyntaxEmphasisPatterns(
            keyword: [#"(?m)^(Process|Path|Identifier|Version|Code Type|Parent Process|Date/Time|OS Version|Report Version|Incident Identifier|Exception Type|Exception Codes|Exception Subtype|Termination Reason|Termination Signal|Crashed Thread|Binary Images):"#],
            comment: [],
            link: [],
            markdownHeading: []
        )
    case "ipynb":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(true|false|null)\b"#],
            comment: [],
            link: [],
            markdownHeading: []
        )
    case "csharp":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(class|interface|enum|struct|namespace|using|public|private|protected|internal|static|readonly|sealed|abstract|virtual|override|async|await|new|return|if|else|for|foreach|while|do|switch|case|break|continue|try|catch|finally|throw)\b"#],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "cobol":
        return SyntaxEmphasisPatterns(
            keyword: [#"(?i)\b(identification|environment|data|procedure|division|section|program-id|author|installati?on|date-written|date-compiled|working-storage|linkage|file-control|input-output|select|assign|fd|01|77|88|level|pic|picture|value|values|move|add|subtract|multiply|divide|compute|if|else|end-if|evaluate|when|perform|until|varying|go|to|goback|stop|run|call|accept|display|open|close|read|write|rewrite|delete|string|unstring|initialize|set|inspect)\b"#],
            comment: [#"(?m)^\s*\*.*$|(?m)^\s*\*>.*$"#],
            link: [],
            markdownHeading: []
        )
    case "dotenv":
        return SyntaxEmphasisPatterns(keyword: [], comment: [#"(?m)#.*$"#], link: [], markdownHeading: [])
    case "proto":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(syntax|package|import|option|message|enum|service|rpc|returns|repeated|map|oneof|reserved|required|optional)\b"#],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#],
            link: [],
            markdownHeading: []
        )
    case "graphql":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(type|interface|enum|union|input|scalar|schema|extend|implements|directive|on|query|mutation|subscription|fragment)\b"#],
            comment: [#"(?m)#.*$"#],
            link: [],
            markdownHeading: []
        )
    case "rst":
        return SyntaxEmphasisPatterns(
            keyword: [#"(?m)^\s*([=\-`:'\"~^_*+<>#]{3,})\s*$"#],
            comment: [#"(?m)#.*$"#],
            link: [],
            markdownHeading: []
        )
    case "nginx":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(http|server|location|upstream|map|if|set|return|rewrite|proxy_pass|listen|server_name|root|index|try_files|include|error_page|access_log|error_log|gzip|ssl|add_header)\b"#],
            comment: [#"(?m)#.*$"#],
            link: [],
            markdownHeading: []
        )
    case "standard":
        return SyntaxEmphasisPatterns(
            keyword: [#"\b(if|else|for|while|do|switch|case|return|class|struct|enum|func|function|var|let|const|import|from|using|namespace|public|private|protected|static|void|new|try|catch|finally|throw)\b"#],
            comment: [#"//.*|/\*([^*]|(\*+[^*/]))*\*+/|#.*"#],
            link: [#"https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"#],
            markdownHeading: []
        )
    case "plain":
        return SyntaxEmphasisPatterns(keyword: [], comment: [], link: [], markdownHeading: [])
    default:
        return SyntaxEmphasisPatterns(keyword: [], comment: [], link: [], markdownHeading: [])
    }
}

// MARK: - Syntax Pattern Lookup

// Regex patterns per language mapped to colors. Keep light-weight for performance.
func getSyntaxPatterns(
    for language: String,
    colors: SyntaxColors,
    profile: SyntaxPatternProfile = .full
) -> [String: Color] {
    let canonical = canonicalSyntaxLanguage(language)
    switch canonical {
    case "swift":
        return [
            // Keywords (extended to include `import`)
            "\\b(func|struct|class|enum|protocol|extension|actor|if|else|for|while|switch|case|default|guard|defer|throw|try|catch|return|init|deinit|import|typealias|associatedtype|where|public|private|fileprivate|internal|open|static|mutating|nonmutating|inout|async|await|throws|rethrows)\\b": colors.keyword,

            // Strings and Characters
            "\"[^\"]*\"": colors.string,
            "'[^'\\](?:\\.[^'\\])*'": colors.string,

            // Numbers
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,
            "\\b0x[0-9A-Fa-f]+\\b": colors.number,
            "\\b0b[01]+\\b": colors.number,

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
            "\\b(self|super)\\b": colors.variable,

            // Common Swift types
            "\\b(String|Int|Double|Bool|Float|UInt|Int64|CGFloat|Any|AnyObject|Void|Never|Self)\\b": colors.type,
            "\\b(true|false|nil)\\b": colors.atom,

            // Function and type names
            "\\bfunc\\s+([A-Za-z_][A-Za-z0-9_]*)": colors.def,
            "\\b(class|struct|enum|protocol|actor)\\s+([A-Za-z_][A-Za-z0-9_]*)": colors.type,

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
    case "ada":
        return [
            #"(?i)\b(abort|abs|abstract|accept|access|aliased|all|and|array|at|begin|body|case|constant|declare|delay|delta|digits|do|else|elsif|end|entry|exception|exit|for|function|generic|goto|if|in|interface|is|limited|loop|mod|new|not|null|of|or|others|out|overriding|package|pragma|private|procedure|protected|raise|range|record|rem|renames|requeue|return|reverse|select|separate|subtype|synchronized|tagged|task|terminate|then|type|until|use|when|while|with|xor)\b"#: colors.keyword,
            #"(?i)\b(boolean|character|duration|float|integer|natural|positive|string)\b"#: colors.type,
            #"(?i)\b(true|false|null)\b"#: colors.atom,
            #"\"(?:[^\"]|\"\")*\"|'[^']'"#: colors.string,
            #"\b(?:\d+(?:_\d+)*(?:\.\d+(?:_\d+)*)?(?:[Ee][+-]?\d+(?:_\d+)*)?)\b"#: colors.number,
            #"(?m)--.*$"#: colors.comment,
            #"'[A-Za-z][A-Za-z0-9_]*"#: colors.attribute
        ]
    case "python":
        return [
            "\\b(def|class|if|else|elif|for|while|try|except|with|as|import|from|return|yield|async|await)\\b": colors.keyword,
            "\\b(int|str|float|bool|list|dict|set|tuple|None|True|False)\\b": colors.type,
            "@\\w+": colors.attribute,
            "\"[^\"]*\"|'[^']*'": colors.string,
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,
            "#.*": colors.comment
        ]
    case "javascript":
        return [
            "\\b(function|var|let|const|if|else|for|while|do|try|catch|finally|return|class|extends|new|import|export|async|await)\\b": colors.keyword,
            "\\b(Number|String|Boolean|Object|Array|Map|Set|Promise|Date)\\b": colors.type,
            "\\b(true|false|null|undefined)\\b": colors.atom,
            "\"[^\"]*\"|'[^']*'|\\`[^\\`]*\\`": colors.string,
            "\\b([0-9]+(\\.[0-9]+)?)\\b": colors.number,
            "//.*|/\\*([^*]|(\\*+[^*/]))*\\*+/": colors.comment
        ]
    case "php":
        return [
            #"\b(function|class|interface|trait|namespace|use|public|private|protected|static|final|abstract|if|else|elseif|for|foreach|while|do|switch|case|default|return|try|catch|throw|new|echo)\b"#: colors.keyword,
            #"\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]+\}"#: colors.variable,
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            #"//.*|#.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment,
            #"<\?php|\?>"#: colors.meta
        ]
    case "expressionengine":
        return [
            #"\{!--[\s\S]*?--\}"#: colors.comment,
            #"\{/?exp:[A-Za-z0-9_:-]+[^}]*\}"#: colors.tag,
            #"\{if(?::elseif)?\b[^}]*\}|\{\/if\}|\{:else\}"#: colors.keyword,
            #"\{[A-Za-z_][A-Za-z0-9_:-]*\}"#: colors.variable,
            #"[A-Za-z_][A-Za-z0-9_:-]*\s*="#: colors.property,
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "html":
        if profile == .htmlFast {
            return [
                // Fast path for very large HTML: focus on structural readability.
                "<[/!A-Za-z][^>]*>": colors.tag,
                "\\b[a-zA-Z_:][-a-zA-Z0-9_:.]*(?=\\s*=)": colors.property
            ]
        }
        return [
            #"(?s)<!--.*?-->"#: colors.comment,
            #"<!DOCTYPE\s+[^>]+>"#: colors.meta,
            #"</?[A-Za-z][A-Za-z0-9:-]*"#: colors.tag,
            #"\b[A-Za-z_:][A-Za-z0-9_:.-]*(?=\s*=)"#: colors.property,
            #""[^"\n]*"|'[^'\n]*'"#: colors.string,
            #"&(?:#\d+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);"#: colors.atom
        ]
    case "css":
        return [
            "\\b([a-zA-Z-]+)\\s*:": colors.property,
            "#[0-9A-Fa-f]{3,6}\\b": colors.number,
            "\"[^\"]*\"|'[^']*'": colors.string
        ]
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
            #"\"[^\"]+\"\s*:"#: colors.property,
            #"\"([^\"\\]|\\.)*\""#: colors.string,
            #"\b(-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?)\b"#: colors.number,
            #"\b(true|false|null)\b"#: colors.keyword,
            #"[{}\[\],:]"#: colors.meta
        ]
    case "markdown":
        return [
            #"(?m)^\s{0,3}---\s*$"#: colors.meta,
            #"(?m)^\s{0,3}#{1,6}\s+.*$"#: colors.meta,
            #"(?m)^\s{0,3}(=+|-+)\s*$"#: colors.meta,
            #"(?m)^\s{0,3}([*\-_])(?:\s*\1){2,}\s*$"#: colors.meta,
            #"(?s)```.*?```|~~~.*?~~~"#: colors.string,
            #"`{1,3}[^`\n]+`{1,3}"#: colors.string,
            #"(?m)^\s{0,3}```[A-Za-z0-9_+.-]*\s*$|(?m)^\s{0,3}~~~[A-Za-z0-9_+.-]*\s*$"#: colors.keyword,
            #"(?m)^\s*[-*+]\s+\[[ xX]\]\s+.*$"#: colors.atom,
            #"(?m)^\s*[-*+]\s+.*$|(?m)^\s*\d+\.\s+.*$"#: colors.keyword,
            #"(?m)^\s{0,3}\|.*\|\s*$"#: colors.property,
            #"(?m)^\s{0,3}\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"#: colors.meta,
            #"\*\*[^*\n]+\*\*|__[^_\n]+__"#: colors.def,
            #"(?<![\w_])_(?!_)[^_\n]+_(?![\w_])|(?<![\w*])\*(?!\*)[^*\n]+\*(?![\w*])"#: colors.def,
            #"~~[^~\n]+~~"#: colors.comment,
            #"!\[[^\]\n]*\]\([^)]+\)"#: colors.type,
            #"\[[^\]\n]+\]\([^)]+\)"#: colors.atom,
            #"(?m)^\s{0,3}\[[^\]\n]+\]:\s+\S+.*$"#: colors.atom,
            #"<https?://[^>\s]+>|https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"#: colors.atom,
            #"(?m)^\s{0,3}>\s?.*$"#: colors.comment,
            #"(?s)<!--.*?-->"#: colors.comment,
            #"(?m)^\s{0,3}[A-Za-z0-9_.-]+:\s+.*$"#: colors.property
        ]
    case "tex":
        return [
            #"\\[A-Za-z@]+(\*?)"#: colors.keyword,
            #"\\begin\{[^}]+\}|\\end\{[^}]+\}"#: colors.meta,
            #"\{[^{}\n]*\}"#: colors.property,
            #"\[[^\]\n]*\]"#: colors.attribute,
            #"\$[^$\n]+\$|\$\$[\s\S]*?\$\$"#: colors.string,
            #"(?m)%.*$"#: colors.comment,
            #"\b[0-9]+(\.[0-9]+)?\b"#: colors.number
        ]
    case "bash":
        return [
            // Keywords and flow control
            #"\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|in|select|until|time)\b"#: colors.keyword,
            // Variables and parameter expansions
            #"\$[A-Za-z_][A-Za-z0-9_]*|\${[^}]+}"#: colors.variable,
            // Command substitution and arithmetic
            #"\$\([^)]*\)|`[^`]*`|\$\(\([^)]*\)\)"#: colors.builtin,
            // Strings
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            // Numbers
            #"\b[0-9]+\b"#: colors.number,
            // Comments
            #"#.*"#: colors.comment,
            // Here-doc markers and redirections/pipes
            #"<<-?\s*[A-Za-z_][A-Za-z0-9_]*"#: colors.meta,
            #"\|\||\|\s|>>?|<<?|2>\&1|2>>?"#: colors.meta
        ]
    case "zsh":
        return [
            "\\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|in|autoload|typeset|setopt|unsetopt)\\b": colors.keyword,
            "\\$[A-Za-z_][A-Za-z0-9_]*|\\${[^}]+}": colors.variable,
            "\\b[0-9]+\\b": colors.number,
            "\\\"[^\\\"]*\\\"|'[^']*'": colors.string,
            "#.*": colors.comment
        ]
    case "powershell":
        return [
            // Keywords and statements
            #"\b(function|param|if|else|elseif|foreach|for|while|switch|break|continue|return|try|catch|finally)\b"#: colors.keyword,
            // Cmdlets (Get-*, Set-*, Write-*, etc.)
            #"\b(Get|Set|New|Remove|Add|Clear|Write|Read|Start|Stop|Enable|Disable|Invoke|Test|Out|Select|Where|ForEach)-[A-Za-z][A-Za-z0-9]*\b"#: colors.builtin,
            // Variables
            #"\$[A-Za-z_][A-Za-z0-9_:]*"#: colors.variable,
            // Strings (single, double)
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            // Numbers
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            // Comments
            #"#.*"#: colors.comment
        ]
    case "java":
        return [
            #"\b(class|interface|enum|public|private|protected|static|final|void|int|double|float|boolean|new|return|if|else|for|while|switch|case)\b"#: colors.keyword,
            #"\"[^\"]*\""#: colors.string,
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "kotlin":
        return [
            #"\b(class|object|fun|val|var|when|if|else|for|while|return|import|package|interface)\b"#: colors.keyword,
            #"\"[^\"]*\"|`[^`]*`"#: colors.string,
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "go":
        return [
            #"\b(package|import|func|var|const|type|struct|interface|if|else|for|switch|case|return|go|defer)\b"#: colors.keyword,
            #"\"[^\"]*\"|`[^`]*`"#: colors.string,
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "ruby":
        return [
            #"\b(def|class|module|if|else|elsif|end|do|while|until|case|when|begin|rescue|ensure|return)\b"#: colors.keyword,
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            #"#.*"#: colors.comment,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "rust":
        return [
            #"\b(fn|let|mut|struct|enum|impl|trait|pub|use|mod|if|else|match|loop|while|for|return)\b"#: colors.keyword,
            #"\"[^\"]*\""#: colors.string,
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "typescript":
        return [
            #"\b(function|class|interface|type|enum|const|let|var|if|else|for|while|do|try|catch|finally|return|extends|implements|import|export|from|as|async|await|new|throw|switch|case|default|break|continue|in|of|instanceof|typeof|void|delete|yield|public|private|protected|readonly|static|abstract|declare|namespace|module|keyof|infer|is|satisfies|asserts|constructor|override|get|set)\b"#: colors.keyword,
            #"\b(string|number|boolean|bigint|symbol|unknown|never|any|void|null|undefined|object|Record|Partial|Required|Readonly|Pick|Omit|Exclude|Extract|NonNullable|Parameters|ReturnType|InstanceType|Promise|Array|ReadonlyArray|Map|Set|WeakMap|WeakSet|Date|Error|RegExp)\b"#: colors.type,
            #"\b[A-Z][A-Za-z0-9_$]*\b"#: colors.type,
            #"\b(true|false|null|undefined|NaN|Infinity)\b"#: colors.atom,
            #"@[A-Za-z_$][A-Za-z0-9_$]*"#: colors.attribute,
            #"\b(?:function|class|interface|type|enum)\s+[A-Za-z_$][A-Za-z0-9_$]*"#: colors.def,
            #"\b[A-Za-z_$][A-Za-z0-9_$]*(?=\s*=\s*(?:async\s*)?\([^)]*\)\s*(?::\s*[^=\n]+?)?=>)"#: colors.def,
            #"\b(?!if\b|for\b|while\b|switch\b|catch\b|function\b)[A-Za-z_$][A-Za-z0-9_$]*(?=\s*\()"#: colors.def,
            #"(?m)^\s*(?:readonly\s+)?[A-Za-z_$][A-Za-z0-9_$]*\??\s*:"#: colors.property,
            #"(?<=\.)[A-Za-z_$][A-Za-z0-9_$]*\b"#: colors.property,
            #"\$[A-Za-z_$][A-Za-z0-9_$]*|\b(this|super)\b"#: colors.variable,
            #"\"([^\"\\]|\\.)*\"|'([^'\\]|\\.)*'|`([^`\\]|\\.)*`"#: colors.string,
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment,
            #"\b(0x[0-9A-Fa-f]+|0b[01]+|0o[0-7]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?n?)\b"#: colors.number,
            #"=>|\?\?|\?\.|[{}()[\].,;:<>|&=+\-*/%!]"#: colors.meta
        ]
    case "objective-c":
        return [
            #"@\w+"#: colors.attribute,
            #"\b(if|else|for|while|switch|case|return)\b"#: colors.keyword,
            #"\"[^\"]*\""#: colors.string,
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "sql":
        return [
            #"\b(SELECT|INSERT|UPDATE|DELETE|CREATE|TABLE|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|GROUP|BY|ORDER|LIMIT|VALUES|INTO)\b"#: colors.keyword,
            #"'[^']*'|\"[^\"]*\""#: colors.string,
            #"--.*"#: colors.comment,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "xml":
        return [
            #"(?s)<!--.*?-->"#: colors.comment,
            #"<\?xml\s+[^>]+\?>|<!DOCTYPE\s+[^>]+>"#: colors.meta,
            #"</?[A-Za-z][A-Za-z0-9:.-]*"#: colors.tag,
            #"\b[A-Za-z_:][A-Za-z0-9_:.-]*(?=\s*=)"#: colors.property,
            #""[^"\n]*"|'[^'\n]*'"#: colors.string,
            #"&(?:#\d+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);"#: colors.atom
        ]
    case "yaml":
        return [
            #"(?m)^\s*#.*$"#: colors.comment,
            #"(?m)#.*$"#: colors.comment,
            #"(?m)^\s*%[A-Z]+(?:\s+.*)?$"#: colors.meta,
            #"(?m)^\s*(---|\.\.\.)\s*(?:#.*)?$"#: colors.meta,
            #"(?m)^(\s*)-\s"#: colors.keyword,
            #"(?m)^\s*(?:-[ \t]+)?[A-Za-z0-9_.-]+\s*:"#: colors.property,
            #"(?m)^\s*(?:-[ \t]+)?\"([^\"\\]|\\.)*\"\s*:"#: colors.property,
            #"(?m)^\s*(?:-[ \t]+)?'[^']*'\s*:"#: colors.property,
            #"\"([^\"\\]|\\.)*\"|'[^']*'"#: colors.string,
            #"(?m):\s*([|>])[-+]?(\s+#.*)?$"#: colors.attribute,
            #"\b(true|false|null|yes|no|on|off)\b"#: colors.atom,
            #"\b(-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\b"#: colors.number,
            #"&[A-Za-z0-9_-]+|\*[A-Za-z0-9_-]+"#: colors.variable,
            #"!<[^>]+>|![A-Za-z0-9_./:-]+"#: colors.attribute
        ]
    case "toml":
        return [
            #"(?m)^\s*\[\[?[^\]\n]+\]?\]\s*(?:#.*)?$"#: colors.meta,
            #"(?m)^\s*(?:[A-Za-z0-9_-]+|\"[^\"\n]+\"|'[^'\n]+')(?:\s*\.\s*(?:[A-Za-z0-9_-]+|\"[^\"\n]+\"|'[^'\n]+'))*\s*(?==)"#: colors.property,
            #"(?s)\"\"\".*?\"\"\"|'''.*?'''|\"([^\"\\]|\\.)*\"|'[^']*'"#: colors.string,
            #"\b(?:0x[0-9A-Fa-f_]+|0o[0-7_]+|0b[01_]+|[+-]?(?:inf|nan|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+-]?[0-9_]+)?))\b"#: colors.number,
            #"\b\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})?)?\b|\b\d{2}:\d{2}:\d{2}(?:\.\d+)?\b"#: colors.atom,
            #"\b(true|false)\b"#: colors.keyword,
            #"(?m)#.*$"#: colors.comment,
            #"[\[\]{},]"#: colors.meta
        ]
    case "nix":
        return [
            #"\b(assert|else|if|in|inherit|let|or|rec|then|with)\b"#: colors.keyword,
            #"\b(true|false|null)\b"#: colors.atom,
            #"\b(builtins|derivation|import|abort|throw|map|removeAttrs)\b"#: colors.def,
            #"(?m)^\s*[A-Za-z_][A-Za-z0-9_'-]*(?:\.[A-Za-z_][A-Za-z0-9_'-]*)*\s*(?==)"#: colors.property,
            #"(?s)''.*?''|\"([^\"\\]|\\.)*\""#: colors.string,
            #"\$\{[^}\n]+\}"#: colors.variable,
            #"(?:\.{0,2}/|/)[^\s;)}\]]+|<[^>\n]+>"#: colors.atom,
            #"\b(?:0x[0-9A-Fa-f]+|[0-9]+(?:\.[0-9]+)?)\b"#: colors.number,
            #"(?m)#.*$|(?s)/\*.*?\*/"#: colors.comment
        ]
    case "eml":
        return [
            #"(?mi)^(from|to|cc|bcc|subject|date|message-id|in-reply-to|references|reply-to|sender|mime-version|content-type|content-transfer-encoding|content-disposition|received|return-path|delivered-to|authentication-results|dkim-signature):"#: colors.property,
            #"(?mi)^(content-type|content-transfer-encoding|content-disposition|mime-version):.*$"#: colors.meta,
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#: colors.atom,
            #"<[^<>\s]+@[^<>\s]+>"#: colors.variable,
            #"https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"#: colors.atom,
            #"(?mi)\b(text/plain|text/html|multipart/[A-Za-z0-9.+-]+|application/[A-Za-z0-9.+-]+|base64|quoted-printable|7bit|8bit|binary)\b"#: colors.keyword,
            #"(?m)^--[^\s]+(?:--)?$"#: colors.def,
            #"(?m)^>.*$"#: colors.comment,
            #"(?m)^\s+[A-Za-z0-9].*$"#: colors.attribute
        ]
    case "csv":
        if profile == .csvFast {
            return [
                // Fast CSV profile for large datasets: keep only separators/headers/quoted chunks.
                #"(?m)^[^\n,]+(,\s*[^\n,]+)*$"#: colors.meta,
                #"\"([^\"\n]|\"\")*\""#: colors.string,
                #","#: colors.property
            ]
        }
        return [
            #"\A([^\n,]+)(,\s*[^\n,]+)*"#: colors.meta,
            #"\"([^\"\n]|\"\")*\""#: colors.string,
            #"\b(-?[0-9]+(\.[0-9]+)?)\b"#: colors.number,
            #","#: colors.property
        ]
    case "ini":
        return [
            #"^\[[^\]]+\]"#: colors.meta,
            #"^;.*$"#: colors.comment,
            #"^\w+\s*=\s*.*$"#: colors.property
        ]
    case "vim":
        return [
            #"\b(set|let|if|endif|for|endfor|while|endwhile|function|endfunction|command|autocmd|syntax|highlight|nnoremap|inoremap|vnoremap|map|nmap|imap|vmap)\b"#: colors.keyword,
            #"\$[A-Za-z_][A-Za-z0-9_]*|[gbwtslv]:[A-Za-z_][A-Za-z0-9_]*"#: colors.variable,
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            #"^\s*\".*$"#: colors.comment,
            #"\b[0-9]+\b"#: colors.number
        ]
    case "log":
        return [
            #"(?i)\b(FATAL|CRITICAL|FAULT|ERROR|ERR|WARN|WARNING|NOTICE|INFO|DEFAULT|DEBUG|TRACE|VERBOSE)\b"#: colors.keyword,
            #"(?m)^\s*(?:\[)?(?:\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?|[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})(?:\])?"#: colors.meta,
            #"(?m)^\s*at\s+[^\n]+|(?i)(Exception|Traceback|Caused by:|stack trace).*"#: colors.attribute,
            #"\b0x[0-9A-Fa-f]+\b|\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            #"https?://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+"#: colors.atom,
            #"\"(timestamp|time|level|severity|message|msg|event|logger|thread|service)\"\s*:"#: colors.property
        ]
    case "crashlog":
        return [
            #"(?m)^(Process|Path|Identifier|Version|Code Type|Parent Process|Date/Time|OS Version|Report Version|Incident Identifier):"#: colors.meta,
            #"(?m)^(Exception Type|Exception Codes|Exception Subtype|Termination Reason|Termination Signal|Crashed Thread):"#: colors.keyword,
            #"(?m)^Thread\s+\d+(?:\s+Crashed)?\s*:.*$"#: colors.def,
            #"(?m)^Binary Images:$"#: colors.attribute,
            #"\b0x[0-9A-Fa-f]+\b"#: colors.number,
            #"\b(EXC_[A-Z_]+|SIG[A-Z]+|KERN_[A-Z_]+)\b"#: colors.keyword,
            #"(?m)^\s*\d+\s+[^\n]+$"#: colors.variable,
            #"\"(incident|procName|exception|termination|threads|usedImages|faultingThread)\"\s*:"#: colors.property,
            #"\"([^\"\\]|\\.)*\""#: colors.string
        ]
    case "ipynb":
        return [
            #"\"(cells|metadata|source|outputs|execution_count|cell_type|kernelspec|language_info)\"\s*:"#: colors.property,
            #"\"([^\"\\]|\\.)*\""#: colors.string,
            #"\b(-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?)\b"#: colors.number,
            #"\b(true|false|null)\b"#: colors.keyword,
            #"[{}\[\],:]"#: colors.meta
        ]
    case "csharp":
        return [
            #"\b(class|interface|enum|struct|namespace|using|public|private|protected|internal|static|readonly|sealed|abstract|virtual|override|async|await|new|return|if|else|for|foreach|while|do|switch|case|break|continue|try|catch|finally|throw)\b"#: colors.keyword,
            #"\b(string|int|double|float|bool|decimal|char|void|object|var|List<[^>]+>|Dictionary<[^>]+>)\b"#: colors.type,
            #"\"[^\"]*\""#: colors.string,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment
        ]
    case "cobol":
        return [
            #"(?i)\b(identification|environment|data|procedure|division|section|program-id|author|installati?on|date-written|date-compiled|working-storage|linkage|file-control|input-output|select|assign|fd|01|77|88|level|pic|picture|value|values|move|add|subtract|multiply|divide|compute|if|else|end-if|evaluate|when|perform|until|varying|go|to|goback|stop|run|call|accept|display|open|close|read|write|rewrite|delete|string|unstring|initialize|set|inspect)\b"#: colors.keyword,
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            #"(?m)^\s*\*.*$|(?m)^\s*\*>.*$"#: colors.comment
        ]
    case "dotenv":
        return [
            #"(?m)^\s*[A-Z_][A-Z0-9_]*\s*="#: colors.property,
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            #"(?m)#.*$"#: colors.comment
        ]
    case "proto":
        return [
            #"\b(syntax|package|import|option|message|enum|service|rpc|returns|repeated|map|oneof|reserved|required|optional)\b"#: colors.keyword,
            #"\b(int32|int64|uint32|uint64|sint32|sint64|fixed32|fixed64|sfixed32|sfixed64|bool|string|bytes|double|float)\b"#: colors.type,
            #"\"[^\"]*\""#: colors.string,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment
        ]
    case "graphql":
        return [
            #"\b(type|interface|enum|union|input|scalar|schema|extend|implements|directive|on|query|mutation|subscription|fragment)\b"#: colors.keyword,
            #"\b([A-Z][A-Za-z0-9_]*)\b"#: colors.type,
            #"\"[^\"]*\""#: colors.string,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            #"(?m)#.*$"#: colors.comment
        ]
    case "rst":
        return [
            #"(?m)^\s*([=\-`:'\"~^_*+<>#]{3,})\s*$"#: colors.keyword,
            #"(?m)^\s*\.\.\s+[A-Za-z-]+::.*$"#: colors.meta,
            #"(?m)^:?[A-Za-z-]+:\s+.*$"#: colors.property,
            #"\*\*[^*]+\*\*"#: colors.def,
            #"(?m)#.*$"#: colors.comment
        ]
    case "nginx":
        return [
            #"\b(http|server|location|upstream|map|if|set|return|rewrite|proxy_pass|listen|server_name|root|index|try_files|include|error_page|access_log|error_log|gzip|ssl|add_header)\b"#: colors.keyword,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            #"\"[^\"]*\"|'[^']*'"#: colors.string,
            #"(?m)#.*$"#: colors.comment,
            #"[{};]"#: colors.meta
        ]
    case "dockerfile":
        return [
            #"(?mi)^(from|run|cmd|entrypoint|copy|add|workdir|env|arg|expose|volume|user|label|healthcheck|shell|stopsignal|onbuild)\b"#: colors.keyword,
            #"(?mi)^\s*--[A-Za-z-]+(?:=[^\s]+)?"#: colors.attribute,
            #"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#: colors.variable,
            #"(?m)#.*$"#: colors.comment,
            #"\"[^\"]*\"|'[^']*'"#: colors.string
        ]
    case "makefile":
        return [
            #"(?m)^[A-Za-z_.-]+\s*(?::=|\?=|\+=|=)"#: colors.property,
            #"(?m)^[A-Za-z_.-]+\s*:(?!=)"#: colors.def,
            #"\$\([A-Za-z_.-]+\)|\$\{[A-Za-z_.-]+\}"#: colors.variable,
            #"(?m)#.*$"#: colors.comment,
            #"\b(if|else|endif|include|define|endef|foreach|call|eval)\b"#: colors.keyword
        ]
    case "hcl":
        return [
            #"\b(terraform|variable|output|module|resource|data|provider|locals|dynamic|for_each|count|depends_on|true|false|null)\b"#: colors.keyword,
            #"\b[A-Za-z_][A-Za-z0-9_-]*(?=\s*=)"#: colors.property,
            #"\"([^\"\\]|\\.)*\""#: colors.string,
            #"(?m)#.*$|//.*|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment,
            #"[{}\[\]=,:]"#: colors.meta
        ]
    case "fish", "perl", "lua", "r":
        return [
            #"\b(function|func|sub|if|else|elseif|then|end|for|while|repeat|until|in|return|local|my|our|use|library|require|let|set)\b"#: colors.keyword,
            #"\"([^\"\\]|\\.)*\"|'([^'\\]|\\.)*'"#: colors.string,
            #"(?m)#.*$|(?m)--.*$"#: colors.comment,
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number
        ]
    case "xcconfig":
        return [
            #"(?m)^\s*[A-Za-z_][A-Za-z0-9_]*\s*(?==)"#: colors.property,
            #"\$\([A-Za-z_][A-Za-z0-9_]*\)"#: colors.variable,
            #"(?mi)^\s*#(include|if|ifdef|ifndef|else|endif)\b.*$"#: colors.keyword,
            #"(?m)//.*$|/\*([^*]|(\*+[^*/]))*\*+/"#: colors.comment
        ]
    case "strings":
        return [
            #"\"([^\"\\]|\\.)*\""#: colors.string,
            #"(?m)/\*([^*]|(\*+[^*/]))*\*+/|(?m)//.*$"#: colors.comment,
            #"="#: colors.meta
        ]
    case "standard":
        return [
            // Strings (double/single/backtick)
            #"\"[^\"]*\"|'[^']*'|`[^`]*`"#: colors.string,
            // Numbers
            #"\b([0-9]+(\.[0-9]+)?)\b"#: colors.number,
            // Line and block comments for C-like and hash comments
            #"//.*|/\*([^*]|(\*+[^*/]))*\*+/|#.*"#: colors.comment,
            // Common keywords from several languages
            #"\b(if|else|for|while|do|switch|case|return|class|struct|enum|func|function|var|let|const|import|from|using|namespace|public|private|protected|static|void|new|try|catch|finally|throw)\b"#: colors.keyword
        ]
    case "plain":
        return [:]
    default:
        return [:]
    }
}

// Simple sheet to edit and persist API tokens for external AI providers.
