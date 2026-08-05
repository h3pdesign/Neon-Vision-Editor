import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit

private final class UndoHostView: NSView {
    private let manager = UndoManager()

    override var undoManager: UndoManager? { manager }
}

@MainActor
final class UndoableTextReplacementTests: XCTestCase {
    func testReplacementIsUndoableWithoutDiscardingEarlierEdits() {
        let textView = NSTextView()
        let hostView = UndoHostView()
        hostView.addSubview(textView)
        textView.allowsUndo = true
        textView.string = "one one"

        guard let undoManager = textView.undoManager else {
            return XCTFail("Expected the text view to have an undo manager")
        }
        undoManager.removeAllActions()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        textView.insertText("!", replacementRange: NSRange(location: 7, length: 0))
        undoManager.endUndoGrouping()

        undoManager.beginUndoGrouping()
        XCTAssertTrue(replaceEntireTextPreservingUndoHistory(in: textView, with: "two two!"))
        undoManager.endUndoGrouping()

        undoManager.undo()
        XCTAssertEqual(textView.string, "one one!")

        undoManager.undo()
        XCTAssertEqual(textView.string, "one one")
        undoManager.removeAllActions()
    }
}
#endif
