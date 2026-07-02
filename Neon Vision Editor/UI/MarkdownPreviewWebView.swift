import SwiftUI
import WebKit

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

#if os(macOS)


// MARK: - Types

@MainActor
struct MarkdownPreviewWebView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = makeConfiguredWebView()
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: nil)
        configureMacOverlayScrollers(in: webView)
        DispatchQueue.main.async {
            configureMacOverlayScrollers(in: webView)
        }
        context.coordinator.lastHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        configureMacOverlayScrollers(in: webView)
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.scheduleReloadPreservingScroll(webView: webView, html: html)
        context.coordinator.lastHTML = html
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        private var pendingReload: DispatchWorkItem?
        private var reloadGeneration: Int = 0

        func scheduleReloadPreservingScroll(webView: WKWebView, html: String) {
            pendingReload?.cancel()
            reloadGeneration &+= 1
            let generation = reloadGeneration
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView, self.reloadGeneration == generation else { return }
                self.reloadPreservingScroll(webView: webView, html: html)
                self.pendingReload = nil
            }
            pendingReload = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        func reloadPreservingScroll(webView: WKWebView, html: String) {
            let capture = "(() => { const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight); return window.scrollY / max; })();"
            webView.evaluateJavaScript(capture) { value, _ in
                let ratio = value as? Double ?? 0
                webView.loadHTMLString(html, baseURL: nil)
                let clamped = min(1.0, max(0.0, ratio))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    let restore = "(() => { const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight); window.scrollTo(0, max * \(clamped)); })();"
                    webView.evaluateJavaScript(restore, completionHandler: nil)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               Self.isExternalHTTPURL(url) {
                Task { @MainActor in
                    openExternalPreviewURL(url)
                }
                decisionHandler(.cancel)
                return
            }
            guard navigationAction.navigationType == .other else {
                decisionHandler(.cancel)
                return
            }
            if let scheme = navigationAction.request.url?.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private static func isExternalHTTPURL(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
    }
}
#elseif os(iOS) || os(visionOS)
@MainActor
struct MarkdownPreviewWebView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = makeConfiguredWebView()
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.scheduleReloadPreservingScroll(webView: webView, html: html)
        context.coordinator.lastHTML = html
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        private var pendingReload: DispatchWorkItem?
        private var reloadGeneration: Int = 0

        func scheduleReloadPreservingScroll(webView: WKWebView, html: String) {
            pendingReload?.cancel()
            reloadGeneration &+= 1
            let generation = reloadGeneration
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView, self.reloadGeneration == generation else { return }
                self.reloadPreservingScroll(webView: webView, html: html)
                self.pendingReload = nil
            }
            pendingReload = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        func reloadPreservingScroll(webView: WKWebView, html: String) {
            let capture = "(() => { const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight); return window.scrollY / max; })();"
            webView.evaluateJavaScript(capture) { value, _ in
                let ratio = value as? Double ?? 0
                webView.loadHTMLString(html, baseURL: nil)
                let clamped = min(1.0, max(0.0, ratio))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    let restore = "(() => { const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight); window.scrollTo(0, max * \(clamped)); })();"
                    webView.evaluateJavaScript(restore, completionHandler: nil)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               Self.isExternalHTTPURL(url) {
                Task { @MainActor in
                    openExternalPreviewURL(url)
                }
                decisionHandler(.cancel)
                return
            }
            guard navigationAction.navigationType == .other else {
                decisionHandler(.cancel)
                return
            }
            if let scheme = navigationAction.request.url?.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private static func isExternalHTTPURL(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
    }
}
#endif

@MainActor
private func makeConfiguredWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let webView = WKWebView(frame: .zero, configuration: configuration)
#if os(macOS)
    webView.setValue(false, forKey: "drawsBackground")
    configureMacOverlayScrollers(in: webView)
#else
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.alwaysBounceHorizontal = false
    webView.scrollView.showsHorizontalScrollIndicator = false
#endif
    webView.allowsBackForwardNavigationGestures = false
#if os(iOS) || os(visionOS)
    webView.scrollView.contentInsetAdjustmentBehavior = .never
#endif
    return webView
}

#if os(macOS)
@MainActor
private func configureMacOverlayScrollers(in view: NSView) {
    if let scrollView = view as? NSScrollView {
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
    }
    for subview in view.subviews {
        configureMacOverlayScrollers(in: subview)
    }
}
#endif

@MainActor
private func openExternalPreviewURL(_ url: URL) {
#if os(macOS)
    NSWorkspace.shared.open(url)
#elseif os(iOS) || os(visionOS)
    UIApplication.shared.open(url)
#endif
}
