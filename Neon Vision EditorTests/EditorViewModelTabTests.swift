import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class EditorViewModelTabTests: XCTestCase {
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
}
