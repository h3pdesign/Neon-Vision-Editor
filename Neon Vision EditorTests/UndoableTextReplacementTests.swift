import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit

@MainActor
final class UndoableTextReplacementTests: XCTestCase {
    func testReplacementIsUndoableWithoutDiscardingEarlierEdits() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.close() }

        let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = textView
        window.makeFirstResponder(textView)
        textView.string = "one one"

        guard let undoManager = textView.undoManager else {
            return XCTFail("Expected the text view to have an undo manager")
        }
        undoManager.removeAllActions()

        textView.insertText("!", replacementRange: NSRange(location: 7, length: 0))
        textView.breakUndoCoalescing()
        XCTAssertTrue(replaceEntireTextPreservingUndoHistory(in: textView, with: "two two!"))

        undoManager.undo()
        XCTAssertEqual(textView.string, "one one!")

        undoManager.undo()
        XCTAssertEqual(textView.string, "one one")
    }
}
#endif
