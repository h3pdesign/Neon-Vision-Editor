#if os(macOS)
import AppKit
import CoreText
import SwiftUI
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class VirtualEditorPerformanceTests: XCTestCase {
    private let lineCount = 100_000
    private let viewportByteCount = 64 * 1024

    func testLargeDocumentTypingLatencyBenchmark() throws {
        let document = FileBackedTextDocument(content: largeDocumentText())
        let location = document.utf16Length / 2
        var replacement = "X"
        var samples: [TimeInterval] = []

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: benchmarkOptions()) {
            let started = ProcessInfo.processInfo.systemUptime
            for _ in 0..<100 {
                try! document.replace(utf16Range: NSRange(location: location, length: 1), with: replacement)
                replacement = replacement == "X" ? "Y" : "X"
            }
            samples.append(ProcessInfo.processInfo.systemUptime - started)
        }
        try assertMedianLatency(samples, budget: "typing")
    }

    func testLargeDocumentScrollingLatencyBenchmark() throws {
        let document = FileBackedTextDocument(content: largeDocumentText())
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let anchors = stride(from: 0, to: lineCount, by: 2_500).map { $0 }
        var renderedFragmentCount = 0
        var samples: [TimeInterval] = []

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: benchmarkOptions()) {
            let started = ProcessInfo.processInfo.systemUptime
            var count = 0
            for anchor in anchors {
                let viewport = try! document.viewport(aroundLine: anchor, maximumByteCount: viewportByteCount)
                let attributed = NSAttributedString(string: viewport.text, attributes: [.font: font])
                count += VirtualEditorVisualLayout.fragments(
                    for: attributed,
                    lineStartUTF16: 0,
                    width: 720,
                    wraps: true
                ).count
            }
            renderedFragmentCount = count
            samples.append(ProcessInfo.processInfo.systemUptime - started)
        }

        XCTAssertGreaterThan(renderedFragmentCount, 0)
        try assertMedianLatency(samples, budget: "scrolling")
    }

    func testLargeDocumentSelectionLatencyBenchmark() throws {
        let document = FileBackedTextDocument(content: largeDocumentText())
        let viewport = try document.viewport(aroundLine: lineCount / 2, maximumByteCount: viewportByteCount)
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attributed = NSAttributedString(string: viewport.text, attributes: [.font: font])
        let fragments = VirtualEditorVisualLayout.fragments(
            for: attributed,
            lineStartUTF16: 0,
            width: 720,
            wraps: true
        )
        let selectedStart = viewport.text.utf16.count / 4
        let selectedEnd = selectedStart + viewport.text.utf16.count / 2
        var measuredWidth: CGFloat = 0
        var samples: [TimeInterval] = []

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: benchmarkOptions()) {
            let started = ProcessInfo.processInfo.systemUptime
            var width: CGFloat = 0
            for _ in 0..<100 {
                for fragment in fragments {
                    let fragmentStart = fragment.absoluteStartUTF16
                    let fragmentEnd = fragmentStart + fragment.lengthUTF16
                    let left = max(fragmentStart, selectedStart)
                    let right = min(fragmentEnd, selectedEnd)
                    guard left < right else { continue }
                    let leftX = CTLineGetOffsetForStringIndex(fragment.line, left, nil)
                    let rightX = CTLineGetOffsetForStringIndex(fragment.line, right, nil)
                    width += CGFloat(max(0, rightX - leftX))
                }
            }
            measuredWidth = width
            samples.append(ProcessInfo.processInfo.systemUptime - started)
        }

        XCTAssertGreaterThan(measuredWidth, 0)
        try assertMedianLatency(samples, budget: "selection")
    }

    func testLargeDocumentViewportReloadLatencyBenchmark() throws {
        let document = FileBackedTextDocument(content: largeDocumentText())
        let anchors = stride(from: 0, to: lineCount, by: 1_000).map { $0 }
        var loadedUTF16Length = 0
        var samples: [TimeInterval] = []

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: benchmarkOptions()) {
            let started = ProcessInfo.processInfo.systemUptime
            var length = 0
            for anchor in anchors {
                length += try! document.viewport(
                    aroundLine: anchor,
                    maximumByteCount: viewportByteCount
                ).text.utf16.count
            }
            loadedUTF16Length = length
            samples.append(ProcessInfo.processInfo.systemUptime - started)
        }

        XCTAssertGreaterThan(loadedUTF16Length, 0)
        try assertMedianLatency(samples, budget: "viewportReload")
    }

    func testCanvasScrollDrawAndHitTestingBenchmark() throws {
        let document = FileBackedTextDocument(content: largeDocumentText())
        let scrollView = VirtualEditorScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.configure(
            document: document, documentID: UUID(), resourceID: "renderer-benchmark",
            displayName: "Benchmark.swift", contentRevision: 0, externalContentRevision: 0,
            caret: 0, language: "swift", colorScheme: .light, fontSize: 14,
            fontName: "", lineHeightMultiplier: 1, isReadOnly: false,
            translucentBackgroundEnabled: false, showsLineNumbers: true,
            highlightCurrentLine: false, lineWrapEnabled: true,
            showsInvisibleCharacters: false, showsIndentationGuides: false,
            showsScopeGuides: false, highlightsScopeBackground: false,
            highlightsMatchingBrackets: false, autoIndentEnabled: true,
            autoCloseBracketsEnabled: false, isSplitPaneResizeInProgress: false,
            onFontSizeChange: nil, onTextMutation: nil
        )
        let canvas = try XCTUnwrap(scrollView.documentView as? VirtualEditorCanvas)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        var hitOffset = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: benchmarkOptions()) {
            for y in stride(from: CGFloat(0), through: 12_000, by: 300) {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.updateForVisibleBoundsChange()
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                canvas.draw(scrollView.contentView.bounds)
                NSGraphicsContext.restoreGraphicsState()
                hitOffset = canvas.characterIndex(for: NSPoint(x: 120, y: y + 300))
            }
        }
        XCTAssertGreaterThan(hitOffset, 0)
    }

    func testTabSwitchActivationBenchmarkRecordsRealSwiftUIViewportAndDraw() async throws {
        let sources = [String(repeating: "# Heading\n**Markdown** é😀\n", count: 50_000),
                       largeDocumentText(), "{\"value\":\"" + String(repeating: "é😀", count: 150_000) + "\"}"]
        let documents = sources.map { FileBackedTextDocument(content: $0) }
        let ids = documents.map { _ in UUID() }
        let languages = ["markdown", "swift", "json"]
        let host = NSHostingView(rootView: editor(FileBackedTextDocument(content: ""), id: UUID(), language: "plain"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        var cold: [Int] = []
        var warm: [Int] = []
        for round in 0..<4 {
            for index in [1, 2, 0] {
                let prior = EditorPerformanceMonitor.shared.recentTabSwitchEvents().last?.id
                EditorPerformanceMonitor.shared.beginTabSwitch(tabID: ids[index])
                host.rootView = editor(documents[index], id: ids[index], language: languages[index])
                let deadline = Date().addingTimeInterval(5)
                var received: EditorPerformanceMonitor.TabSwitchEvent?
                while Date() < deadline {
                    host.layoutSubtreeIfNeeded()
                    host.displayIfNeeded()
                    let event = EditorPerformanceMonitor.shared.recentTabSwitchEvents().last
                    if let event, event.id != prior { received = event; break }
                    try await Task.sleep(for: .milliseconds(1))
                }
                let event = try XCTUnwrap(received, "Actual drawing must complete the monitor event")
                XCTAssertNotNil(event.swiftUIUpdateMilliseconds)
                XCTAssertNotNil(event.viewportMilliseconds)
                print("native-tab-switch stage round=\(round) language=\(languages[index]) ui_ms=\(event.swiftUIUpdateMilliseconds ?? -1) viewport_ms=\(event.viewportMilliseconds ?? -1) draw_ms=\(event.elapsedMilliseconds) active=\(NSApp.isActive) key=\(window.isKeyWindow) visible=\(window.occlusionState.contains(.visible))")
                if round == 0 { cold.append(event.elapsedMilliseconds) }
                else { warm.append(event.elapsedMilliseconds) }
            }
        }
        let sorted = warm.sorted()
        print("native-tab-switch cold_ms=\(cold) warm_median_ms=\(sorted[sorted.count / 2]) warm_p95_ms=\(sorted.last!)")
        XCTAssertLessThan(sorted[sorted.count / 2], 100, "Warm SwiftUI-to-first-draw regression budget")
        XCTAssertLessThan(sorted.last!, 250, "Warm tail latency regression budget")
    }

    func testRapidActivationTypingAndRevisionChangesNeverInstallStaleViewport() async throws {
        let first = FileBackedTextDocument(content: "first document\n")
        let second = FileBackedTextDocument(content: "second document\n")
        let ids = [UUID(), UUID()]
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(CGSize(width: 800, height: 600))
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        window.orderFront(nil)
        defer { window.close() }
        func configure(_ document: FileBackedTextDocument, id: UUID, revision: Int = 0, fontSize: CGFloat = 14) {
            canvas.configure(document: document, documentID: id, resourceID: id.uuidString, displayName: "test.txt",
                             contentRevision: revision, externalContentRevision: 0, caret: 0, language: "plain",
                             colorScheme: .dark, fontSize: fontSize, fontName: "", lineHeightMultiplier: 1,
                             isReadOnly: false, translucentBackgroundEnabled: false, showsLineNumbers: true,
                             highlightCurrentLine: false, lineWrapEnabled: true, showsInvisibleCharacters: false,
                             showsIndentationGuides: false, showsScopeGuides: false, highlightsScopeBackground: false,
                             highlightsMatchingBrackets: false, autoIndentEnabled: true, autoCloseBracketsEnabled: false,
                             onFontSizeChange: nil, onTextMutation: { mutation in
                do {
                    if let viewport = mutation.viewport {
                        try document.replace(in: viewport, utf16Range: mutation.range, with: mutation.replacement)
                    } else {
                        try document.replace(utf16Range: mutation.range, with: mutation.replacement)
                    }
                    return true
                }
                catch { return false }
            })
        }
        configure(first, id: ids[0])
        configure(second, id: ids[1])
        XCTAssertTrue(canvas.isViewportActivationPending)
        canvas.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(second.string(), "Xsecond document\n")
        XCTAssertEqual(first.string(), "first document\n")
        configure(second, id: ids[1], revision: 1)
        configure(first, id: ids[0])
        configure(second, id: ids[1], revision: 1)
        let deadline = Date().addingTimeInterval(3)
        while canvas.isViewportActivationPending && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertFalse(canvas.isViewportActivationPending)
        XCTAssertTrue(canvas.installedViewportTextForTesting.hasPrefix("Xsecond"))
        configure(first, id: ids[0])
        configure(second, id: ids[1], revision: 1)
        XCTAssertTrue(canvas.activationCacheHit)
        XCTAssertFalse(canvas.isViewportActivationPending)
        configure(first, id: ids[0])
        configure(second, id: ids[1], revision: 1, fontSize: 18)
        XCTAssertFalse(canvas.activationCacheHit, "Layout configuration must invalidate warm state")
        XCTAssertLessThanOrEqual(canvas.cachedRenderStateCountForTesting, 8)
        XCTAssertEqual(canvas.accessibilityRole(), .textArea)
        XCTAssertTrue(canvas.acceptsFirstResponder)
    }

    func testColdLazyActivationDoesNotPrepareLiveIndexOnMainActor() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lazy-tab-\(UUID()).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try String(repeating: "# lazy é😀\n", count: 100_000).write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url, knownEncoding: .utf8)
        let id = UUID()
        let host = NSHostingView(rootView: editor(FileBackedTextDocument(content: ""), id: UUID(), language: "plain"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let previous = EditorPerformanceMonitor.shared.recentTabSwitchEvents().last?.id
        EditorPerformanceMonitor.shared.beginTabSwitch(tabID: id)
        host.rootView = editor(document, id: id, language: "markdown")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            if EditorPerformanceMonitor.shared.recentTabSwitchEvents().last?.id != previous { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNotEqual(EditorPerformanceMonitor.shared.recentTabSwitchEvents().last?.id, previous)
        XCTAssertNil(document.viewportIndexPreparedOnMainThread, "Activation must not index live storage on its owner")
        XCTAssertFalse(document.isViewportIndexReady, "Any missing index is prepared on the worker copy, not live storage")
    }

    func testDifferentDocumentIdentityAtSameResourceCannotReusePreviousViewport() async throws {
        let first = FileBackedTextDocument(content: "previous resource contents")
        let second = FileBackedTextDocument(content: "reopened resource contents")
        let host = NSHostingView(rootView: editor(first, id: UUID(), language: "plain", resourceID: "same-resource"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let id = UUID()
        let previous = EditorPerformanceMonitor.shared.recentTabSwitchEvents().last?.id
        EditorPerformanceMonitor.shared.beginTabSwitch(tabID: id)
        host.rootView = editor(second, id: id, language: "plain", resourceID: "same-resource")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            if EditorPerformanceMonitor.shared.recentTabSwitchEvents().last?.id != previous { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNotEqual(EditorPerformanceMonitor.shared.recentTabSwitchEvents().last?.id, previous)
    }

    private func editor(_ document: FileBackedTextDocument, id: UUID, language: String, resourceID: String? = nil) -> VirtualEditorView {
        VirtualEditorView(document: document, documentID: id, documentResourceID: resourceID ?? id.uuidString,
                          documentDisplayName: "fixture.\(language)", contentRevision: 0, externalContentRevision: 0,
                          storedCaretLocation: 0, language: language, colorScheme: .dark, themeRefreshToken: 0,
                          fontSize: 14, fontName: "", lineHeightMultiplier: 1, isReadOnly: false,
                          translucentBackgroundEnabled: false, showsLineNumbers: true, highlightCurrentLine: false,
                          lineWrapEnabled: true, showsInvisibleCharacters: false, showsIndentationGuides: false,
                          showsScopeGuides: false, highlightsScopeBackground: false, highlightsMatchingBrackets: false,
                          autoIndentEnabled: true, autoCloseBracketsEnabled: false, indentStyle: "spaces", indentWidth: 4,
                          isSplitPaneResizeInProgress: false, preferredLayoutWidth: 800,
                          focusesEditorOnInitialWindowAttachment: false, onFontSizeChange: nil, onTextMutation: nil)
    }

    private func benchmarkOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    private func assertMedianLatency(_ samples: [TimeInterval], budget name: String) throws {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL = fileURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryURL.appendingPathComponent("docs/performance-baselines.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let interactions = try XCTUnwrap(root["interactionBenchmarks"] as? [String: Any])
        let budgets = try XCTUnwrap(interactions["maximumMedianSeconds"] as? [String: Double])
        let maximum = try XCTUnwrap(budgets[name])
        let sorted = samples.sorted()
        let median = try XCTUnwrap(sorted.isEmpty ? nil : sorted[sorted.count / 2])
        XCTAssertLessThanOrEqual(
            median,
            maximum,
            "Median \(name) latency \(median)s exceeded the \(maximum)s budget"
        )
    }

    private func largeDocumentText() -> String {
        (0..<lineCount).map { index in
            "let benchmarkValue\(index) = \(index) // virtual editor performance fixture\n"
        }.joined()
    }
}
#endif
