import XCTest
@testable import Neon_Vision_Editor

final class MarkdownPreviewPDFRendererTests: XCTestCase {
    func testPaginatedSourceRangesCoverLongMarkdownWithoutGaps() {
        let ranges = MarkdownPreviewPDFRenderer.paginatedSourceRanges(
            sourceHeight: 4_850,
            preferredBlockBottoms: [220, 715, 1_412, 1_998, 2_704, 3_390, 4_100, 4_742],
            sliceHeight: 1_120
        )

        XCTAssertGreaterThan(ranges.count, 2)
        XCTAssertEqual(ranges.first?.top, 0)
        XCTAssertEqual(ranges.last?.bottom, 4_850)

        for (previous, current) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(previous.bottom, current.top)
            XCTAssertGreaterThan(current.bottom, current.top)
        }
    }

    func testPaginatedSourceRangesIgnoreInvalidBlockMeasurements() {
        let ranges = MarkdownPreviewPDFRenderer.paginatedSourceRanges(
            sourceHeight: 2_400,
            preferredBlockBottoms: [-24, 0, 640, 1_200, 2_400, 9_999],
            sliceHeight: 900
        )

        XCTAssertEqual(ranges.first?.top, 0)
        XCTAssertEqual(ranges.last?.bottom, 2_400)
        XCTAssertTrue(ranges.allSatisfy { $0.top >= 0 && $0.bottom <= 2_400 })
    }
}
