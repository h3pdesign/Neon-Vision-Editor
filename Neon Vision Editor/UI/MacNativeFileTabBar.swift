#if os(macOS)
import AppKit
import SwiftUI

struct MacNativeFileTabSnapshot: Equatable, Identifiable {
    let id: UUID
    let title: String
    let isDirty: Bool
    let isRemote: Bool
    let isReadOnly: Bool
}

struct MacNativeFileTabBar: NSViewRepresentable {
    let tabs: [MacNativeFileTabSnapshot]
    let selectedTabID: UUID?
    let usesOpaqueEditorCanvas: Bool
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onMove: (UUID, UUID, Bool) -> Void
    let onAdd: () -> Void

    func makeNSView(context: Context) -> MacNativeFileTabBarView {
        let view = MacNativeFileTabBarView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: MacNativeFileTabBarView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: MacNativeFileTabBarView) {
        view.onSelect = onSelect
        view.onClose = onClose
        view.onMove = onMove
        view.onAdd = onAdd
        view.usesOpaqueEditorCanvas = usesOpaqueEditorCanvas
        view.apply(tabs: tabs, selectedTabID: selectedTabID)
    }
}

@MainActor
final class MacNativeFileTabBarView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onMove: ((UUID, UUID, Bool) -> Void)?
    var onAdd: (() -> Void)?

    private let scrollView = NSScrollView()
    private let tabsView = MacNativeFileTabDocumentView()
    private let addButton = NSButton()
    private let scrollEdgeMask = CAGradientLayer()
    private var tabViewsByID: [UUID: MacNativeFileTabItemView] = [:]
    private(set) var orderedTabIDs: [UUID] = []
    private(set) var selectedTabID: UUID?
    private(set) var scrollEdgeFadeState = (left: false, right: false)
    var usesOpaqueEditorCanvas = false

    var managedTabViewCount: Int { tabViewsByID.count }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = tabsView
        scrollView.wantsLayer = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollEdgeMask.startPoint = CGPoint(x: 0, y: 0.5)
        scrollEdgeMask.endPoint = CGPoint(x: 1, y: 0.5)
        scrollView.layer?.mask = scrollEdgeMask
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        addSubview(scrollView)

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        addButton.imagePosition = .imageOnly
        addButton.bezelStyle = .accessoryBarAction
        addButton.controlSize = .small
        addButton.target = self
        addButton.action = #selector(addTab)
        addButton.toolTip = "New Tab"
        addButton.setAccessibilityLabel("New Tab")
        addButton.setAccessibilityHelp("Creates a new untitled tab")
        addSubview(addButton)

    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let leadingInset: CGFloat = 8
        let tabToButtonSpacing: CGFloat = 8
        let buttonWidth: CGFloat = 36
        let trailingInset: CGFloat = 10
        let buttonX = bounds.width - trailingInset - buttonWidth
        addButton.frame = NSRect(x: buttonX, y: 6, width: buttonWidth, height: max(24, bounds.height - 12))
        scrollView.frame = NSRect(
            x: leadingInset,
            y: 0,
            width: max(0, buttonX - tabToButtonSpacing - leadingInset),
            height: max(0, bounds.height)
        )
        // The document view must fill the clip viewport. Deriving its height
        // from contentSize can reuse a stale/short document height during a
        // relayout, making the scroll view clip the rounded tab layers at the
        // bottom (most visible against dark chrome).
        tabsView.frame.size.height = scrollView.contentView.bounds.height
        tabsView.layoutTabs(viewportWidth: scrollView.contentSize.width)
        updateScrollEdgeMask()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The representable can retain its NSView while SwiftUI replaces the
        // toolbar/editor surface. Refresh the item layers from the container
        // so their semantic colors are resolved against the new appearance.
        for tabView in tabViewsByID.values {
            tabView.refreshForContainerAppearanceChange()
        }
    }

    func apply(tabs: [MacNativeFileTabSnapshot], selectedTabID: UUID?) {
        let incomingIDs = Set(tabs.map(\.id))
        let staleIDs = tabViewsByID.keys.filter { !incomingIDs.contains($0) }
        for staleID in staleIDs {
            tabViewsByID.removeValue(forKey: staleID)?.removeFromSuperview()
        }

        orderedTabIDs = tabs.map(\.id)
        self.selectedTabID = selectedTabID
        var orderedViews: [MacNativeFileTabItemView] = []
        orderedViews.reserveCapacity(tabs.count)

        for snapshot in tabs {
            let tabView: MacNativeFileTabItemView
            if let existing = tabViewsByID[snapshot.id] {
                tabView = existing
            } else {
                tabView = MacNativeFileTabItemView(tabID: snapshot.id)
                tabView.onSelect = { [weak self] id in self?.onSelect?(id) }
                tabView.onClose = { [weak self] id in self?.onClose?(id) }
                tabViewsByID[snapshot.id] = tabView
            }
            tabView.apply(
                snapshot: snapshot,
                isSelected: snapshot.id == selectedTabID,
                usesOpaqueEditorCanvas: usesOpaqueEditorCanvas
            )
            orderedViews.append(tabView)
        }

        tabsView.setTabViews(orderedViews)
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let selectedTabID, let selectedView = tabViewsByID[selectedTabID] {
            selectedView.scrollToVisible(selectedView.bounds)
        }
    }

    func selectTabForTesting(_ id: UUID) {
        onSelect?(id)
    }

    func closeTabForTesting(_ id: UUID) {
        onClose?(id)
    }

    func moveTabForTesting(_ source: UUID, destination: UUID, before: Bool) {
        onMove?(source, destination, before)
    }

    func selectionIndicatorFrameForTesting(_ id: UUID) -> NSRect? {
        tabViewsByID[id]?.selectionIndicatorFrameForTesting
    }

    func visualStateForTesting(_ id: UUID) -> (backgroundAlpha: CGFloat, borderWidth: CGFloat, borderAlpha: CGFloat)? {
        tabViewsByID[id]?.visualStateForTesting
    }

    func outlineGeometryForTesting(_ id: UUID) -> (pathBounds: CGRect, viewBounds: CGRect)? {
        tabViewsByID[id]?.outlineGeometryForTesting
    }

    func outlineZPositionForTesting(_ id: UUID) -> CGFloat? {
        tabViewsByID[id]?.outlineZPositionForTesting
    }

    func setHoveredForTesting(_ id: UUID, hovered: Bool) {
        tabViewsByID[id]?.setHoveredForTesting(hovered)
    }

    func titleLayoutForTesting(_ id: UUID) -> (titleFrame: NSRect, tabBounds: NSRect)? {
        tabViewsByID[id]?.titleLayoutForTesting
    }

    var addButtonLayoutForTesting: (buttonFrame: NSRect, tabsFrame: NSRect) {
        (addButton.frame, scrollView.frame)
    }

    var horizontalScrollLayoutForTesting: (documentWidth: CGFloat, viewportWidth: CGFloat) {
        (tabsView.frame.width, scrollView.contentSize.width)
    }

    func scrollToEndForTesting() {
        let destination = max(0, tabsView.frame.width - scrollView.contentSize.width)
        scrollView.contentView.scroll(to: NSPoint(x: destination, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateScrollEdgeMask()
    }

    func selectAdjacentTab(from id: UUID, offset: Int) {
        guard let index = orderedTabIDs.firstIndex(of: id) else { return }
        let destinationIndex = index + offset
        guard orderedTabIDs.indices.contains(destinationIndex) else { return }
        let destinationID = orderedTabIDs[destinationIndex]
        onSelect?(destinationID)
        window?.makeFirstResponder(tabViewsByID[destinationID])
    }

    @objc private func addTab() {
        onAdd?()
    }

    @objc private func scrollBoundsDidChange() {
        updateScrollEdgeMask()
    }

    private func updateScrollEdgeMask() {
        let viewportWidth = scrollView.contentSize.width
        let maximumOffset = max(0, tabsView.frame.width - viewportWidth)
        let offset = min(max(0, scrollView.contentView.bounds.minX), maximumOffset)
        let showsLeftFade = offset > 0.5
        let showsRightFade = maximumOffset - offset > 0.5
        scrollEdgeFadeState = (showsLeftFade, showsRightFade)

        let opaque = NSColor.black.cgColor
        let clear = NSColor.clear.cgColor
        scrollEdgeMask.frame = scrollView.bounds
        scrollEdgeMask.colors = [
            showsLeftFade ? clear : opaque,
            opaque,
            opaque,
            showsRightFade ? clear : opaque
        ]
        scrollEdgeMask.locations = [0, 0.035, 0.965, 1]
    }
}

@MainActor
private final class MacNativeFileTabDocumentView: NSView {
    private var tabViews: [MacNativeFileTabItemView] = []

    override var isFlipped: Bool { true }

    func setTabViews(_ views: [MacNativeFileTabItemView]) {
        guard tabViews.map(\.tabID) != views.map(\.tabID) else { return }
        tabViews = views
        subviews = views
        needsLayout = true
    }

    func layoutTabs(viewportWidth: CGFloat) {
        let count = tabViews.count
        guard count > 0 else {
            frame.size.width = viewportWidth
            return
        }

        let spacing: CGFloat = 5
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let contentWidth = tabViews.reduce(0) { $0 + $1.preferredWidth } + totalSpacing
        frame.size.width = max(viewportWidth, contentWidth)
        var x: CGFloat = 0
        for tabView in tabViews {
            let width = tabView.preferredWidth
            // Keep a full-pixel breathing room around the rounded layer. The
            // previous 5-point inset put the lower border on the scroll view's
            // clipping boundary in dark appearance, making inactive tabs look
            // cut off at the bottom.
            tabView.frame = NSRect(x: x, y: 6, width: width, height: max(24, bounds.height - 12))
            x += width + spacing
        }
    }
}

@MainActor
private final class MacNativeFileTabItemView: NSView, NSDraggingSource {
    let tabID: UUID
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let remoteLabel = NSTextField(labelWithString: "Remote")
    private let lockImage = NSImageView()
    private let closeButton = NSButton()
    private let divider = NSBox()
    private let selectionIndicator = NSBox()
    private let outlineLayer = CAShapeLayer()
    private var trackingAreaReference: NSTrackingArea?
    private var snapshot: MacNativeFileTabSnapshot?
    private var isSelected = false
    private var isHovered = false
    private var isDragging = false
    private var insertionBefore: Bool?
    private var usesOpaqueEditorCanvas = false

    var selectionIndicatorFrameForTesting: NSRect { selectionIndicator.frame }
    var visualStateForTesting: (backgroundAlpha: CGFloat, borderWidth: CGFloat, borderAlpha: CGFloat) {
        (layer?.backgroundColor?.alpha ?? 0, outlineLayer.lineWidth, outlineLayer.strokeColor?.alpha ?? 0)
    }
    var outlineGeometryForTesting: (pathBounds: CGRect, viewBounds: CGRect)? {
        guard let path = outlineLayer.path else { return nil }
        return (path.boundingBox, bounds)
    }
    var outlineZPositionForTesting: CGFloat { outlineLayer.zPosition }

    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered
        updateAppearance()
    }
    var titleLayoutForTesting: (titleFrame: NSRect, tabBounds: NSRect) { (titleLabel.frame, bounds) }
    var preferredWidth: CGFloat {
        let titleWidth = ceil(titleLabel.intrinsicContentSize.width)
        let remoteContribution: CGFloat = snapshot?.isRemote == true ? 51 : 0
        let lockContribution: CGFloat = snapshot?.isReadOnly == true ? 19 : 0
        let chromeWidth: CGFloat = 41
        return min(256, max(128, titleWidth + remoteContribution + lockContribution + chromeWidth))
    }

    init(tabID: UUID) {
        self.tabID = tabID
        super.init(frame: .zero)
        wantsLayer = true
        outlineLayer.fillColor = NSColor.clear.cgColor
        outlineLayer.lineJoin = .round
        // Keep the complete outline above labels and AppKit control layers.
        // During an appearance/material relayout those child layers can be
        // composited after the default-z sublayer and cover its lower edge.
        outlineLayer.zPosition = 10
        outlineLayer.needsDisplayOnBoundsChange = true
        layer?.addSublayer(outlineLayer)
        registerForDraggedTypes([.string])

        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.font = .systemFont(ofSize: 12)
        addSubview(titleLabel)

        remoteLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        remoteLabel.textColor = .secondaryLabelColor
        remoteLabel.alignment = .center
        remoteLabel.wantsLayer = true
        remoteLabel.layer?.cornerRadius = 5
        remoteLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        addSubview(remoteLabel)

        lockImage.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Read Only")
        lockImage.contentTintColor = .secondaryLabelColor
        lockImage.imageScaling = .scaleProportionallyDown
        addSubview(lockImage)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
        closeButton.imagePosition = .imageOnly
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.controlSize = .small
        closeButton.image = closeButton.image?.withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        closeButton.target = self
        closeButton.action = #selector(closeTab)
        addSubview(closeButton)

        divider.boxType = .separator
        addSubview(divider)

        selectionIndicator.boxType = .custom
        selectionIndicator.borderWidth = 0
        selectionIndicator.fillColor = .controlAccentColor
        selectionIndicator.cornerRadius = 1
        addSubview(selectionIndicator)

        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49: // Return or Space
            onSelect?(tabID)
        case 123: // Left Arrow
            enclosingBar?.selectAdjacentTab(from: tabID, offset: -1)
        case 124: // Right Arrow
            enclosingBar?.selectAdjacentTab(from: tabID, offset: 1)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?(tabID)
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func refreshForContainerAppearanceChange() {
        updateAppearance()
        needsLayout = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        insertionBefore = nil
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(tabID)
        if event.clickCount == 2 {
            onClose?(tabID)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging else { return }
        isDragging = true
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tabID.uuidString, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: bitmapImageRepForCachingDisplay(in: bounds))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateInsertion(for: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateInsertion(for: sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        insertionBefore = nil
        updateAppearance()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            insertionBefore = nil
            updateAppearance()
        }
        guard let value = sender.draggingPasteboard.string(forType: .string),
              let sourceID = UUID(uuidString: value),
              sourceID != tabID else { return false }
        let before = insertionBefore ?? true
        guard let bar = enclosingBar else { return false }
        bar.onMove?(sourceID, tabID, before)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        insertionBefore = nil
        updateAppearance()
    }

    override func layout() {
        super.layout()
        let borderWidth: CGFloat = 0.5
        let borderInset = borderWidth / 2
        outlineLayer.frame = bounds
        outlineLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        outlineLayer.lineWidth = borderWidth
        outlineLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: borderInset, dy: borderInset),
            cornerWidth: 7 - borderInset,
            cornerHeight: 7 - borderInset,
            transform: nil
        )
        let closeWidth: CGFloat = 22
        let sidePadding: CGFloat = 10
        let remoteWidth: CGFloat = snapshot?.isRemote == true ? 45 : 0
        let lockWidth: CGFloat = snapshot?.isReadOnly == true ? 14 : 0
        let remoteGap: CGFloat = remoteWidth > 0 ? 6 : 0
        let lockGap: CGFloat = lockWidth > 0 ? 5 : 0

        closeButton.frame = NSRect(x: bounds.width - closeWidth - 4, y: 2, width: closeWidth, height: bounds.height - 4)
        remoteLabel.frame = NSRect(x: sidePadding, y: max(7, bounds.height - 20), width: remoteWidth, height: 15)
        let titleX = sidePadding + remoteWidth + remoteGap
        let titleWidth = max(12, bounds.width - titleX - closeWidth - lockWidth - lockGap - 5)
        titleLabel.frame = NSRect(x: titleX, y: max(7, bounds.height - 22), width: titleWidth, height: 18)
        lockImage.frame = NSRect(x: titleLabel.frame.maxX + lockGap, y: max(9, bounds.height - 18), width: lockWidth, height: 12)
        divider.frame = NSRect(x: bounds.width + 2, y: 7, width: 1, height: max(0, bounds.height - 14))
        selectionIndicator.frame = NSRect(
            x: insertionBefore == nil ? 8 : (insertionBefore == true ? -3 : bounds.width + 1),
            y: insertionBefore == nil ? bounds.height - 2 : 3,
            width: insertionBefore == nil ? max(0, bounds.width - 16) : 2,
            height: insertionBefore == nil ? 2 : bounds.height - 6
        )
    }

    func apply(
        snapshot: MacNativeFileTabSnapshot,
        isSelected: Bool,
        usesOpaqueEditorCanvas: Bool
    ) {
        self.snapshot = snapshot
        self.isSelected = isSelected
        self.usesOpaqueEditorCanvas = usesOpaqueEditorCanvas
        titleLabel.stringValue = snapshot.title + (snapshot.isDirty ? " •" : "")
        titleLabel.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        remoteLabel.isHidden = !snapshot.isRemote
        lockImage.isHidden = !snapshot.isReadOnly
        closeButton.toolTip = "Close \(snapshot.title)"
        closeButton.setAccessibilityLabel("Close \(snapshot.title)")
        setAccessibilityLabel(accessibilityLabel(for: snapshot))
        setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        setAccessibilityHelp("Press to select this tab. Use the left and right arrow keys to move between tabs.")
        updateAppearance()
        needsLayout = true
    }

    private var enclosingBar: MacNativeFileTabBarView? {
        var candidate = superview
        while let view = candidate {
            if let bar = view as? MacNativeFileTabBarView { return bar }
            candidate = view.superview
        }
        return nil
    }

    private func updateInsertion(for sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        insertionBefore = point.x < bounds.midX
        updateAppearance()
    }

    private func updateAppearance() {
        let isDarkAppearance = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let stateColor: NSColor? = if snapshot?.isDirty == true {
            .systemOrange
        } else if isSelected {
            .controlAccentColor
        } else {
            nil
        }
        let fillColor: NSColor
        if let stateColor {
            fillColor = stateColor.withAlphaComponent(snapshot?.isDirty == true ? 0.13 : 0.105)
        } else if isHovered {
            fillColor = .labelColor.withAlphaComponent(0.075)
        } else {
            // Opaque light editor chrome is close to white, so the very low
            // contrast used by translucent/dark surfaces makes inactive tabs
            // visually disappear. Keep them quiet, but give each tab a clear
            // surface boundary in light mode.
            fillColor = .labelColor.withAlphaComponent(isDarkAppearance ? 0.025 : 0.055)
        }
        layer?.backgroundColor = fillColor.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 0
        // Resolve the inactive outline to a concrete color before handing it
        // to Core Animation. Retaining separatorColor's dynamic CGColor lets
        // AppKit's material/hover recomposition replace the resolved contrast,
        // which is why the border could flash once and then disappear.
        let inactiveOutlineColor = NSColor(
            calibratedWhite: isDarkAppearance ? 1 : 0,
            alpha: !isDarkAppearance && usesOpaqueEditorCanvas ? 0.32 : (isDarkAppearance ? 0.34 : 0.28)
        )
        outlineLayer.strokeColor = stateColor != nil
            ? stateColor?.withAlphaComponent(0.24).cgColor
            : inactiveOutlineColor.cgColor
        closeButton.isHidden = !(isSelected || isHovered || snapshot?.isDirty == true)
        selectionIndicator.isHidden = insertionBefore == nil && stateColor == nil
        selectionIndicator.fillColor = insertionBefore == nil ? (stateColor ?? .controlAccentColor) : .keyboardFocusIndicatorColor
        divider.isHidden = true
        needsLayout = true
    }

    private func accessibilityLabel(for snapshot: MacNativeFileTabSnapshot) -> String {
        var parts = [snapshot.title, snapshot.isRemote ? "remote document" : "local document"]
        if snapshot.isReadOnly { parts.append("read only") }
        if snapshot.isDirty { parts.append("unsaved changes") }
        return parts.joined(separator: ", ")
    }

    @objc private func closeTab() {
        onClose?(tabID)
    }
}
#endif
