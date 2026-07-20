import Foundation
import SwiftUI

@main
struct SyntaxHighlightingRegressionRunner {
    static func main() {
        let colors = SyntaxColors.fromVibrantLightTheme(colorScheme: .dark)
        let htmlSample = #"<a href="https://example.com" class="btn">Open</a>"#
        let patterns = getSyntaxPatterns(for: "html", colors: colors)

        require(anyPatternMatches(htmlSample, from: patterns), "HTML patterns did not match a basic element.")
        require(matchesRegex(htmlSample, pattern: #"</?[A-Za-z][A-Za-z0-9:-]*"#), "HTML tag pattern did not match.")
        require(matchesRegex(htmlSample, pattern: #"\b[A-Za-z_:][A-Za-z0-9_:.-]*(?=\s*=)"#), "HTML attribute pattern did not match.")
        require(matchesRegex(htmlSample, pattern: #""[^"\n]*"|'[^'\n]*'"#), "HTML string pattern did not match.")

        // Typing leaves attributes incomplete; every returned range must remain safe to apply.
        let incompleteHTML = "<section class=\"card\">\n  <a href=\"https://example.com"
        let text = incompleteHTML as NSString
        let ranges = fastHTMLSyntaxColorRanges(
            text: text,
            in: NSRange(location: 0, length: text.length),
            colors: colors
        )
        require(!ranges.isEmpty, "Incomplete HTML produced no fast highlight ranges.")
        require(
            ranges.allSatisfy { isSyntaxHighlightRangeValid($0.0, utf16Length: text.length) },
            "Incomplete HTML produced an invalid highlight range."
        )

        require(isSyntaxHighlightRangeValid(NSRange(location: 0, length: 1), utf16Length: 1), "Valid highlight range was rejected.")
        require(!isSyntaxHighlightRangeValid(NSRange(location: 1, length: 1), utf16Length: 1), "Out-of-bounds highlight range was accepted.")

        let languageSamples: [(language: String, sample: String)] = [
            ("swift", "@MainActor\nfunc load() async throws -> Int { return 1 }"),
            ("json", #"{"enabled": true, "count": 3}"#),
            ("markdown", "# Heading\n[Docs](https://example.com)"),
            ("python", "async def load_data() -> int:\n    return 1"),
            ("typescript", "export interface User { readonly id: string }"),
            ("yaml", "services:\n  enabled: true"),
            ("css", "body { background-color: #ffaa33; }"),
            ("xml", #"<item id="42">value</item>"#),
            ("crashlog", "Exception Type: EXC_BAD_ACCESS (SIGSEGV)\nCrashed Thread: 0")
        ]
        for entry in languageSamples {
            let patterns = getSyntaxPatterns(for: entry.language, colors: colors)
            require(!patterns.isEmpty, "\(entry.language) returned no syntax patterns.")
            require(anyPatternMatches(entry.sample, from: patterns), "\(entry.language) patterns did not match a representative sample.")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }

    private static func matchesRegex(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func anyPatternMatches(_ text: String, from patterns: [String: Color]) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return patterns.keys.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }
}
