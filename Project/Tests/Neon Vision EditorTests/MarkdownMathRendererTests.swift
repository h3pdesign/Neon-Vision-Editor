import Foundation
import Testing
@testable import Neon_Vision_Editor

struct MarkdownMathRendererTests {
    @Test func formulasPreserveTeXBeforeMarkdownFormatting() {
        let html = ContentView.inlineMarkdownToHTML(#"**Result:** $\frac{x_i}{y_j} + \alpha_0$ and *text*."#)
        #expect(html.contains("<strong>Result:</strong>"))
        #expect(html.contains("<em>text</em>"))
        #expect(html.contains("class=\"katex\""))
        #expect(html.contains("<annotation encoding=\"application/x-tex\">\\frac{x_i}{y_j} + \\alpha_0</annotation>"))
        #expect(!html.contains("katex-error"))
    }

    @Test func tableMathPreservesBackslashesAndVerticalBars() {
        let source = #"| $\mu$ | $\frac{1}{2}$ | $\left|x_i\right|$ |"#
        let cells = ContentView.splitMarkdownTableRow(source)
        #expect(cells == [#"$\mu$"#, #"$\frac{1}{2}$"#, #"$\left|x_i\right|$"#])
        let html = ContentView.simpleMarkdownToHTML("| A | B | C |\n| --- | --- | --- |\n" + source)
        #expect(html.contains("<annotation encoding=\"application/x-tex\">\\mu</annotation>"))
        #expect(html.contains("<annotation encoding=\"application/x-tex\">\\frac{1}{2}</annotation>"))
        #expect(html.contains("<annotation encoding=\"application/x-tex\">\\left|x_i\\right|</annotation>"))
    }

    @Test(arguments: [#"$x_i$"#, #"\(x_i\)"#, #"$ x_i $"#])
    func inlineDelimiters(_ source: String) {
        let html = ContentView.inlineMarkdownToHTML(source)
        #expect(html.contains("class=\"katex\""))
        #expect(!html.contains("katex-display"))
    }

    @Test(arguments: ["$$x_i = y_j$$", "$$\nx_i = y_j\n$$", "\\[\nx_i = y_j\n\\]"])
    func displayDelimiters(_ source: String) {
        let html = ContentView.simpleMarkdownToHTML(source + "\n\nAfter **math**.")
        #expect(html.contains("class=\"markdown-math-display\""))
        #expect(html.contains("class=\"katex-display\""))
        #expect(html.contains("After <strong>math</strong>."))
        #expect(!html.contains("katex-error"))
    }

    @Test func multilineAlignmentIsNotSplitIntoParagraphsOrTables() {
        let source = #"""
        $$
        \begin{aligned}
        a_i &= b_i + c_i \\
        d_i &= \frac{1}{2}
        \end{aligned}
        $$
        """#
        let html = ContentView.simpleMarkdownToHTML(source)
        #expect(html.contains("class=\"katex-display\""))
        #expect(!html.contains("<br/>"))
        #expect(!html.contains("katex-error"))
    }

    @Test func headingsListsTablesAndQuotesUseTheSameRenderer() {
        let html = ContentView.simpleMarkdownToHTML(#"""
        # Estimate $x_i$
        - Value $y_j$

        | Term | Value |
        | --- | --- |
        | $z_k$ | $\frac{1}{2}$ |

        > $$
        > \sum_i x_i
        > $$
        """#)
        #expect(html.components(separatedBy: "class=\"katex\"").count - 1 == 5)
        #expect(html.contains("<h1>Estimate <span class=\"katex\""))
        #expect(html.contains("<blockquote>\n<div class=\"markdown-math-display\""))
        #expect(!html.contains("katex-error"))
    }

    @Test func codeAndEscapedDollarsRemainLiteral() {
        let inline = ContentView.inlineMarkdownToHTML(#"`$x_i$` and ``$y_j$`` and \$5 and $z_k$"#)
        #expect(inline.components(separatedBy: "class=\"katex\"").count - 1 == 1)
        let fenced = ContentView.simpleMarkdownToHTML("```text\n$x_i$\n$$\ny_j\n$$\n```")
        #expect(!fenced.contains("class=\"katex"))
        #expect(fenced.contains("$x_i$"))
    }

    @Test func currencyAndUnmatchedDelimitersDoNotConsumeFollowingMath() {
        let html = ContentView.inlineMarkdownToHTML("Costs $5 and $10; formula $x_i$.")
        #expect(html.contains("Costs $5 and $10; formula <span class=\"katex\""))
        #expect(html.components(separatedBy: "class=\"katex\"").count - 1 == 1)
        #expect(!ContentView.simpleMarkdownToHTML("$$\nunclosed").contains("class=\"katex"))
        #expect(ContentView.inlineMarkdownToHTML("unclosed $x").contains("unclosed $x"))
    }

    @Test func linkDestinationsImagesAndHTMLAttributesAreNotMath() {
        let html = ContentView.inlineMarkdownToHTML(#"[link](https://example.com/$x$) ![$y$](image.png) <span title="$z$">text</span> https://example.com/$v$ $w$"#)
        #expect(html.components(separatedBy: "class=\"katex\"").count - 1 == 1)
        #expect(html.contains("href=\"https://example.com/$x$\""))
        #expect(html.contains("alt=\"$y$\""))
        #expect(html.contains("$z$"))
        #expect(html.contains("href=\"https://example.com/$v$\""))
    }

    @Test func invalidAndUntrustedTeXStayInertAndDoNotBreakLaterFormulas() {
        let invalid = MarkdownMathRenderer.render(#"\frac{<script>alert(1)</script>"#, display: false)
        #expect(invalid.contains("katex-error"))
        #expect(!invalid.contains("<script>"))
        let untrusted = MarkdownMathRenderer.render(#"\href{javascript:alert(1)}{click}"#, display: false)
        #expect(!untrusted.contains("<a "))
        #expect(!untrusted.contains("href=\"javascript:"))
        #expect(MarkdownMathRenderer.render("x_i", display: false).contains("class=\"katex\""))
    }

    @Test func macrosDoNotLeakBetweenDocuments() {
        _ = MarkdownMathRenderer.render(#"\gdef\neonTestMacro{x}\neonTestMacro"#, display: false)
        #expect(MarkdownMathRenderer.render(#"\neonTestMacro"#, display: false).contains("#cc0000"))
    }

    @Test func stylesheetEmbedsFontsAndIsOnlyIncludedForMath() {
        #expect(MarkdownMathRenderer.stylesheet(for: "<p>plain text</p>").isEmpty)
        let css = MarkdownMathRenderer.stylesheet(for: MarkdownMathRenderer.render("x_i", display: true))
        #expect(css.contains("data:font/woff2;base64,"))
        #expect(css.contains(".katex-display"))
        #expect(css.contains("overflow-x: auto"))
        #expect(!css.contains("url(fonts/"))
        #expect(!css.contains("https://"))
    }
}
