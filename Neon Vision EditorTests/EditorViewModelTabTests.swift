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
}
