import SwiftUI

#if os(macOS)
import AppKit

@MainActor
enum MacOverlayScrollerPolicy {
    static let idleHideDelay: Duration = .milliseconds(850)
    static let controlSize: NSControl.ControlSize = .mini

    static func configure(_ scrollView: NSScrollView, clearBackground: Bool = false) {
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if clearBackground {
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.contentView.drawsBackground = false
        }
        for scroller in [scrollView.verticalScroller, scrollView.horizontalScroller].compactMap({ $0 }) {
            if scroller.controlSize != controlSize {
                scroller.controlSize = controlSize
            }
        }
    }
}

@MainActor
func applyMacOverlayScrollerStyle(to scrollView: NSScrollView, clearBackground: Bool = false) {
    MacOverlayScrollerPolicy.configure(scrollView, clearBackground: clearBackground)
}

@MainActor
func applyMacOverlayScrollerStyle(in view: NSView, clearBackground: Bool = false) {
    if let scrollView = view as? NSScrollView {
        applyMacOverlayScrollerStyle(to: scrollView, clearBackground: clearBackground)
    }
    for subview in view.subviews {
        applyMacOverlayScrollerStyle(in: subview, clearBackground: clearBackground)
    }
}


private struct MacOverlayScrollerConfigurator: NSViewRepresentable {
    let clearBackground: Bool

    func makeNSView(context: Context) -> MacOverlayScrollerConfiguratorView {
        MacOverlayScrollerConfiguratorView(clearBackground: clearBackground)
    }

    func updateNSView(_ nsView: MacOverlayScrollerConfiguratorView, context: Context) {
        nsView.clearBackground = clearBackground
        nsView.configureNearestScrollView()
        nsView.scheduleConfiguration()
    }
}

@MainActor
private final class MacOverlayScrollerConfiguratorView: NSView {
    var clearBackground: Bool
    private weak var configuredScrollView: NSScrollView?
    private var hideTask: Task<Void, Never>?
    private var isLiveScrolling = false

    init(clearBackground: Bool) {
        self.clearBackground = clearBackground
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        clearBackground = false
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureNearestScrollView()
        scheduleConfiguration()
    }


    func scheduleConfiguration() {
        DispatchQueue.main.async { [weak self] in
            self?.configureNearestScrollView()
        }
    }

    func configureNearestScrollView() {
        if let enclosingScrollView {
            configure(enclosingScrollView)
            return
        }

        // SwiftUI places a background representable outside the platform
        // scroll view for modifiers applied directly to List/ScrollView. In
        // that case `enclosingScrollView` is nil even though the scroll view
        // is a sibling descendant of the hosting container. Select the
        // smallest descendant containing this configurator so nested or
        // adjacent scroll views are not configured accidentally.
        var ancestor = superview
        while let current = ancestor {
            let candidates = descendantScrollViews(in: current).filter { $0 !== self }
            let boundsInAncestor = convert(bounds, to: current)
            let origin = CGPoint(x: boundsInAncestor.midX, y: boundsInAncestor.midY)
            if let scrollView = candidates
                .filter({ $0.convert($0.bounds, to: current).contains(origin) })
                .min(by: {
                    let lhs = $0.convert($0.bounds, to: current)
                    let rhs = $1.convert($1.bounds, to: current)
                    return lhs.width * lhs.height < rhs.width * rhs.height
                }) {
                configure(scrollView)
                return
            }
            ancestor = current.superview
        }
    }

    private func descendantScrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap(descendantScrollViews(in:))
    }

    private func configure(_ scrollView: NSScrollView) {
        applyMacOverlayScrollerStyle(to: scrollView, clearBackground: clearBackground)
        if configuredScrollView !== scrollView {
            if let configuredScrollView {
                NotificationCenter.default.removeObserver(self, name: nil, object: configuredScrollView)
            }
            configuredScrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(liveScrollWillStart),
                name: NSScrollView.willStartLiveScrollNotification,
                object: scrollView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollDidEnd),
                name: NSScrollView.didEndLiveScrollNotification,
                object: scrollView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }
        scrollView.tile()
        // AppKit may recreate/reveal the scrollers while tiling. Apply the
        // idle state after tiling so the native scroller cannot remain painted
        // merely because the system's "Always show scroll bars" preference is
        // enabled.
        hideScrollersImmediately(in: scrollView)
    }

    @objc private func liveScrollWillStart() {
        guard let configuredScrollView else { return }
        isLiveScrolling = true
        showScrollers(in: configuredScrollView)
    }

    @objc private func scrollDidEnd() {
        isLiveScrolling = false
        guard let configuredScrollView else { return }
        hideScrollersImmediately(in: configuredScrollView)
    }

    @objc private func contentBoundsDidChange() {
        guard !isLiveScrolling, let configuredScrollView else { return }
        // SwiftUI/AppKit may repaint or recreate the native scroller during
        // idle layout. Bounds changes are not scrolling signals; they only
        // re-assert the idle-hidden state after that repaint.
        hideScrollersImmediately(in: configuredScrollView)
    }

    private func showScrollers(in scrollView: NSScrollView) {
        hideTask?.cancel()
        for scroller in [scrollView.verticalScroller, scrollView.horizontalScroller].compactMap({ $0 }) {
            scroller.isHidden = false
            scroller.alphaValue = 1
        }
        scheduleHide()
    }

    private func hideScrollersImmediately(in scrollView: NSScrollView) {
        hideTask?.cancel()
        for scroller in [scrollView.verticalScroller, scrollView.horizontalScroller].compactMap({ $0 }) {
            scroller.alphaValue = 0
            scroller.isHidden = true
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: MacOverlayScrollerPolicy.idleHideDelay)
            guard !Task.isCancelled, let self, let scrollView = self.configuredScrollView else { return }
            self.hideScrollersImmediately(in: scrollView)
        }
    }

}

#endif

extension View {
    @ViewBuilder
    func macOverlayScrollerStyle(_ isEnabled: Bool = true, transparentBackground: Bool = false) -> some View {
#if os(macOS)
        if isEnabled {
            background(MacOverlayScrollerConfigurator(clearBackground: transparentBackground))
        } else {
            self
        }
#else
        self
#endif
    }
}
