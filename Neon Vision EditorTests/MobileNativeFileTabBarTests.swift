#if os(iOS)
import UIKit
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class MobileNativeFileTabBarTests: XCTestCase {
    func testApplyingSnapshotsKeepsStableViewsAndSelectionHistory() throws {
        let firstID = UUID()
        let secondID = UUID()
        let view = MobileNativeFileTabBarView()

        view.apply(
            tabs: [snapshot(id: firstID, title: "First.swift"), snapshot(id: secondID, title: "Second.md")],
            selectedTabID: firstID,
        )
        XCTAssertEqual(view.orderedTabIDs, [firstID, secondID])
        XCTAssertEqual(view.managedTabViewCount, 2)

        view.apply(
            tabs: [snapshot(id: secondID, title: "Renamed.md", isDirty: true), snapshot(id: firstID, title: "First.swift")],
            selectedTabID: secondID,
        )

        XCTAssertEqual(view.orderedTabIDs, [secondID, firstID])
        XCTAssertEqual(view.selectedTabID, secondID)
        XCTAssertEqual(view.managedTabViewCount, 2)
        XCTAssertEqual(try XCTUnwrap(view.visualStateForTesting(secondID)).selected, true)
        XCTAssertEqual(try XCTUnwrap(view.visualStateForTesting(secondID)).dirty, true)
    }

    func testRemovingTabDropsItsManagedView() {
        let firstID = UUID()
        let secondID = UUID()
        let view = MobileNativeFileTabBarView()
        view.apply(
            tabs: [snapshot(id: firstID, title: "One"), snapshot(id: secondID, title: "Two")],
            selectedTabID: firstID,
        )

        view.apply(tabs: [snapshot(id: secondID, title: "Two")], selectedTabID: secondID)

        XCTAssertEqual(view.orderedTabIDs, [secondID])
        XCTAssertEqual(view.managedTabViewCount, 1)
    }

    func testNativeActionsRetainExistingViewModelRouting() {
        let sourceID = UUID()
        let destinationID = UUID()
        let view = MobileNativeFileTabBarView()
        var selectedID: UUID?
        var closedID: UUID?
        var move: (UUID, UUID, Bool)?
        var addCount = 0
        view.onSelect = { selectedID = $0 }
        view.onClose = { closedID = $0 }
        view.onMove = { move = ($0, $1, $2) }
        view.onAdd = { addCount += 1 }

        view.selectTabForTesting(sourceID)
        view.closeTabForTesting(destinationID)
        view.moveTabForTesting(sourceID, destination: destinationID, before: false)
        view.addTabForTesting()

        XCTAssertEqual(selectedID, sourceID)
        XCTAssertEqual(closedID, destinationID)
        XCTAssertEqual(move?.0, sourceID)
        XCTAssertEqual(move?.1, destinationID)
        XCTAssertEqual(move?.2, false)
        XCTAssertEqual(addCount, 1)
    }

    func testSelectedTabAccessibilityIncludesStateAndMetadata() throws {
        let id = UUID()
        let view = MobileNativeFileTabBarView()
        view.apply(
            tabs: [MobileNativeFileTabSnapshot(
                id: id,
                title: "Notes.md",
                isDirty: true,
                isRemote: true,
                isReadOnly: true
            )],
            selectedTabID: id,
        )

        let state = try XCTUnwrap(view.accessibilityStateForTesting(id))
        XCTAssertEqual(state.label, "Notes.md, remote document, read only, unsaved changes")
        XCTAssertTrue(state.traits.contains(.button))
        XCTAssertTrue(state.traits.contains(.selected))
        XCTAssertEqual(view.accessibilityActionsForTesting(id)?.first, "Close Tab")
        XCTAssertEqual(view.accessibilityActionsForTesting(id), ["Close Tab", "Move Tab Left", "Move Tab Right"])
    }

    func testAddButtonStaysOutsideHorizontallyScrollingTabs() {
        let view = MobileNativeFileTabBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 42))
        view.apply(
            tabs: (0..<12).map { snapshot(id: UUID(), title: "Document \($0)") },
            selectedTabID: nil,
        )
        view.layoutIfNeeded()

        XCTAssertEqual(view.addButtonFrameForTesting.width, 32)
        XCTAssertEqual(view.trailingTransitionFrameForTesting.minX, view.scrollViewFrameForTesting.maxX, accuracy: 0.5)
        XCTAssertEqual(view.trailingTransitionFrameForTesting.maxX, view.addButtonFrameForTesting.minX, accuracy: 0.5)
        XCTAssertEqual(view.trailingTransitionFrameForTesting.width, 2, accuracy: 0.5)
        XCTAssertFalse(view.trailingTransitionAcceptsTouchesForTesting)
        XCTAssertTrue(view.trailingTransitionIsVisibleForTesting)
        XCTAssertEqual(view.scrollViewFrameForTesting.minX, 8)
    }

    func testSelectingOverflowingLastTabScrollsItIntoView() throws {
        let ids = (0..<12).map { _ in UUID() }
        let lastID = try XCTUnwrap(ids.last)
        let view = MobileNativeFileTabBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 42))
        view.apply(
            tabs: ids.enumerated().map { snapshot(id: $0.element, title: "Document \($0.offset)") },
            selectedTabID: lastID,
        )
        view.layoutIfNeeded()

        XCTAssertGreaterThan(view.horizontalContentWidthForTesting, view.scrollViewFrameForTesting.width)
        XCTAssertGreaterThan(view.horizontalContentOffsetForTesting, 0)
        XCTAssertGreaterThan(try XCTUnwrap(view.tabFrameForTesting(lastID)).minX, view.scrollViewFrameForTesting.width)
        XCTAssertFalse(view.trailingTransitionIsVisibleForTesting)
    }

    func testSelectingFirstTabAfterScrollingRightReturnsItFullyIntoView() throws {
        let ids = (0..<12).map { _ in UUID() }
        let firstID = try XCTUnwrap(ids.first)
        let lastID = try XCTUnwrap(ids.last)
        let view = MobileNativeFileTabBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 42))
        let tabs = ids.enumerated().map { snapshot(id: $0.element, title: "Document \($0.offset)") }

        view.apply(tabs: tabs, selectedTabID: lastID)
        view.layoutIfNeeded()
        XCTAssertGreaterThan(view.horizontalContentOffsetForTesting, 0)

        view.apply(tabs: tabs, selectedTabID: firstID)
        view.layoutIfNeeded()

        XCTAssertEqual(view.horizontalContentOffsetForTesting, 0, accuracy: 0.5)
        XCTAssertTrue(view.trailingTransitionIsVisibleForTesting)
        let visibleFrame = try XCTUnwrap(view.tabFrameInScrollViewForTesting(firstID))
        XCTAssertGreaterThanOrEqual(visibleFrame.minX, -0.5)
        XCTAssertLessThanOrEqual(visibleFrame.maxX, view.scrollViewFrameForTesting.width + 0.5)
    }

    func testRelayoutKeepsSelectedFirstTabAtTheLeadingEdge() throws {
        let ids = (0..<10).map { _ in UUID() }
        let firstID = try XCTUnwrap(ids.first)
        let view = MobileNativeFileTabBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 42))
        let tabs = ids.enumerated().map { snapshot(id: $0.element, title: "Document \($0.offset)") }

        view.apply(tabs: tabs, selectedTabID: firstID)
        view.layoutIfNeeded()
        view.setContentOffsetForTesting(x: 120)
        view.frame.size.width = 320
        view.setNeedsLayout()
        view.layoutIfNeeded()

        XCTAssertEqual(view.horizontalContentOffsetForTesting, 0, accuracy: 0.5)
    }

    func testSelectingFirstTabAfterScrollingRightReturnsItFullyIntoView() throws {
        let ids = (0..<12).map { _ in UUID() }
        let firstID = try XCTUnwrap(ids.first)
        let lastID = try XCTUnwrap(ids.last)
        let view = MobileNativeFileTabBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 42))
        let tabs = ids.enumerated().map { snapshot(id: $0.element, title: "Document \($0.offset)") }

        view.apply(tabs: tabs, selectedTabID: lastID)
        view.layoutIfNeeded()
        XCTAssertGreaterThan(view.horizontalContentOffsetForTesting, 0)

        view.apply(tabs: tabs, selectedTabID: firstID)
        view.layoutIfNeeded()

        XCTAssertEqual(view.horizontalContentOffsetForTesting, 0, accuracy: 0.5)
        let visibleFrame = try XCTUnwrap(view.tabFrameInScrollViewForTesting(firstID))
        XCTAssertGreaterThanOrEqual(visibleFrame.minX, -0.5)
        XCTAssertLessThanOrEqual(visibleFrame.maxX, view.scrollViewFrameForTesting.width + 0.5)
    }

    func testPhoneTabsUseAReadableDefaultWidthForLongFilenames() throws {
        let ids = (0..<3).map { _ in UUID() }
        let view = MobileNativeFileTabBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 42))
        view.apply(
            tabs: ids.map { snapshot(id: $0, title: "architecture.md") },
            selectedTabID: ids.first,
        )
        view.layoutIfNeeded()

        let expectedMinimumWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 136 : 128
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(view.tabFrameForTesting(ids[1])).width, expectedMinimumWidth)
    }

    func testLargeSnapshotUpdateReusesViewsWithinInteractiveBudget() {
        let ids = (0..<250).map { _ in UUID() }
        let view = MobileNativeFileTabBarView(frame: CGRect(x: 0, y: 0, width: 1_024, height: 42))
        let initial = ids.enumerated().map { snapshot(id: $0.element, title: "Document \($0.offset)") }
        view.apply(tabs: initial, selectedTabID: ids.first)

        let start = ProcessInfo.processInfo.systemUptime
        view.apply(
            tabs: initial.reversed().enumerated().map {
                snapshot(id: $0.element.id, title: $0.element.title, isDirty: $0.offset.isMultiple(of: 3))
            },
            selectedTabID: ids.last,
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        XCTAssertEqual(view.managedTabViewCount, ids.count)
        XCTAssertLessThan(elapsed, 1)
    }

    private func snapshot(
        id: UUID,
        title: String,
        isDirty: Bool = false
    ) -> MobileNativeFileTabSnapshot {
        MobileNativeFileTabSnapshot(
            id: id,
            title: title,
            isDirty: isDirty,
            isRemote: false,
            isReadOnly: false
        )
    }
}
#endif
