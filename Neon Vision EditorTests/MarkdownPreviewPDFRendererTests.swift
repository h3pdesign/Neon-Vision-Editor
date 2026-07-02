import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

@MainActor
final class MarkdownPreviewPDFRendererTests: XCTestCase {
    func testPaginatedSourceRangesCoverLongMarkdownWithoutGaps() {
        let ranges = MarkdownPreviewPDFRenderer.paginatedSourceRanges(
            sourceHeight: 4_850,
            preferredBlockBottoms: [220, 715, 1_412, 1_998, 2_704, 3_390, 4_100, 4_742],
            sliceHeight: 1_120
        )

        XCTAssertGreaterThan(ranges.count, 2)
        XCTAssertEqual(ranges.first?.top, 0)
        XCTAssertEqual(ranges.last?.bottom, 4_850)

        for (previous, current) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(previous.bottom, current.top)
            XCTAssertGreaterThan(current.bottom, current.top)
        }
    }

    func testPaginatedSourceRangesIgnoreInvalidBlockMeasurements() {
        let ranges = MarkdownPreviewPDFRenderer.paginatedSourceRanges(
            sourceHeight: 2_400,
            preferredBlockBottoms: [-24, 0, 640, 1_200, 2_400, 9_999],
            sliceHeight: 900
        )

        XCTAssertEqual(ranges.first?.top, 0)
        XCTAssertEqual(ranges.last?.bottom, 2_400)
        XCTAssertTrue(ranges.allSatisfy { $0.top >= 0 && $0.bottom <= 2_400 })
    }

    func testPaginatedSourceRangesKeepSinglePageForShortContent() {
        let ranges = MarkdownPreviewPDFRenderer.paginatedSourceRanges(
            sourceHeight: 680,
            preferredBlockBottoms: [120, 320, 640],
            sliceHeight: 1_120
        )

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first?.top, 0)
        XCTAssertEqual(ranges.first?.bottom, 680)
    }

    func testPaginatedSourceRangesRemainStrictlyAscendingWithDenseBlocks() {
        let ranges = MarkdownPreviewPDFRenderer.paginatedSourceRanges(
            sourceHeight: 5_600,
            preferredBlockBottoms: stride(from: 80, through: 5_520, by: 80).map(CGFloat.init),
            sliceHeight: 1_120
        )

        XCTAssertFalse(ranges.isEmpty)
        XCTAssertEqual(ranges.first?.top, 0)
        XCTAssertEqual(ranges.last?.bottom, 5_600)

        for range in ranges {
            XCTAssertGreaterThan(range.bottom, range.top)
        }
        for (previous, current) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(previous.bottom, current.top)
        }
    }

    func testAllMarkdownPreviewThemesKeepCompactViewportGuardrails() {
        let contentView = ContentView()
        let requiredCSSFragments = [
            "box-sizing: border-box",
            "min-width: 0",
            "max-width: 100%",
            "overflow-x: hidden",
            "overflow-wrap: break-word",
            "overflow-wrap: anywhere",
            "display: block",
            "white-space: pre"
        ]

        for option in ContentView.markdownPreviewTemplateOptions {
            for preferDarkMode in [false, true] {
                let css = contentView.markdownPreviewCSS(
                    template: option.id,
                    preferDarkMode: preferDarkMode,
                    backgroundStyle: .template,
                    translucentBackgroundEnabled: false
                )

                for fragment in requiredCSSFragments {
                    XCTAssertTrue(
                        css.contains(fragment),
                        "\(option.id) missing compact viewport guardrail: \(fragment)"
                    )
                }
                XCTAssertFalse(
                    css.contains("width: 100vw"),
                    "\(option.id) must not use viewport-width content sizing because it can clip inside iOS WKWebView sheets."
                )
                XCTAssertFalse(
                    css.contains("max-width: 100vw"),
                    "\(option.id) must not use viewport-width max sizing because it can exceed the visible iOS WKWebView width."
                )
            }
        }
    }

    func testMarkdownPreviewRuntimeFontSizeUsesEditorValue() {
        let contentView = ContentView()
        let css = contentView.markdownPreviewCSS(
            template: "default",
            preferDarkMode: false,
            backgroundStyle: .template,
            translucentBackgroundEnabled: false,
            runtimeFontSize: 18
        )

        XCTAssertTrue(css.contains("font-size: 18px;"))
        XCTAssertFalse(css.contains("font-size: 19px;"))
        XCTAssertFalse(css.contains("max(19px, 1.18em)"))
    }

    func testGFMPreviewRendersGitHubExtensionsByDefault() {
        let markdown = """
        - [x] Done
        - [ ] Todo

        | Area | Status |
        | --- | :---: |
        | Markdown | ~~Draft~~ Done |

        Visit https://example.com
        """

        let html = ContentView.simpleMarkdownToHTML(markdown)

        XCTAssertTrue(html.contains("task-list-item"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked/>"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<del>Draft</del>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">https://example.com</a>"))
    }

    func testCommonMarkPreviewDoesNotApplyGFMExtensions() {
        let markdown = """
        - [x] Done

        | Area | Status |
        | --- | :---: |
        | Markdown | ~~Draft~~ Done |
        """

        let html = ContentView.simpleMarkdownToHTML(markdown, dialect: .commonMark)

        XCTAssertFalse(html.contains("task-list-item"))
        XCTAssertFalse(html.contains("<table>"))
        XCTAssertFalse(html.contains("<del>Draft</del>"))
        XCTAssertTrue(html.contains("[x] Done"))
    }

    func testGFMMermaidFenceRendersStaticDiagram() {
        let markdown = """
        ```mermaid
        graph TD
          A[Start] --> B[Review]
          B --> C[Ship]
        ```
        """

        let html = ContentView.simpleMarkdownToHTML(markdown, dialect: .gfm)

        XCTAssertTrue(html.contains("class=\"mermaid-diagram\""))
        XCTAssertTrue(html.contains("<svg class=\"mermaid-svg\""))
        XCTAssertTrue(html.contains("Start"))
        XCTAssertFalse(html.contains("<script"))
    }

    func testCommonMarkMermaidFenceStaysCodeBlock() {
        let markdown = """
        ```mermaid
        graph TD
          A --> B
        ```
        """

        let html = ContentView.simpleMarkdownToHTML(markdown, dialect: .commonMark)

        XCTAssertTrue(html.contains("language-mermaid"))
        XCTAssertFalse(html.contains("mermaid-svg"))
    }

    func testCodeFenceKeepsExplicitLanguageAndPicker() {
        let markdown = """
        ```swift
        import SwiftUI

        struct Demo: View {
            var body: some View { Text("Hi") }
        }
        ```
        """

        let html = ContentView.simpleMarkdownToHTML(markdown, dialect: .gfm)

        XCTAssertTrue(html.contains("class=\"code-block\""))
        XCTAssertTrue(html.contains("data-code-language=\"swift\""))
        XCTAssertTrue(html.contains("class=\"language-swift\""))
        XCTAssertTrue(html.contains("code-block-language-picker"))
        XCTAssertTrue(html.contains("<option value=\"swift\" selected>Swift</option>"))
    }

    func testCodeFenceInfersLanguageWhenFenceInfoIsMissing() {
        let markdown = """
        ```
        {
          "name": "Neon",
          "enabled": true
        }
        ```
        """

        let html = ContentView.simpleMarkdownToHTML(markdown, dialect: .gfm)

        XCTAssertTrue(html.contains("data-code-language=\"json\""))
        XCTAssertTrue(html.contains("class=\"language-json\""))
        XCTAssertTrue(html.contains("<option value=\"json\" selected>JSON</option>"))
    }

    func testCodeBlockRuntimeIncludesLocalSyntaxHighlighter() {
        let html = ContentView.markdownPreviewCodeBlockScript()

        XCTAssertTrue(html.contains("highlightBlock"))
        XCTAssertTrue(html.contains("syntax-${token}"))
        XCTAssertTrue(html.contains("code-block-language-picker"))
        XCTAssertTrue(html.contains("localStorage"))
        XCTAssertTrue(html.contains("maxHighlightedCodeUnits"))
        XCTAssertTrue(html.contains("unhandledrejection"))
        XCTAssertTrue(html.contains("enhanceCodeBlocks"))
        XCTAssertFalse(html.contains("https://"))
    }

    func testHeadingLineDoesNotCreateCodeLanguagePicker() {
        let markdown = """
        # Release Notes

        Regular paragraph.
        """

        let html = ContentView.simpleMarkdownToHTML(markdown, dialect: .gfm)

        XCTAssertTrue(html.contains("<h1>Release Notes</h1>"))
        XCTAssertFalse(html.contains("code-block-language-picker"))
        XCTAssertFalse(html.contains("data-code-language=\"swift\""))
    }
}
