import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class MarkdownListReturnTests: XCTestCase {
    func testReturnAfterKeyboardReplacementRangePreservesTypedListText() {
        let text = "- bek" as NSString
        let proposedRange = NSRange(location: 2, length: 3)
        let selectedRange = NSRange(location: 5, length: 0)

        let context = autoIndentReturnContext(
            in: text,
            proposedRange: proposedRange,
            selectedRange: selectedRange
        )

        XCTAssertEqual(context?.replacementRange, NSRange(location: 5, length: 0))
        XCTAssertEqual(context?.linePrefix, "- bek")
        XCTAssertEqual(
            continuedMarkdownListPrefix(for: context?.linePrefix ?? "", normalizedIndent: ""),
            "- "
        )
    }

    func testReturnWithExplicitSelectionStillReplacesSelection() {
        let text = "- remove" as NSString
        let proposedRange = NSRange(location: 2, length: 6)
        let selectedRange = proposedRange

        let context = autoIndentReturnContext(
            in: text,
            proposedRange: proposedRange,
            selectedRange: selectedRange
        )

        XCTAssertEqual(context?.replacementRange, proposedRange)
        XCTAssertEqual(context?.linePrefix, "- ")
    }

    func testOrderedMarkdownListContinuationIncrementsNumber() {
        XCTAssertEqual(continuedMarkdownListPrefix(for: "1. First", normalizedIndent: ""), "2. ")
        XCTAssertEqual(continuedMarkdownListPrefix(for: "  9) Ninth", normalizedIndent: "  "), "  10) ")
    }

    func testUnorderedMarkdownListContinuationPreservesMarker() {
        XCTAssertEqual(continuedMarkdownListPrefix(for: "- First", normalizedIndent: ""), "- ")
        XCTAssertEqual(continuedMarkdownListPrefix(for: "  * First", normalizedIndent: "  "), "  * ")
    }

#if os(iOS) || os(visionOS)
    func testCollapsedSelectionUsesSystemEditMenu() {
        XCTAssertTrue(EditorEditMenuPolicy.shouldUseDefaultMenu(for: NSRange(location: 4, length: 0)))
        XCTAssertFalse(EditorEditMenuPolicy.shouldUseDefaultMenu(for: NSRange(location: 4, length: 3)))
    }
#endif

    func testMoveCurrentLineUpPreservesCaretColumn() throws {
        let source = "first\nsecond\nthird"
        let result = try XCTUnwrap(
            editorLineMove(
                in: source,
                selectedRange: NSRange(location: 8, length: 0),
                direction: .up
            )
        )

        let updated = (source as NSString).replacingCharacters(
            in: result.replacementRange,
            with: result.replacement
        )
        XCTAssertEqual(updated, "second\nfirst\nthird")
        XCTAssertEqual(result.selectedRange, NSRange(location: 2, length: 0))
    }

    func testMoveSelectedLinesDownKeepsSelectionLength() throws {
        let source = "one\ntwo\nthree\nfour"
        let selection = NSRange(location: 4, length: 9)
        let result = try XCTUnwrap(
            editorLineMove(in: source, selectedRange: selection, direction: .down)
        )

        let updated = (source as NSString).replacingCharacters(
            in: result.replacementRange,
            with: result.replacement
        )
        XCTAssertEqual(updated, "one\nfour\ntwo\nthree")
        XCTAssertEqual(result.selectedRange, NSRange(location: 9, length: selection.length))
    }

    func testMoveLineStopsAtDocumentBoundary() {
        XCTAssertNil(
            editorLineMove(
                in: "first\nsecond",
                selectedRange: NSRange(location: 0, length: 0),
                direction: .up
            )
        )
        XCTAssertNil(
            editorLineMove(
                in: "first\nsecond",
                selectedRange: NSRange(location: 12, length: 0),
                direction: .down
            )
        )
        XCTAssertNil(
            editorLineMove(
                in: "first\nsecond\n",
                selectedRange: NSRange(location: 6, length: 0),
                direction: .down
            )
        )
    }

    func testHTMLAutoCloseAddsOnlyNonVoidClosingTags() throws {
        let source = "<section class=\"hero\"" as NSString
        let insertion = try XCTUnwrap(
            htmlAutoCloseInsertion(
                in: source,
                insertionRange: NSRange(location: source.length, length: 0),
                language: "html"
            )
        )
        XCTAssertEqual(insertion.replacement, "></section>")
        XCTAssertEqual(insertion.caretOffset, 1)

        let image = "<img src=\"hero.png\"" as NSString
        XCTAssertNil(
            htmlAutoCloseInsertion(
                in: image,
                insertionRange: NSRange(location: image.length, length: 0),
                language: "html"
            )
        )
    }
}
