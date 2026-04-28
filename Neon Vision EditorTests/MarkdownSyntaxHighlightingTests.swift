import XCTest
import SwiftUI
@testable import Neon_Vision_Editor



/// MARK: - Tests

final class MarkdownSyntaxHighlightingTests: XCTestCase {
    private func markdownPatterns() -> [String: Color] {
        getSyntaxPatterns(
            for: "markdown",
            colors: SyntaxColors.fromVibrantLightTheme(colorScheme: .dark)
        )
    }

    func testMarkdownPatternsMatchClaudeStyleDocumentSections() {
        let sample = """
        # Claude Export

        Here is prose with an [inline link](https://example.com).

        - First bullet
        - Second bullet with *emphasis*

        ```swift
        struct Demo { let id: Int }
        ```

        > This is a quoted block.
        """

        let patterns = markdownPatterns()
        let headingPattern = patterns.keys.first { $0.contains("#{1,6}") }
        let listPattern = patterns.keys.first { $0.contains("[-*+]") }
        let quotePattern = patterns.keys.first { $0.contains(">\\s?") }

        XCTAssertNotNil(headingPattern)
        XCTAssertNotNil(listPattern)
        XCTAssertNotNil(quotePattern)

        for pattern in [headingPattern, listPattern, quotePattern].compactMap({ $0 }) {
            guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                XCTFail("Failed to compile regex: \(pattern)")
                continue
            }
            let matches = regex.matches(in: sample, options: [], range: NSRange(sample.startIndex..., in: sample))
            XCTAssertFalse(matches.isEmpty, "Expected markdown regex to match sample sections: \(pattern)")
        }
    }

    func testMarkdownCodeFenceRegexKeepsSeparateFences() {
        let sample = """
        Intro paragraph.

        ```swift
        let x = 1
        ```

        middle text with `inline` code

        ```json
        {"a": 1}
        ```
        """

        let patterns = markdownPatterns()
        guard let fencePattern = patterns.keys.first(where: { $0.contains("```.*?```") }) else {
            XCTFail("Fence regex pattern missing")
            return
        }
        guard let inlineCodePattern = patterns.keys.first(where: { $0.contains("[^`\\n]+") }) else {
            XCTFail("Inline code regex pattern missing")
            return
        }
        guard let regex = cachedSyntaxRegex(pattern: fencePattern, options: [.dotMatchesLineSeparators]) else {
            XCTFail("Fence regex failed to compile")
            return
        }
        guard let inlineRegex = cachedSyntaxRegex(pattern: inlineCodePattern, options: [.dotMatchesLineSeparators]) else {
            XCTFail("Inline code regex failed to compile")
            return
        }

        let matches = regex.matches(in: sample, options: [], range: NSRange(sample.startIndex..., in: sample))
        let inlineMatches = inlineRegex.matches(in: sample, options: [], range: NSRange(sample.startIndex..., in: sample))
        XCTAssertEqual(matches.count, 2, "Expected 2 fenced blocks")
        XCTAssertEqual(inlineMatches.count, 1, "Expected 1 inline code span")
    }

    func testMarkdownPatternsRecognizeCommonDocumentStructure() {
        let sample = """
        ---
        title: Release Notes
        ---

        ## Checklist

        - [x] Ship syntax tuning
        - [ ] Verify iPad build

        | Area | Status |
        | --- | :---: |
        | Markdown | Done |

        ![Preview](preview.png)
        See [reference][docs] and <https://example.com>.

        [docs]: https://example.com/docs

        <!-- internal note -->
        ---
        """

        let patterns = markdownPatterns()
        let expectedPatternFragments = [
            "\\[[ xX]\\]",
            "\\|.*\\|",
            "!\\[",
            "\\[[^\\]\\n]+\\]:",
            "<https?",
            "<!--",
            "([*\\-_])"
        ]

        for fragment in expectedPatternFragments {
            guard let pattern = patterns.keys.first(where: { $0.contains(fragment) }) else {
                XCTFail("Expected markdown pattern containing fragment: \(fragment)")
                continue
            }
            guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines, .dotMatchesLineSeparators]) else {
                XCTFail("Failed to compile regex: \(pattern)")
                continue
            }
            let matches = regex.matches(in: sample, range: NSRange(sample.startIndex..., in: sample))
            XCTAssertFalse(matches.isEmpty, "Expected markdown regex to match sample: \(pattern)")
        }
    }
}
