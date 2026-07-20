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
