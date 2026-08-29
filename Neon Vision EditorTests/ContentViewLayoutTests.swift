import XCTest
@testable import Neon_Vision_Editor

final class ContentViewLayoutTests: XCTestCase {
    func testRegularWidthSplitUsesAppOwnedChrome() {
        XCTAssertTrue(
            IOSSplitChromePolicy.usesAppOwnedChrome(
                usesUnifiedTopHost: true,
                usesSplitView: true
            )
        )
    }

    func testSingleColumnLayoutKeepsUnifiedChromeWithEditor() {
        XCTAssertFalse(
            IOSSplitChromePolicy.usesAppOwnedChrome(
                usesUnifiedTopHost: true,
                usesSplitView: false
            )
        )
    }

    func testSplitLayoutWithoutUnifiedHostKeepsPlatformChrome() {
        XCTAssertFalse(
            IOSSplitChromePolicy.usesAppOwnedChrome(
                usesUnifiedTopHost: false,
                usesSplitView: true
            )
        )
    }

    func testFindChromeSuppressesFloatingAndPinnedStatus() {
        XCTAssertFalse(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: false,
                findPresented: true,
                pinnedPresentation: false
            )
        )
        XCTAssertFalse(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: true,
                findPresented: true,
                pinnedPresentation: true
            )
        )
    }

    func testFloatingStatusUsesOnlyItsRequestedPresentation() {
        XCTAssertTrue(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: false,
                findPresented: false,
                pinnedPresentation: false
            )
        )
        XCTAssertTrue(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: true,
                findPresented: false,
                pinnedPresentation: true
            )
        )
    }

    func testMobileFindChromeSuppressesMarkdownFormattingChrome() {
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldShow(
                isMarkdown: true,
                isReadOnlyPreview: false,
                brainDumpLayoutEnabled: false,
                isLoadingContent: false,
                findPresented: true,
                findOccupiesEditorChrome: true
            )
        )
    }

    func testSeparateFindWindowDoesNotSuppressMarkdownFormattingChrome() {
        XCTAssertTrue(
            MarkdownFormattingChromePolicy.shouldShow(
                isMarkdown: true,
                isReadOnlyPreview: false,
                brainDumpLayoutEnabled: false,
                isLoadingContent: false,
                findPresented: true,
                findOccupiesEditorChrome: false
            )
        )
    }

    func testCollapsedPhoneFormattingChromeOverlaysEditorWithoutReservingARow() {
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldReserveMobileFormattingRow(
                isPhone: true,
                shouldShow: true,
                isCollapsed: true
            )
        )
        XCTAssertTrue(
            MarkdownFormattingChromePolicy.shouldReserveMobileFormattingRow(
                isPhone: true,
                shouldShow: true,
                isCollapsed: false
            )
        )
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldReserveMobileFormattingRow(
                isPhone: false,
                shouldShow: true,
                isCollapsed: false
            )
        )
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldRenderInEditorStack(
                shouldShow: true,
                overlaysEditor: true,
                reservesChromeRow: true
            )
        )
    }

    func testCollapsedFormattingControlUsesOpaqueSurfaceWhileExpandedControlMayUseGlass() {
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.usesTranslucentControlSurface(
                isCollapsed: true,
                liquidGlassEnabled: true
            )
        )
        XCTAssertTrue(
            MarkdownFormattingChromePolicy.usesTranslucentControlSurface(
                isCollapsed: false,
                liquidGlassEnabled: true
            )
        )
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.usesTranslucentControlSurface(
                isCollapsed: false,
                liquidGlassEnabled: false
            )
        )
    }
}
