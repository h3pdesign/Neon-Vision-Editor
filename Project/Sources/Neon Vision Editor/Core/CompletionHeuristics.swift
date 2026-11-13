import Foundation
#if os(macOS)
import AppKit
#endif

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
        "meierscript": MeierScriptLanguage.completionVocabulary,
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
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_()[]{}.,;:+-/*=<>!|&%?\"'`#$@\\^~ \t")
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

        return hasUnclosedStringDelimiter(in: linePrefix, language: normalizedLanguage)
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

    /// Line comment markers for each editor language. Languages without
    /// line comments, such as JSON, CSS, CSV and logs, have none, so a URL's
    /// "//" does not read as a comment there.
    private static func lineCommentMarkers(for language: String) -> [String] {
        switch language {
        case "python", "bash", "zsh", "fish", "powershell", "ruby", "perl", "r", "yaml", "yml", "toml", "nix",
             "dockerfile", "makefile", "nginx", "dotenv", "graphql":
            return ["#"]
        case "php", "hcl":
            return ["//", "#"]
        case "sql", "lua", "ada":
            return ["--"]
        case "ini":
            return [";", "#"]
        case "cobol":
            return ["*>"]
        case "tex", "latex", "bibtex":
            return ["%"]
        case "html", "xml", "markdown":
            return ["<!--"]
        case "expressionengine":
            return ["<!--", "{!--"]
        case "vim":
            return ["\""]
        case "json", "ipynb", "css", "csv", "log", "crashlog", "eml":
            return []
        default:
            return ["//"]
        }
    }

    private static func isLineCommentPrefix(_ prefix: String, language: String) -> Bool {
        lineCommentMarkers(for: language).contains { prefix.hasPrefix($0) }
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
        // Vim's comment quote also opens strings, so only a leading one
        // (handled by isLineCommentPrefix) is a comment.
        guard language != "vim" else { return false }
        // In shells "#" starts a comment only at the start of a word, so
        // "${#items}" is code.
        let needsWordStart = ["bash", "zsh", "fish"].contains(language)

        for marker in lineCommentMarkers(for: language) {
            var searchStart = linePrefix.startIndex
            while let range = linePrefix.range(of: marker, range: searchStart..<linePrefix.endIndex) {
                searchStart = range.upperBound
                let before = linePrefix[..<range.lowerBound]
                if needsWordStart, let previous = before.last, !previous.isWhitespace { continue }
                // A marker inside a string, such as a URL's "//", is skipped.
                if !isStringDelimiterOpen(in: String(before), language: language) {
                    return true
                }
            }
        }
        return false
    }

    private static func hasUnclosedStringDelimiter(in linePrefix: String, language: String) -> Bool {
        isStringDelimiterOpen(in: linePrefix, language: language)
    }

    private static func isStringDelimiterOpen(in text: String, language: String = "") -> Bool {
        // TeX and Typst have no single-quoted or backtick strings, so an
        // apostrophe in prose such as "don't" is not an open string.
        let quotesOnlyDouble = ["tex", "latex", "typst"].contains(language)
        let isRust = language == "rust"
        let characters = Array(text)
        var singleOpen = false
        var doubleOpen = false
        var backtickOpen = false
        var escaped = false

        for (index, character) in characters.enumerated() {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            switch character {
            case "'" where !doubleOpen && !backtickOpen && !quotesOnlyDouble:
                // A Rust lifetime such as 'a or 'static is not a char literal.
                if isRust, !singleOpen, isRustLifetime(characters, at: index) { continue }
                singleOpen.toggle()
            case "\"" where !singleOpen && !backtickOpen:
                doubleOpen.toggle()
            case "`" where !singleOpen && !doubleOpen && !quotesOnlyDouble:
                backtickOpen.toggle()
            default:
                continue
            }
        }

        return singleOpen || doubleOpen || backtickOpen
    }

    private static func isRustLifetime(_ characters: [Character], at index: Int) -> Bool {
        let next = index + 1
        guard next < characters.count,
              characters[next].isLetter || characters[next] == "_" else { return false }
        // 'a' is a char literal; 'a followed by anything else is a lifetime.
        let afterNext = next + 1
        return afterNext >= characters.count || characters[afterNext] != "'"
    }

    private static func normalizeCandidate(_ candidate: String, prefix: String, normalizedPrefix: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: whitespaceCharacters)
        guard trimmed.count > prefix.count else { return nil }
        guard trimmed.lowercased().hasPrefix(normalizedPrefix) else { return nil }
        guard trimmed.lowercased() != normalizedPrefix else { return nil }
        return trimmed
    }

    static let vocabularyCompletionDefaultsKey = "SettingsVocabularyCompletionEnabled"
    /// Return accepts the selected entry of the completion list, as in Xcode,
    /// instead of only after choosing one with the arrow keys. Off by default.
    static let returnAcceptsCompletionDefaultsKey = "SettingsCompletionReturnAccepts"

    /// Languages whose keyword and built-in vocabulary is offered while typing
    /// without an AI provider.
    static func usesLocalVocabularyCompletion(for language: String) -> Bool {
        language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == MeierScriptLanguage.identifier
    }

    /// Completion suffixes for the identifier before the caret: language
    /// vocabulary first (shortest first), then identifiers from the nearby
    /// document. Only case-sensitive prefix matches qualify, because the editor
    /// appends the suffix to the typed prefix. With `insertsCallTemplates`,
    /// MeierScript functions complete as calls with their required parameters,
    /// such as `print(string)` or `getCommands()`, as in Xcode.
    static func vocabularySuffixes(
        in text: NSString,
        caretLocation: Int,
        language: String,
        minimumPrefixLength: Int = 2,
        limit: Int = 6,
        insertsCallTemplates: Bool = false
    ) -> (prefix: String, suffixes: [String]) {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard limit > 0,
              let prefix = currentIdentifierPrefix(in: text, caretLocation: caretLocation),
              prefix.count >= minimumPrefixLength,
              prefix.first.map({ !$0.isNumber }) == true,
              !isLikelyInCommentOrString(in: text, caretLocation: caretLocation, language: normalizedLanguage) else {
            return ("", [])
        }
        let vocabulary = syntaxKeywords(for: normalizedLanguage)
            .filter { $0.hasPrefix(prefix) && $0 != prefix }
            .sorted { lhs, rhs in lhs.count != rhs.count ? lhs.count < rhs.count : lhs < rhs }
        var documentScores: [String: Int] = [:]
        collectDocumentCandidates(into: &documentScores, in: text, caretLocation: caretLocation,
                                  prefix: prefix, normalizedPrefix: prefix.lowercased())
        let documentWords = documentScores
            .filter { $0.key.hasPrefix(prefix) }
            .sorted { lhs, rhs in lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key }
            .map(\.key)
        let userFunctions = insertsCallTemplates && normalizedLanguage == MeierScriptLanguage.identifier
            && !isFunctionNameDeclaration(in: text, prefixStart: caretLocation - (prefix as NSString).length)
            ? meierScriptFunctionParameters(in: text, caretLocation: caretLocation)
            : nil
        var seen = Set<String>()
        var suffixes: [String] = []
        for word in vocabulary + documentWords where seen.insert(word).inserted {
            var completion = word
            if let userFunctions {
                if let parameters = userFunctions[word] {
                    completion = "\(word)(\(parameters))"
                } else if let template = MeierScriptLanguage.callTemplate(forBuiltin: word) {
                    completion = template
                }
            }
            suffixes.append(String(completion.dropFirst(prefix.count)))
            if suffixes.count == limit { break }
        }
        return (prefix, suffixes)
    }

    /// Range of the first argument placeholder in a completed call, relative
    /// to `completion`, such as `string` in `print(string)`. A call without
    /// arguments returns an empty range after its closing parenthesis, so the
    /// caret continues after the call.
    static func callArgumentPlaceholderRange(in completion: String) -> NSRange? {
        let text = completion as NSString
        guard text.length > 1, text.hasSuffix(")") else { return nil }
        let open = text.range(of: "(")
        guard open.location != NSNotFound else { return nil }
        let start = NSMaxRange(open)
        let close = text.length - 1
        guard start <= close else { return nil }
        if start == close { return NSRange(location: text.length, length: 0) }
        let comma = text.range(of: ",", range: NSRange(location: start, length: close - start))
        let end = comma.location == NSNotFound ? close : comma.location
        return NSRange(location: start, length: end - start)
    }

    /// True when the identifier being typed follows `func`, where it names a
    /// new function rather than calling one.
    private static func isFunctionNameDeclaration(in text: NSString, prefixStart: Int) -> Bool {
        let start = max(0, prefixStart - 40)
        guard prefixStart > start else { return false }
        let before = text.substring(with: NSRange(location: start, length: prefixStart - start))
        return before.range(of: #"\bfunc\s+$"#, options: .regularExpression) != nil
    }

    /// Parameter names of the MeierScript functions declared in the text
    /// before the caret, keyed by function name: `func greet(name: String)`
    /// gives `"greet": "name"`.
    private static func meierScriptFunctionParameters(in text: NSString, caretLocation: Int) -> [String: String] {
        let start = max(0, caretLocation - 16_000)
        let searchText = text.substring(with: NSRange(location: start, length: max(0, caretLocation - start)))
        guard let regex = cachedSyntaxRegex(pattern: #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)\n]*)\)"#) else { return [:] }
        let nsSearchText = searchText as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: searchText, range: NSRange(location: 0, length: nsSearchText.length)) {
            let name = nsSearchText.substring(with: match.range(at: 1))
            let parameters = nsSearchText.substring(with: match.range(at: 2))
                .split(separator: ",")
                .compactMap { parameter -> String? in
                    let label = parameter.split(separator: ":", maxSplits: 1).first?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    return label.isEmpty ? nil : label
                }
            result[name] = parameters.joined(separator: ", ")
        }
        return result
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

#if os(macOS)
/// Offline prose completion from the user's Text Replacements and the macOS
/// spelling dictionary. The editor shows the best match inline and the
/// others in a list below the caret.
enum SystemWordCompletion {
    static let enabledDefaultsKey = "SettingsSystemWordCompletionEnabled"
    static let debounceNanoseconds: UInt64 = 150_000_000
    static let minimumPrefixLength = 2

    static func continuesWord(_ nextCharacter: String) -> Bool {
        nextCharacter.first.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "'" } ?? false
    }

    /// The most suggestions the completion list shows at once.
    static let maximumSuggestionCount = 6

    static func suffix(forWordPrefix prefix: String) -> String? {
        suffixes(forWordPrefix: prefix).first
    }

    /// Ranked completion suffixes for the word before the caret, best first.
    static func suffixes(forWordPrefix prefix: String, limit: Int = maximumSuggestionCount) -> [String] {
        guard prefix.count >= minimumPrefixLength,
              prefix.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return [] }
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        var words = checker.completions(
            forPartialWordRange: range, in: prefix, language: nil, inSpellDocumentWithTag: 0
        ) ?? []
        // With "Automatic by Language" the checker can have no current
        // language for a two-letter fragment; ask the user's first
        // preferred spelling language instead of returning nothing.
        if words.isEmpty, let language = checker.userPreferredLanguages.first {
            words = checker.completions(
                forPartialWordRange: range, in: prefix, language: language, inSpellDocumentWithTag: 0
            ) ?? []
        }
        return rankedSuffixes(
            forWordPrefix: prefix,
            replacementPhrases: Array(checker.userReplacementsDictionary.values),
            dictionaryWords: words,
            limit: limit
        )
    }

    /// The longest Text Replacement shortcut the user can type.
    static let maximumShortcutLength = 32

    /// The Text Replacement shortcut that ends at the caret, with its
    /// phrases, such as "omw" for "On my way!" (#959). Accepting one
    /// replaces the typed shortcut instead of appending to it. Shortcuts may contain punctuation, such as ";sig", "e.g" or
    /// "@@" (#994), so the shortcut is not limited to the identifier before
    /// the caret. It starts at the beginning of the text after the last
    /// whitespace or at a boundary between a word character and punctuation,
    /// so "omw" matches after "(" but not inside "xomw". The longest
    /// matching shortcut wins.
    static func replacementMatch(beforeCaret text: String) -> (shortcut: String, phrases: [String])? {
        replacementMatch(beforeCaret: text, replacements: NSSpellChecker.shared.userReplacementsDictionary)
    }

    static func replacementMatch(
        beforeCaret text: String,
        replacements: [String: String],
        limit: Int = maximumSuggestionCount
    ) -> (shortcut: String, phrases: [String])? {
        guard !replacements.isEmpty, limit > 0 else { return nil }
        let run = Array(text.suffix(maximumShortcutLength).reversed().prefix { !$0.isWhitespace }.reversed())
        guard run.count >= minimumPrefixLength else { return nil }
        // Starts run left to right, so the first match is the longest. Each
        // candidate uses replacementPhrases' own case-insensitive comparison,
        // which also matches "STRASSE" to "straße".
        for start in 0...(run.count - minimumPrefixLength) {
            if start > 0, isShortcutWordCharacter(run[start - 1]), isShortcutWordCharacter(run[start]) { continue }
            let shortcut = String(run[start...])
            let phrases = replacementPhrases(forShortcut: shortcut, replacements: replacements, limit: limit)
            if !phrases.isEmpty { return (shortcut, phrases) }
        }
        return nil
    }

    private static func isShortcutWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// Matches the shortcut case-insensitively, like the system does, and
    /// skips phrases that equal the typed text. Multi-line phrases, such as
    /// a note template, are offered too (#994); the list shows them with
    /// `previewLine(forPhrase:)`.
    static func replacementPhrases(
        forShortcut shortcut: String,
        replacements: [String: String],
        limit: Int = maximumSuggestionCount
    ) -> [String] {
        guard !shortcut.isEmpty, limit > 0 else { return [] }
        var seen = Set<String>()
        return replacements
            .filter { key, phrase in
                key.caseInsensitiveCompare(shortcut) == .orderedSame
                    && !phrase.isEmpty
                    && phrase != shortcut
            }
            .map(\.value)
            .sorted { lhs, rhs in lhs.count != rhs.count ? lhs.count < rhs.count : lhs < rhs }
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// The longest first line a multi-line phrase preview shows.
    static let maximumPreviewLength = 60

    /// One line for a Text Replacement phrase in the completion list and the
    /// inline hint. A multi-line phrase shows its first line and an ellipsis;
    /// accepting it still inserts every line (#994).
    static func previewLine(forPhrase phrase: String) -> String {
        guard let firstBreak = phrase.firstIndex(where: \.isNewline) else { return phrase }
        let firstLine = phrase[..<firstBreak].trimmingCharacters(in: .whitespaces)
        let shown = String(firstLine.prefix(maximumPreviewLength))
        return shown.isEmpty ? "\u{2026}" : shown + " \u{2026}"
    }

    /// Text Replacement phrases win over dictionary words because the user
    /// defined them. The shortest phrase is preferred; dictionary words keep
    /// the spell checker's ranking.
    static func bestSuffix(forWordPrefix prefix: String, replacementPhrases: [String], dictionaryWords: [String]) -> String? {
        rankedSuffixes(forWordPrefix: prefix, replacementPhrases: replacementPhrases,
                       dictionaryWords: dictionaryWords, limit: 1).first
    }

    /// Text Replacement phrases first (shortest first), then dictionary words
    /// in the spell checker's order, without case-insensitive duplicates.
    static func rankedSuffixes(
        forWordPrefix prefix: String,
        replacementPhrases: [String],
        dictionaryWords: [String],
        limit: Int = maximumSuggestionCount
    ) -> [String] {
        guard limit > 0 else { return [] }
        let phrases = replacementPhrases
            .compactMap { completionSuffix(of: $0, extending: prefix) }
            .sorted { lhs, rhs in lhs.count != rhs.count ? lhs.count < rhs.count : lhs < rhs }
        var seen = Set<String>()
        var result: [String] = []
        for suffix in phrases + dictionaryWords.compactMap({ completionSuffix(of: $0, extending: prefix) }) {
            guard seen.insert(suffix.lowercased()).inserted else { continue }
            result.append(suffix)
            if result.count == limit { break }
        }
        return result
    }

    private static func completionSuffix(of candidate: String, extending prefix: String) -> String? {
        guard !candidate.contains(where: \.isNewline),
              let match = candidate.range(of: prefix, options: [.anchored, .caseInsensitive]),
              match.upperBound < candidate.endIndex else { return nil }
        return String(candidate[match.upperBound...])
    }
}
#endif
