# Markdown PDF Export Long Regression Fixture

This fixture is intentionally longer than two A4 pages. Use it when checking
that paginated Markdown PDF export includes the full document and that one-page
export grows to the required content height with tight margins.

## Export Checklist

- Paginated Fit should produce multiple pages.
- Every numbered section below should appear in the exported PDF.
- One Page Fit should produce one flexible-height page.
- Headings, tables, lists, links, block quotes, and fenced code should remain legible.

## Section 1: Release Summary

Neon Vision Editor keeps the editor surface small while improving practical
writing and code-review workflows across macOS, iPhone, and iPad. This paragraph
contains enough prose to make wrapping and page slicing visible during export.
The exported result must not stop after the first pages.

## Section 2: Toolbar Parity

| Platform | Expected behavior |
|---|---|
| macOS | Primary actions stay in the native toolbar and menus. |
| iPhone | Compact actions remain reachable through the scrollable toolbar and sheets. |
| iPad | Toolbar Help, Settings, export, and preview controls remain discoverable. |

## Section 3: Project Sidebar

- Open File presents the platform file importer.
- Open Folder presents the folder importer where supported.
- New File asks for a filename and opens the created file in a tab.
- New Folder asks for a folder name and refreshes the project tree.

## Section 4: Markdown Content

Markdown preview should preserve document structure, including lists, links, and
quoted notes. See [Neon Vision Editor](https://github.com/h3pdesign/Neon-Vision-Editor)
for the current release notes and roadmap.

> Regression checks should use content that is long enough to expose page
> slicing bugs, not just short smoke-test documents.

## Section 5: Code Fence

```swift
struct ExportScenario {
    let title: String
    let expectedPages: ClosedRange<Int>
    let requiresCompleteText: Bool
}

let longMarkdown = ExportScenario(
    title: "Long Markdown PDF",
    expectedPages: 3...8,
    requiresCompleteText: true
)
```

## Section 6: Repeated Body A

The first body block verifies that ordinary paragraphs continue after tables and
code fences. The page boundary should not cut off text permanently. If a heading
lands close to the bottom of a page, the following page should continue with the
remaining prose.

## Section 7: Repeated Body B

The second body block keeps the document flowing. It includes inline `code`,
emphasis, and a short checklist:

- [x] Build the app.
- [x] Export the Markdown preview.
- [ ] Compare the first, middle, and final sections in the PDF.

## Section 8: Repeated Body C

This text exists to push content beyond the earlier two-page failure mode.
Paginated export should continue until the final section. One-page export should
avoid large margins and grow vertically instead of clipping.

## Section 9: Repeated Body D

Long notes often include operational details. A release checklist can span many
sections, and the exported PDF must be useful as an archive. The renderer should
prefer complete content over a visually compact but truncated result.

## Section 10: Repeated Body E

The fixture includes enough repeated natural language to exercise line wrapping
and block measurements. It should remain readable with the default Markdown
preview typography.

## Section 11: Repeated Body F

When testing on iPad, use both portrait and landscape if possible. The PDF export
path should not depend on the current split-view width once the export HTML is
prepared.

## Section 12: Repeated Body G

When testing on iPhone, verify the export controls through the compact toolbar or
Markdown preview sheet. The generated PDF should match the same content coverage
as macOS and iPad.

## Section 13: Repeated Body H

This paragraph is intentionally plain. A regression fixture should be easy to
scan after export so that missing trailing pages are obvious.

## Section 14: Repeated Body I

The final page should still include complete paragraphs and should not show a
large blank area before the last content unless the document naturally ends
there.

## Section 15: Final Marker

If this final marker is missing from the exported PDF, the long Markdown export
regression is still present.

**FINAL MARKER: v0.6.4 Markdown PDF export coverage reached the end.**
