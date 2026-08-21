import XCTest
import SwiftUI
@testable import Neon_Vision_Editor



/// MARK: - Tests

@MainActor
final class MarkdownSyntaxHighlightingTests: XCTestCase {
    private func markdownPatterns() -> [String: Color] {
        getSyntaxPatterns(
            for: "markdown",
            colors: SyntaxColors.fromVibrantLightTheme(colorScheme: .dark)
        )
    }

    func testMarkdownPreviewSemanticPalettesProvideDistinctLightAndDarkSurfaces() {
        let light = ContentView.MarkdownPreviewSemanticPalette.make(template: "neon-editorial", dark: false)
        let dark = ContentView.MarkdownPreviewSemanticPalette.make(template: "neon-editorial", dark: true)

        XCTAssertNotEqual(light.bodyBackground, dark.bodyBackground)
        XCTAssertNotEqual(light.contentBackground, dark.contentBackground)
        XCTAssertNotEqual(light.link, dark.link)
        XCTAssertFalse(ContentView.markdownPreviewSemanticCSS(template: "developer-slate", dark: true).isEmpty)
    }

    func testMarkdownPreviewSemanticCSSDefinesCoreReadableComponents() {
        let css = ContentView.markdownPreviewSemanticCSS(template: "solarized", dark: false)

        XCTAssertTrue(css.contains("--md-heading-color"))
        XCTAssertTrue(css.contains("--md-code-background"))
        XCTAssertTrue(css.contains(".code-block-toolbar"))
        XCTAssertTrue(css.contains("tbody tr:nth-child(even)"))
    }

    func testMarkdownPreviewThemeExtractsTypographyAndLayoutTokens() {
        let theme = ContentView.MarkdownPreviewTheme.make(template: "developer-slate", dark: true)

        XCTAssertEqual(theme.fontSize, "15px")
        XCTAssertEqual(theme.lineHeight, "1.65")
        XCTAssertEqual(theme.contentMaxWidth, "980px")
        XCTAssertTrue(ContentView.markdownPreviewSemanticCSS(template: "developer-slate", dark: true).contains("--md-body-padding"))
    }

    func testMarkdownPreviewVividThemesAndComponentRulesAreDistinct() {
        let vividIDs = ["electric-pop", "aurora", "citrus", "plasma", "deep-ocean"]
        let palettes = vividIDs.map { ContentView.MarkdownPreviewSemanticPalette.make(template: $0, dark: true) }
        XCTAssertEqual(Set(palettes.map(\.accent)).count, vividIDs.count)
        XCTAssertEqual(Set(palettes.map(\.bodyBackground)).count, vividIDs.count)

        let css = ContentView.markdownPreviewSemanticCSS(template: "electric-pop", dark: true)
        for token in ["linear-gradient", ".content > p:first-of-type", "text-underline-offset", "checkbox", "position: sticky", ".markdown-image", "--md-table-cell-padding"] {
            XCTAssertTrue(css.contains(token), "Vivid theme is missing \(token)")
        }
        XCTAssertTrue(ContentView.markdownPreviewSemanticCSS(template: "developer-slate", dark: true).contains(".content > p:first-of-type { margin-top"))
        XCTAssertFalse(ContentView.markdownPreviewSemanticCSS(template: "developer-slate", dark: true).contains("font-size: 1.1em"))
        XCTAssertTrue(ContentView.markdownPreviewSemanticCSS(template: "high-contrast", dark: true).contains("#000000"))
        XCTAssertTrue(ContentView.markdownPreviewSemanticCSS(template: "warm-sepia", dark: false).contains("#f3e6d2"))
        XCTAssertNotEqual(
            ContentView.markdownPreviewSemanticCSS(template: "electric-pop", dark: true),
            ContentView.markdownPreviewSemanticCSS(template: "developer-slate", dark: true)
        )
    }

    func testVisibleMarkdownThemesHaveDistinctSemanticAccents() {
        let visibleIDs = [
            "default", "neon-editorial", "developer-slate", "nordic-light", "solarized",
            "article", "notebook", "high-contrast", "terminal-notes", "warm-sepia",
            "electric-pop", "aurora", "citrus", "plasma", "deep-ocean", "ember-glow",
            "forest-canopy", "ultraviolet", "cobalt", "mint-paper"
        ]
        let light = visibleIDs.map { ContentView.MarkdownPreviewSemanticPalette.make(template: $0, dark: false) }
        let dark = visibleIDs.map { ContentView.MarkdownPreviewSemanticPalette.make(template: $0, dark: true) }

        XCTAssertEqual(Set(light.map(\.accent)).count, visibleIDs.count, light.map(\.accent).description)
        XCTAssertEqual(Set(dark.map(\.accent)).count, visibleIDs.count, dark.map(\.accent).description)
        XCTAssertNotEqual(ContentView.MarkdownPreviewSemanticPalette.make(template: "article", dark: false).accent, ContentView.MarkdownPreviewSemanticPalette.make(template: "default", dark: false).accent)
        XCTAssertNotEqual(ContentView.MarkdownPreviewSemanticPalette.make(template: "notebook", dark: true).accent, ContentView.MarkdownPreviewSemanticPalette.make(template: "solarized", dark: true).accent)
        XCTAssertNotEqual(ContentView.MarkdownPreviewSemanticPalette.make(template: "terminal-notes", dark: true).bodyBackground, ContentView.MarkdownPreviewSemanticPalette.make(template: "developer-slate", dark: true).bodyBackground)
    }

    func testMarkdownPreviewImageCaptionsUseRoundedContainers() {
        let html = ContentView.inlineMarkdownToHTML("![A diagram](diagram.png)")
        XCTAssertTrue(html.contains("<figure class=\"markdown-image\">"))
        XCTAssertTrue(html.contains("<figcaption>A diagram</figcaption>"))
    }

    func testMarkdownPreviewLiveAndExportContractsShareThemeCSS() {
        let sharedCSS = ContentView.markdownPreviewSemanticCSS(template: "neon-editorial", dark: false)
        let liveHTML = "<style>\(sharedCSS)</style><main class=\"content\"></main>"
        let exportHTML = "<style>\(sharedCSS)</style><main class=\"content pdf-export\"></main>"
        let tokens = ["--md-accent-color", "--md-code-background", "--md-quote-border", "--md-table-header-background"]

        XCTAssertEqual(liveHTML.replacingOccurrences(of: "<main class=\"content\"></main>", with: ""),
                       exportHTML.replacingOccurrences(of: "<main class=\"content pdf-export\"></main>", with: ""))
        XCTAssertTrue(tokens.allSatisfy(liveHTML.contains), "Live preview is missing semantic CSS tokens")
        XCTAssertTrue(tokens.allSatisfy(exportHTML.contains), "Export preview is missing semantic CSS tokens")
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
        let listPattern = patterns.keys.first { $0.contains("[-*+]") && !$0.contains("\\[[ xX]\\]") }
        let quotePattern = patterns.keys.first { $0.contains(">\\s?") }

        XCTAssertNotNil(headingPattern)
        XCTAssertNotNil(listPattern)
        XCTAssertNotNil(quotePattern)

        for pattern in [headingPattern, listPattern, quotePattern].compactMap({ $0 }) {
            guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines, .dotMatchesLineSeparators]) else {
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
