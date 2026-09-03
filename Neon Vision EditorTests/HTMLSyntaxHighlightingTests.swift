import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

@MainActor
final class HTMLSyntaxHighlightingTests: XCTestCase {
    private let colors = SyntaxColors.fromVibrantLightTheme(colorScheme: .dark)

    func testFeedbackStyleBlockAndInlineStylesUseNumberColor() {
        let source = """
        <STYLE type="text/css">
        html, body { margin: 0 auto !important; padding: 0; height: 100%; width: 100%; }
        table, td { mso-table-lspace: 0pt !important; }
        .logo-mark { --accent: #64b2ba; opacity: .18; left: -2.5px; transform: rotate(135deg); }
        </STYLE>
        <div STYLE="margin:0; width:100%; font-size:1px" width="680">2026</div>
        """
        let spans = scan(source)
        for token in ["0 auto", "0pt", "100%", "#64b2ba", ".18", "-2.5px", "135deg", "1px"] {
            assertColor(token == "0 auto" ? "0" : token, in: source, spans: spans, is: colors.number)
        }
        assertColor("mso-table-lspace", in: source, spans: spans, is: colors.property)
        assertColor("!important", in: source, spans: spans, is: colors.keyword)
        assertColor("680", in: source, spans: spans, is: colors.string)
        XCTAssertNil(color(at: (source as NSString).range(of: "2026").location, spans: spans))
        let inline = #"<div style='padding:0; width:100%' data-id='42'>"#
        assertColor("100%", in: inline, spans: scan(inline), is: colors.number)
        assertColor("42", in: inline, spans: scan(inline), is: colors.string)
    }

    func testCommentsStringsAndRawTextDoNotBecomeCSSNumbers() {
        let source = """
        <!-- <style>height: 101px;</style> -->
        <script>const html = '<style>width: 202px;</style>';</script>
        <textarea><style>width: 303px;</style></textarea>
        <style>
        /* comment: 404px; content: "test";
           still comment: 405px; */
        div { content: "505px \\"quoted\\""; width: 606px; }
        </style>
        <div title="width:707px" style="content:'808px';width:909px"></div>
        """
        let spans = scan(source)
        for token in ["101px", "404px", "405px"] { assertColor(token, in: source, spans: spans, is: colors.comment) }
        for token in ["505px", "707px", "808px"] { assertColor(token, in: source, spans: spans, is: colors.string) }
        for token in ["606px", "909px"] { assertColor(token, in: source, spans: spans, is: colors.number) }
        for token in ["202px", "303px"] { XCTAssertNil(color(at: (source as NSString).range(of: token).location, spans: spans)) }
    }

    func testContextSurvivesLinesIncompleteAttributesAndRecovery() {
        var state = HTMLSyntaxState()
        let lines = ["<style>\n", "/* 10px\n", "20px */\n", "p { width: 30px; }\n", "</style>\n", "<div\n", " STYLE =\n", " \"width:40px;\n", "height:50px\" data-size=60>70</div>\n"]
        let expected: [String: Color] = ["10px": colors.comment, "20px": colors.comment, "30px": colors.number, "40px": colors.number, "50px": colors.number, "60": colors.string]
        for line in lines {
            let spans = scan(line, state: &state)
            for (token, color) in expected where line.contains(token) { assertColor(token, in: line, spans: spans, is: color) }
        }
        XCTAssertEqual(state.phase, .text)
        XCTAssertEqual(scan("", state: &state).count, 0)
        let malformed = #"<div style="width:12px" title="unfinished"#
        assertColor("12px", in: malformed, spans: scan(malformed), is: colors.number)
        var invalidState = HTMLSyntaxState()
        XCTAssertTrue(HTMLSyntaxHighlighter.ranges(in: "abc", range: NSRange(location: NSNotFound, length: 1), state: &invalidState, colors: colors).isEmpty)
    }

    func testChunkBoundariesProduceSameContextAsWholePrefix() {
        let contexts = ["<style>/* 12px */\n", "<!-- <style> -->\n", "<script>'<style>'\n", "<div style=\"content:'hi';\n", "<style>div{content:\"abc\\\"def\";}\n"]
        for prefix in contexts {
            for padding in 0..<90 {
                let text = String(repeating: "😀 ", count: padding) + prefix
                var whole = HTMLSyntaxState()
                _ = scan(text, state: &whole)
                var chunked = HTMLSyntaxState()
                var pending = ""
                // Different artificial byte boundaries, including within delimiters.
                for character in text {
                    pending.append(character)
                    let ns = pending as NSString
                    if ns.length > 80 {
                        let cut = HTMLSyntaxHighlighter.safePrefixLength(ns)
                        _ = scan(ns.substring(to: cut), state: &chunked)
                        pending = ns.substring(from: cut)
                    }
                }
                _ = scan(pending, state: &chunked)
                XCTAssertEqual(chunked, whole, "padding=\(padding), prefix=\(prefix)")
            }
        }
    }

    private func scan(_ source: String) -> [(NSRange, Color)] {
        var state = HTMLSyntaxState()
        return scan(source, state: &state)
    }
    private func scan(_ source: String, state: inout HTMLSyntaxState) -> [(NSRange, Color)] {
        HTMLSyntaxHighlighter.ranges(in: source as NSString, range: NSRange(location: 0, length: source.utf16.count), state: &state, colors: colors)
    }
    private func color(at index: Int, spans: [(NSRange, Color)]) -> Color? {
        spans.last { NSLocationInRange(index, $0.0) }?.1
    }
    private func assertColor(_ token: String, in source: String, spans: [(NSRange, Color)], is expected: Color, file: StaticString = #filePath, line: UInt = #line) {
        let range = (source as NSString).range(of: token)
        XCTAssertNotEqual(range.location, NSNotFound, file: file, line: line)
        guard range.location != NSNotFound else { return }
        for index in range.location..<NSMaxRange(range) {
            XCTAssertEqual(color(at: index, spans: spans), expected, "\(token) at \(index)", file: file, line: line)
        }
    }
}

#if os(macOS)
import AppKit

@MainActor
final class HTMLVirtualEditorTests: XCTestCase {
    func testRenderedColorsSurviveScrollingEditsAndCancellation() async throws {
        let source = "<style>\n" + String(repeating: ".box { width:100%; margin:0pt; }\n", count: 4_000) + "</style>\n<div style=\"font-size:1px\" width=\"680\"></div>\n"
        let document = FileBackedTextDocument(content: source)
        let documentID = UUID()
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(NSSize(width: 800, height: 600))
        let started = ProcessInfo.processInfo.systemUptime
        configure(canvas, document: document, id: documentID, revision: 0, caret: source.utf16.count / 2)
        await canvas.syntaxHighlightTask?.value
        let colors = SyntaxColors.from(theme: currentEditorTheme(colorScheme: .dark))
        XCTAssertFalse((canvas.accessibilityValue() as? String ?? "").contains("<style>"))
        try assertRendered("100%", canvas: canvas, expected: NSColor(colors.number))
        print("HTML_INITIAL_CONTEXT_AND_RENDER_MS=\((ProcessInfo.processInfo.systemUptime - started) * 1000)")
        for location in [0, source.utf16.count - 60, source.utf16.count / 2] {
            NotificationCenter.default.post(name: .moveCursorToRange, object: nil, userInfo: [
                EditorCommandUserInfo.documentID: documentID.uuidString,
                EditorCommandUserInfo.rangeLocation: location,
                EditorCommandUserInfo.rangeLength: 0,
                EditorCommandUserInfo.centerSelection: true
            ])
            await canvas.syntaxHighlightTask?.value
            try assertRendered("100%", canvas: canvas, expected: NSColor(colors.number))
        }
        // Same-length edits above the viewport must invalidate lexical context.
        try document.replace(utf16Range: NSRange(location: 1, length: 5), with: "xxxxx")
        configure(canvas, document: document, id: documentID, revision: 1, caret: 0)
        await canvas.syntaxHighlightTask?.value
        try assertRendered("100%", canvas: canvas, expected: NSColor(currentEditorTheme(colorScheme: .dark).text))
        try document.replace(utf16Range: NSRange(location: 1, length: 5), with: "style")
        configure(canvas, document: document, id: documentID, revision: 2, caret: 0)
        try document.replace(utf16Range: NSRange(location: 1, length: 5), with: "xxxxx")
        configure(canvas, document: document, id: documentID, revision: 3, caret: 0)
        await canvas.syntaxHighlightTask?.value
        try assertRendered("100%", canvas: canvas, expected: NSColor(currentEditorTheme(colorScheme: .dark).text))
        // The existing accessibility and keyboard input contract stays intact.
        XCTAssertEqual(canvas.accessibilityRole(), .textArea)
        XCTAssertTrue(canvas.acceptsFirstResponder)
        XCTAssertTrue(canvas.isAccessibilityElement())
    }

    func testRenderedInlineStylesAndNumbersUseCurrentTheme() async throws {
        let source = #"<div style="font-size:1px; width:100%" width="680">"#
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(NSSize(width: 800, height: 600))
        let document = FileBackedTextDocument(content: source)
        let id = UUID()
        for scheme in [ColorScheme.light, .dark] {
            configure(canvas, document: document, id: id, revision: 0, caret: 0, scheme: scheme)
            await canvas.syntaxHighlightTask?.value
            let colors = SyntaxColors.from(theme: currentEditorTheme(colorScheme: scheme))
            try assertRendered("1px", canvas: canvas, expected: NSColor(colors.number))
            try assertRendered("100%", canvas: canvas, expected: NSColor(colors.number))
            try assertRendered("680", canvas: canvas, expected: NSColor(colors.string))
        }
    }

    private func assertRendered(_ token: String, canvas: VirtualEditorCanvas, expected: NSColor, file: StaticString = #filePath, line: UInt = #line) throws {
        let visible = try XCTUnwrap(canvas.accessibilityValue() as? String)
        let lines = visible.components(separatedBy: "\n")
        let index = try XCTUnwrap(lines.firstIndex { $0.contains(token) })
        let attributed = canvas.attributedLine(lines[index], localLine: index)
        let range = (lines[index] as NSString).range(of: token)
        for offset in range.location..<NSMaxRange(range) {
            XCTAssertEqual(attributed.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor, expected, file: file, line: line)
        }
    }

    private func configure(_ canvas: VirtualEditorCanvas, document: FileBackedTextDocument, id: UUID, revision: Int, caret: Int, scheme: ColorScheme = .dark) {
        canvas.configure(document: document, documentID: id, resourceID: "html-feedback", displayName: "feedback.html",
            contentRevision: revision, externalContentRevision: 0, caret: caret, language: "html", colorScheme: scheme,
            fontSize: 14, fontName: "", lineHeightMultiplier: 1, isReadOnly: false, translucentBackgroundEnabled: false,
            showsLineNumbers: true, highlightCurrentLine: false, lineWrapEnabled: true, showsInvisibleCharacters: false,
            showsIndentationGuides: false, showsScopeGuides: false, highlightsScopeBackground: false,
            highlightsMatchingBrackets: false, autoIndentEnabled: true, autoCloseBracketsEnabled: false,
            onFontSizeChange: nil, onTextMutation: nil)
    }
}
#endif
