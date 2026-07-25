import SwiftUI

#if os(macOS)
import AppKit

@MainActor
func applyMacOverlayScrollerStyle(to scrollView: NSScrollView) {
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
}

@MainActor
func applyMacOverlayScrollerStyle(in view: NSView) {
    if let scrollView = view as? NSScrollView {
        applyMacOverlayScrollerStyle(to: scrollView)
    }
    for subview in view.subviews {
        applyMacOverlayScrollerStyle(in: subview)
    }
}

private struct MacOverlayScrollerProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> MacOverlayScrollerProbeView {
        MacOverlayScrollerProbeView()
    }

    func updateNSView(_ nsView: MacOverlayScrollerProbeView, context: Context) {
        nsView.configureScrollViewsInNearestScope()
    }
}

@MainActor
private final class MacOverlayScrollerProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScrollViewsInNearestScope()
        Task { @MainActor [weak self] in
            self?.configureScrollViewsInNearestScope()
        }
    }

    override func layout() {
        super.layout()
        configureScrollViewsInNearestScope()
    }

    func configureScrollViewsInNearestScope() {
        var candidate = superview
        while let view = candidate {
            if containsScrollView(view) {
                applyMacOverlayScrollerStyle(in: view)
                return
            }
            candidate = view.superview
        }
    }

    private func containsScrollView(_ view: NSView) -> Bool {
        if view is NSScrollView {
            return true
        }
        return view.subviews.contains(where: containsScrollView)
    }
}
#endif

extension View {
    @ViewBuilder
    func macOverlayScrollerStyle() -> some View {
#if os(macOS)
        background(MacOverlayScrollerProbe())
#else
        self
#endif
    }
}
