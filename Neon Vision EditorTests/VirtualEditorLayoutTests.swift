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

    func testVisualFragmentLayoutPerformanceBaseline() {
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attributed = NSAttributedString(
            string: String(repeating: "let value = 42 // benchmark\n", count: 2_000),
            attributes: [.font: font]
        )

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            _ = VirtualEditorVisualLayout.fragments(
                for: attributed,
                lineStartUTF16: 0,
                width: 640,
                wraps: true
            )
        }
    }

    func testVisualRowIndexMapsLogicalLinesToStableEstimatedRows() {
        let index = VirtualEditorVisualRowIndex(logicalLineCount: 100, estimatedRowsPerLogicalLine: 2)

        XCTAssertEqual(index.estimatedRowCount, 200)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 0), 0)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 25), 50)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 99), 198)
    }

    func testScrollAnchorPolicyLoadsTheFinalDocumentLineAtTheBottom() {
        XCTAssertEqual(
            VirtualEditorScrollAnchorPolicy.anchorLine(
                scrollY: 1_000,
                lineHeight: 20,
                estimatedRowsPerLogicalLine: 1.5,
                prefetchLines: 20,
                documentLineCount: 10_000,
                isAtBottom: true
            ),
            9_999
        )
    }

    func testScrollAnchorPolicyPrefetchesAboveTheVisibleViewport() {
        XCTAssertEqual(
            VirtualEditorScrollAnchorPolicy.anchorLine(
                scrollY: 1_000,
                lineHeight: 20,
                estimatedRowsPerLogicalLine: 1.5,
                prefetchLines: 20,
                documentLineCount: 10_000,
                isAtBottom: false
            ),
            13
        )
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

    func testWrappedContinuationRowUsesLogicalLineCoreTextIndices() {
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "continuation",
            attributes: [.font: font]
        ))
        let row = VirtualEditorCanvas.VisualRow(
            logicalLine: 4,
            localStart: 100,
            fragment: VirtualEditorVisualFragment(
                absoluteStartUTF16: 112,
                lengthUTF16: 8,
                line: line
            ),
            baseline: 40,
            isFirstFragment: false
        )

        XCTAssertEqual(row.coreTextStringIndex(forViewportOffset: 112), 12)
        XCTAssertEqual(row.coreTextStringIndex(forViewportOffset: 120), 20)
        XCTAssertEqual(row.viewportOffset(forCoreTextStringIndex: 12, trailingFallback: false), 112)
        XCTAssertEqual(row.viewportOffset(forCoreTextStringIndex: 20, trailingFallback: false), 120)
        XCTAssertEqual(row.viewportOffset(forCoreTextStringIndex: kCFNotFound, trailingFallback: false), 112)
        XCTAssertEqual(row.viewportOffset(forCoreTextStringIndex: kCFNotFound, trailingFallback: true), 120)
    }

    func testFirstVisualRowBaselineLeavesRoomForTheFontAscender() {
        XCTAssertEqual(
            VirtualEditorVisualLayout.baseline(
                rowOrigin: 0,
                lineHeight: 21,
                fontAscender: 13
            ),
            15
        )
    }

    func testLineNumberOriginAlignsWithCoreTextBaselineAcrossFontSizes() {
        for size: CGFloat in [11, 14, 24] {
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            for multiplier: CGFloat in [1, 1.25, 1.6] {
                let lineHeight = (font.ascender - font.descender + font.leading + 4) * multiplier
                let baseline = VirtualEditorVisualLayout.baseline(
                    rowOrigin: 3,
                    lineHeight: lineHeight,
                    fontAscender: font.ascender
                )

                XCTAssertEqual(
                    VirtualEditorVisualLayout.lineNumberOriginY(
                        baseline: baseline,
                        fontAscender: font.ascender
                    ),
                    baseline - font.ascender,
                    accuracy: 0.001
                )
            }
        }
    }

    func testVisualRowOwnershipCoversWrapGapsAndEndpoints() {
        let canvas = VirtualEditorCanvas(frame: .zero)
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        func row(start: Int, length: Int) -> VirtualEditorCanvas.VisualRow {
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: String(repeating: "x", count: max(1, length)),
                attributes: [.font: font]
            ))
            return VirtualEditorCanvas.VisualRow(
                logicalLine: 0,
                localStart: start,
                fragment: VirtualEditorVisualFragment(
                    absoluteStartUTF16: start,
                    lengthUTF16: length,
                    line: line
                ),
                baseline: 0,
                isFirstFragment: start == 0
            )
        }

        let rows = [row(start: 0, length: 5), row(start: 5, length: 5), row(start: 11, length: 0), row(start: 12, length: 3)]

        XCTAssertEqual(canvas.visualRow(containing: 5, in: rows)?.fragment.absoluteStartUTF16, 5)
        XCTAssertEqual(canvas.visualRow(containing: 10, in: rows)?.fragment.absoluteStartUTF16, 5)
        XCTAssertEqual(canvas.visualRow(containing: 11, in: rows)?.fragment.absoluteStartUTF16, 11)
        XCTAssertEqual(canvas.visualRow(containing: 15, in: rows)?.fragment.absoluteStartUTF16, 12)
        XCTAssertNil(canvas.visualRow(containing: -1, in: rows))
        XCTAssertNil(canvas.visualRow(containing: 16, in: rows))
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

    func testWrapCacheTracksEverySidebarAndPreviewWidthTransition() {
        let text = String(repeating: "pane transition wrapping ", count: 24)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]
        )
        var cache = VirtualEditorVisualFragmentCache()
        let widths: [CGFloat] = [
            1_100, // no sidebar or preview
            820,   // sidebar only
            620,   // preview only
            340,   // sidebar and preview
            620,   // sidebar closes
            820,   // preview closes while sidebar remains
            1_100  // sidebar closes
        ]

        let fragmentCounts = widths.map { width in
            cache.fragments(
                for: attributed,
                localLine: 0,
                lineStartUTF16: 0,
                width: width,
                wraps: true
            ).count
        }

        XCTAssertGreaterThan(fragmentCounts[1], fragmentCounts[0])
        XCTAssertGreaterThan(fragmentCounts[2], fragmentCounts[1])
        XCTAssertGreaterThan(fragmentCounts[3], fragmentCounts[2])
        XCTAssertEqual(fragmentCounts[4], fragmentCounts[2])
        XCTAssertEqual(fragmentCounts[5], fragmentCounts[1])
        XCTAssertEqual(fragmentCounts[6], fragmentCounts[0])
    }

    func testWrapCacheDoesNotReuseWrappedFragmentsAfterDisablingLineWrap() {
        let attributed = NSAttributedString(
            string: String(repeating: "long line ", count: 30),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]
        )
        var cache = VirtualEditorVisualFragmentCache()

        XCTAssertGreaterThan(cache.fragments(
            for: attributed,
            localLine: 0,
            lineStartUTF16: 0,
            width: 180,
            wraps: true
        ).count, 1)
        XCTAssertEqual(cache.fragments(
            for: attributed,
            localLine: 0,
            lineStartUTF16: 0,
            width: 180,
            wraps: false
        ).count, 1)
    }

    func testCanvasFillsAndAcceptsInputAcrossEveryPaneTransition() throws {
        let scrollView = VirtualEditorScrollView(frame: NSRect(x: 0, y: 0, width: 1_100, height: 700))
        let widths: [CGFloat] = [1_100, 820, 620, 340, 620, 820, 1_100]

        for width in widths {
            scrollView.setFrameSize(NSSize(width: width, height: 700))
            scrollView.layoutSubtreeIfNeeded()
            scrollView.layout()

            let visibleWidth = scrollView.contentView.bounds.width
            let canvas = try XCTUnwrap(scrollView.documentView)
            XCTAssertEqual(canvas.frame.width, visibleWidth, accuracy: 1)
            XCTAssertTrue(canvas.acceptsFirstResponder)
            XCTAssertNotNil(canvas.hitTest(NSPoint(x: max(0, visibleWidth - 2), y: 2)))
        }
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

    func testWorkspaceModeReplacementUsesTheAllocatedScrollWidth() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 1, height: 1),
            scrollViewBounds: CGSize(width: 600, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 585, height: 700))
    }

    func testBrainDumpEditorSuppliesItsPreferredWidthWhenSwiftUIHasNoProposal() {
        XCTAssertEqual(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: nil,
                proposedHeight: 700,
                preferredWidth: 920
            ),
            CGSize(width: 920, height: 700)
        )
    }

    func testBrainDumpEditorUsesTheParentProposalUpToItsPreferredWidth() {
        XCTAssertEqual(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: 600,
                proposedHeight: 700,
                preferredWidth: 920
            ),
            CGSize(width: 600, height: 700)
        )
    }

    func testBrainDumpEditorRejectsCollapsedWidthProposal() {
        XCTAssertEqual(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: 1,
                proposedHeight: 700,
                preferredWidth: 920
            ),
            CGSize(width: 920, height: 700)
        )
    }

    func testStandardEditorDefersCollapsedWidthProposalToItsParent() {
        XCTAssertNil(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: 1,
                proposedHeight: 700,
                preferredWidth: nil
            )
        )
    }

    func testStandardEditorHasNoSyntheticIntrinsicWidthDuringPreviewTransition() {
        XCTAssertNil(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: nil,
                proposedHeight: 700,
                preferredWidth: nil
            )
        )
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

    func testSidebarCloseUsesExpandedScrollAllocationWhenClipViewIsStale() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 405, height: 700),
            scrollViewBounds: CGSize(width: 900, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 885, height: 700))
    }

    func testCollapsedInitialViewportIsDeferredUntilLayoutProvidesUsableWidth() {
        XCTAssertNil(VirtualEditorViewportGeometry.stabilizedSize(
            CGSize(width: 1, height: 700),
            previous: .zero,
            minimumUsableWidth: 90
        ))
    }

    func testPreviewPaneDragUsesItsCapturedMaximumWidth() {
        let width = PreviewPaneResizeGeometry.width(
            startWidth: 420,
            translation: -180,
            minimumWidth: 280,
            maximumWidth: 600
        )

        XCTAssertEqual(width, 600)
    }

    func testSplitPaneResizeDefersVirtualEditorReflow() {
        XCTAssertFalse(VirtualEditorResizePolicy.shouldReflow(isSplitPaneResizeInProgress: true))
        XCTAssertTrue(VirtualEditorResizePolicy.shouldReflow(isSplitPaneResizeInProgress: false))
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

    func testCloseTabRoutingMatchesConfiguredShortcutExactly() {
        let shortcut = EditorShortcutDescriptor(key: "k", modifiers: [.command, .shift])

        XCTAssertTrue(VirtualEditorKeyRouting.matches(
            charactersIgnoringModifiers: "k",
            keyCode: 40,
            modifiers: [.command, .shift],
            shortcut: shortcut
        ))
        XCTAssertFalse(VirtualEditorKeyRouting.matches(
            charactersIgnoringModifiers: "k",
            keyCode: 40,
            modifiers: [.command],
            shortcut: shortcut
        ))
        XCTAssertFalse(VirtualEditorKeyRouting.matches(
            charactersIgnoringModifiers: "k",
            keyCode: 40,
            modifiers: [.command, .shift, .option],
            shortcut: shortcut
        ))
    }

    func testDefaultCloseTabRoutingUsesPhysicalWKeyFallback() {
        XCTAssertTrue(VirtualEditorKeyRouting.matches(
            charactersIgnoringModifiers: "z",
            keyCode: 13,
            modifiers: [.command],
            shortcut: EditorShortcutAction.closeTab.defaultShortcut
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
