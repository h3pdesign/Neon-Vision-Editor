#if os(macOS)
import AppKit
import SwiftUI

/// Native document layout. SwiftUI owns accessory state, not the text view or
/// its layout/focus lifetime. Factories for absent accessories are never called.
@MainActor
final class MacDocumentContentController: NSViewController {
    struct Pane {
        let editor: VirtualEditorView
        var minimap: (() -> AnyView)?
        var header: (() -> AnyView)?
    }

    struct Configuration {
        var primary: Pane?
        var secondary: Pane?
        var replacement: (() -> AnyView)?
        var header: (() -> AnyView)?
        var status: (() -> AnyView)?
        var find: (() -> AnyView)?
        var contentInsets = NSEdgeInsets()
        var maximumEditorWidth: CGFloat?
        var hostContent: (AnyView) -> AnyView = { $0 }
        var startupOverlay: (() -> AnyView)?
        var formattingOverlay: (() -> AnyView)?
    }

    private let column = NSStackView()
    private lazy var root = OverlayContainer(content: column)
    private let editors = NSStackView()
    private let contentContainer = ContentContainer()
    private var accessoryHosts: [String: NSHostingView<AnyView>] = [:]
    private(set) var primaryController: EditorPaneController?
    private(set) var secondaryController: EditorPaneController?
    private var hostContent: (AnyView) -> AnyView = { $0 }
    private var exposesSplitGroup = false

    override func loadView() {
        column.orientation = .vertical
        column.alignment = .width
        column.spacing = 0
        editors.orientation = .horizontal
        editors.alignment = .height
        editors.distribution = .fillEqually
        editors.spacing = 1
        view = root
    }

    func update(_ configuration: Configuration) {
        loadViewIfNeeded()
        hostContent = configuration.hostContent
        let splitGroup = configuration.secondary != nil && configuration.replacement == nil
        if exposesSplitGroup != splitGroup {
            exposesSplitGroup = splitGroup
            editors.setAccessibilityElement(splitGroup)
            editors.setAccessibilityRole(.group)
            editors.setAccessibilityLabel(splitGroup ? NSLocalizedString("Split editor", comment: "Editor accessibility group") : nil)
        }
        let header = updateAccessory("header", factory: configuration.header)
        let status = updateAccessory("status", factory: configuration.status)
        let find = updateAccessory("find", factory: configuration.find)
        let replacement = updateAccessory("replacement", factory: configuration.replacement, fillsHeight: true)
        contentContainer.installOverlay(updateAccessory("startup", factory: configuration.startupOverlay, fillsHeight: true))
        root.installOverlay(updateAccessory("formatting", factory: configuration.formattingOverlay))
        if configuration.secondary == nil, let controller = secondaryController {
            editors.removeView(controller.view)
            controller.removeFromParent()
            secondaryController = nil
        }
        let content: NSView
        if let replacement {
            // A structured/reading mode is a separate, lazily hosted surface.
            // Do not construct either source editor until it is needed.
            content = replacement
        } else {
            var panes: [NSView] = []
            if let primary = configuration.primary {
                let controller = primaryController ?? EditorPaneController()
                if primaryController == nil { primaryController = controller; addChild(controller) }
                controller.update(primary, hostContent: configuration.hostContent)
                panes.append(controller.view)
            }
            if let secondary = configuration.secondary {
                let controller = secondaryController ?? EditorPaneController()
                if secondaryController == nil { secondaryController = controller; addChild(controller) }
                controller.update(secondary, hostContent: configuration.hostContent)
                panes.append(controller.view)
            }
            Self.install(panes, in: editors)
            content = editors
        }
        contentContainer.install(content, insets: configuration.contentInsets, maximumWidth: configuration.maximumEditorWidth)
        contentContainer.setContentHuggingPriority(.init(1), for: .vertical)
        contentContainer.setContentCompressionResistancePriority(.init(1), for: .vertical)
        Self.install([header, contentContainer, status, find].compactMap { $0 }, in: column)
    }

    private func updateAccessory(_ key: String, factory: (() -> AnyView)?, fillsHeight: Bool = false) -> NSView? {
        guard let factory else {
            accessoryHosts.removeValue(forKey: key)?.removeFromSuperview()
            return nil
        }
        if let host = accessoryHosts[key] {
            host.rootView = hostContent(factory())
            return host
        }
        let host = NSHostingView(rootView: hostContent(factory()))
        host.sceneBridgingOptions = []
        host.sizingOptions = fillsHeight ? [] : [.intrinsicContentSize]
        if !fillsHeight {
            host.setContentHuggingPriority(.required, for: .vertical)
            host.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        accessoryHosts[key] = host
        return host
    }

    fileprivate static func install(_ views: [NSView], in stack: NSStackView) {
        guard stack.arrangedSubviews.count != views.count ||
                zip(stack.arrangedSubviews, views).contains(where: { pair in pair.0 !== pair.1 }) else { return }
        for previous in stack.views where !views.contains(where: { $0 === previous }) {
            stack.removeView(previous)
        }
        NSLayoutConstraint.deactivate(stack.constraints.filter { $0.identifier == "NeonDocumentCrossAxis" })
        stack.setViews(views, in: .center)
        // NSStackView's alignment constraints have default-low priority. A
        // hosting view's intrinsic height can therefore collapse an entire
        // preview/sidebar to its header. These are viewport regions: the stack
        // owns their cross-axis extent; SwiftUI only supplies their contents.
        let constraints = views.flatMap { view -> [NSLayoutConstraint] in
            if stack.orientation == .horizontal {
                return [view.topAnchor.constraint(equalTo: stack.topAnchor, constant: stack.edgeInsets.top),
                    view.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: -stack.edgeInsets.bottom)]
            }
            return [view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: stack.edgeInsets.left),
                view.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -stack.edgeInsets.right)]
        }
        constraints.forEach { $0.identifier = "NeonDocumentCrossAxis" }
        NSLayoutConstraint.activate(constraints)
    }

    private final class ContentContainer: NSView {
        private var content: NSView?
        private var insets = NSEdgeInsets()
        private var maximumWidth: CGFloat?
        private var overlay: NSView?

        func installOverlay(_ view: NSView?) {
            guard overlay !== view else { return }
            overlay?.removeFromSuperview()
            overlay = view
            if let view { addSubview(view) }
            needsLayout = true
        }

        func install(_ view: NSView, insets: NSEdgeInsets, maximumWidth: CGFloat?) {
            if content !== view {
                content?.removeFromSuperview()
                content = view
                addSubview(view, positioned: .below, relativeTo: overlay)
            }
            self.insets = insets
            self.maximumWidth = maximumWidth
            needsLayout = true
        }

        override func layout() {
            super.layout()
            // Unattached/hidden controllers can legitimately have zero bounds.
            // Insets must never produce a negative native view size.
            let availableWidth = max(0, bounds.width - insets.left - insets.right)
            let width = min(availableWidth, maximumWidth ?? availableWidth)
            content?.frame = NSRect(x: bounds.minX + insets.left + (availableWidth - width) / 2, y: bounds.minY + insets.bottom,
                width: width, height: max(0, bounds.height - insets.top - insets.bottom))
            overlay?.frame = bounds
        }
    }

    private final class OverlayContainer: NSView {
        private let content: NSView
        private var overlay: NSView?
        init(content: NSView) {
            self.content = content
            super.init(frame: .zero)
            addSubview(content)
        }
        required init?(coder: NSCoder) { nil }
        func installOverlay(_ view: NSView?) {
            guard overlay !== view else { return }
            overlay?.removeFromSuperview()
            overlay = view
            if let view { addSubview(view) }
            needsLayout = true
        }
        override func layout() {
            super.layout()
            content.frame = bounds
            if let overlay {
                // Never wider than the editor: a narrower frame lets the bar
                // switch to its scrolling layout instead of overflowing left.
                let size = overlay.fittingSize
                let width = min(size.width, bounds.width)
                overlay.frame = NSRect(x: bounds.maxX - width, y: bounds.maxY - size.height,
                    width: width, height: size.height)
            }
        }
    }

    @MainActor
    final class EditorPaneController: NSViewController {
        private let column = NSStackView()
        private let row = NSStackView()
        private(set) var editorView: VirtualEditorScrollView?
        private var minimap: NSHostingView<AnyView>?
        private var header: NSHostingView<AnyView>?

        override func loadView() {
            column.orientation = .vertical
            column.alignment = .width
            column.spacing = 0
            row.orientation = .horizontal
            row.alignment = .height
            row.spacing = 0
            view = column
        }

        func update(_ configuration: Pane, hostContent: (AnyView) -> AnyView = { $0 }) {
            loadViewIfNeeded()
            let editor: VirtualEditorScrollView
            if let existing = editorView {
                editor = existing
                configuration.editor.updateEditorView(editor)
            } else {
                editor = configuration.editor.makeEditorView()
                editorView = editor
                editor.setContentHuggingPriority(.init(1), for: .horizontal)
                editor.setContentCompressionResistancePriority(.init(1), for: .horizontal)
            }
            if let makeMinimap = configuration.minimap {
                if let minimap { minimap.rootView = hostContent(makeMinimap()) }
                else {
                    let host = NSHostingView(rootView: hostContent(makeMinimap()))
                    host.sceneBridgingOptions = []
                    host.sizingOptions = [.intrinsicContentSize]
                    host.setContentHuggingPriority(.required, for: .horizontal)
                    host.setContentCompressionResistancePriority(.required, for: .horizontal)
                    // The minimap's natural height follows the document (one
                    // line for a short file). It must take the row's height,
                    // never pull the editor row down to its own.
                    host.setContentHuggingPriority(.init(1), for: .vertical)
                    host.setContentCompressionResistancePriority(.init(1), for: .vertical)
                    minimap = host
                }
            } else {
                minimap?.removeFromSuperview()
                minimap = nil
            }
            if let makeHeader = configuration.header {
                if let header { header.rootView = hostContent(makeHeader()) }
                else {
                    let host = NSHostingView(rootView: hostContent(makeHeader()))
                    host.sceneBridgingOptions = []
                    host.sizingOptions = [.intrinsicContentSize]
                    host.setContentHuggingPriority(.required, for: .vertical)
                    header = host
                }
            } else {
                header?.removeFromSuperview()
                header = nil
            }
            Self.installRow(editor: editor, minimap: minimap, row: row)
            row.setContentHuggingPriority(.init(1), for: .vertical)
            row.setContentCompressionResistancePriority(.init(1), for: .vertical)
            MacDocumentContentController.install([header, row].compactMap { $0 }, in: column)
        }

        private static func installRow(editor: NSView, minimap: NSView?, row: NSStackView) {
            MacDocumentContentController.install([editor, minimap].compactMap { $0 }, in: row)
        }
    }
}

/// Window-level layout is AppKit-owned as well. Each region is a separate,
/// stable host; absent inspectors/previews allocate no view graph or renderer.
struct MacDocumentLayout: NSViewControllerRepresentable {
    struct Region {
        let id: String
        let content: () -> AnyView
    }
    var primary: Region
    var source: MacDocumentContentController.Configuration?
    var leadingSidebar: Region?
    var trailingSidebar: Region?
    var leadingPreview: Region?
    var preview: Region?
    var trailingPreview: Region?
    var availablePreviewWidthChanged: (CGFloat) -> Void

    final class Controller: NSViewController {
        private let row = NSStackView()
        private let center = MeasuredStackView()
        private var hosts: [String: NSHostingView<AnyView>] = [:]
        private(set) var sourceController: MacDocumentContentController?

        override func loadView() {
            for stack in [row, center] {
                stack.orientation = .horizontal
                stack.alignment = .height
                stack.spacing = 0
            }
            center.setContentHuggingPriority(.init(1), for: .horizontal)
            center.setContentCompressionResistancePriority(.init(1), for: .horizontal)
            view = row
        }

        func update(_ configuration: MacDocumentLayout) {
            loadViewIfNeeded()
            center.widthChanged = configuration.availablePreviewWidthChanged
            let regions = [configuration.leadingSidebar, configuration.trailingSidebar, configuration.source == nil ? configuration.primary : nil,
                configuration.leadingPreview, configuration.preview, configuration.trailingPreview].compactMap { $0 }
            let identifiers = Set(regions.map(\.id))
            for id in Array(hosts.keys) where !identifiers.contains(id) {
                if let host = hosts.removeValue(forKey: id) {
                    if row.views.contains(where: { $0 === host }) { row.removeView(host) }
                    if center.views.contains(where: { $0 === host }) { center.removeView(host) }
                }
            }
            func host(_ region: Region?) -> NSView? {
                guard let region else { return nil }
                let isPrimary = region.id == configuration.primary.id
                if let host = hosts[region.id] {
                    host.rootView = region.content()
                    return host
                }
                let host = NSHostingView(rootView: region.content())
                host.identifier = .init("NeonDocumentRegion." + region.id)
                host.sceneBridgingOptions = []
                host.sizingOptions = isPrimary ? [] : [.intrinsicContentSize]
                host.setContentHuggingPriority(isPrimary ? .init(1) : .required, for: .horizontal)
                host.setContentCompressionResistancePriority(isPrimary ? .init(1) : .required, for: .horizontal)
                hosts[region.id] = host
                return host
            }
            let primary: NSView?
            if let source = configuration.source {
                let controller = sourceController ?? MacDocumentContentController()
                if sourceController == nil { sourceController = controller; addChild(controller) }
                controller.update(source)
                controller.view.setContentHuggingPriority(.init(1), for: .horizontal)
                controller.view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
                primary = controller.view
            } else {
                primary = host(configuration.primary)
            }
            let before = host(configuration.leadingPreview)
            let preview = host(configuration.preview)
            let after = host(configuration.trailingPreview)
            MacDocumentContentController.install([primary, before, preview, after].compactMap { $0 }, in: center)
            let left = host(configuration.leadingSidebar)
            let right = host(configuration.trailingSidebar)
            MacDocumentContentController.install([left, center, right].compactMap { $0 }, in: row)
        }

        private final class MeasuredStackView: NSStackView {
            var widthChanged: ((CGFloat) -> Void)?
            private var publishedWidth: CGFloat?
            private var publication: Task<Void, Never>?
            override func layout() {
                super.layout()
                guard bounds.width > 0, bounds.width != publishedWidth else { return }
                publishedWidth = bounds.width
                publication?.cancel()
                // SwiftUI state must not be published during native layout.
                publication = Task { @MainActor [weak self] in
                    guard !Task.isCancelled, let self else { return }
                    self.widthChanged?(self.bounds.width)
                    self.publication = nil
                }
            }
        }
    }

    func makeNSViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.update(self)
        return controller
    }
    func updateNSViewController(_ controller: Controller, context: Context) { controller.update(self) }
}
#endif
