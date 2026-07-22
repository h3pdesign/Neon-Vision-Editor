import Foundation

enum CompletionHeuristics {
    private static let identifierCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    private static let whitespaceCharacters = CharacterSet.whitespacesAndNewlines
    private static let keywordSets: [String: [String]] = [
        "swift": ["actor", "associatedtype", "async", "await", "break", "case", "class", "continue", "default", "defer", "do", "else", "enum", "extension", "fallthrough", "false", "for", "func", "guard", "if", "import", "in", "init", "let", "nil", "protocol", "public", "private", "repeat", "return", "self", "static", "struct", "switch", "throw", "throws", "true", "try", "var", "where", "while"],
        "python": ["and", "as", "async", "await", "break", "class", "continue", "def", "elif", "else", "except", "False", "finally", "for", "from", "if", "import", "in", "is", "None", "not", "or", "pass", "raise", "return", "self", "True", "try", "while", "with", "yield"],
        "javascript": ["async", "await", "break", "case", "catch", "class", "const", "continue", "default", "else", "export", "extends", "false", "finally", "for", "function", "if", "import", "in", "let", "new", "null", "return", "switch", "this", "throw", "true", "try", "typeof", "var", "while"],
        "typescript": ["async", "await", "break", "case", "catch", "class", "const", "continue", "default", "else", "enum", "export", "extends", "false", "finally", "for", "function", "if", "implements", "import", "in", "interface", "let", "namespace", "new", "null", "private", "protected", "public", "readonly", "return", "switch", "this", "throw", "true", "try", "type", "var", "while"],
        "json": ["false", "null", "true"],
        "markdown": ["```", "###", "##", "#", "- ", "1. ", "> "],
        "tex": ["\\begin{}", "\\end{}", "\\section{}", "\\subsection{}", "\\textbf{}", "\\emph{}", "\\item", "\\cite{}", "\\label{}", "\\ref{}"],
        "plain": []
    ]

    struct TokenContext: Equatable {
        let prefix: String
        let nextDocumentText: String
    }

    static func tokenContext(in text: NSString, caretLocation: Int, nextTextLimit: Int = 80) -> TokenContext {
        let prefix = currentIdentifierPrefix(in: text, caretLocation: caretLocation) ?? ""
        let nextLength = min(nextTextLimit, max(0, text.length - caretLocation))
        let nextDocumentText = nextLength > 0 ? text.substring(with: NSRange(location: caretLocation, length: nextLength)) : ""
        return TokenContext(prefix: prefix, nextDocumentText: nextDocumentText)
    }

    static func currentIdentifierPrefix(in text: NSString, caretLocation: Int) -> String? {
        guard caretLocation > 0, caretLocation <= text.length else { return nil }
        var start = caretLocation
        while start > 0, isIdentifierCodeUnit(text.character(at: start - 1)) {
            start -= 1
        }
        guard start < caretLocation else { return nil }
        return text.substring(with: NSRange(location: start, length: caretLocation - start))
    }

    static func localSuggestion(
        in text: NSString,
        caretLocation: Int,
        language: String,
        includeDocumentWords: Bool,
        includeSyntaxKeywords: Bool
    ) -> String? {
        let context = tokenContext(in: text, caretLocation: caretLocation)
        let prefix = context.prefix
        guard prefix.count >= 2 else { return nil }

        let normalizedPrefix = prefix.lowercased()
        var candidates: [String: Int] = [:]

        if includeDocumentWords {
            collectDocumentCandidates(
                into: &candidates,
                in: text,
                caretLocation: caretLocation,
                prefix: prefix,
                normalizedPrefix: normalizedPrefix
            )
        }

        if includeSyntaxKeywords {
            for keyword in syntaxKeywords(for: language) {
                guard let normalized = normalizeCandidate(keyword, prefix: prefix, normalizedPrefix: normalizedPrefix) else { continue }
                let caseBonus = keyword.hasPrefix(prefix) ? 8 : 0
                let score = 120 + caseBonus - min(24, normalized.count - prefix.count)
                candidates[normalized] = max(candidates[normalized] ?? .min, score)
            }
        }

        guard let bestCandidate = candidates
            .sorted(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                if lhs.key.count != rhs.key.count { return lhs.key.count < rhs.key.count }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            })
            .first?
            .key
        else {
            return nil
        }

        let suffix = String(bestCandidate.dropFirst(prefix.count))
        return trimTrailingOverlap(suffix, nextDocumentText: context.nextDocumentText)
    }

    static func sanitizeModelSuggestion(
        _ raw: String,
        currentTokenPrefix: String,
        nextDocumentText: String,
        maxLength: Int = 40,
        allowsNaturalLanguage: Bool = false
    ) -> String {
        let preservesLeadingSpace = allowsNaturalLanguage && currentTokenPrefix.isEmpty && raw.first == " "
        var result = raw.trimmingCharacters(in: whitespaceCharacters)

        while result.hasPrefix("```") {
            if let fenceEndIndex = result.firstIndex(of: "\n") {
                result = String(result[fenceEndIndex...]).trimmingCharacters(in: whitespaceCharacters)
            } else {
                break
            }
        }

        if let closingFenceRange = result.range(of: "```") {
            result = String(result[..<closingFenceRange.lowerBound]).trimmingCharacters(in: whitespaceCharacters)
        }

        if let firstLine = result.components(separatedBy: .newlines).first {
            result = firstLine
        }

        result = result.trimmingCharacters(in: whitespaceCharacters)
        guard !result.isEmpty else { return "" }

        if !currentTokenPrefix.isEmpty, result.lowercased().hasPrefix(currentTokenPrefix.lowercased()) {
            result.removeFirst(currentTokenPrefix.count)
        }

        result = result.trimmingCharacters(in: .whitespaces)

        if result.count > maxLength {
            let idx = result.index(result.startIndex, offsetBy: maxLength)
            result = String(result[..<idx])
            if let lastSpace = result.lastIndex(of: " ") {
                result = String(result[..<lastSpace])
            }
        }

        if allowsNaturalLanguage {
            if result.unicodeScalars.contains(where: { scalar in
                scalar == "\n" || scalar == "\r" || scalar.properties.generalCategory == .control
            }) {
                return ""
            }
        } else {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_()[]{}.,;:+-/*=<>!|&%?\"'` \t")
            if result.unicodeScalars.contains(where: { !allowed.contains($0) }) {
                return ""
            }
        }

        result = trimTrailingOverlap(result, nextDocumentText: nextDocumentText)
        if preservesLeadingSpace, !result.isEmpty, !result.hasPrefix(" ") {
            result = " " + result
        }
        return result
    }

    static func usesNaturalLanguageCompletion(for language: String) -> Bool {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "plain", "markdown", "rst", "text", "txt":
            return true
        default:
            return false
        }
    }

    static func shouldTriggerAfterWhitespace(
        in text: NSString,
        caretLocation: Int,
        language: String
    ) -> Bool {
        guard caretLocation > 0, caretLocation <= text.length else { return false }
        let previous = text.substring(with: NSRange(location: caretLocation - 1, length: 1))
        guard previous.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else { return false }

        if previous == "\n" || previous == "\t" {
            return true
        }

        if language == "markdown" {
            let lineRange = text.lineRange(for: NSRange(location: max(0, caretLocation - 1), length: 0))
            let lineText = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)
            if ["-", "*", "+", ">"].contains(trimmed) { return true }
            if trimmed.range(of: #"^\d+\.$"#, options: .regularExpression) != nil { return true }
        }

        var cursor = caretLocation - 1
        while cursor > 0 {
            let codeUnit = text.character(at: cursor - 1)
            if isWhitespaceCodeUnit(codeUnit) {
                cursor -= 1
                continue
            }
            let character = String(UnicodeScalar(codeUnit) ?? "\0")
            return [".", ":", "=", "(", "{", "[", ","].contains(character)
        }

        return false
    }

    static func isLikelyInCommentOrString(
        in text: NSString,
        caretLocation: Int,
        language: String
    ) -> Bool {
        guard caretLocation > 0, caretLocation <= text.length else { return false }
        let currentLine = text.lineRange(for: NSRange(location: max(0, caretLocation - 1), length: 0))
        let prefixLength = max(0, caretLocation - currentLine.location)
        guard prefixLength > 0 else { return false }

        let linePrefix = text.substring(with: NSRange(location: currentLine.location, length: prefixLength))
        let trimmedPrefix = linePrefix.trimmingCharacters(in: .whitespaces)
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if isLineCommentPrefix(trimmedPrefix, language: normalizedLanguage) {
            return true
        }

        if containsLineCommentBeforeCaret(linePrefix, language: normalizedLanguage) {
            return true
        }

        return hasUnclosedStringDelimiter(in: linePrefix)
    }

    private static func collectDocumentCandidates(
        into candidates: inout [String: Int],
        in text: NSString,
        caretLocation: Int,
        prefix: String,
        normalizedPrefix: String
    ) {
        let leadingWindow = min(16_000, caretLocation)
        let trailingWindow = min(4_000, max(0, text.length - caretLocation))
        let start = max(0, caretLocation - leadingWindow)
        let length = min(text.length - start, leadingWindow + trailingWindow)
        guard length > 0 else { return }

        let searchText = text.substring(with: NSRange(location: start, length: length))
        let nsSearchText = searchText as NSString
        let regex = cachedSyntaxRegex(pattern: #"\b[A-Za-z_][A-Za-z0-9_]{1,}\b"#)
        let matches = regex?.matches(in: searchText, options: [], range: NSRange(location: 0, length: nsSearchText.length)) ?? []

        for match in matches {
            let candidate = nsSearchText.substring(with: match.range)
            guard let normalized = normalizeCandidate(candidate, prefix: prefix, normalizedPrefix: normalizedPrefix) else { continue }
            let absoluteLocation = start + match.range.location
            let distance = abs(absoluteLocation - caretLocation)
            let distancePenalty = min(60, distance / 180)
            let caseBonus = candidate.hasPrefix(prefix) ? 12 : 0
            let score = 160 + caseBonus - distancePenalty - min(18, normalized.count - prefix.count)
            candidates[normalized] = max(candidates[normalized] ?? .min, score)
        }
    }

    private static func isLineCommentPrefix(_ prefix: String, language: String) -> Bool {
        switch language {
        case "python", "bash", "zsh", "powershell", "ruby", "yaml", "yml", "toml":
            return prefix.hasPrefix("#")
        case "tex", "latex", "bibtex":
            return prefix.hasPrefix("%")
        case "html", "markdown":
            return prefix.hasPrefix("<!--")
        default:
            return prefix.hasPrefix("//")
        }
    }

    private static func isIdentifierCodeUnit(_ codeUnit: unichar) -> Bool {
        if codeUnit == 95 { return true } // "_"
        if codeUnit >= 48 && codeUnit <= 57 { return true }
        if codeUnit >= 65 && codeUnit <= 90 { return true }
        if codeUnit >= 97 && codeUnit <= 122 { return true }
        guard let scalar = UnicodeScalar(codeUnit) else { return false }
        return identifierCharacters.contains(scalar)
    }

    private static func isWhitespaceCodeUnit(_ codeUnit: unichar) -> Bool {
        switch codeUnit {
        case 9, 10, 11, 12, 13, 32:
            return true
        default:
            guard let scalar = UnicodeScalar(codeUnit) else { return false }
            return whitespaceCharacters.contains(scalar)
        }
    }

    private static func containsLineCommentBeforeCaret(_ linePrefix: String, language: String) -> Bool {
        let markers: [String]
        switch language {
        case "python", "bash", "zsh", "powershell", "ruby", "yaml", "yml", "toml":
            markers = ["#"]
        case "tex", "latex", "bibtex":
            markers = ["%"]
        case "html", "markdown":
            markers = ["<!--"]
        default:
            markers = ["//"]
        }

        for marker in markers {
            if let range = linePrefix.range(of: marker),
               !isStringDelimiterOpen(in: String(linePrefix[..<range.lowerBound])) {
                return true
            }
        }
        return false
    }

    private static func hasUnclosedStringDelimiter(in linePrefix: String) -> Bool {
        isStringDelimiterOpen(in: linePrefix)
    }

    private static func isStringDelimiterOpen(in text: String) -> Bool {
        var singleOpen = false
        var doubleOpen = false
        var backtickOpen = false
        var escaped = false

        for character in text {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            switch character {
            case "'" where !doubleOpen && !backtickOpen:
                singleOpen.toggle()
            case "\"" where !singleOpen && !backtickOpen:
                doubleOpen.toggle()
            case "`" where !singleOpen && !doubleOpen:
                backtickOpen.toggle()
            default:
                continue
            }
        }

        return singleOpen || doubleOpen || backtickOpen
    }

    private static func normalizeCandidate(_ candidate: String, prefix: String, normalizedPrefix: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: whitespaceCharacters)
        guard trimmed.count > prefix.count else { return nil }
        guard trimmed.lowercased().hasPrefix(normalizedPrefix) else { return nil }
        guard trimmed.lowercased() != normalizedPrefix else { return nil }
        return trimmed
    }

    private static func syntaxKeywords(for language: String) -> [String] {
        if let exact = keywordSets[language] {
            return exact
        }
        return keywordSets["plain"] ?? []
    }

    private static func trimTrailingOverlap(_ suggestion: String, nextDocumentText: String) -> String {
        guard !suggestion.isEmpty, !nextDocumentText.isEmpty else { return suggestion }

        let suggestionScalars = Array(suggestion)
        let nextScalars = Array(nextDocumentText)
        let maxOverlap = min(suggestionScalars.count, nextScalars.count)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let suffix = String(suggestionScalars.suffix(overlap))
            let prefix = String(nextScalars.prefix(overlap))
            if suffix == prefix {
                let trimmed = String(suggestionScalars.dropLast(overlap)).trimmingCharacters(in: whitespaceCharacters)
                return trimmed
            }
        }

        return suggestion
    }
}
