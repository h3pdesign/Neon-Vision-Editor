import XCTest
import SwiftUI
@testable import Neon_Vision_Editor



/// MARK: - Tests

@MainActor
final class ReleaseRuntimePolicyTests: XCTestCase {
    func testSettingsTabFallsBackToGeneral() {
        XCTAssertEqual(ReleaseRuntimePolicy.settingsTab(from: nil), "general")
        XCTAssertEqual(ReleaseRuntimePolicy.settingsTab(from: ""), "general")
        XCTAssertEqual(ReleaseRuntimePolicy.settingsTab(from: "   "), "general")
        XCTAssertEqual(ReleaseRuntimePolicy.settingsTab(from: "ai"), "ai")
    }

    func testPreferredColorSchemeMapping() {
        XCTAssertEqual(ReleaseRuntimePolicy.preferredColorScheme(for: "light"), .light)
        XCTAssertEqual(ReleaseRuntimePolicy.preferredColorScheme(for: "dark"), .dark)
        XCTAssertNil(ReleaseRuntimePolicy.preferredColorScheme(for: "system"))
        XCTAssertNil(ReleaseRuntimePolicy.preferredColorScheme(for: "unknown"))
    }

    func testFindNextMovesCursorForwardAndWraps() {
        let text = "alpha beta alpha"
        let first = ReleaseRuntimePolicy.nextFindMatch(
            in: text,
            query: "alpha",
            useRegex: false,
            caseSensitive: true,
            cursorLocation: 0
        )
        XCTAssertEqual(first?.range.location, 0)
        XCTAssertEqual(first?.nextCursorLocation, 5)

        let second = ReleaseRuntimePolicy.nextFindMatch(
            in: text,
            query: "alpha",
            useRegex: false,
            caseSensitive: true,
            cursorLocation: first?.nextCursorLocation ?? 0
        )
        XCTAssertEqual(second?.range.location, 11)
        XCTAssertEqual(second?.nextCursorLocation, 16)

        let wrapped = ReleaseRuntimePolicy.nextFindMatch(
            in: text,
            query: "alpha",
            useRegex: false,
            caseSensitive: true,
            cursorLocation: second?.nextCursorLocation ?? 0
        )
        XCTAssertEqual(wrapped?.range.location, 0)
    }

    func testFindNextRegexSearch() {
        let text = "id-12 id-345"
        let match = ReleaseRuntimePolicy.nextFindMatch(
            in: text,
            query: "id-[0-9]+",
            useRegex: true,
            caseSensitive: true,
            cursorLocation: 0
        )
        XCTAssertEqual(match?.range.location, 0)
        XCTAssertEqual(match?.range.length, 5)
    }

    func testFindSessionReturnsAllMatchesAndStartsAtCaret() {
        let result = ReleaseRuntimePolicy.findMatches(
            in: "alpha beta alpha alpha",
            query: "alpha",
            useRegex: false,
            caseSensitive: true
        )

        XCTAssertEqual(result.ranges.map(\.location), [0, 11, 17])
        XCTAssertEqual(
            ReleaseRuntimePolicy.initialFindMatchIndex(in: result.ranges, caretLocation: 7),
            1
        )
        XCTAssertEqual(
            ReleaseRuntimePolicy.movedFindMatchIndex(currentIndex: 2, matchCount: 3, delta: 1),
            0
        )
        XCTAssertEqual(
            ReleaseRuntimePolicy.movedFindMatchIndex(currentIndex: 0, matchCount: 3, delta: -1),
            2
        )
        XCTAssertEqual(
            ReleaseRuntimePolicy.movedFindMatchIndex(currentIndex: nil, matchCount: 3, delta: 1),
            0
        )
        XCTAssertEqual(
            ReleaseRuntimePolicy.movedFindMatchIndex(currentIndex: nil, matchCount: 3, delta: -1),
            2
        )
    }

    func testWholeWordFindDoesNotMatchIdentifierFragments() {
        let result = ReleaseRuntimePolicy.findMatches(
            in: "cat concatenate cat_2 cat",
            query: "cat",
            useRegex: false,
            caseSensitive: true,
            wholeWord: true
        )

        XCTAssertEqual(result.ranges.map(\.location), [0, 22])
    }

    func testInvalidRegexReturnsAnErrorWithoutMatches() {
        let result = ReleaseRuntimePolicy.findMatches(
            in: "alpha",
            query: "[",
            useRegex: true,
            caseSensitive: true
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.ranges.isEmpty)
        XCTAssertEqual(result.errorMessage, "Invalid regular expression")
    }

    func testSingleFindReplacementOnlyTransformsSelectedMatch() {
        let source = "alpha beta alpha"
        let replacement = ReleaseRuntimePolicy.replacementForFindMatch(
            in: source,
            range: NSRange(location: 11, length: 5),
            query: "alpha",
            replacement: "omega",
            useRegex: false,
            caseSensitive: true
        )

        XCTAssertEqual(replacement, "omega")
        XCTAssertEqual(
            (source as NSString).replacingCharacters(in: NSRange(location: 11, length: 5), with: replacement ?? ""),
            "alpha beta omega"
        )
    }

    func testRegexReplacementUsesCaptureGroupsForSelectedMatch() {
        let replacement = ReleaseRuntimePolicy.replacementForFindMatch(
            in: "id-12 id-345",
            range: NSRange(location: 6, length: 6),
            query: "id-([0-9]+)",
            replacement: "value-$1",
            useRegex: true,
            caseSensitive: true
        )

        XCTAssertEqual(replacement, "value-345")
    }

    func testSubscriptionButtonEnablement() {
        XCTAssertTrue(
            ReleaseRuntimePolicy.subscriptionButtonsEnabled(
                canUseInAppPurchases: true,
                isPurchasing: false,
                isLoadingProducts: false
            )
        )
        XCTAssertFalse(
            ReleaseRuntimePolicy.subscriptionButtonsEnabled(
                canUseInAppPurchases: false,
                isPurchasing: false,
                isLoadingProducts: false
            )
        )
        XCTAssertFalse(
            ReleaseRuntimePolicy.subscriptionButtonsEnabled(
                canUseInAppPurchases: true,
                isPurchasing: true,
                isLoadingProducts: false
            )
        )
        XCTAssertFalse(
            ReleaseRuntimePolicy.subscriptionButtonsEnabled(
                canUseInAppPurchases: true,
                isPurchasing: false,
                isLoadingProducts: true
            )
        )
    }

    func testSafeModeStartupDecision() {
        XCTAssertFalse(
            ReleaseRuntimePolicy.shouldEnterSafeMode(
                consecutiveFailedLaunches: 0,
                requestedManually: false
            )
        )
        XCTAssertFalse(
            ReleaseRuntimePolicy.shouldEnterSafeMode(
                consecutiveFailedLaunches: 1,
                requestedManually: false
            )
        )
        XCTAssertTrue(
            ReleaseRuntimePolicy.shouldEnterSafeMode(
                consecutiveFailedLaunches: ReleaseRuntimePolicy.safeModeFailureThreshold,
                requestedManually: false
            )
        )
        XCTAssertTrue(
            ReleaseRuntimePolicy.shouldEnterSafeMode(
                consecutiveFailedLaunches: 0,
                requestedManually: true
            )
        )
    }

    func testSafeModeStartupMessageExplainsTrigger() {
        XCTAssertNil(
            ReleaseRuntimePolicy.safeModeStartupMessage(
                consecutiveFailedLaunches: 0,
                requestedManually: false
            )
        )

        let automatic = ReleaseRuntimePolicy.safeModeStartupMessage(
            consecutiveFailedLaunches: 2,
            requestedManually: false
        )
        XCTAssertEqual(
            automatic,
            "Safe Mode is active because the last 2 launch attempts did not finish cleanly. Session restore, startup diagnostics, Markdown preview, and code minimap are paused."
        )

        let manual = ReleaseRuntimePolicy.safeModeStartupMessage(
            consecutiveFailedLaunches: 0,
            requestedManually: true
        )
        XCTAssertEqual(
            manual,
            "Safe Mode is active for this launch. Session restore, startup diagnostics, Markdown preview, and code minimap are paused."
        )
    }
}
