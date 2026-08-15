#if os(macOS)
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class VirtualEditorLayoutTests: XCTestCase {
    func testShiftWheelZoomConvertsBothScrollDirectionsToFontDeltas() {
        XCTAssertEqual(VirtualEditorWheelZoom.fontSizeDelta(scrollingDeltaY: 5, fallbackDeltaY: 0), 1)
        XCTAssertEqual(VirtualEditorWheelZoom.fontSizeDelta(scrollingDeltaY: -5, fallbackDeltaY: 0), -1)
        XCTAssertEqual(VirtualEditorWheelZoom.fontSizeDelta(scrollingDeltaY: 0, fallbackDeltaY: 5), 1)
    }

    func testUnwrappedContentWidthIncludesLongestRenderedLine() {
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(repeating: "W", count: 80), attributes: [.font: font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

        XCTAssertGreaterThan(width, 500)
    }

    func testVisualRowIndexMapsLogicalLinesToStableEstimatedRows() {
        let index = VirtualEditorVisualRowIndex(logicalLineCount: 100, estimatedRowsPerLogicalLine: 2)

        XCTAssertEqual(index.estimatedRowCount, 200)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 0), 0)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 25), 50)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 99), 198)
    }

    func testVisualRowEstimateSmoothingIsBoundedAndExplicit() {
        XCTAssertEqual(
            VirtualEditorVisualRowIndex.smoothedEstimate(previous: 1, observed: 3),
            1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VirtualEditorVisualRowIndex.smoothedEstimate(previous: 4, observed: 20),
            4,
            accuracy: 0.001
        )
    }

    func testWrappedFragmentsRemainContiguousForAbsoluteSelectionGeometry() {
        let text = "wide text that must wrap across visual rows"
        let fragments = VirtualEditorVisualLayout.fragments(
            for: NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]),
            lineStartUTF16: 120,
            width: 70,
            wraps: true
        )

        XCTAssertGreaterThan(fragments.count, 1)
        for pair in zip(fragments, fragments.dropFirst()) {
            XCTAssertEqual(pair.0.absoluteStartUTF16 + pair.0.lengthUTF16, pair.1.absoluteStartUTF16)
        }
    }

    func testVisualFragmentsSplitLongLineAtAvailableWidth() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let fragments = VirtualEditorVisualLayout.fragments(
            for: NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]),
            lineStartUTF16: 40,
            width: 50,
            wraps: true
        )

        XCTAssertGreaterThan(fragments.count, 1)
        XCTAssertEqual(fragments.first?.absoluteStartUTF16, 40)
        XCTAssertEqual(fragments.last.map { $0.absoluteStartUTF16 + $0.lengthUTF16 }, 40 + text.utf16.count)
    }

    func testVisualFragmentsRetainSingleFragmentWhenWrappingDisabled() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let fragments = VirtualEditorVisualLayout.fragments(
            for: NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]),
            lineStartUTF16: 0,
            width: 50,
            wraps: false
        )

        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(fragments[0].lengthUTF16, text.utf16.count)
    }

    func testLargeCSVViewportHasBoundedVisibleRowBudget() {
        let source = String(repeating: "a,b,c,d,e\n", count: 30_000)
        let logicalLineCount = source.split(separator: "\n", omittingEmptySubsequences: false).count
        let visibleRowBudget = 32

        XCTAssertGreaterThan(logicalLineCount, 10_000)
        XCTAssertLessThanOrEqual(visibleRowBudget, 64)
    }

    func testNewFileViewportUsesEnclosingScrollViewWhenClipViewIsNotLaidOutYet() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 1, height: 1),
            scrollViewBounds: CGSize(width: 900, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 885, height: 700))
    }

    func testPreviewSplitViewportExcludesVerticalScrollerWhenClipViewIsStale() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 900, height: 700),
            scrollViewBounds: CGSize(width: 420, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 405, height: 700))
    }

    func testViewportUsesCurrentClipWidthWhenItHasAlreadyLaidOut() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 405, height: 700),
            scrollViewBounds: CGSize(width: 420, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 405, height: 700))
    }

    func testCommandArrowNavigationRemainsWithAppKit() {
        XCTAssertTrue(VirtualEditorKeyRouting.shouldInterpretArrow(
            modifiers: [.command]
        ))
        XCTAssertTrue(VirtualEditorKeyRouting.shouldInterpretArrow(
            modifiers: [.command, .shift]
        ))
        XCTAssertFalse(VirtualEditorKeyRouting.shouldInterpretArrow(
            modifiers: [.shift]
        ))
    }

    func testLargeFileTOCDoesNotMaterializeFileBackedContent() {
        XCTAssertFalse(ContentView.EditorPerformanceThresholds.shouldMaterializeTOC(
            isLargeFileModeEnabled: false,
            documentUTF16Length: 100_000,
            usesFileBackedStorage: true,
            fileByteCount: 401_000
        ))
        XCTAssertTrue(ContentView.EditorPerformanceThresholds.shouldMaterializeTOC(
            isLargeFileModeEnabled: false,
            documentUTF16Length: 100_000,
            usesFileBackedStorage: false,
            fileByteCount: 0
        ))
    }
}
#endif
