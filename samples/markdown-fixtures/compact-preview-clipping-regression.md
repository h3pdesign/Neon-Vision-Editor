# Compact Preview Clipping Regression Fixture With A Deliberately Long Heading That Must Wrap Cleanly On Narrow iPhone Widths

This fixture is intentionally hostile to compact Markdown preview layouts. It combines long headings, long links, inline code, tables, quotes, and preformatted blocks so every preview theme has to stay inside the viewport.

Long URL:
https://example.com/releases/2026/06/07/neon-vision-editor/markdown-preview/theme-audit/this-path-is-deliberately-long-to-force-anywhere-wrapping-on-iphone-without-horizontal-page-clipping

Inline code: `VeryLongInlineCodeIdentifierThatShouldWrapWithoutPushingTheMarkdownPreviewWiderThanTheViewportWhenShownOnIPhone`

> A blockquote with a deliberately long token: BlockquoteTokenWithoutNaturalBreaksThatStillNeedsToWrapInsideThePreviewContentContainer.

| Platform | Scenario | Expected behavior |
| --- | --- | --- |
| iPhone | Long heading and long URL | Text wraps inside the viewport with no left or right clipping. |
| iPhone | Wide table | Table scrolls horizontally inside its own block instead of widening the whole page. |
| iPad | Code block | Code remains readable and does not force document-level horizontal scrolling. |

```swift
let deliberatelyLongSwiftIdentifierThatShouldStayInsideThePreformattedScrollContainerWithoutClippingThePage = "abcdefghijklmnopqrstuvwxyz-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ"
```

## Secondary Heading With AnotherLongUnbrokenTokenThatShouldWrapInsteadOfDisappearingPastTheViewportEdge

- A list item with https://example.com/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z
- A list item with `AnotherLongInlineCodeTokenForCompactPreviewGuardrails`
