import SwiftUI
import WebKit

#if os(macOS)


/// MARK: - Types

struct MarkdownPreviewWebView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = makeConfiguredWebView()
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.reloadPreservingScroll(webView: webView, html: html)
        context.coordinator.lastHTML = html
    }

    final class Coordinator {
        var lastHTML: String = ""

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
    }
}
#elseif os(iOS)
struct MarkdownPreviewWebView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = makeConfiguredWebView()
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.reloadPreservingScroll(webView: webView, html: html)
        context.coordinator.lastHTML = html
    }

    final class Coordinator {
        var lastHTML: String = ""

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
    }
}
#endif

private func makeConfiguredWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let webView = WKWebView(frame: .zero, configuration: configuration)
#if os(macOS)
    webView.setValue(false, forKey: "drawsBackground")
#else
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
#endif
    webView.allowsBackForwardNavigationGestures = false
#if os(iOS)
    webView.scrollView.contentInsetAdjustmentBehavior = .never
#endif
    return webView
}
