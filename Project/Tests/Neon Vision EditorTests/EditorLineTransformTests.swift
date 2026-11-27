import XCTest
@testable import Neon_Vision_Editor

/// Line commands change only the lines the selection touches.
@MainActor
final class EditorLineTransformTests: XCTestCase {
    private func apply(
        _ transform: EditorLineTransform,
        to text: String,
        selection: NSRange,
        language: String = "swift"
    ) throws -> (text: String, selection: NSRange) {
        let result = try XCTUnwrap(
            editorLineTransform(in: text, selectedRange: selection, transform: transform, language: language)
        )
        let updated = (text as NSString).replacingCharacters(in: result.replacementRange, with: result.replacement)
        return (updated, result.selectedRange)
    }

    // MARK: Duplicate and delete

    func testDuplicateCopiesCaretLineBelowAndMovesCaretOntoCopy() throws {
        let output = try apply(.duplicate, to: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(output.text, "one\ntwo\ntwo\nthree")
        XCTAssertEqual(output.selection, NSRange(location: 9, length: 0))
    }

    func testDuplicateCopiesEverySelectedLine() throws {
        let output = try apply(.duplicate, to: "a\nb\nc", selection: NSRange(location: 0, length: 3))
        XCTAssertEqual(output.text, "a\nb\na\nb\nc")
        XCTAssertEqual(output.selection, NSRange(location: 4, length: 3))
    }

    func testDeleteRemovesOnlyTheCaretLine() throws {
        let output = try apply(.delete, to: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(output.text, "one\nthree")
        XCTAssertEqual(output.selection, NSRange(location: 4, length: 0))
    }

    func testDeleteLastLineRemovesPrecedingLineBreak() throws {
        let output = try apply(.delete, to: "one\ntwo", selection: NSRange(location: 6, length: 0))
        XCTAssertEqual(output.text, "one")
        XCTAssertEqual(output.selection, NSRange(location: 0, length: 0))
    }

    func testSelectionEndingAfterLineBreakExcludesNextLine() throws {
        let output = try apply(.delete, to: "a\nb\nc", selection: NSRange(location: 0, length: 2))
        XCTAssertEqual(output.text, "b\nc")
    }

    func testDuplicateLastLineOfCRLFDocumentKeepsCRLF() throws {
        let output = try apply(.duplicate, to: "a\r\nb", selection: NSRange(location: 4, length: 0))
        XCTAssertEqual(output.text, "a\r\nb\r\nb")
        XCTAssertEqual(output.selection, NSRange(location: 7, length: 0))
        XCTAssertEqual(try apply(.duplicate, to: "a\r\nb\r\n", selection: NSRange(location: 0, length: 0)).text, "a\r\na\r\nb\r\n")
        XCTAssertEqual(try apply(.duplicate, to: "a\r\nb", selection: NSRange(location: 0, length: 4)).text, "a\r\nb\r\na\r\nb")
    }

    func testDeleteLastLineOfCRLFDocumentRemovesWholeLineBreak() throws {
        let output = try apply(.delete, to: "one\r\ntwo", selection: NSRange(location: 6, length: 0))
        XCTAssertEqual(output.text, "one")
        XCTAssertEqual(output.selection, NSRange(location: 0, length: 0))
    }

    func testDeleteInEmptyDocumentDoesNothing() {
        XCTAssertNil(editorLineTransform(in: "", selectedRange: NSRange(location: 0, length: 0), transform: .delete))
    }

    // MARK: Toggle comment

    func testToggleCommentCommentsCaretLineAtItsIndentation() throws {
        let output = try apply(.toggleComment, to: "let a = 1\n    let b = 2\nlet c = 3", selection: NSRange(location: 14, length: 0))
        XCTAssertEqual(output.text, "let a = 1\n    // let b = 2\nlet c = 3")
        XCTAssertEqual(output.selection, NSRange(location: 17, length: 0))
    }

    func testToggleCommentUncommentsWhenEverySelectedLineIsCommented() throws {
        let output = try apply(.toggleComment, to: "// a\n  // b\nc", selection: NSRange(location: 0, length: 11))
        XCTAssertEqual(output.text, "a\n  b\nc")
    }

    func testToggleCommentCommentsMixedSelectionAtSharedIndentAndSkipsBlankLines() throws {
        let source = "    if x {\n\n        // y\n    }"
        let output = try apply(.toggleComment, to: source, selection: NSRange(location: 0, length: (source as NSString).length))
        XCTAssertEqual(output.text, "    // if x {\n\n    //     // y\n    // }")
    }

    func testToggleCommentUsesLanguageSyntax() throws {
        XCTAssertEqual(try apply(.toggleComment, to: "x = 1", selection: NSRange(location: 0, length: 0), language: "python").text, "# x = 1")
        XCTAssertEqual(try apply(.toggleComment, to: "SELECT 1", selection: NSRange(location: 0, length: 0), language: "sql").text, "-- SELECT 1")
        XCTAssertEqual(try apply(.toggleComment, to: "<p>Hi</p>", selection: NSRange(location: 0, length: 0), language: "html").text, "<!-- <p>Hi</p> -->")
        XCTAssertEqual(try apply(.toggleComment, to: "a { }", selection: NSRange(location: 0, length: 0), language: "css").text, "/* a { } */")
        XCTAssertEqual(try apply(.toggleComment, to: "{title}", selection: NSRange(location: 0, length: 0), language: "expressionengine").text, "{!-- {title} --}")
        XCTAssertEqual(try apply(.toggleComment, to: "{!-- {title} --}", selection: NSRange(location: 0, length: 0), language: "expressionengine").text, "{title}")
        XCTAssertEqual(try apply(.toggleComment, to: "DISPLAY X.", selection: NSRange(location: 0, length: 0), language: "cobol").text, "*> DISPLAY X.")
    }

    func testToggleCommentRemovesBlockDelimiters() throws {
        XCTAssertEqual(try apply(.toggleComment, to: "  <!-- <p>Hi</p> -->", selection: NSRange(location: 4, length: 0), language: "html").text, "  <p>Hi</p>")
        XCTAssertEqual(try apply(.toggleComment, to: "/*a*/", selection: NSRange(location: 0, length: 0), language: "css").text, "a")
    }

    func testToggleCommentKeepsCarriageReturns() throws {
        let output = try apply(.toggleComment, to: "a\r\nb\r\nc", selection: NSRange(location: 0, length: 4), language: "html")
        XCTAssertEqual(output.text, "<!-- a -->\r\n<!-- b -->\r\nc")
    }

    func testToggleCommentDoesNothingWithoutCommentSyntax() {
        XCTAssertNil(editorLineTransform(in: "{\"a\": 1}", selectedRange: NSRange(location: 0, length: 0), transform: .toggleComment, language: "json"))
        XCTAssertNil(editorLineTransform(in: "text", selectedRange: NSRange(location: 0, length: 0), transform: .toggleComment, language: "plain"))
    }

    func testToggleCommentOnBlankLineDoesNothing() {
        XCTAssertNil(editorLineTransform(in: "a\n   \nb", selectedRange: NSRange(location: 3, length: 0), transform: .toggleComment))
    }

    // MARK: Case, sort, join

    func testUppercaseChangesOnlyTheSelection() throws {
        let output = try apply(.uppercase, to: "hello world\nnext", selection: NSRange(location: 6, length: 5))
        XCTAssertEqual(output.text, "hello WORLD\nnext")
        XCTAssertEqual(output.selection, NSRange(location: 6, length: 5))
    }

    func testLowercaseWithoutSelectionChangesTheCaretLine() throws {
        let output = try apply(.lowercase, to: "KEEP\nLOWER ME\nKEEP", selection: NSRange(location: 7, length: 0))
        XCTAssertEqual(output.text, "KEEP\nlower me\nKEEP")
        XCTAssertEqual(output.selection, NSRange(location: 7, length: 0))
    }

    func testSortSortsOnlySelectedLines() throws {
        let output = try apply(.sort, to: "z\nc\nb\na\nz", selection: NSRange(location: 2, length: 5))
        XCTAssertEqual(output.text, "z\na\nb\nc\nz")
        XCTAssertEqual(output.selection, NSRange(location: 2, length: 5))
    }

    func testSortUniqueRemovesExactDuplicatesInSelection() throws {
        let output = try apply(.sortUnique, to: "b\na\nb\nkeep", selection: NSRange(location: 0, length: 5))
        XCTAssertEqual(output.text, "a\nb\nkeep")
    }

    func testSortKeepsCRLFWhenLastLineHasNoLineBreak() throws {
        let source = "b\r\nc\r\na"
        let output = try apply(.sort, to: source, selection: NSRange(location: 0, length: (source as NSString).length))
        XCTAssertEqual(output.text, "a\r\nb\r\nc")
        let unique = try apply(.sortUnique, to: "b\r\na\r\nb", selection: NSRange(location: 0, length: 7))
        XCTAssertEqual(unique.text, "a\r\nb")
    }

    func testMoveLastLineOfCRLFDocumentKeepsCRLF() throws {
        let source = "a\r\nb"
        let up = try XCTUnwrap(editorLineMove(in: source, selectedRange: NSRange(location: 3, length: 0), direction: .up))
        XCTAssertEqual((source as NSString).replacingCharacters(in: up.replacementRange, with: up.replacement), "b\r\na")
        XCTAssertEqual(up.selectedRange, NSRange(location: 0, length: 0))
        let down = try XCTUnwrap(editorLineMove(in: source, selectedRange: NSRange(location: 0, length: 0), direction: .down))
        XCTAssertEqual((source as NSString).replacingCharacters(in: down.replacementRange, with: down.replacement), "b\r\na")
        XCTAssertEqual(down.selectedRange, NSRange(location: 3, length: 0))
    }

    func testJoinWithoutSelectionJoinsCaretLineWithNextLine() throws {
        let output = try apply(.join, to: "first  \n   second\nthird", selection: NSRange(location: 2, length: 0))
        XCTAssertEqual(output.text, "first second\nthird")
        XCTAssertEqual(output.selection, NSRange(location: 5, length: 0))
    }

    func testJoinSelectedLinesKeepsIndentAndOtherLines() throws {
        let source = "keep\n  a\n\n  b\nkeep"
        let output = try apply(.join, to: source, selection: NSRange(location: 5, length: 8))
        XCTAssertEqual(output.text, "keep\n  a b\nkeep")
    }

    func testJoinOnLastLineDoesNothing() {
        XCTAssertNil(editorLineTransform(in: "a\nb", selectedRange: NSRange(location: 3, length: 0), transform: .join))
    }

    func testJoinKeepsCarriageReturnOfLastJoinedLine() throws {
        XCTAssertEqual(try apply(.join, to: "a\r\nb\r\nc", selection: NSRange(location: 0, length: 0)).text, "a b\r\nc")
    }

    // MARK: Trim trailing whitespace

    func testTrimTrailingWhitespaceKeepsIndentationAndLineEndings() {
        XCTAssertEqual(
            ContentView.trimmingTrailingWhitespace("    indented  \n\tline\t\r\nlast   "),
            "    indented\n\tline\r\nlast"
        )
    }
}
