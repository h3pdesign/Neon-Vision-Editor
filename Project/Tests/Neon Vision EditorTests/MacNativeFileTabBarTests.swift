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

    func testMouseDownDoesNotActivateAnInactiveTabBeforeDragCanBegin() throws {
        let selectedID = UUID()
        let draggedID = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 42))
        view.apply(
            tabs: [snapshot(id: selectedID, title: "Selected"), snapshot(id: draggedID, title: "Drag me")],
            selectedTabID: selectedID
        )
        let draggedTab = try XCTUnwrap(view.descendants.first {
            NSStringFromClass(type(of: $0)).contains("MacNativeFileTabItemView")
                && $0.accessibilityLabel() == "Drag me, local document"
        })
        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        var selected: [UUID] = []
        view.onSelect = {
            selected.append($0)
            Thread.sleep(forTimeInterval: 0.2) // Simulate an editor activation on a slow document.
        }

        let mouseDownStart = ProcessInfo.processInfo.systemUptime
        draggedTab.mouseDown(with: down)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - mouseDownStart, 0.1)
        XCTAssertTrue(selected.isEmpty, "Starting a drag must not synchronously activate another document")
        draggedTab.mouseUp(with: up)
        XCTAssertEqual(selected, [draggedID], "A completed click still selects the tab")
    }

    func testSelectedTabClickIsNotReloadedAndDoubleClickStillCloses() throws {
        let selectedID = UUID()
        let otherID = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 42))
        view.apply(
            tabs: [snapshot(id: selectedID, title: "Selected"), snapshot(id: otherID, title: "Other")],
            selectedTabID: selectedID
        )
        let selectedTab = try XCTUnwrap(view.descendants.first {
            NSStringFromClass(type(of: $0)).contains("MacNativeFileTabItemView")
                && $0.accessibilityLabel() == "Selected, local document"
        })
        let otherTab = try XCTUnwrap(view.descendants.first {
            NSStringFromClass(type(of: $0)).contains("MacNativeFileTabItemView")
                && $0.accessibilityLabel() == "Other, local document"
        })
        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let doubleDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 2, pressure: 1
        ))
        var selections: [UUID] = []
        var closed: [UUID] = []
        view.onSelect = { selections.append($0) }
        view.onClose = { closed.append($0) }

        selectedTab.mouseDown(with: down)
        selectedTab.mouseUp(with: up)
        XCTAssertTrue(selections.isEmpty)
        otherTab.mouseDown(with: doubleDown)
        XCTAssertEqual(closed, [otherID])
        XCTAssertTrue(selections.isEmpty)
    }

    func testWholeTabStripAcceptsDropsIncludingGapsAndTrailingSpace() throws {
        let firstID = UUID()
        let secondID = UUID()
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 700, height: 42))
        view.apply(
            tabs: [snapshot(id: firstID, title: "One"), snapshot(id: secondID, title: "Two")],
            selectedTabID: nil
        )
        let document = try XCTUnwrap(view.descendants.compactMap { ($0 as? NSScrollView)?.documentView }.first)
        XCTAssertTrue(document.registeredDraggedTypes.contains(.string), "The strip, not just tab cells, must accept drops")
        let first = try XCTUnwrap(view.tabFrameForTesting(firstID))
        let second = try XCTUnwrap(view.tabFrameForTesting(secondID))
        let gapTarget = try XCTUnwrap(view.dropTargetForTesting(atDocumentX: (first.maxX + second.minX) / 2))
        XCTAssertEqual(gapTarget.id, secondID)
        XCTAssertTrue(gapTarget.before)
        let trailingTarget = try XCTUnwrap(view.dropTargetForTesting(atDocumentX: second.maxX + 20))
        XCTAssertEqual(trailingTarget.id, secondID)
        XCTAssertFalse(trailingTarget.before)
        let leadingTarget = try XCTUnwrap(view.dropTargetForTesting(atDocumentX: -20))
        XCTAssertEqual(leadingTarget.id, firstID)
        XCTAssertTrue(leadingTarget.before)
        var move: (source: UUID, destination: UUID, before: Bool)?
        view.onMove = { move = ($0, $1, $2) }
        XCTAssertTrue(view.performDropForTesting(secondID, atDocumentX: first.minX + 1))
        XCTAssertEqual(move?.source, secondID)
        XCTAssertEqual(move?.destination, firstID)
        XCTAssertEqual(move?.before, true)
        XCTAssertFalse(view.performDropForTesting(firstID, atDocumentX: first.minX + 1))
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

    func testFocusedTabRoutesHardwareArrowKeysAndMovesFocus() throws {
        let ids = [UUID(), UUID(), UUID()]
        let tabs = ids.enumerated().map { snapshot(id: $0.element, title: "Keyboard \($0.offset).swift") }
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 520, height: 42))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.onSelect = { [weak view] in view?.apply(tabs: tabs, selectedTabID: $0) }
        view.apply(tabs: tabs, selectedTabID: ids[0])
        let first = try XCTUnwrap(view.descendants.first {
            $0.accessibilityLabel() == "Keyboard 0.swift, local document"
        })
        XCTAssertTrue(window.makeFirstResponder(first))
        let right = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124))
        first.keyDown(with: right)
        XCTAssertEqual(view.selectedTabID, ids[1])
        let second = try XCTUnwrap(window.firstResponder as? NSView)
        XCTAssertEqual(second.accessibilityLabel(), "Keyboard 1.swift, local document")
        second.keyDown(with: right)
        XCTAssertEqual(view.selectedTabID, ids[2])
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

    func testUpdatingUnchangedSelectionDoesNotUndoManualOverflowScrolling() throws {
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 520, height: 42))
        let tabs = (0..<12).map { snapshot(id: UUID(), title: "Overflow document \($0).swift") }
        view.apply(tabs: tabs, selectedTabID: tabs[0].id)
        view.scrollToEndForTesting()
        let scroll = try XCTUnwrap(view.descendants.compactMap { $0 as? NSScrollView }.first)
        let offset = scroll.contentView.bounds.minX
        XCTAssertGreaterThan(offset, 0)
        view.apply(tabs: tabs, selectedTabID: tabs[0].id)
        XCTAssertEqual(scroll.contentView.bounds.minX, offset, accuracy: 0.5,
                       "Status/dirty-state redraws must not snap away from the tabs the user is browsing")
    }

    func testSelectingBeforeInitialLayoutRevealsTabAfterViewportHasSize() throws {
        let view = MacNativeFileTabBarView()
        let tabs = (0..<12).map { snapshot(id: UUID(), title: "Overflow document \($0).swift") }
        view.apply(tabs: tabs, selectedTabID: tabs.last?.id)
        view.setFrameSize(NSSize(width: 520, height: 42))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(view.descendants.compactMap { $0 as? NSScrollView }.first)
        let last = try XCTUnwrap(view.tabFrameForTesting(tabs.last!.id))
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)
        XCTAssertLessThanOrEqual(last.maxX, scroll.contentView.bounds.maxX + 0.5)
    }

    func testOverflowButtonsReachHiddenTabsAndExposeAccessibleActions() async throws {
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 520, height: 42))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Overflow tabs QA"
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let tabs = (0..<12).map { snapshot(id: UUID(), title: "Overflow document \($0).swift") }
        view.apply(tabs: tabs, selectedTabID: tabs[0].id)
        let buttons = view.descendants.compactMap { $0 as? NSButton }
        let left = try XCTUnwrap(buttons.first { $0.toolTip == NSLocalizedString("Scroll Tabs Left", comment: "") })
        let right = try XCTUnwrap(buttons.first { $0.toolTip == NSLocalizedString("Scroll Tabs Right", comment: "") })
        XCTAssertFalse(left.isHidden)
        XCTAssertFalse(right.isHidden)
        XCTAssertFalse(left.isEnabled)
        XCTAssertTrue(right.isEnabled)
        XCTAssertEqual(right.accessibilityLabel(), right.toolTip)
        try await Task.sleep(for: .milliseconds(100))
        window.displayIfNeeded()
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        let attachment = XCTAttachment(data: try XCTUnwrap(image.representation(using: .png, properties: [:])),
                                       uniformTypeIdentifier: "public.png")
        attachment.name = "Overflow tab strip 520x42"
        attachment.lifetime = .keepAlways
        add(attachment)
        if ProcessInfo.processInfo.environment["NVE_TAB_INTERACTIVE_QA"] == "1" {
            view.onSelect = { [weak view] in view?.apply(tabs: tabs, selectedTabID: $0) }
            FileHandle.standardOutput.write(Data("OVERFLOW_TABS_QA_READY\n".utf8))
            let deadline = Date().addingTimeInterval(180)
            let scroll = try XCTUnwrap(view.descendants.compactMap { $0 as? NSScrollView }.first)
            var observedAdvance = false
            var observedReturn = false
            while Date() < deadline && !observedReturn {
                observedAdvance = observedAdvance || scroll.contentView.bounds.minX > 0
                observedReturn = observedAdvance && scroll.contentView.bounds.minX <= 0.5
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(observedAdvance)
            XCTAssertTrue(observedReturn)
            view.apply(tabs: tabs, selectedTabID: tabs[0].id)
        }
        right.performClick(nil)
        let scroll = try XCTUnwrap(view.descendants.compactMap { $0 as? NSScrollView }.first)
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)
        for _ in 0..<20 { right.performClick(nil) }
        XCTAssertFalse(right.isEnabled)
        XCTAssertTrue(left.isEnabled)
        let lastFrame = try XCTUnwrap(view.tabFrameForTesting(tabs.last!.id))
        XCTAssertLessThanOrEqual(lastFrame.maxX, scroll.contentView.bounds.maxX + 0.5)
        for _ in 0..<20 { left.performClick(nil) }
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
        view.apply(tabs: [tabs[0]], selectedTabID: tabs[0].id)
        XCTAssertTrue(left.isHidden)
        XCTAssertTrue(right.isHidden)
    }

    func testChangingSelectionRevealsTheNewTabButUnchangedMetadataKeepsScroll() throws {
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 520, height: 42))
        let tabs = (0..<12).map { snapshot(id: UUID(), title: "Overflow document \($0).swift") }
        view.apply(tabs: tabs, selectedTabID: tabs[0].id)
        view.apply(tabs: tabs, selectedTabID: tabs.last?.id)
        let scroll = try XCTUnwrap(view.descendants.compactMap { $0 as? NSScrollView }.first)
        let offset = scroll.contentView.bounds.minX
        XCTAssertGreaterThan(offset, 0)
        let changed = tabs.map { snapshot(id: $0.id, title: $0.title, isDirty: true) }
        view.apply(tabs: changed, selectedTabID: tabs.last?.id)
        XCTAssertEqual(scroll.contentView.bounds.minX, offset, accuracy: 0.5)
    }

    func testRemovingOverflowAndResizingDoesNotLeaveTabsOutsideTheViewport() throws {
        let view = MacNativeFileTabBarView(frame: NSRect(x: 0, y: 0, width: 520, height: 42))
        let tabs = (0..<12).map { snapshot(id: UUID(), title: "Overflow document \($0).swift") }
        view.apply(tabs: tabs, selectedTabID: tabs[0].id)
        view.scrollToEndForTesting()
        let scroll = try XCTUnwrap(view.descendants.compactMap { $0 as? NSScrollView }.first)
        view.apply(tabs: [tabs[0]], selectedTabID: tabs[0].id)
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
        view.apply(tabs: tabs, selectedTabID: tabs[0].id)
        view.scrollToEndForTesting()
        view.setFrameSize(NSSize(width: 4_000, height: 42))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
        view.apply(tabs: [], selectedTabID: nil)
        XCTAssertEqual(view.managedTabViewCount, 0)
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
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
