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

    func testToolbarPresetsExposeStablePlatformActions() {
        XCTAssertEqual(ToolbarPreset.standard.macOSIDs.first, "openFile")
        XCTAssertTrue(ToolbarPreset.developer.macOSIDs.contains("gitChanges"))
        XCTAssertTrue(ToolbarPreset.writing.mobileIDs.contains("markdownPreview"))
        XCTAssertFalse(ToolbarPreset.focus.mobileIDs.contains("gitChanges"))
        XCTAssertTrue(ToolbarPreset.all.macOSIDs.contains("help"))
        XCTAssertTrue(ToolbarPreset.all.mobileIDs.contains("markdownProjectPreview"))
        XCTAssertTrue(ToolbarPreset.all.mobileIDs.contains("fontIncrease"))
        XCTAssertEqual(ToolbarPreset.mobileSelectableIDs.count, Set(ToolbarPreset.mobileSelectableIDs).count)
    }

    func testOrderedIDsPreserveSavedOrderAndAppendNewDefinitions() {
        XCTAssertEqual(
            ToolbarActionSelection.orderedIDs(from: "findReplace,openFile,findReplace", fallback: ["openFile", "saveFile", "findReplace"]),
            ["findReplace", "openFile", "saveFile"]
        )
    }

    func testPreviewModeOpensRequestedPreviewFromNone() {
        XCTAssertEqual(
            ContentView.PreviewMode.none.toggled(for: .markdown),
            .markdown
        )
    }

    func testPreviewModeClosesWhenTogglingSamePreview() {
        XCTAssertEqual(
            ContentView.PreviewMode.web.toggled(for: .web),
            .none
        )
    }

    func testPreviewModeSwitchesDirectlyBetweenMarkdownAndWeb() {
        XCTAssertEqual(
            ContentView.PreviewMode.markdown.toggled(for: .web),
            .web
        )
    }
}
