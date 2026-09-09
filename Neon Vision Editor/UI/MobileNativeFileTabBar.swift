#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MobileNativeFileTabSnapshot: Equatable, Identifiable {
    let id: UUID
    let title: String
    let isDirty: Bool
    let isRemote: Bool
    let isReadOnly: Bool
}

struct MobileNativeFileTabBar: UIViewRepresentable {
    let tabs: [MobileNativeFileTabSnapshot]
    let selectedTabID: UUID?
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onMove: (UUID, UUID, Bool) -> Void
    let onAdd: () -> Void

    func makeUIView(context: Context) -> MobileNativeFileTabBarView {
        let view = MobileNativeFileTabBarView()
        configure(view)
        return view
    }

    func updateUIView(_ uiView: MobileNativeFileTabBarView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: MobileNativeFileTabBarView) {
        view.onSelect = onSelect
        view.onClose = onClose
        view.onMove = onMove
        view.onAdd = onAdd
        view.apply(tabs: tabs, selectedTabID: selectedTabID)
    }
}

@MainActor
final class MobileNativeFileTabBarView: UIView {
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onMove: ((UUID, UUID, Bool) -> Void)?
    var onAdd: (() -> Void)?

    private let scrollView = UIScrollView()
    private let tabsView = UIView()
    private let addButton = UIButton(type: .system)
    private let separator = UIView()
    private let rightEdgeFadeMask = CAGradientLayer()
    private var tabViewsByID: [UUID: MobileNativeFileTabItemView] = [:]
    private(set) var orderedTabIDs: [UUID] = []
    private(set) var selectedTabID: UUID?

    var managedTabViewCount: Int { tabViewsByID.count }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.addSubview(tabsView)
        rightEdgeFadeMask.colors = [
            UIColor.white.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor
        ]
        rightEdgeFadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        rightEdgeFadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        scrollView.layer.mask = rightEdgeFadeMask
        addSubview(scrollView)

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "plus")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        configuration.contentInsets = .zero
        addButton.configuration = configuration
        addButton.accessibilityLabel = "New Tab"
        addButton.accessibilityHint = "Creates a new untitled tab"
        addButton.addTarget(self, action: #selector(addTab), for: .touchUpInside)
        addSubview(addButton)

        separator.backgroundColor = .separator.withAlphaComponent(0.45)
        separator.isAccessibilityElement = false
        addSubview(separator)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(1, traitCollection.displayScale)
        let separatorHeight = 1 / scale
        let leadingInset: CGFloat = 8
        let buttonWidth: CGFloat = 44
        let trailingInset: CGFloat = 4
        let spacing: CGFloat = 4
        let buttonX = max(leadingInset, bounds.width - trailingInset - buttonWidth)

        separator.frame = CGRect(x: 0, y: bounds.height - separatorHeight, width: bounds.width, height: separatorHeight)
        addButton.frame = CGRect(x: buttonX, y: 0, width: buttonWidth, height: max(0, bounds.height - separatorHeight))
        scrollView.frame = CGRect(
            x: leadingInset,
            y: 0,
            width: max(0, buttonX - spacing - leadingInset),
            height: max(0, bounds.height - separatorHeight)
        )
        rightEdgeFadeMask.frame = scrollView.bounds
        let fadeWidth = min(18, scrollView.bounds.width)
        let fadeStart = max(0, 1 - fadeWidth / max(scrollView.bounds.width, 1))
        rightEdgeFadeMask.locations = [0, NSNumber(value: Double(fadeStart)), 1]
        layoutTabs(viewportWidth: scrollView.bounds.width)
    }

    func apply(
        tabs: [MobileNativeFileTabSnapshot],
        selectedTabID: UUID?,
    ) {
        let incomingIDs = Set(tabs.map(\.id))
        for staleID in tabViewsByID.keys.filter({ !incomingIDs.contains($0) }) {
            tabViewsByID.removeValue(forKey: staleID)?.removeFromSuperview()
        }

        orderedTabIDs = tabs.map(\.id)
        self.selectedTabID = selectedTabID

        for snapshot in tabs {
            let tabView: MobileNativeFileTabItemView
            if let existing = tabViewsByID[snapshot.id] {
                tabView = existing
            } else {
                tabView = MobileNativeFileTabItemView(tabID: snapshot.id)
                tabView.onSelect = { [weak self] id in self?.onSelect?(id) }
                tabView.onClose = { [weak self] id in self?.onClose?(id) }
                tabView.onMove = { [weak self] source, destination, before in
                    self?.onMove?(source, destination, before)
                }
                tabViewsByID[snapshot.id] = tabView
                tabsView.addSubview(tabView)
            }
            tabView.apply(
                snapshot: snapshot,
                isSelected: snapshot.id == selectedTabID,
                allowsReordering: traitCollection.userInterfaceIdiom == .pad
            )
        }

        for (index, id) in orderedTabIDs.enumerated() {
            guard let tabView = tabViewsByID[id] else { continue }
            tabsView.insertSubview(tabView, at: index)
        }

        setNeedsLayout()
        layoutIfNeeded()
        scrollSelectedTabToVisible(animated: window != nil)
    }

    private func layoutTabs(viewportWidth: CGFloat) {
        let count = orderedTabIDs.count
        guard count > 0 else {
            tabsView.frame = CGRect(x: 0, y: 0, width: viewportWidth, height: scrollView.bounds.height)
            scrollView.contentSize = tabsView.bounds.size
            return
        }

        let spacing: CGFloat = 5
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let maximumWidth: CGFloat = traitCollection.userInterfaceIdiom == .pad ? 220 : 188
        let minimumWidth: CGFloat = traitCollection.userInterfaceIdiom == .pad ? 136 : 104
        var tabWidths = orderedTabIDs.map { id in
            guard let tabView = tabViewsByID[id] else { return minimumWidth }
            return min(maximumWidth, max(minimumWidth, tabView.preferredTabWidth))
        }
        let preferredTotal = tabWidths.reduce(0, +) + totalSpacing
        if preferredTotal < viewportWidth {
            let extraPerTab = (viewportWidth - preferredTotal) / CGFloat(count)
            tabWidths = tabWidths.map { min(maximumWidth, $0 + extraPerTab) }
        }
        let contentWidth = max(viewportWidth, tabWidths.reduce(0, +) + totalSpacing)
        tabsView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: scrollView.bounds.height)
        scrollView.contentSize = tabsView.bounds.size

        var x: CGFloat = 0
        for (index, id) in orderedTabIDs.enumerated() {
            let tabWidth = tabWidths[index]
            tabViewsByID[id]?.frame = CGRect(x: x, y: 5, width: tabWidth, height: max(28, tabsView.bounds.height - 10))
            x += tabWidth + spacing
        }
    }

    private func scrollSelectedTabToVisible(animated: Bool) {
        guard let selectedTabID, let selectedView = tabViewsByID[selectedTabID] else { return }
        let visibleRect = selectedView.frame.insetBy(dx: -6, dy: 0)
        guard !scrollView.bounds.contains(visibleRect) else { return }
        scrollView.scrollRectToVisible(visibleRect, animated: animated)
    }

    func selectTabForTesting(_ id: UUID) { onSelect?(id) }
    func closeTabForTesting(_ id: UUID) { onClose?(id) }
    func moveTabForTesting(_ source: UUID, destination: UUID, before: Bool) {
        onMove?(source, destination, before)
    }
    func addTabForTesting() { onAdd?() }

    func visualStateForTesting(_ id: UUID) -> (selected: Bool, previous: Bool, dirty: Bool)? {
        tabViewsByID[id]?.visualStateForTesting
    }

    func accessibilityStateForTesting(_ id: UUID) -> (label: String?, traits: UIAccessibilityTraits)? {
        guard let view = tabViewsByID[id] else { return nil }
        return (view.accessibilityLabel, view.accessibilityTraits)
    }

    func accessibilityActionsForTesting(_ id: UUID) -> [String]? {
        tabViewsByID[id]?.accessibilityCustomActions?.map(\.name)
    }

    func tabFrameForTesting(_ id: UUID) -> CGRect? { tabViewsByID[id]?.frame }

    var addButtonFrameForTesting: CGRect { addButton.frame }
    var scrollViewFrameForTesting: CGRect { scrollView.frame }
    var horizontalContentOffsetForTesting: CGFloat { scrollView.contentOffset.x }
    var horizontalContentWidthForTesting: CGFloat { scrollView.contentSize.width }

    @objc private func addTab() {
        onAdd?()
    }
}

@MainActor
private final class MobileNativeFileTabItemView: UIControl, UIDragInteractionDelegate, UIDropInteractionDelegate {
    let tabID: UUID
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onMove: ((UUID, UUID, Bool) -> Void)?
    var allowsReordering = false {
        didSet {
            dragInteraction.isEnabled = allowsReordering
            updateAccessibilityActions()
        }
    }

    private let remoteLabel = UILabel()
    private let titleLabel = UILabel()
    private let lockImage = UIImageView()
    private let dirtyIndicator = UIView()
    private let closeButton = UIButton(type: .system)
    private let selectionIndicator = UIView()
    private lazy var dragInteraction = UIDragInteraction(delegate: self)
    private lazy var dropInteraction = UIDropInteraction(delegate: self)
    private var snapshot: MobileNativeFileTabSnapshot?
    private var isCurrentSelection = false
    private var insertionBefore: Bool?

    var preferredTabWidth: CGFloat {
        let titleWidth = titleLabel.intrinsicContentSize.width
        let remoteWidth: CGFloat = snapshot?.isRemote == true ? 49 : 0
        let lockWidth: CGFloat = snapshot?.isReadOnly == true ? 17 : 0
        let dirtyWidth: CGFloat = snapshot?.isDirty == true ? 11 : 0
        return titleWidth + 50 + remoteWidth + lockWidth + dirtyWidth
    }

    var visualStateForTesting: (selected: Bool, previous: Bool, dirty: Bool) {
        (isCurrentSelection, false, snapshot?.isDirty == true)
    }

    init(tabID: UUID) {
        self.tabID = tabID
        super.init(frame: .zero)
        layer.cornerCurve = .continuous
        layer.cornerRadius = 8
        layer.borderWidth = 0.5
        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(selectTab), for: .touchUpInside)

        remoteLabel.text = "Remote"
        remoteLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        remoteLabel.textColor = .secondaryLabel
        remoteLabel.textAlignment = .center
        remoteLabel.layer.cornerRadius = 5
        remoteLabel.layer.backgroundColor = UIColor.tintColor.withAlphaComponent(0.12).cgColor
        remoteLabel.clipsToBounds = true
        remoteLabel.isAccessibilityElement = false
        addSubview(remoteLabel)

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabel
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.numberOfLines = 1
        titleLabel.isAccessibilityElement = false
        addSubview(titleLabel)

        lockImage.image = UIImage(systemName: "lock.fill")
        lockImage.tintColor = .secondaryLabel
        lockImage.contentMode = .scaleAspectFit
        lockImage.isAccessibilityElement = false
        addSubview(lockImage)

        dirtyIndicator.backgroundColor = .systemOrange
        dirtyIndicator.layer.cornerRadius = 3
        dirtyIndicator.isAccessibilityElement = false
        addSubview(dirtyIndicator)

        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.image = UIImage(systemName: "xmark")
        closeConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        closeConfiguration.contentInsets = .zero
        closeButton.configuration = closeConfiguration
        closeButton.accessibilityHint = "Closes this editor tab"
        closeButton.addTarget(self, action: #selector(closeTab), for: .touchUpInside)
        addSubview(closeButton)

        selectionIndicator.backgroundColor = .tintColor
        selectionIndicator.layer.cornerRadius = 1
        selectionIndicator.isAccessibilityElement = false
        addSubview(selectionIndicator)

        addInteraction(dragInteraction)
        addInteraction(dropInteraction)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let closeWidth: CGFloat = 36
        let sidePadding: CGFloat = 10
        let remoteWidth: CGFloat = snapshot?.isRemote == true ? 43 : 0
        let lockWidth: CGFloat = snapshot?.isReadOnly == true ? 13 : 0
        let dirtyWidth: CGFloat = snapshot?.isDirty == true ? 6 : 0
        let remoteGap: CGFloat = remoteWidth > 0 ? 6 : 0
        let lockGap: CGFloat = lockWidth > 0 ? 4 : 0
        let dirtyGap: CGFloat = dirtyWidth > 0 ? 5 : 0

        closeButton.frame = CGRect(x: bounds.width - closeWidth, y: 0, width: closeWidth, height: bounds.height)
        remoteLabel.frame = CGRect(x: sidePadding, y: max(7, bounds.height - 22), width: remoteWidth, height: 15)
        let titleX = sidePadding + remoteWidth + remoteGap
        let reservedWidth = closeWidth + lockWidth + lockGap + dirtyWidth + dirtyGap + 4
        titleLabel.frame = CGRect(
            x: titleX,
            y: max(6, bounds.height - 23),
            width: max(12, bounds.width - titleX - reservedWidth),
            height: 18
        )
        lockImage.frame = CGRect(x: titleLabel.frame.maxX + lockGap, y: max(8, bounds.height - 20), width: lockWidth, height: 13)
        dirtyIndicator.frame = CGRect(x: lockImage.frame.maxX + dirtyGap, y: bounds.midY - 3, width: dirtyWidth, height: dirtyWidth)
        selectionIndicator.frame = CGRect(x: 8, y: bounds.height - 2, width: max(0, bounds.width - 16), height: 2)

        if let insertionBefore {
            selectionIndicator.frame = CGRect(
                x: insertionBefore ? -2 : bounds.width,
                y: 3,
                width: 2,
                height: max(0, bounds.height - 6)
            )
        }
    }

    func apply(
        snapshot: MobileNativeFileTabSnapshot,
        isSelected: Bool,
        allowsReordering: Bool
    ) {
        self.snapshot = snapshot
        isCurrentSelection = isSelected
        titleLabel.text = snapshot.title
        titleLabel.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        // Secondary-label gray is too faint over the light editor surface.
        // Keep inactive tabs subordinate without sacrificing filename
        // readability in light mode.
        titleLabel.textColor = isSelected ? .label : UIColor.label.withAlphaComponent(0.72)
        remoteLabel.isHidden = !snapshot.isRemote
        lockImage.isHidden = !snapshot.isReadOnly
        dirtyIndicator.isHidden = !snapshot.isDirty
        closeButton.accessibilityLabel = "Close \(snapshot.title)"
        accessibilityLabel = accessibilityLabel(for: snapshot)
        accessibilityValue = isSelected ? "Selected" : nil
        accessibilityHint = allowsReordering
            ? "Double tap to select. Drag to reorder tabs."
            : "Double tap to select this editor tab."
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        self.allowsReordering = allowsReordering
        updateAppearance()
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    private func updateAppearance() {
        let fillColor: UIColor
        if isCurrentSelection {
            fillColor = tintColor.withAlphaComponent(0.14)
        } else if isHighlighted {
            fillColor = UIColor.label.withAlphaComponent(0.10)
        } else {
            // Keep inactive tabs legible against both light and dark toolbar
            // materials without introducing the heavy gray slab seen in the
            // system secondary fill on translucent surfaces.
            fillColor = UIColor.label.withAlphaComponent(0.055)
        }
        backgroundColor = fillColor
        layer.borderColor = isCurrentSelection
            ? tintColor.withAlphaComponent(0.28).cgColor
            : UIColor.separator.withAlphaComponent(0.18).cgColor
        selectionIndicator.isHidden = insertionBefore == nil && !isCurrentSelection
        selectionIndicator.backgroundColor = insertionBefore == nil ? tintColor : .systemBlue
    }

    private func updateAccessibilityActions() {
        var actions = [
            UIAccessibilityCustomAction(name: "Close Tab", target: self, selector: #selector(closeForAccessibility))
        ]
        guard allowsReordering else {
            accessibilityCustomActions = actions
            return
        }
        actions.append(contentsOf: [
            UIAccessibilityCustomAction(name: "Move Tab Left", target: self, selector: #selector(moveLeftForAccessibility)),
            UIAccessibilityCustomAction(name: "Move Tab Right", target: self, selector: #selector(moveRightForAccessibility))
        ])
        accessibilityCustomActions = actions
    }

    private func accessibilityLabel(for snapshot: MobileNativeFileTabSnapshot) -> String {
        var parts = [snapshot.title, snapshot.isRemote ? "remote document" : "local document"]
        if snapshot.isReadOnly { parts.append("read only") }
        if snapshot.isDirty { parts.append("unsaved changes") }
        return parts.joined(separator: ", ")
    }

    @objc private func selectTab() { onSelect?(tabID) }
    @objc private func closeTab() { onClose?(tabID) }

    @objc private func closeForAccessibility() -> Bool {
        onClose?(tabID)
        return true
    }

    @objc private func moveLeftForAccessibility() -> Bool {
        moveForAccessibility(offset: -1)
    }

    @objc private func moveRightForAccessibility() -> Bool {
        moveForAccessibility(offset: 1)
    }

    private func moveForAccessibility(offset: Int) -> Bool {
        guard let bar = superview?.superview?.superview as? MobileNativeFileTabBarView,
              let index = bar.orderedTabIDs.firstIndex(of: tabID) else { return false }
        let destinationIndex = index + offset
        guard bar.orderedTabIDs.indices.contains(destinationIndex) else { return false }
        onMove?(tabID, bar.orderedTabIDs[destinationIndex], offset < 0)
        return true
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard allowsReordering else { return [] }
        let provider = NSItemProvider(object: tabID.uuidString as NSString)
        let item = UIDragItem(itemProvider: provider)
        item.localObject = tabID
        return [item]
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        guard allowsReordering,
              let sourceID = session.items.first?.localObject as? UUID,
              sourceID != tabID else {
            insertionBefore = nil
            updateAppearance()
            return UIDropProposal(operation: .forbidden)
        }
        insertionBefore = session.location(in: self).x < bounds.midX
        updateAppearance()
        setNeedsLayout()
        return UIDropProposal(operation: .move)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        insertionBefore = nil
        updateAppearance()
        setNeedsLayout()
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        defer {
            insertionBefore = nil
            updateAppearance()
            setNeedsLayout()
        }
        guard let sourceID = session.items.first?.localObject as? UUID,
              sourceID != tabID else { return }
        onMove?(sourceID, tabID, insertionBefore ?? true)
    }
}
#endif
