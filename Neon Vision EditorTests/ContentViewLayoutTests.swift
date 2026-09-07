import XCTest
@testable import Neon_Vision_Editor

final class ContentViewLayoutTests: XCTestCase {
    @MainActor
    func testSecondaryContentRequestInvalidatesForSeparatorChangeWithoutAnEdit() {
        let id = UUID()
        let csv = ContentView.SecondaryContentRequest(
            context: .init(tabID: id, fileURL: nil, language: "csv"),
            revision: 1, delimitedMode: .table, plistMode: .text,
            crashMode: .text, logMode: .text
        )
        let tsv = ContentView.SecondaryContentRequest(
            context: .init(tabID: id, fileURL: nil, language: "tsv"),
            revision: 1, delimitedMode: .table, plistMode: .text,
            crashMode: .text, logMode: .text
        )
        XCTAssertNotEqual(csv, tsv, "Changing the delimiter must replace the parse task even without editing text.")
    }

    @MainActor
    func testSecondaryContentRequestDistinguishesTabsWithIdenticalRevisions() {
        func request(_ id: UUID, revision: Int = 0) -> ContentView.SecondaryContentRequest {
            .init(context: .init(tabID: id, fileURL: nil, language: "csv"),
                  revision: revision, delimitedMode: .table, plistMode: .text,
                  crashMode: .text, logMode: .text)
        }
        let id = UUID()
        XCTAssertEqual(request(id), request(id), "An unchanged request must not restart parsing.")
        XCTAssertNotEqual(request(id), request(UUID()), "New tabs commonly have the same content revision.")
        XCTAssertNotEqual(request(id), request(id, revision: 1), "Edits must replace the parse task.")
    }

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
