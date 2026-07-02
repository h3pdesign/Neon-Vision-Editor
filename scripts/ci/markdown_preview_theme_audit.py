#!/usr/bin/env python3
"""Static guardrail audit for Markdown preview theme CSS.

This intentionally avoids WebKit so it can run in release preflight contexts where
simulators are unavailable. XCTest covers the generated CSS; this script protects
the source-level contracts that prevent compact iPhone preview clipping.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PREVIEW_EXPORT = ROOT / "Neon Vision Editor" / "UI" / "ContentView+MarkdownPreviewExport.swift"
PREVIEW_UI = ROOT / "Neon Vision Editor" / "UI" / "ContentView+MarkdownPreviewUI.swift"
CLIPPING_FIXTURE = ROOT / "samples" / "markdown-fixtures" / "compact-preview-clipping-regression.md"

REQUIRED_SOURCE_FRAGMENTS = {
    "global box sizing": "box-sizing: border-box",
    "document min width clamp": "min-width: 0",
    "document horizontal clamp": "overflow-x: hidden",
    "content width clamp": "max-width: \\(maxWidth)",
    "runtime content min width clamp": ".content {\n          width: 100%;\n          min-width: 0;",
    "runtime child width clamp": ".content > * {\n          max-width: 100%;\n        }",
    "heading wrapping": "overflow-wrap: break-word",
    "long token wrapping": "overflow-wrap: anywhere",
    "table horizontal containment": "display: block;\n          max-width: 100%;\n          overflow-x: auto;",
    "runtime inertial table scrolling": "-webkit-overflow-scrolling: touch",
    "preformatted block containment": "pre {\n          max-width: 100%",
    "GFM dialect enum": "enum MarkdownPreviewDialect: String, CaseIterable, Identifiable",
    "GFM default": 'case gfm = "gfm"',
    "CommonMark dialect": 'case commonMark = "commonmark"',
    "GFM task list rendering": "task-list-item",
    "GFM strikethrough rendering": "<del>",
    "GFM Mermaid rendering": "mermaidDiagramHTML",
    "static Mermaid SVG": "simpleMermaidFlowchartSVG",
    "code block language picker": "code-block-language-picker",
    "code block syntax highlighter": "highlightBlock",
    "code block language inference": "inferredMarkdownPreviewCodeLanguage",
    "code block picker persistence": "localStorage",
    "large code highlight guard": "maxHighlightedCodeUnits",
    "preview runtime rejection guard": "unhandledrejection",
    "isolated code block enhancement": "enhanceCodeBlocks",
    "runtime iPhone safe area": "env(safe-area-inset-left)",
    "runtime iPhone heading clamp": "font-size: clamp(1.45em, 8vw, 1.7em)",
}

REQUIRED_UI_FRAGMENTS = {
    "iPhone WebView host inset": "iPhoneMarkdownPreviewWebViewHorizontalInset",
    "iPhone WebView horizontal padding": ".padding(.horizontal, iPhoneMarkdownPreviewWebViewHorizontalInset)",
    "iPhone WebView bottom inset": ".padding(.bottom, 8)",
    "single preview WebView host": "markdownPreviewWebViewHost",
}


def fail(message: str) -> None:
    print(f"[markdown-preview-theme-audit] {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    source = PREVIEW_EXPORT.read_text(encoding="utf-8")
    ui_source = PREVIEW_UI.read_text(encoding="utf-8")
    template_ids = re.findall(r'MarkdownPreviewTemplateOption\(id: "([^"]+)"', source)

    if len(template_ids) < 20:
        fail(f"expected at least 20 preview templates, found {len(template_ids)}")
    if len(template_ids) != len(set(template_ids)):
        duplicates = sorted({template_id for template_id in template_ids if template_ids.count(template_id) > 1})
        fail(f"duplicate template ids: {', '.join(duplicates)}")

    for description, fragment in REQUIRED_SOURCE_FRAGMENTS.items():
        if fragment not in source:
            fail(f"missing guardrail: {description}")
    for description, fragment in REQUIRED_UI_FRAGMENTS.items():
        if fragment not in ui_source:
            fail(f"missing compact iPhone UI guardrail: {description}")

    if "width: min(100%," in source:
        fail("invalid compact width guardrail: width:min cannot be used with templates whose maxWidth is none")
    if re.search(r"@media \(max-width: 480px\)[\s\S]*?\.content \{[\s\S]*?width:\s*100vw", source):
        fail("invalid iPhone preview clamp: .content must use width:100%, not 100vw")
    if re.search(r"@media \(max-width: 480px\)[\s\S]*?\.content \{[\s\S]*?max-width:\s*100vw", source):
        fail("invalid iPhone preview clamp: .content max-width must use 100%, not 100vw")
    if "max(19px, 1.18em)" in source or "112%" in source or "108%" in source:
        fail("invalid runtime font scaling: Markdown preview must stay anchored to the editor font size")
    if "-webkit-text-size-adjust: 100%" not in source or "font-size: 1em !important" not in source:
        fail("missing editor-size parity guardrail for iOS Markdown preview runtime CSS")

    fixture = CLIPPING_FIXTURE.read_text(encoding="utf-8")
    fixture_contracts = {
        "long heading": "Deliberately Long Heading",
        "long URL": "this-path-is-deliberately-long",
        "wide table": "| iPhone | Wide table |",
        "long inline code": "VeryLongInlineCodeIdentifierThatShouldWrap",
        "preformatted code block": "```swift",
    }
    for description, fragment in fixture_contracts.items():
        if fragment not in fixture:
            fail(f"fixture missing compact preview case: {description}")

    print(f"[markdown-preview-theme-audit] OK ({len(template_ids)} templates)")


if __name__ == "__main__":
    main()
