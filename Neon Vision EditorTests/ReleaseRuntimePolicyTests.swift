import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

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
}
