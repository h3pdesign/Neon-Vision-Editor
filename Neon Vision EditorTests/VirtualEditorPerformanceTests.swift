#if os(macOS)
import AppKit
import CoreText
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

    private func benchmarkOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    private func assertMedianLatency(_ samples: [TimeInterval], budget name: String) throws {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL = fileURL.deletingLastPathComponent().deletingLastPathComponent()
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
