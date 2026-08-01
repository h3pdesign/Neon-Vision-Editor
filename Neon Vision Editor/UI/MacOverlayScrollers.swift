import SwiftUI

#if os(macOS)
import AppKit

@MainActor
func applyMacOverlayScrollerStyle(to scrollView: NSScrollView, clearBackground: Bool = false) {
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
    let isDark = scrollView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    scrollView.verticalScroller?.knobStyle = isDark ? .light : .dark
    scrollView.horizontalScroller?.knobStyle = isDark ? .light : .dark
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
                .filter({ $0.frame.contains(origin) })
                .min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
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
        let scrollers = [scrollView.verticalScroller, scrollView.horizontalScroller].compactMap { $0 }
        let needsMiniScroller = scrollers.contains { $0.controlSize != .mini }
        if needsMiniScroller {
            for scroller in scrollers {
                scroller.controlSize = .mini
            }
            scrollView.tile()
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
