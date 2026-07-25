import SwiftUI
import WebKit
import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit

@MainActor
final class MacOverlayScrollerTests: XCTestCase {
    func testNativeScrollViewUsesEditorOverlayBehavior() {
        let scrollView = NSScrollView()
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy

        applyMacOverlayScrollerStyle(to: scrollView)

        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
    }

    func testSwiftUIListConfiguresItsNativeScrollViewAsOverlay() async {
        let rootView = List(0..<30) { index in
            Text("Row \(index)")
        }
        .macOverlayScrollerStyle()
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()

        let scrollViews = descendantScrollViews(in: hostingView)
        XCTAssertFalse(scrollViews.isEmpty)
        XCTAssertTrue(scrollViews.allSatisfy(\.autohidesScrollers))
        XCTAssertTrue(scrollViews.allSatisfy { $0.scrollerStyle == .overlay })
    }

    func testPreviewWebViewInstallsScrollActivatedOverlayStyle() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.addUserScript(makeMacPreviewOverlayScrollerUserScript())
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200), configuration: configuration)
        let navigation = NavigationWaiter()
        webView.navigationDelegate = navigation
        webView.loadHTMLString(
            "<html><body>" + String(repeating: "<p>Preview content</p>", count: 100) + "</body></html>",
            baseURL: nil
        )
        await navigation.waitForFinish()

        let hasInjectedStyle = try await webView.evaluateJavaScript(
            "document.getElementById('nve-overlay-scrollbars') !== null"
        ) as? Bool
        XCTAssertEqual(hasInjectedStyle, true)

        let usesInsetThumbWithoutFullWidthColor = try await webView.evaluateJavaScript(
            """
            (() => {
              const css = document.getElementById('nve-overlay-scrollbars')?.textContent ?? '';
              return css.includes('border: 2px solid transparent') && !css.includes('scrollbar-color');
            })()
            """
        ) as? Bool
        XCTAssertEqual(usesInsetThumbWithoutFullWidthColor, true)

        let becomesActive = try await webView.evaluateJavaScript(
            "window.scrollTo(0, 100); window.dispatchEvent(new Event('scroll')); document.documentElement.classList.contains('nve-scroll-active')"
        ) as? Bool
        XCTAssertEqual(becomesActive, true)

        try await Task.sleep(for: .milliseconds(950))
        let becomesHidden = try await webView.evaluateJavaScript(
            "!document.documentElement.classList.contains('nve-scroll-active')"
        ) as? Bool
        XCTAssertEqual(becomesHidden, true)
    }

    private func descendantScrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap(descendantScrollViews)
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didFinish = false

    func waitForFinish() async {
        if didFinish {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish = true
        continuation?.resume()
        continuation = nil
    }
}
#endif
