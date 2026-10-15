import XCTest
@testable import Neon_Vision_Editor
#if os(macOS)
import AppKit
import SwiftUI
import WebKit
#endif

@MainActor
final class MarkdownPreviewContentUpdateTests: XCTestCase {
    private func html(_ body: String, dark: Bool = false) -> String {
        ContentView().markdownPreviewHTML(bodyHTML: body, template: "default", preferDarkMode: dark,
                                         backgroundStyle: .template, translucentBackgroundEnabled: false)
    }

    func testOnlyCompatibleUnambiguousShellsProduceDataEncodedUpdates() throws {
        let old = html("<p>old</p>")
        let new = html("<p>quotes: \" ' \\ 😀</p>")
        let script = try XCTUnwrap(MarkdownPreviewContentUpdate.script(from: old, to: new))
        XCTAssertTrue(script.contains("DOMParser"))
        XCTAssertTrue(script.contains("isEqualNode"))
        XCTAssertTrue(script.contains("\\\""))
        XCTAssertNil(MarkdownPreviewContentUpdate.script(from: old, to: html("<p>new</p>", dark: true)))
        XCTAssertNil(MarkdownPreviewContentUpdate.script(from: old, to: "<html>legacy</html>"))
        XCTAssertNil(MarkdownPreviewContentUpdate.script(from: old, to: html("<!-- nve-preview-content-start --><p>ambiguous</p>")))
    }

#if os(macOS)
    func testInPlaceUpdateRetainsUnchangedNodesAndInertPageWithoutReload() async throws {
        let old = html("<a id='keep' href='#change'>keep</a><p id='change'>old</p>")
        let new = html("<a id='keep' href='#change'>keep</a><p id='change'>new 😀</p>")
        let coordinator = MarkdownPreviewWebView.Coordinator()
        coordinator.documentID = UUID()
        coordinator.loadedDocumentID = coordinator.documentID
        coordinator.loadedHTML = old
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        web.navigationDelegate = coordinator
        web.configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        web.loadHTMLString(old, baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if coordinator.isLoaded,
               (try? await evaluate("document.querySelector('#change')?.textContent || ''", in: web)) == "old" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await assertScript("document.querySelector('#change')?.textContent || ''", equals: "old", in: web)
        _ = try await evaluate("window.__keep = document.getElementById('keep'); window.__keep.focus(); window.__identity = 'initial'; 'ok'", in: web)
        let reloadsBefore = EditorPerformanceMonitor.shared.previewReloadSnapshot().executed
        coordinator.scheduleReloadPreservingScroll(webView: web, html: html("<p>obsolete</p>"), baseURL: nil)
        coordinator.scheduleReloadPreservingScroll(webView: web, html: new, baseURL: nil)
        try await waitFor("document.querySelector('#change')?.textContent || ''", equals: "new 😀", in: web)
        XCTAssertEqual(coordinator.loadedHTML, new)
        XCTAssertEqual(EditorPerformanceMonitor.shared.previewReloadSnapshot().executed, reloadsBefore)
        try await assertScript("document.getElementById('change').textContent", equals: "new 😀", in: web)
        try await assertScript("String(window.__keep === document.getElementById('keep'))", equals: "true", in: web)
        try await assertScript("String(document.activeElement === window.__keep)", equals: "true", in: web)
        try await assertScript("window.__identity", equals: "initial", in: web)
        let unsafe = html("<script>window.__identity='unsafe'</script><p>unsafe</p>")
        let rejected = try XCTUnwrap(MarkdownPreviewContentUpdate.script(from: new, to: unsafe))
        try await assertScript("String(\(rejected.dropLast()))", equals: "false", in: web)
        try await assertScript("window.__identity", equals: "initial", in: web)
        coordinator.scheduleReloadPreservingScroll(webView: web, html: html("<p id='change'>dark</p>", dark: true), baseURL: nil)
        try await waitFor("document.querySelector('#change')?.textContent || ''", equals: "dark", in: web)
        XCTAssertEqual(EditorPerformanceMonitor.shared.previewReloadSnapshot().executed, reloadsBefore + 1)
        try await assertScript("String(window.__identity)", equals: "undefined", in: web)
        web.stopLoading()
    }

    private func waitFor(_ script: String, equals expected: String, in web: WKWebView) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? await evaluate(script, in: web)) == expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await assertScript(script, equals: expected, in: web)
    }

    private func assertScript(_ script: String, equals expected: String, in web: WKWebView) async throws {
        let result = try await evaluate(script, in: web)
        XCTAssertEqual(result, expected)
    }

    private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value as? String ?? "") }
            }
        }
    }
#endif
}
