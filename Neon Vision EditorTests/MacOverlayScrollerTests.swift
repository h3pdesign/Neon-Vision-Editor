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

    func testOverlayConfigurationIsIdempotent() {
        let scrollView = ScrollerStyleTrackingScrollView()
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.scrollerStyleSetCount = 0

        applyMacOverlayScrollerStyle(to: scrollView)
        applyMacOverlayScrollerStyle(to: scrollView)

        XCTAssertEqual(scrollView.scrollerStyleSetCount, 1)
    }

    func testSwiftUIListConfiguresOnlyItsEnclosingScrollView() async {
        let rootView = List {
            ForEach(0..<30) { index in
                Text("Row \(index)")
                    .macOverlayScrollerStyle(index == 0)
            }
        }
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
        XCTAssertEqual(scrollViews.count, 1)
        XCTAssertTrue(scrollViews[0].autohidesScrollers)
        XCTAssertEqual(scrollViews[0].scrollerStyle, .overlay)
        XCTAssertEqual(scrollViews[0].verticalScroller?.controlSize, .mini)
    }

    func testDirectListModifierConfiguresItsScrollView() async {
        let rootView = List {
            ForEach(0..<30) { index in
                Text("Row \(index)")
            }
        }
        .macOverlayScrollerStyle()
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()

        let scrollViews = descendantScrollViews(in: hostingView)
        XCTAssertEqual(scrollViews.count, 1)
        XCTAssertTrue(scrollViews[0].autohidesScrollers)
        XCTAssertEqual(scrollViews[0].scrollerStyle, .overlay)
    }

    func testDirectScrollViewModifierConfiguresItsScrollView() async {
        let rootView = ScrollView {
            LazyVStack {
                ForEach(0..<30) { index in
                    Text("Row \(index)")
                }
            }
        }
        .macOverlayScrollerStyle()
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()

        let scrollViews = descendantScrollViews(in: hostingView)
        XCTAssertEqual(scrollViews.count, 1)
        XCTAssertTrue(scrollViews[0].autohidesScrollers)
        XCTAssertEqual(scrollViews[0].scrollerStyle, .overlay)
    }

    func testGitChangesEditorConfiguresItsListScroller() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NVE-GitScroller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "initial\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(in: root, arguments: ["init"])
        runGit(in: root, arguments: ["config", "user.email", "test@example.com"])
        runGit(in: root, arguments: ["config", "user.name", "NVE Tests"])
        runGit(in: root, arguments: ["add", "README.md"])
        runGit(in: root, arguments: ["commit", "-m", "Initial"])
        try "changed\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let model = GitViewModel()
        model.setProjectURL(root)
        for _ in 0..<50 where model.entries.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(model.entries.isEmpty)

        let hostingView = NSHostingView(rootView: GitChangesEditorView(gitViewModel: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()

        let scrollViews = descendantScrollViews(in: hostingView)
        XCTAssertFalse(scrollViews.isEmpty)
        let descriptions = scrollViews.map {
            "style=\($0.scrollerStyle.rawValue), autohide=\($0.autohidesScrollers), vertical=\($0.verticalScroller != nil)"
        }.joined(separator: " | ")
        XCTAssertTrue(
            scrollViews.contains { $0.scrollerStyle == .overlay && $0.autohidesScrollers },
            "Git scroll views: \(descriptions)"
        )
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

    private func runGit(in directory: URL, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/git")
        process.currentDirectoryURL = directory
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
    }
}

private final class ScrollerStyleTrackingScrollView: NSScrollView {
    var scrollerStyleSetCount = 0

    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set {
            scrollerStyleSetCount += 1
            super.scrollerStyle = newValue
        }
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
