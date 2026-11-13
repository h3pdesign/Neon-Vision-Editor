import XCTest
@testable import Neon_Vision_Editor
#if os(macOS)
import AppKit
#endif

final class StructureFoldingTests: XCTestCase {
    private let json = """
    {
      "a": {
        "b": 1
      },
      "c": [
        1,
        2
      ],
      "s": "{ [ not structure",
      "d": {"x": 1}
    }
    """

    private let xml = """
    <?xml version="1.0"?>
    <root>
      <!-- a
      comment -->
      <item id="a>b">
        <child/>
        <![CDATA[ <not> ]]>
      </item>
      <empty></empty>
    </root>
    """

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    // MARK: Scanner

    func testLineOpensStructureIgnoresStringsAndClosedStructures() {
        XCTAssertTrue(StructureFoldScanner.lineOpensStructure(#"  "a": {"#, syntax: .json))
        XCTAssertTrue(StructureFoldScanner.lineOpensStructure("}, [", syntax: .json))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure(#"  "d": {"x": 1}"#, syntax: .json))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure(#"  "s": "{ ["#, syntax: .json))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure(#"  "s": "\" {""#, syntax: .json))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure("  // {", syntax: .json))

        XCTAssertTrue(StructureFoldScanner.lineOpensStructure(#"  <item id="a>b">"#, syntax: .xml))
        XCTAssertTrue(StructureFoldScanner.lineOpensStructure("  <!-- a", syntax: .xml))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure("  <child/>", syntax: .xml))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure("  <empty></empty>", syntax: .xml))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure(#"<?xml version="1.0"?>"#, syntax: .xml))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure("  <![CDATA[ <not> ]]>", syntax: .xml))
        XCTAssertFalse(StructureFoldScanner.lineOpensStructure(String(repeating: "[", count: 30_000), syntax: .json))
    }

    func testJSONRegionsEndOnTheMatchingCloserLine() throws {
        let document = FileBackedTextDocument(content: json)
        XCTAssertEqual(try StructureFoldScanner.region(startingAt: 0, in: document, syntax: .json)?.endLine, 10)
        XCTAssertEqual(try StructureFoldScanner.region(startingAt: 1, in: document, syntax: .json)?.endLine, 3)
        XCTAssertEqual(try StructureFoldScanner.region(startingAt: 4, in: document, syntax: .json)?.endLine, 7)
        XCTAssertNil(try StructureFoldScanner.region(startingAt: 2, in: document, syntax: .json))
        XCTAssertNil(try StructureFoldScanner.region(startingAt: 8, in: document, syntax: .json))
        XCTAssertNil(try StructureFoldScanner.region(startingAt: 9, in: document, syntax: .json))

        let region = try XCTUnwrap(StructureFoldScanner.region(startingAt: 4, in: document, syntax: .json))
        let source = json as NSString
        XCTAssertEqual(source.substring(with: NSRange(
            location: region.hiddenStartUTF16, length: region.hiddenEndUTF16 - region.hiddenStartUTF16
        )), "    1,\n    2\n")
    }

    func testXMLRegionsSkipCommentsCDATASelfClosingTagsAndQuotedBrackets() throws {
        let document = FileBackedTextDocument(content: xml)
        XCTAssertEqual(try StructureFoldScanner.region(startingAt: 1, in: document, syntax: .xml)?.endLine, 9)
        XCTAssertEqual(try StructureFoldScanner.region(startingAt: 4, in: document, syntax: .xml)?.endLine, 7)
        // A two-line comment has nothing between its lines to hide.
        XCTAssertNil(try StructureFoldScanner.region(startingAt: 2, in: document, syntax: .xml))
        XCTAssertNil(try StructureFoldScanner.region(startingAt: 0, in: document, syntax: .xml))
        XCTAssertNil(try StructureFoldScanner.region(startingAt: 8, in: document, syntax: .xml))
    }

    func testAllRegionsMatchSingleRegionScansWithDepthAndOffsets() throws {
        for (text, syntax) in [(json, StructureFoldSyntax.json), (xml, .xml)] {
            let document = FileBackedTextDocument(content: text)
            let all = try StructureFoldScanner.allRegions(in: document, syntax: syntax)
            XCTAssertFalse(all.isEmpty)
            for region in all {
                let single = try XCTUnwrap(StructureFoldScanner.region(startingAt: region.headerLine, in: document, syntax: syntax))
                XCTAssertEqual(single.endLine, region.endLine)
                XCTAssertEqual(single.hiddenStartUTF16, region.hiddenStartUTF16)
                XCTAssertEqual(single.hiddenEndUTF16, region.hiddenEndUTF16)
            }
            XCTAssertEqual(all.filter { $0.depth == 0 }.count, 1)
        }
        let nonASCII = "{\n  \"é😀\": [\n    \"😀\"\n  ]\n}"
        let document = FileBackedTextDocument(content: nonASCII)
        let region = try XCTUnwrap(StructureFoldScanner.allRegions(in: document, syntax: .json).first { $0.headerLine == 1 })
        XCTAssertEqual((nonASCII as NSString).substring(with: NSRange(
            location: region.hiddenStartUTF16, length: region.hiddenEndUTF16 - region.hiddenStartUTF16
        )), "    \"😀\"\n")
    }

    // MARK: Model and folded document

    private func foldedJSON() throws -> (FileBackedTextDocument, StructureFoldModel, FoldedEditorDocument) {
        let base = FileBackedTextDocument(content: json)
        let model = StructureFoldModel()
        for header in [1, 4] {
            model.add(try XCTUnwrap(StructureFoldScanner.region(startingAt: header, in: base, syntax: .json)).fold)
        }
        return (base, model, FoldedEditorDocument(base: base, model: model))
    }

    func testFoldedDocumentHidesLinesBetweenHeaderAndCloser() throws {
        let (base, model, folded) = try foldedJSON()
        let all = lines(json)
        let visible = [0, 1, 3, 4, 7, 8, 9, 10]
        let expected = visible.map { all[$0] }.joined(separator: "\n")

        XCTAssertEqual(folded.lineCount, visible.count)
        XCTAssertEqual(folded.utf16Length, (expected as NSString).length)
        XCTAssertEqual(try folded.viewport(aroundLine: 0, maximumByteCount: 64 * 1024, maximumLineCount: 512).text, expected)
        for (foldedLine, documentLine) in visible.enumerated() {
            XCTAssertEqual(model.documentLine(forFoldedLine: foldedLine), documentLine)
            XCTAssertEqual(model.foldedLine(forDocumentLine: documentLine), foldedLine)
        }
        // Hidden lines map to their fold's header.
        XCTAssertEqual(model.foldedLine(forDocumentLine: 2), 1)
        XCTAssertEqual(model.foldedLine(forDocumentLine: 6), 3)

        // A window in the middle is stitched from the visible parts.
        let middle = try folded.viewport(aroundLine: 3, maximumByteCount: 64 * 1024, maximumLineCount: 2)
        XCTAssertEqual(middle.lineRange, 2...3)
        XCTAssertEqual(middle.text, all[3] + "\n" + all[4] + "\n")
        XCTAssertEqual((expected as NSString).substring(with: NSRange(location: middle.startUTF16Offset, length: (middle.text as NSString).length)), middle.text)

        // Every folded offset maps to the same character in the document.
        let source = json as NSString
        let foldedSource = expected as NSString
        for offset in 0..<foldedSource.length {
            let documentOffset = model.documentOffset(forFoldedOffset: offset)
            XCTAssertEqual(source.character(at: documentOffset), foldedSource.character(at: offset), "offset \(offset)")
            XCTAssertEqual(model.foldedOffset(forDocumentOffset: documentOffset), offset)
            let position = try folded.position(atUTF16Offset: offset)
            let documentPosition = try base.position(atUTF16Offset: documentOffset)
            XCTAssertEqual(position.column, documentPosition.column)
            XCTAssertEqual(model.documentLine(forFoldedLine: position.line), documentPosition.line)
        }
    }

    func testRangesAcrossFoldsIncludeHiddenLinesOnlyWhenTheySpanThem() throws {
        let (_, model, folded) = try foldedJSON()
        let foldedSource = try folded.viewport(aroundLine: 0, maximumByteCount: 64 * 1024, maximumLineCount: 512).text as NSString
        let headerEnd = foldedSource.range(of: "\"a\": {").upperBound
        // The header's line break up to the closing line: no hidden text.
        let lineBreak = NSRange(location: headerEnd, length: 1)
        XCTAssertFalse(model.foldedRangeSpansHiddenText(lineBreak))
        XCTAssertEqual(model.documentRange(forFoldedRange: lineBreak).length, 1)
        // Header through closer: spans the hidden line, and copying includes it.
        let span = NSRange(location: headerEnd - 1, length: 3)
        XCTAssertTrue(model.foldedRangeSpansHiddenText(span))
        XCTAssertEqual(try folded.text(inUTF16Range: span), "{\n    \"b\": 1\n ")
    }

    func testEditsMoveLaterFoldsAndRemoveTouchedFolds() throws {
        let (base, model, folded) = try foldedJSON()
        let before = model.folds
        // Insert a line at the document start: both folds move down a line.
        try folded.replace(utf16Range: NSRange(location: 0, length: 0), with: "\n")
        XCTAssertEqual(base.string(), "\n" + json)
        XCTAssertEqual(model.folds.map(\.headerLine), before.map { $0.headerLine + 1 })
        XCTAssertEqual(model.folds.map(\.hiddenStartUTF16), before.map { $0.hiddenStartUTF16 + 1 })
        let region = try XCTUnwrap(StructureFoldScanner.region(startingAt: 2, in: base, syntax: .json))
        XCTAssertEqual(model.folds.first, region.fold)

        // Deleting the first header's line break opens that fold only.
        let firstHeaderBreak = model.folds[0].hiddenStartUTF16 - 1
        model.applyEdit(range: NSRange(location: firstHeaderBreak, length: 1), replacementUTF16Length: 0, lineDelta: -1)
        XCTAssertEqual(model.folds.count, 1)
        XCTAssertEqual(model.folds[0].headerLine, before[1].headerLine)

        // An edit after a fold leaves it alone.
        let last = model.folds[0]
        model.applyEdit(range: NSRange(location: last.hiddenEndUTF16 + 2, length: 0), replacementUTF16Length: 4, lineDelta: 0)
        XCTAssertEqual(model.folds, [last])
    }

    func testNestedFoldsStayFoldedWhenTheirParentOpens() throws {
        let base = FileBackedTextDocument(content: json)
        let model = StructureFoldModel()
        let regions = try StructureFoldScanner.allRegions(in: base, syntax: .json)
        model.setFolds(regions.map(\.fold))
        XCTAssertEqual(model.visibleFolds.map(\.headerLine), [0])
        XCTAssertEqual(FoldedEditorDocument(base: base, model: model).lineCount, 2)
        XCTAssertTrue(model.removeFold(headerLine: 0))
        XCTAssertEqual(model.visibleFolds.map(\.headerLine), [1, 4])

        XCTAssertTrue(model.reveal(NSRange(location: model.visibleFolds[0].hiddenStartUTF16, length: 0)))
        XCTAssertEqual(model.visibleFolds.map(\.headerLine), [4])
        XCTAssertTrue(model.reveal(line: 5))
        XCTAssertTrue(model.isEmpty)
    }

    func testFoldSyntaxCoversJSONAndXMLOnly() {
        for language in ["json", "JSON", "jsonc", "json5", "ipynb"] {
            XCTAssertEqual(StructureFoldSyntax.forLanguage(language), .json, language)
        }
        for language in ["xml", "plist", "svg"] {
            XCTAssertEqual(StructureFoldSyntax.forLanguage(language), .xml, language)
        }
        for language in ["html", "swift", "plain", "yaml"] {
            XCTAssertNil(StructureFoldSyntax.forLanguage(language), language)
        }
    }

    // MARK: Editor

#if os(macOS)
    @MainActor
    func testCanvasFoldsEditsAndPublishesDocumentCoordinates() throws {
        let base = FileBackedTextDocument(content: json)
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(CGSize(width: 800, height: 600))
        let documentID = UUID()
        var revision = 0
        var appliedRanges: [NSRange] = []
        func configure() {
            canvas.configure(
                document: base, documentID: documentID, resourceID: "fold.json", displayName: "fold.json",
                contentRevision: revision, externalContentRevision: 0, caret: 0, language: "json",
                colorScheme: .light, fontSize: 14, fontName: "", lineHeightMultiplier: 1,
                isReadOnly: false, translucentBackgroundEnabled: false, showsLineNumbers: true,
                highlightCurrentLine: false, lineWrapEnabled: true, showsInvisibleCharacters: false,
                showsIndentationGuides: false, showsScopeGuides: false, highlightsScopeBackground: false,
                highlightsMatchingBrackets: false, autoIndentEnabled: false, autoCloseBracketsEnabled: false,
                onFontSizeChange: nil,
                onTextMutation: { mutation in
                    XCTAssertNil(mutation.viewport, "Folded edits are sent in document coordinates")
                    appliedRanges.append(mutation.range)
                    try? base.replace(utf16Range: mutation.range, with: mutation.replacement)
                    revision += 1
                    return true
                }
            )
        }
        configure()
        XCTAssertTrue(canvas.toggleFold(atCanvasLine: 4))
        XCTAssertFalse(canvas.foldModel.isEmpty)
        let all = lines(json)
        XCTAssertEqual(canvas.installedViewportTextForTesting, ([0, 1, 2, 3, 4, 7, 8, 9, 10].map { all[$0] }).joined(separator: "\n"))
        XCTAssertEqual(canvas.documentLine(forCanvasLine: 5), 7)

        // Typing at the start of the closing line lands there in the document.
        let closingLineStart = (canvas.installedViewportTextForTesting as NSString).range(of: "  ],").location
        canvas.setAccessibilitySelectedTextRange(NSRange(location: closingLineStart, length: 0))
        canvas.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        configure()
        let documentClosingLineStart = (json as NSString).range(of: "  ],").location
        XCTAssertEqual(appliedRanges.last, NSRange(location: documentClosingLineStart, length: 0))
        XCTAssertTrue(base.string().contains("    2\nX  ],"))
        XCTAssertFalse(canvas.foldModel.isEmpty, "An edit after the hidden lines keeps the fold")

        // Unfolding restores every line.
        XCTAssertTrue(canvas.toggleFold(atCanvasLine: 4))
        XCTAssertTrue(canvas.foldModel.isEmpty)
        XCTAssertEqual(canvas.installedViewportTextForTesting, base.string())
    }

    @MainActor
    func testCanvasOpensAFoldInsteadOfReplacingHiddenLines() throws {
        let base = FileBackedTextDocument(content: json)
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(CGSize(width: 800, height: 600))
        var mutations = 0
        canvas.configure(
            document: base, documentID: UUID(), resourceID: "span.json", displayName: "span.json",
            contentRevision: 0, externalContentRevision: 0, caret: 0, language: "json",
            colorScheme: .light, fontSize: 14, fontName: "", lineHeightMultiplier: 1,
            isReadOnly: false, translucentBackgroundEnabled: false, showsLineNumbers: true,
            highlightCurrentLine: false, lineWrapEnabled: true, showsInvisibleCharacters: false,
            showsIndentationGuides: false, showsScopeGuides: false, highlightsScopeBackground: false,
            highlightsMatchingBrackets: false, autoIndentEnabled: false, autoCloseBracketsEnabled: false,
            onFontSizeChange: nil,
            onTextMutation: { _ in
                mutations += 1
                return true
            }
        )
        XCTAssertTrue(canvas.toggleFold(atCanvasLine: 1))
        let folded = canvas.installedViewportTextForTesting as NSString
        let header = folded.range(of: "\"a\": {")
        canvas.setAccessibilitySelectedTextRange(NSRange(location: header.location, length: folded.range(of: "},").upperBound - header.location))
        canvas.insertText("Z", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(mutations, 0)
        XCTAssertTrue(canvas.foldModel.isEmpty)
        XCTAssertEqual(base.string(), json)
    }
#endif
}

private extension NSRange {
    var upperBound: Int { NSMaxRange(self) }
}
