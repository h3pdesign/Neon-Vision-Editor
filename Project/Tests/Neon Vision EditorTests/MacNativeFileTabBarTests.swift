#if os(macOS)
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class MacNativeFileTabBarTests: XCTestCase {
    func testApplyingTabSnapshotsKeepsStableViewsAndSelection() {
        let firstID = UUID()
        let secondID = UUID()
        let view = MacNativeFileTabBarView()
        let initial = [
            snapshot(id: firstID, title: "First.swift"),
            snapshot(id: secondID, title: "Second.md")
        ]

        view.apply(tabs: initial, selectedTabID: firstID)
        XCTAssertEqual(view.orderedTabIDs, [firstID, secondID])
        XCTAssertEqual(view.selectedTabID, firstID)
        XCTAssertEqual(view.managedTabViewCount, 2)

        view.apply(
            tabs: [
                snapshot(id: secondID, title: "Renamed.md", isDirty: true),
                snapshot(id: firstID, title: "First.swift")
            ],
            selectedTabID: secondID
        )

        XCTAssertEqual(view.orderedTabIDs, [secondID, firstID])
        XCTAssertEqual(view.selectedTabID, secondID)
        XCTAssertEqual(view.managedTabViewCount, 2)
    }

    func testRemovingTabDropsItsManagedView() {
        let firstID = UUID()
        let secondID = UUID()
        let view = MacNativeFileTabBarView()
        view.apply(
            tabs: [snapshot(id: firstID, title: "One"), snapshot(id: secondID, title: "Two")],
            selectedTabID: firstID
        )

        view.apply(tabs: [snapshot(id: secondID, title: "Two")], selectedTabID: secondID)

        XCTAssertEqual(view.orderedTabIDs, [secondID])
        XCTAssertEqual(view.managedTabViewCount, 1)
    }

    func testNativeTabActionsRetainExistingViewModelRouting() {
        let sourceID = UUID()
        let destinationID = UUID()
        let view = MacNativeFileTabBarView()
        var selectedID: UUID?
        var closedID: UUID?
        var move: (UUID, UUID, Bool)?
        view.onSelect = { selectedID = $0 }
        view.onClose = { closedID = $0 }
        view.onMove = { move = ($0, $1, $2) }

        view.selectTabForTesting(sourceID)
        view.closeTabForTesting(destinationID)
        view.moveTabForTesting(sourceID, destination: destinationID, before: false)

        XCTAssertEqual(selectedID, sourceID)
        XCTAssertEqual(closedID, destinationID)
        XCTAssertEqual(move?.0, sourceID)
        XCTAssertEqual(move?.1, destinationID)
        XCTAssertEqual(move?.2, false)
    }

    func testTabItemsRejectWindowBackgroundDraggingSoReorderingReceivesMouseDrags() throws {
        let id = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 42))
        view.apply(tabs: [snapshot(id: id, title: "Document")], selectedTabID: id)

        let tabItem = try XCTUnwrap(view.descendants.first {
            NSStringFromClass(type(of: $0)).contains("MacNativeFileTabItemView")
        })
        XCTAssertFalse(tabItem.mouseDownCanMoveWindow)
    }

    func testKeyboardAdjacentSelectionUsesOrderedTabsAndStopsAtEdges() {
        let firstID = UUID()
        let secondID = UUID()
        let view = MacNativeFileTabBarView()
        var selectedIDs: [UUID] = []
        view.onSelect = { selectedIDs.append($0) }
        view.apply(
            tabs: [snapshot(id: firstID, title: "One"), snapshot(id: secondID, title: "Two")],
            selectedTabID: firstID
        )

        view.selectAdjacentTab(from: firstID, offset: 1)
        view.selectAdjacentTab(from: firstID, offset: -1)
        view.selectAdjacentTab(from: secondID, offset: 1)

        XCTAssertEqual(selectedIDs, [secondID])
    }

    func testSelectedIndicatorStartsAtTheSelectedTabsLeadingEdge() throws {
        let selectedID = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 32))
        view.apply(
            tabs: [snapshot(id: UUID(), title: "One"), snapshot(id: selectedID, title: "Two")],
            selectedTabID: selectedID
        )

        let indicatorFrame = try XCTUnwrap(view.selectionIndicatorFrameForTesting(selectedID))
        XCTAssertEqual(indicatorFrame.minX, 8)
        XCTAssertGreaterThan(indicatorFrame.width, 100)
    }

    func testInactiveTabsKeepAVisibleTranslucentBoundary() throws {
        let inactiveID = UUID()
        let selectedID = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 32))
        view.apply(
            tabs: [snapshot(id: inactiveID, title: "Inactive"), snapshot(id: selectedID, title: "Selected")],
            selectedTabID: selectedID
        )

        let inactiveState = try XCTUnwrap(view.visualStateForTesting(inactiveID))
        XCTAssertGreaterThan(inactiveState.backgroundAlpha, 0)
        XCTAssertEqual(inactiveState.borderWidth, 0.5)

        let outline = try XCTUnwrap(view.outlineGeometryForTesting(inactiveID))
        XCTAssertEqual(outline.pathBounds.minX, 0.25, accuracy: 0.001)
        XCTAssertEqual(outline.pathBounds.minY, 0.25, accuracy: 0.001)
        XCTAssertEqual(outline.pathBounds.maxX, outline.viewBounds.maxX - 0.25, accuracy: 0.001)
        XCTAssertEqual(outline.pathBounds.maxY, outline.viewBounds.maxY - 0.25, accuracy: 0.001)
    }

    func testInactiveOutlineIsCompositedAboveTabControls() throws {
        let id = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 42))
        view.apply(tabs: [snapshot(id: id, title: "Document")], selectedTabID: nil)

        let state = try XCTUnwrap(view.visualStateForTesting(id))
        XCTAssertGreaterThan(state.borderWidth, 0)
        XCTAssertEqual(view.outlineZPositionForTesting(id), 10)

        let borderBeforeHover = state.borderAlpha
        view.setHoveredForTesting(id, hovered: true)
        let borderDuringHover = try XCTUnwrap(view.visualStateForTesting(id)).borderAlpha
        XCTAssertEqual(borderDuringHover, borderBeforeHover, accuracy: 0.001)
    }

    func testOpaqueLightCanvasUsesAVisibleInactiveOutline() throws {
        let inactiveID = UUID()
        let selectedID = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 42))
        view.appearance = NSAppearance(named: .aqua)
        view.usesOpaqueEditorCanvas = true
        view.apply(
            tabs: [snapshot(id: inactiveID, title: "Inactive"), snapshot(id: selectedID, title: "Selected")],
            selectedTabID: selectedID
        )

        let inactiveState = try XCTUnwrap(view.visualStateForTesting(inactiveID))
        XCTAssertEqual(inactiveState.borderAlpha, 0.32, accuracy: 0.001)

        view.apply(
            tabs: [snapshot(id: inactiveID, title: "Inactive"), snapshot(id: selectedID, title: "Selected")],
            selectedTabID: inactiveID
        )

        let previouslySelectedState = try XCTUnwrap(view.visualStateForTesting(selectedID))
        XCTAssertEqual(previouslySelectedState.borderAlpha, 0.32, accuracy: 0.001)
    }

    func testTabTitleIsAlignedTowardTheBottomEdge() throws {
        let id = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 42))
        view.apply(tabs: [snapshot(id: id, title: "Document")], selectedTabID: id)

        let layout = try XCTUnwrap(view.titleLayoutForTesting(id))
        XCTAssertLessThanOrEqual(layout.tabBounds.height - layout.titleFrame.maxY, 5)
        XCTAssertGreaterThan(layout.titleFrame.midY, layout.tabBounds.midY)
    }

    func testNewTabButtonHasDeliberateSpacingFromTabsAndWindowEdge() {
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 42))
        view.layoutSubtreeIfNeeded()

        let layout = view.addButtonLayoutForTesting
        XCTAssertEqual(layout.buttonFrame.width, 36)
        XCTAssertGreaterThanOrEqual(layout.buttonFrame.minX - layout.tabsFrame.maxX, 8)
        XCTAssertGreaterThanOrEqual(view.bounds.maxX - layout.buttonFrame.maxX, 10)
    }

    func testFilenameWidthsAreBoundedAndOverflowScrollsWithEdgeFades() {
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 520, height: 42))
        let tabs = (0..<6).map { index in
            snapshot(id: UUID(), title: "A-very-long-professional-document-name-\(index).swift")
        }
        view.apply(tabs: tabs, selectedTabID: tabs.first?.id)

        let initial = view.horizontalScrollLayoutForTesting
        XCTAssertGreaterThan(initial.documentWidth, initial.viewportWidth)
        XCTAssertFalse(view.scrollEdgeFadeState.left)
        XCTAssertTrue(view.scrollEdgeFadeState.right)

        view.scrollToEndForTesting()
        XCTAssertTrue(view.scrollEdgeFadeState.left)
        XCTAssertFalse(view.scrollEdgeFadeState.right)
    }

    func testTabWidthTracksFilenameWithinStandardAndDoubleWidthLimits() throws {
        let shortID = UUID()
        let longID = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 700, height: 42))
        view.apply(
            tabs: [
                snapshot(id: shortID, title: "a.swift"),
                snapshot(id: longID, title: String(repeating: "long-file-name-", count: 8) + ".swift")
            ],
            selectedTabID: shortID
        )

        let shortWidth = try XCTUnwrap(view.titleLayoutForTesting(shortID)?.tabBounds.width)
        let longWidth = try XCTUnwrap(view.titleLayoutForTesting(longID)?.tabBounds.width)
        XCTAssertEqual(shortWidth, 128)
        XCTAssertGreaterThan(longWidth, shortWidth)
        XCTAssertEqual(longWidth, 256)
    }

    func testDirtyColorSupersedesSelectionColor() throws {
        let dirtyID = UUID()
        let previousID = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 42))
        view.apply(
            tabs: [
                snapshot(id: dirtyID, title: "Dirty", isDirty: true),
                snapshot(id: previousID, title: "Previous")
            ],
            selectedTabID: dirtyID
        )

        let dirty = try XCTUnwrap(view.visualStateForTesting(dirtyID))
        let previous = try XCTUnwrap(view.visualStateForTesting(previousID))
        XCTAssertGreaterThan(dirty.backgroundAlpha, previous.backgroundAlpha)
    }

    private func snapshot(
        id: UUID,
        title: String,
        isDirty: Bool = false
    ) -> MacNativeFileTabSnapshot {
        MacNativeFileTabSnapshot(
            id: id,
            title: title,
            isDirty: isDirty,
            isRemote: false,
            isReadOnly: false
        )
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
#endif
