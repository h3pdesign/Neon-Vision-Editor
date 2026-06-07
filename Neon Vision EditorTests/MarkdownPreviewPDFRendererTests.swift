import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

@MainActor
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

    func testPaginatedSourceRangesKeepSinglePageForShortContent() {
        let ranges = MarkdownPreviewPDFRenderer.paginatedSourceRanges(
            sourceHeight: 680,
            preferredBlockBottoms: [120, 320, 640],
            sliceHeight: 1_120
        )

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first?.top, 0)
        XCTAssertEqual(ranges.first?.bottom, 680)
    }

    func testPaginatedSourceRangesRemainStrictlyAscendingWithDenseBlocks() {
        let ranges = MarkdownPreviewPDFRenderer.paginatedSourceRanges(
            sourceHeight: 5_600,
            preferredBlockBottoms: stride(from: 80, through: 5_520, by: 80).map(CGFloat.init),
            sliceHeight: 1_120
        )

        XCTAssertFalse(ranges.isEmpty)
        XCTAssertEqual(ranges.first?.top, 0)
        XCTAssertEqual(ranges.last?.bottom, 5_600)

        for range in ranges {
            XCTAssertGreaterThan(range.bottom, range.top)
        }
        for (previous, current) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(previous.bottom, current.top)
        }
    }

    func testAllMarkdownPreviewThemesKeepCompactViewportGuardrails() {
        let contentView = ContentView()
        let requiredCSSFragments = [
            "box-sizing: border-box",
            "min-width: 0",
            "max-width: 100%",
            "overflow-x: hidden",
            "overflow-wrap: break-word",
            "overflow-wrap: anywhere",
            "display: block",
            "white-space: pre"
        ]

        for option in ContentView.markdownPreviewTemplateOptions {
            for preferDarkMode in [false, true] {
                let css = contentView.markdownPreviewCSS(
                    template: option.id,
                    preferDarkMode: preferDarkMode,
                    backgroundStyle: .template,
                    translucentBackgroundEnabled: false
                )

                for fragment in requiredCSSFragments {
                    XCTAssertTrue(
                        css.contains(fragment),
                        "\(option.id) missing compact viewport guardrail: \(fragment)"
                    )
                }
                XCTAssertFalse(
                    css.contains("width: 100vw"),
                    "\(option.id) must not use viewport-width content sizing because it can clip inside iOS WKWebView sheets."
                )
                XCTAssertFalse(
                    css.contains("max-width: 100vw"),
                    "\(option.id) must not use viewport-width max sizing because it can exceed the visible iOS WKWebView width."
                )
            }
        }
    }
}
