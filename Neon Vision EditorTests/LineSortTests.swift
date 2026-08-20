import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class LineSortTests: XCTestCase {
    func testSortUniqueLinesSortsAndRemovesExactDuplicates() {
        XCTAssertEqual(
            ContentView.sortedUniqueLines("beta\nAlpha\nbeta\nalpha\nAlpha"),
            "Alpha\nalpha\nbeta"
        )
    }

    func testSortUniqueLinesPreservesBlankLineAsAValue() {
        XCTAssertEqual(
            ContentView.sortedUniqueLines("beta\n\nalpha\n"),
            "\nalpha\nbeta"
        )
    }
}
