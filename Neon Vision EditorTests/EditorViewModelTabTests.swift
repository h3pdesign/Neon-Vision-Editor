import Observation
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class EditorViewModelTabTests: XCTestCase {
    func testDraftSnapshotPreservesLineEndingAndDecodesOlderSnapshots() throws {
        let snapshot = ContentView.SavedDraftTabSnapshot(
            name: "Windows.txt",
            content: "one\ntwo",
            language: "plain",
            fileURLString: nil,
            lineEndingRawValue: TextLineEnding.crlf.rawValue
        )
        let roundTrip = try JSONDecoder().decode(
            ContentView.SavedDraftTabSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(roundTrip.lineEndingRawValue, TextLineEnding.crlf.rawValue)

        let legacyData = try XCTUnwrap(
            #"{"name":"Legacy.txt","content":"one\ntwo","language":"plain","fileURLString":null}"#
                .data(using: .utf8)
        )
        let legacy = try JSONDecoder().decode(ContentView.SavedDraftTabSnapshot.self, from: legacyData)
        XCTAssertNil(legacy.lineEndingRawValue)
    }

    func testDraftRecoveryDeduplicatesExactDuplicateTabs() {
        let duplicate = ContentView.SavedDraftTabSnapshot(
            name: "Untitled 1",
            content: "import os",
            language: "Python",
            fileURLString: nil
        )
        let distinct = ContentView.SavedDraftTabSnapshot(
            name: "Untitled 1",
            content: "print('hello')",
            language: "Python",
            fileURLString: nil
        )

        let restored = deduplicatedDraftSnapshotTabs([duplicate, distinct, duplicate])

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.map(\.content), [duplicate.content, distinct.content])
    }

    func testSelectTabUpdatesSelectedTabID() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        XCTAssertEqual(tabs.count, 2)

        viewModel.selectTab(id: tabs[0].id)
        XCTAssertEqual(viewModel.selectedTabID, tabs[0].id)

        viewModel.selectTab(id: tabs[1].id)
        XCTAssertEqual(viewModel.selectedTabID, tabs[1].id)
    }

    func testCloseTabRemovesTargetTabAndKeepsSurvivorSelected() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        XCTAssertEqual(tabs.count, 2)

        viewModel.selectTab(id: tabs[0].id)
        viewModel.closeTab(tabID: tabs[0].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), [tabs[1].id])
        XCTAssertEqual(viewModel.selectedTabID, tabs[1].id)
    }

    func testMoveTabPlacesDraggedTabBeforeDestinationWithoutChangingSelection() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        viewModel.selectTab(id: tabs[2].id)
        viewModel.moveTab(tabID: tabs[2].id, beforeTabID: tabs[0].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), [tabs[2].id, tabs[0].id, tabs[1].id])
        XCTAssertEqual(viewModel.selectedTabID, tabs[2].id)
    }

    func testMoveTabPlacesDraggedTabAfterDestinationInEitherDirection() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        viewModel.selectTab(id: tabs[0].id)
        viewModel.moveTab(tabID: tabs[0].id, afterTabID: tabs[2].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), [tabs[1].id, tabs[2].id, tabs[0].id])
        XCTAssertEqual(viewModel.selectedTabID, tabs[0].id)

        viewModel.moveTab(tabID: tabs[0].id, afterTabID: tabs[1].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), [tabs[1].id, tabs[0].id, tabs[2].id])
    }

    func testAdjacentTabMovesDoNotInvalidateTabState() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        let initialOrder = tabs.map(\.id)
        let initialToken = viewModel.tabsObservationToken

        viewModel.moveTab(tabID: tabs[0].id, beforeTabID: tabs[1].id)
        viewModel.moveTab(tabID: tabs[1].id, afterTabID: tabs[0].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), initialOrder)
        XCTAssertEqual(viewModel.tabsObservationToken, initialToken)
    }

    func testTabContentMutationInvalidatesTokenObservers() async throws {
        let viewModel = EditorViewModel()
        let tab = try XCTUnwrap(viewModel.selectedTab)
        let invalidated = expectation(description: "Tab observation token invalidated")

        withObservationTracking {
            _ = viewModel.tabsObservationToken
        } onChange: {
            invalidated.fulfill()
        }

        viewModel.updateTabContent(tabID: tab.id, content: "Updated content")

        await fulfillment(of: [invalidated], timeout: 1)
    }
}
