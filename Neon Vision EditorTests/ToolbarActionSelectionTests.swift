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

    func testVisibleActionsUseTheToolbarOrderAndRequestedCount() {
        let visible = ToolbarActionSelection.visibleActions(
            enabledActions: TestAction.allCases,
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

    func testNamedPresetsIgnoreCustomActionIDs() {
        XCTAssertFalse(
            ToolbarActionSelection.isAllowedByPreset(
                actionID: "gitChanges",
                preset: .writing,
                customIDsRawValue: "gitChanges"
            )
        )
        XCTAssertFalse(
            ToolbarActionSelection.isAllowedByPreset(
                actionID: "openFile",
                preset: .custom,
                customIDsRawValue: "gitChanges"
            )
        )
    }

    func testOverflowContainsOnlyEnabledActionsThatAreNotVisible() {
        let enabled = TestAction.allCases
        let visible = ToolbarActionSelection.visibleActions(
            enabledActions: enabled,
            requestedCount: 4
        )
        let overflow = ToolbarActionSelection.overflowActions(
            enabledActions: enabled,
            visibleActions: visible
        )

        XCTAssertEqual(overflow.map(\.rawValue), ["clearEditor", "insertTemplate", "newTab", "saveFile", "findReplace"])
        XCTAssertTrue(Set(visible).isDisjoint(with: Set(overflow)))
    }

    func testScrollableToolbarIncludesEveryPresetAction() {
        XCTAssertEqual(
            ToolbarActionSelection.actionsForScrollableToolbar(enabledActions: TestAction.allCases),
            TestAction.allCases
        )
    }

    func testNamedPresetsDoNotApplyCustomSectionVisibility() {
        XCTAssertFalse(ToolbarActionSelection.honorsSectionVisibility(preset: .standard))
        XCTAssertFalse(ToolbarActionSelection.honorsSectionVisibility(preset: .all))
        XCTAssertTrue(ToolbarActionSelection.honorsSectionVisibility(preset: .custom))
    }

    func testPresetFilteringControlsPrimaryAndOverflowActions() {
        XCTAssertTrue(
            ToolbarActionSelection.isAllowedByPreset(
                actionID: "openFile",
                preset: .standard,
                customIDsRawValue: ""
            ), "standard openFile"
        )
        XCTAssertFalse(
            ToolbarActionSelection.isAllowedByPreset(
                actionID: "compareTabs",
                preset: .writing,
                customIDsRawValue: ""
            ), "writing compareTabs"
        )
        XCTAssertTrue(
            ToolbarActionSelection.isAllowedByPreset(
                actionID: "gitChanges",
                preset: .developer,
                customIDsRawValue: ""
            ), "developer gitChanges"
        )
        XCTAssertTrue(
            ToolbarActionSelection.isAllowedByPreset(
                actionID: "settings",
                preset: .custom,
                customIDsRawValue: "openFile",
                universalIDs: ToolbarActionSelection.universallyAvailableMobileActionIDs
            ), "custom settings"
        )
        XCTAssertTrue(
            ToolbarActionSelection.isAllowedByPreset(
                actionID: "help",
                preset: .writing,
                customIDsRawValue: "",
                universalIDs: ToolbarActionSelection.universallyAvailableMobileActionIDs
            ), "writing help"
        )
        XCTAssertFalse(
            ToolbarActionSelection.isAllowedByPreset(
                actionID: "gitChanges",
                preset: .custom,
                customIDsRawValue: "openFile",
                universalIDs: ["settings", "help"]
            ), "custom gitChanges"
        )
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
