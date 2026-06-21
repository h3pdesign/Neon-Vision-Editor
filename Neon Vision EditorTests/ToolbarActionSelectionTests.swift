import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ToolbarActionSelectionTests: XCTestCase {
    private enum TestAction: String, CaseIterable {
        case openFile
        case undo
        case settings
        case help
        case clearEditor
        case insertTemplate
        case newTab
        case saveFile
        case findReplace
    }

    func testVisibleLimitSupportsSevenActions() {
        XCTAssertEqual(ToolbarActionSelection.visibleLimit(requestedCount: 7, fallback: TestAction.allCases.count), 7)
    }

    func testCustomVisibleActionsRespectSelectedCountAndToolbarOrder() {
        let visible = ToolbarActionSelection.visibleActions(
            enabledActions: TestAction.allCases,
            customIDsRawValue: "saveFile,openFile,findReplace,undo,settings,help,clearEditor,insertTemplate,newTab",
            usesCustomSelection: true,
            requestedCount: 7
        )

        XCTAssertEqual(
            visible.map(\.rawValue),
            [
                "openFile",
                "undo",
                "settings",
                "help",
                "clearEditor",
                "insertTemplate",
                "newTab"
            ]
        )
    }

    func testCustomSelectionFallsBackToVisibleCountWhenNoCustomIDsMatch() {
        let visible = ToolbarActionSelection.visibleActions(
            enabledActions: TestAction.allCases,
            customIDsRawValue: "missing",
            usesCustomSelection: true,
            requestedCount: 4
        )

        XCTAssertEqual(visible.map(\.rawValue), ["openFile", "undo", "settings", "help"])
    }

    func testToggledSelectionPreservesDeclaredOrderAndCapsAtLimit() {
        let orderedIDs = TestAction.allCases.map(\.rawValue)
        var rawValue = ""
        for action in TestAction.allCases {
            rawValue = ToolbarActionSelection.toggledSelectionRawValue(
                toggledID: action.rawValue,
                currentRawValue: rawValue,
                orderedIDs: orderedIDs,
                limit: 7
            )
        }

        XCTAssertEqual(rawValue, "openFile,undo,settings,help,clearEditor,insertTemplate,newTab")

        let removed = ToolbarActionSelection.toggledSelectionRawValue(
            toggledID: "settings",
            currentRawValue: rawValue,
            orderedIDs: orderedIDs,
            limit: 7
        )
        XCTAssertEqual(removed, "openFile,undo,help,clearEditor,insertTemplate,newTab")
    }

    // Tab select/close dispatch wiring. The tab strip's per-tab select and close
    // buttons drive viewModel.selectTab(id:) and viewModel.closeTab(tabID:). These
    // tests keep that wiring verified so the mouse-click handlers restored by the
    // tab-bar hit-testing fix (issue #150) stay correct.
    func testSelectTabUpdatesSelectedTabID() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()

        XCTAssertEqual(viewModel.tabs.count, 2)
        let firstTab = viewModel.tabs[0]
        let secondTab = viewModel.tabs[1]

        viewModel.selectTab(id: firstTab.id)
        XCTAssertEqual(viewModel.selectedTabID, firstTab.id)

        viewModel.selectTab(id: secondTab.id)
        XCTAssertEqual(viewModel.selectedTabID, secondTab.id)
    }

    func testCloseTabRemovesTabFromViewModel() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()

        XCTAssertEqual(viewModel.tabs.count, 2)
        let closingTab = viewModel.tabs[0]
        let survivingTab = viewModel.tabs[1]

        viewModel.closeTab(tabID: closingTab.id)

        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertFalse(viewModel.tabs.contains { $0.id == closingTab.id })
        XCTAssertTrue(viewModel.tabs.contains { $0.id == survivingTab.id })
    }
}
