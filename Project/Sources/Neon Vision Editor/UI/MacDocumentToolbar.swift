#if os(macOS)
import AppKit
import SwiftUI

/// The window owns its toolbar before joining a document-tab group. Hosted
/// controls may change, but SwiftUI must not replace the group's toolbar bridge
/// each time another document finishes loading.
@MainActor
struct MacDocumentToolbar: NSViewRepresentable {
    struct Group: Equatable {
        let id: String
        let items: [String]
    }

    struct NativeButton: Equatable {
        let symbol: String
        let title: String
        let help: String
        var isEnabled = true
        var tint: NSColor = .controlAccentColor
        var accessibilityValue: String?
        var accessibilityHint: String?
        var pointSize: CGFloat = 17
        var weight: NSFont.Weight = .regular
    }

    final class Toolbar: NSToolbar {}
    let owner: EditorViewModel
    let groups: [Group]
    let isVisible: Bool
    let label: (String) -> String
    let control: (String) -> AnyView
    let overflow: (String) -> AnyView
    var nativeButton: ((String) -> NativeButton?)? = nil
    var performNativeAction: ((String) -> Void)? = nil

    static func prepare(_ window: NSWindow) {
        guard !(window.toolbar is Toolbar) else { return }
        // AppKit synchronizes insertion/removal across equal toolbar IDs even
        // with autosaving disabled. Settings owns shared presets; each document
        // owns its physical toolbar and controls independently.
        let toolbar = Toolbar(identifier: .init("NeonVisionEditor.DocumentControls.\(UUID())"))
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false // Settings retains the existing presets/order.
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
    }

    final class Anchor: NSView {
        var configuration: MacDocumentToolbar?
        func apply() {
            guard let window, let configuration else { return }
            MacDocumentWindowTabs.shared.bindToolbar(configuration, to: window)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
    }

    /// AppKit requests the menu form when constructing its overflow menu.
    /// Keep the hosting menu alive for its copied item's action dispatcher.
    final class Item: NSToolbarItem {
        var makeOverflow: (() -> AnyView)?
        private var overflowHost: NSHostingMenu<AnyView>?
        override var menuFormRepresentation: NSMenuItem? {
            get {
                guard let makeOverflow else { return super.menuFormRepresentation }
                let menu = NSHostingMenu(rootView: makeOverflow())
                menu.update()
                overflowHost = menu
                if menu.items.count == 1 { return menu.items[0].copy() as? NSMenuItem }
                let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                item.submenu = menu
                return item
            }
            set { super.menuFormRepresentation = newValue }
        }
    }

    final class ToolbarCoordinator: NSObject, NSToolbarDelegate {
        var configuration: MacDocumentToolbar
        private(set) weak var window: NSWindow?
        private(set) var hosts: [String: NSHostingView<AnyView>] = [:]
        private(set) var nativeButtons: [String: NSButton] = [:]
        private var nativeAppearances: [String: NativeButton] = [:]
        private var installedGroups: [Group] = []

        init(_ configuration: MacDocumentToolbar) { self.configuration = configuration }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.flexibleSpace] + configuration.groups.filter { !$0.items.isEmpty }.map { .init($0.id) }
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            // A newly created document starts with an empty, stable toolbar.
            // The binding installs its actual groups after content is ready;
            // AppKit must not also populate the same groups from defaults.
            []
        }

        func bind(_ window: NSWindow?) {
            guard let window else {
                self.window = nil
                return
            }
            let windowChanged = self.window !== window
            self.window = window
            MacDocumentToolbar.prepare(window)
            guard let toolbar = window.toolbar else { return }
            if toolbar.isVisible != configuration.isVisible { toolbar.isVisible = configuration.isVisible }
            toolbar.delegate = self
            let groups = configuration.groups.filter { !$0.items.isEmpty }
            if windowChanged || installedGroups != groups {
                let previousGroups = installedGroups
                installedGroups = groups
                // Keep existing group views and focus when only their actions
                // change. An empty-then-populated toolbar forces two AppKit
                // layout transactions even on the first document opening.
                for group in toolbar.items.compactMap({ $0 as? NSToolbarItemGroup }) {
                    guard let definition = groups.first(where: { $0.id == group.itemIdentifier.rawValue }) else { continue }
                    if previousGroups.first(where: { $0.id == definition.id })?.items != definition.items {
                        group.subitems = makeSubitems(definition)
                    }
                    updateGroup(definition, group: group)
                }
                let liveIDs = Set(groups.flatMap(\.items))
                hosts = hosts.filter { id, _ in groups.contains { $0.id == id } || liveIDs.contains(id) }
                nativeButtons = nativeButtons.filter { liveIDs.contains($0.key) }
                nativeAppearances = nativeAppearances.filter { liveIDs.contains($0.key) }
                let identifiers: [NSToolbarItem.Identifier] = [.flexibleSpace] + groups.map { .init($0.id) }
                if #available(macOS 15.0, *) {
                    if toolbar.itemIdentifiers != identifiers { toolbar.itemIdentifiers = identifiers }
                } else {
                    if toolbar.items.map(\.itemIdentifier) != identifiers {
                        while !toolbar.items.isEmpty { toolbar.removeItem(at: 0) }
                        for (index, id) in identifiers.enumerated() {
                            toolbar.insertItem(withItemIdentifier: id, at: index)
                        }
                    }
                }
            } else {
                for group in toolbar.items.compactMap({ $0 as? NSToolbarItemGroup }) {
                    if let definition = groups.first(where: { $0.id == group.itemIdentifier.rawValue }) {
                        updateGroup(definition, group: group)
                    }
                    for item in group.subitems { item.label = configuration.label(item.itemIdentifier.rawValue) }
                }
            }
        }

        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            guard let definition = installedGroups.first(where: { $0.id == identifier.rawValue }) else { return nil }
            let group = NSToolbarItemGroup(itemIdentifier: identifier)
            group.controlRepresentation = .automatic
            group.subitems = makeSubitems(definition)
            if configuration.nativeButton != nil {
                let stack = NSStackView()
                stack.orientation = .horizontal
                stack.alignment = .centerY
                stack.spacing = 4
                group.view = stack
                updateGroup(definition, group: group)
            } else {
                let host = NSHostingView(rootView: groupControls(definition))
                host.sizingOptions = [.intrinsicContentSize]
                host.sceneBridgingOptions = []
                group.view = host
                hosts[definition.id] = host
            }
            return group
        }

        private func updateGroup(_ definition: Group, group: NSToolbarItemGroup) {
            guard let stack = group.view as? NSStackView else {
                hosts[definition.id]?.rootView = groupControls(definition)
                return
            }
            let views: [NSView] = definition.items.map { id in
                if let appearance = configuration.nativeButton?(id) {
                    let button: NSButton
                    if let existing = nativeButtons[id] { button = existing }
                    else {
                        button = NSButton()
                        NSLayoutConstraint.activate([
                            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
                            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
                        ])
                    }
                    nativeButtons[id] = button
                    if nativeAppearances[id] != appearance {
                        nativeAppearances[id] = appearance
                        button.identifier = .init(id)
                        button.target = self
                        button.action = #selector(performButtonAction(_:))
                        button.setButtonType(.momentaryPushIn)
                        button.isBordered = false
                        button.imagePosition = .imageOnly
                        button.image = NSImage(systemSymbolName: appearance.symbol, accessibilityDescription: nil)
                        button.symbolConfiguration = .init(pointSize: appearance.pointSize, weight: appearance.weight)
                        button.contentTintColor = appearance.tint
                        button.isEnabled = appearance.isEnabled
                        button.toolTip = appearance.help
                        button.setAccessibilityLabel(appearance.title)
                        button.setAccessibilityValue(appearance.accessibilityValue)
                        button.setAccessibilityHelp(appearance.accessibilityHint)
                        button.setContentHuggingPriority(.required, for: .horizontal)
                    }
                    return button
                }
                let host: NSHostingView<AnyView>
                if let existing = hosts[id] {
                    host = existing
                    host.rootView = configuration.control(id)
                } else {
                    host = NSHostingView(rootView: configuration.control(id))
                    host.sizingOptions = [.intrinsicContentSize]
                    host.sceneBridgingOptions = []
                    hosts[id] = host
                }
                return host
            }
            if stack.arrangedSubviews.count != views.count ||
                zip(stack.arrangedSubviews, views).contains(where: { pair in pair.0 !== pair.1 }) {
                stack.setViews(views, in: .leading)
            }
        }

        @objc private func performButtonAction(_ sender: NSButton) {
            guard sender.isEnabled, let id = sender.identifier?.rawValue,
                  nativeButtons[id] === sender else { return }
            configuration.performNativeAction?(id)
        }

        private func makeSubitems(_ definition: Group) -> [NSToolbarItem] {
            definition.items.map { id in
                let item = Item(itemIdentifier: .init(id))
                item.label = configuration.label(id)
                item.paletteLabel = item.label
                item.makeOverflow = { [weak self] in self?.configuration.overflow(id) ?? AnyView(EmptyView()) }
                return item
            }
        }

        private func groupControls(_ definition: Group) -> AnyView {
            let control = configuration.control
            return AnyView(HStack(spacing: 4) {
                ForEach(definition.items, id: \.self) { id in control(id) }
            }
            // Standalone hosts do not inherit SwiftUI's native toolbar font.
            // Restore the 17-point action symbols without enlarging menu text.
            .font(definition.id == "primary" ? .system(size: 17) : nil))
        }

        func release() {
            if window?.toolbar?.delegate === self { window?.toolbar?.delegate = nil }
            window = nil
            hosts.removeAll()
            nativeButtons.removeAll()
            nativeAppearances.removeAll()
            installedGroups.removeAll()
        }
    }

    func makeNSView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.configuration = self
        return anchor
    }
    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.configuration = self
        anchor.apply()
    }
    static func dismantleNSView(_ anchor: Anchor, coordinator: ()) {
        anchor.configuration = nil
    }
}
#endif
