import Foundation
import SwiftUI
import AppKit

@main
struct SyntaxHighlightingRegressionRunner {
    @MainActor
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

        let extendedHTML = #"<section class="card" data-state=open>&amp;</section>"#
        let extendedText = extendedHTML as NSString
        let extendedRanges = fastHTMLSyntaxColorRanges(
            text: extendedText,
            in: NSRange(location: 0, length: extendedText.length),
            colors: colors
        )
        let extendedTokens = Set(extendedRanges.map { extendedText.substring(with: $0.0) })
        require(extendedTokens.contains("class"), "Fast HTML scanner missed an attribute name.")
        require(extendedTokens.contains(#""card""#), "Fast HTML scanner missed a quoted value.")
        require(extendedTokens.contains("data-state"), "Fast HTML scanner missed a data attribute.")
        require(extendedTokens.contains("open"), "Fast HTML scanner missed an unquoted value.")
        require(extendedTokens.contains("&amp;"), "Fast HTML scanner missed an entity.")

        require(
            supportsResponsiveLargeFileHighlight(language: "xhtml", textLength: extendedText.length),
            "XHTML below the syntax cutoff was excluded from responsive highlighting."
        )

        let defaults = UserDefaults.standard
        let syntaxModeKey = "SettingsLargeFileSyntaxHighlighting"
        let openModeKey = "SettingsLargeFileOpenMode"
        let previousSyntaxMode = defaults.object(forKey: syntaxModeKey)
        let previousOpenMode = defaults.object(forKey: openModeKey)
        defer {
            if let previousSyntaxMode {
                defaults.set(previousSyntaxMode, forKey: syntaxModeKey)
            } else {
                defaults.removeObject(forKey: syntaxModeKey)
            }
            if let previousOpenMode {
                defaults.set(previousOpenMode, forKey: openModeKey)
            } else {
                defaults.removeObject(forKey: openModeKey)
            }
        }
        defaults.set("minimal", forKey: syntaxModeKey)
        defaults.set("deferred", forKey: openModeKey)

        let largeHTML = NSString(string: String(repeating: extendedHTML + "\n", count: 30_000))
        require(
            largeHTML.length > EditorRuntimeLimits.syntaxMinimalUTF16Length,
            "Large HTML fixture did not cross the syntax cutoff."
        )
        require(
            syntaxProfile(for: "xhtml", text: largeHTML) == .htmlFast,
            "XHTML did not select the fast HTML profile."
        )
        require(
            supportsResponsiveLargeFileHighlight(language: "xhtml", textLength: largeHTML.length),
            "Large XHTML within the responsive syntax limit was excluded."
        )
        require(
            !supportsResponsiveLargeFileHighlight(
                language: "xhtml",
                textLength: EditorRuntimeLimits.htmlResponsiveSyntaxUTF16Length + 1
            ),
            "XHTML above the responsive syntax limit was not excluded."
        )
        let visibleRange = NSRange(location: largeHTML.length / 2, length: 8_000)
        let visibleRanges = fastHTMLSyntaxColorRanges(
            text: largeHTML,
            in: visibleRange,
            colors: colors
        )
        require(!visibleRanges.isEmpty, "Large HTML visible range produced no syntax colors.")
        require(
            visibleRanges.allSatisfy { isSyntaxHighlightRangeValid($0.0, utf16Length: largeHTML.length) },
            "Large HTML visible range produced an invalid attribute range."
        )

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        textView.isRichText = false
        textView.string = extendedHTML
        require(
            applyMacSyntaxForegroundColors(
                to: textView,
                in: NSRange(location: 0, length: extendedText.length),
                coloredRanges: extendedRanges
            ),
            "AppKit syntax colors could not be applied."
        )
        let tagLocation = extendedText.range(of: "section").location
        require(
            textView.layoutManager?.temporaryAttribute(
                .foregroundColor,
                atCharacterIndex: tagLocation,
                effectiveRange: nil
            ) is NSColor,
            "Plain-text NSTextView did not retain its temporary syntax color."
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
