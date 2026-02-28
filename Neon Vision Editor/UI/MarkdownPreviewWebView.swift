import SwiftUI
import WebKit

#if os(macOS)
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
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastHTML = html
    }

    final class Coordinator {
        var lastHTML: String = ""
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
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastHTML = html
    }

    final class Coordinator {
        var lastHTML: String = ""
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
