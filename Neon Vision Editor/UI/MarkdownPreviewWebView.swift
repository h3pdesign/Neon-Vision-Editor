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
    var baseURL: URL?
    var allowsContentJavaScript: Bool = false
    var documentID: UUID?
    var synchronizedScrollFraction: CGFloat? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = makeConfiguredWebView(allowsContentJavaScript: allowsContentJavaScript, scrollMessageHandler: context.coordinator)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: baseURL)
        applyMacOverlayScrollerStyle(in: webView)
        DispatchQueue.main.async {
            applyMacOverlayScrollerStyle(in: webView)
        }
        context.coordinator.lastHTML = html
        context.coordinator.lastBaseURL = baseURL
        context.coordinator.documentID = documentID
        context.coordinator.updateSynchronizedScroll(webView: webView, fraction: synchronizedScrollFraction)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        applyMacOverlayScrollerStyle(in: webView)
        context.coordinator.documentID = documentID
        context.coordinator.updateSynchronizedScroll(webView: webView, fraction: synchronizedScrollFraction)
        guard context.coordinator.lastHTML != html || context.coordinator.lastBaseURL != baseURL else { return }
        context.coordinator.scheduleReloadPreservingScroll(webView: webView, html: html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        context.coordinator.lastBaseURL = baseURL
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String = ""
        var lastBaseURL: URL?
        private var pendingReload: DispatchWorkItem?
        private var reloadGeneration: Int = 0
        private let reloadCoalescingDelay: TimeInterval = 0.06
        private var pendingSynchronizedScrollFraction: CGFloat?
        private var lastAppliedSynchronizedScrollFraction: CGFloat?

        func updateSynchronizedScroll(webView: WKWebView, fraction: CGFloat?) {
            pendingSynchronizedScrollFraction = fraction.map { min(max($0, 0), 1) }
            guard let fraction = pendingSynchronizedScrollFraction,
                  lastAppliedSynchronizedScrollFraction.map({ abs($0 - fraction) > 0.001 }) ?? true else { return }
            let script = "(() => { const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight); window.__nveApplyingSynchronizedScroll = true; window.scrollTo({ top: max * \(fraction), left: 0, behavior: 'auto' }); requestAnimationFrame(() => { window.__nveApplyingSynchronizedScroll = false; }); })();"
            webView.evaluateJavaScript(script, completionHandler: nil)
            lastAppliedSynchronizedScrollFraction = fraction
        }

        var documentID: UUID?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.scrollMessageName,
                  let payload = message.body as? [String: Any],
                  let fraction = payload["fraction"] as? Double,
                  let documentID else { return }
            NotificationCenter.default.post(
                name: .markdownPreviewViewportDidChange,
                object: nil,
                userInfo: [
                    EditorCommandUserInfo.documentID: documentID.uuidString,
                    EditorCommandUserInfo.viewportTopFraction: min(max(fraction, 0), 1)
                ]
            )
        }

        private static let scrollMessageName = "nvePreviewScroll"

        func scheduleReloadPreservingScroll(webView: WKWebView, html: String, baseURL: URL?) {
            pendingReload?.cancel()
            reloadGeneration &+= 1
            let generation = reloadGeneration
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView, self.reloadGeneration == generation else { return }
                self.reloadPreservingScroll(webView: webView, html: html, baseURL: baseURL, generation: generation)
                self.pendingReload = nil
            }
            pendingReload = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + reloadCoalescingDelay, execute: workItem)
        }

        func reloadPreservingScroll(webView: WKWebView, html: String, baseURL: URL?, generation: Int) {
            let capture = "(() => { const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight); return window.scrollY / max; })();"
            webView.evaluateJavaScript(capture) { [weak self, weak webView] value, _ in
                guard let self, let webView, self.reloadGeneration == generation else { return }
                let ratio = value as? Double ?? 0
                webView.loadHTMLString(html, baseURL: baseURL)
                let clamped = min(1.0, max(0.0, ratio))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self, weak webView] in
                    guard let self, let webView, self.reloadGeneration == generation else { return }
                    let restore = "(() => { const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight); window.__nveApplyingSynchronizedScroll = true; window.scrollTo({ top: max * \(clamped), left: 0, behavior: 'auto' }); requestAnimationFrame(() => { window.__nveApplyingSynchronizedScroll = false; }); })();"
                    webView.evaluateJavaScript(restore, completionHandler: nil)
                    self.lastAppliedSynchronizedScrollFraction = nil
                    self.updateSynchronizedScroll(webView: webView, fraction: self.pendingSynchronizedScrollFraction)
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyMacOverlayScrollerStyle(in: webView)
            lastAppliedSynchronizedScrollFraction = nil
            updateSynchronizedScroll(webView: webView, fraction: pendingSynchronizedScrollFraction)
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
    var baseURL: URL?
    var allowsContentJavaScript: Bool = false
    var documentID: UUID?
    var synchronizedScrollFraction: CGFloat? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = makeConfiguredWebView(allowsContentJavaScript: allowsContentJavaScript, scrollMessageHandler: context.coordinator)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        context.coordinator.lastBaseURL = baseURL
        context.coordinator.documentID = documentID
        context.coordinator.updateSynchronizedScroll(webView: webView, fraction: synchronizedScrollFraction)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.documentID = documentID
        context.coordinator.updateSynchronizedScroll(webView: webView, fraction: synchronizedScrollFraction)
        guard context.coordinator.lastHTML != html || context.coordinator.lastBaseURL != baseURL else { return }
        context.coordinator.scheduleReloadPreservingScroll(webView: webView, html: html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        context.coordinator.lastBaseURL = baseURL
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String = ""
        var lastBaseURL: URL?
        private var pendingReload: DispatchWorkItem?
        private var reloadGeneration: Int = 0
        private let reloadCoalescingDelay: TimeInterval = 0.06
        private var pendingSynchronizedScrollFraction: CGFloat?
        private var lastAppliedSynchronizedScrollFraction: CGFloat?

        func updateSynchronizedScroll(webView: WKWebView, fraction: CGFloat?) {
            pendingSynchronizedScrollFraction = fraction.map { min(max($0, 0), 1) }
            guard let fraction = pendingSynchronizedScrollFraction,
                  lastAppliedSynchronizedScrollFraction.map({ abs($0 - fraction) > 0.001 }) ?? true else { return }
            let script = "(() => { const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight); window.__nveApplyingSynchronizedScroll = true; window.scrollTo({ top: max * \(fraction), left: 0, behavior: 'auto' }); requestAnimationFrame(() => { window.__nveApplyingSynchronizedScroll = false; }); })();"
            webView.evaluateJavaScript(script, completionHandler: nil)
            lastAppliedSynchronizedScrollFraction = fraction
        }

        var documentID: UUID?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.scrollMessageName,
                  let payload = message.body as? [String: Any],
                  let fraction = payload["fraction"] as? Double,
                  let documentID else { return }
            NotificationCenter.default.post(
                name: .markdownPreviewViewportDidChange,
                object: nil,
                userInfo: [
                    EditorCommandUserInfo.documentID: documentID.uuidString,
                    EditorCommandUserInfo.viewportTopFraction: min(max(fraction, 0), 1)
                ]
            )
        }

        private static let scrollMessageName = "nvePreviewScroll"

        func scheduleReloadPreservingScroll(webView: WKWebView, html: String, baseURL: URL?) {
            pendingReload?.cancel()
            reloadGeneration &+= 1
            let generation = reloadGeneration
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView, self.reloadGeneration == generation else { return }
                self.reloadPreservingScroll(webView: webView, html: html, baseURL: baseURL, generation: generation)
                self.pendingReload = nil
            }
            pendingReload = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + reloadCoalescingDelay, execute: workItem)
        }

        func reloadPreservingScroll(webView: WKWebView, html: String, baseURL: URL?, generation: Int) {
            let capture = "(() => { const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight); return window.scrollY / max; })();"
            webView.evaluateJavaScript(capture) { [weak self, weak webView] value, _ in
                guard let self, let webView, self.reloadGeneration == generation else { return }
                let ratio = value as? Double ?? 0
                webView.loadHTMLString(html, baseURL: baseURL)
                let clamped = min(1.0, max(0.0, ratio))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self, weak webView] in
                    guard let self, let webView, self.reloadGeneration == generation else { return }
                    let restore = "(() => { const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight); window.__nveApplyingSynchronizedScroll = true; window.scrollTo({ top: max * \(clamped), left: 0, behavior: 'auto' }); requestAnimationFrame(() => { window.__nveApplyingSynchronizedScroll = false; }); })();"
                    webView.evaluateJavaScript(restore, completionHandler: nil)
                    self.lastAppliedSynchronizedScrollFraction = nil
                    self.updateSynchronizedScroll(webView: webView, fraction: self.pendingSynchronizedScrollFraction)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastAppliedSynchronizedScrollFraction = nil
            updateSynchronizedScroll(webView: webView, fraction: pendingSynchronizedScrollFraction)
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
private func makeConfiguredWebView(
    allowsContentJavaScript: Bool,
    scrollMessageHandler: WKScriptMessageHandler? = nil
) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = allowsContentJavaScript
    if let scrollMessageHandler {
        configuration.userContentController.add(scrollMessageHandler, name: "nvePreviewScroll")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                (() => {
                  let lastFraction = -1;
                  let postScroll = () => {
                    const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                    const fraction = Math.min(1, Math.max(0, window.scrollY / max));
                    if (window.__nveApplyingSynchronizedScroll) {
                      lastFraction = fraction;
                      return;
                    }
                    if (Math.abs(fraction - lastFraction) > 0.002) {
                      lastFraction = fraction;
                      window.webkit.messageHandlers.nvePreviewScroll.postMessage({ fraction });
                    }
                  };
                  window.addEventListener('scroll', postScroll, { passive: true });
                  window.addEventListener('load', postScroll, { once: true });
                })();
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
    }
#if os(macOS)
    configuration.userContentController.addUserScript(makeMacPreviewOverlayScrollerUserScript())
#endif
    let webView = WKWebView(frame: .zero, configuration: configuration)
#if os(macOS)
    webView.setValue(false, forKey: "drawsBackground")
    applyMacOverlayScrollerStyle(in: webView)
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
func makeMacPreviewOverlayScrollerUserScript() -> WKUserScript {
    WKUserScript(
        source: """
        (() => {
          const styleID = 'nve-overlay-scrollbars';
          if (!document.getElementById(styleID)) {
            const style = document.createElement('style');
            style.id = styleID;
            style.textContent = `
              *::-webkit-scrollbar {
                width: 10px;
                height: 10px;
              }
              *::-webkit-scrollbar-track,
              *::-webkit-scrollbar-corner {
                background: transparent;
              }
              *::-webkit-scrollbar-thumb {
                background-color: transparent;
                background-clip: padding-box;
                border: 2px solid transparent;
                border-radius: 999px;
              }
              html.nve-scroll-active *::-webkit-scrollbar-thumb,
              html.nve-scroll-active::-webkit-scrollbar-thumb {
                background-color: rgba(128, 128, 128, 0.72);
              }
            `;
            (document.head || document.documentElement).appendChild(style);
          }

          let hideTask;
          const showOverlayScroller = () => {
            document.documentElement.classList.add('nve-scroll-active');
            clearTimeout(hideTask);
            hideTask = setTimeout(() => {
              document.documentElement.classList.remove('nve-scroll-active');
            }, 850);
          };
          window.addEventListener('scroll', showOverlayScroller, { capture: true, passive: true });
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )
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
