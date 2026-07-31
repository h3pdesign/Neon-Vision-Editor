import SwiftUI

#if os(macOS)
import AppKit

@MainActor
func applyMacOverlayScrollerStyle(to scrollView: NSScrollView) {
    if !scrollView.autohidesScrollers {
        scrollView.autohidesScrollers = true
    }
    if scrollView.scrollerStyle != .overlay {
        scrollView.scrollerStyle = .overlay
    }
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

private struct MacOverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> MacOverlayScrollerConfiguratorView {
        MacOverlayScrollerConfiguratorView()
    }

    func updateNSView(_ nsView: MacOverlayScrollerConfiguratorView, context: Context) {
        nsView.configureNearestScrollView()
        nsView.scheduleConfiguration()
    }
}

@MainActor
private final class MacOverlayScrollerConfiguratorView: NSView {
    private weak var configuredScrollView: NSScrollView?
    private var fadeTask: Task<Void, Never>?

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
        guard let enclosingScrollView else { return }
        configure(enclosingScrollView)
    }

    private func configure(_ scrollView: NSScrollView) {
        applyMacOverlayScrollerStyle(to: scrollView)
        if scrollView.verticalScroller?.controlSize != .small {
            scrollView.verticalScroller?.controlSize = .small
            scrollView.tile()
        }
        guard configuredScrollView !== scrollView else { return }

        if let configuredScrollView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: configuredScrollView.contentView
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSScrollView.didEndLiveScrollNotification,
                object: configuredScrollView
            )
        }
        fadeTask?.cancel()
        configuredScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.verticalScroller?.isHidden = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollDidEnd),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
        )
    }

    @objc private func contentBoundsDidChange(_ notification: Notification) {
        showScrollerTemporarily()
    }

    @objc private func scrollDidEnd(_ notification: Notification) {
        showScrollerTemporarily()
    }

    private func showScrollerTemporarily() {
        guard let scroller = configuredScrollView?.verticalScroller else { return }
        if let fadeTask, !fadeTask.isCancelled {
            return
        }
        fadeTask?.cancel()
        scroller.alphaValue = 1
        scroller.isHidden = false
        fadeTask = Task { @MainActor [weak self, weak scroller] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, self != nil, let scroller else { return }
            // Keep the delayed hide deterministic. AppKit's animator can leave
            // the presentation value at 1 while a test or a rapid scroll is
            // still draining the main run loop.
            scroller.alphaValue = 0
            scroller.isHidden = true
            self?.fadeTask = nil
        }
    }

}

#endif

extension View {
    @ViewBuilder
    func macOverlayScrollerStyle(_ isEnabled: Bool = true) -> some View {
#if os(macOS)
        if isEnabled {
            background(MacOverlayScrollerConfigurator())
        } else {
            self
        }
#else
        self
#endif
    }
}
