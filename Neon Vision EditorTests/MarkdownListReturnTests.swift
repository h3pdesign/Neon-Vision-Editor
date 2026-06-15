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
}
