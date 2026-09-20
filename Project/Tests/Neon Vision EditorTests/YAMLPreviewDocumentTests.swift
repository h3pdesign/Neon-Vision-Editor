import XCTest
@testable import Neon_Vision_Editor

final class YAMLPreviewDocumentTests: XCTestCase {
    @MainActor func testRouting() {
        XCTAssertTrue(YAMLPreviewDocument.supports(extension: "YML", language: "plain"))
        XCTAssertTrue(YAMLPreviewDocument.supports(extension: nil, language: "yaml"))
        XCTAssertFalse(YAMLPreviewDocument.supports(extension: "json", language: "json"))
        XCTAssertEqual(ContentView.PreviewMode.none.toggled(for: .yaml), .yaml)
        XCTAssertEqual(ContentView.PreviewMode.yaml.toggled(for: .yaml), .none)
    }

    func testPreservesIndentationCommentsAndUnicodeAcrossPages() throws {
        let source = String(repeating: "  - key: '日本語😀' # comment\r\n", count: 1_000)
        let document = try YAMLPreviewDocument.prepare(source)
        XCTAssertGreaterThan(document.pages.count, 1)
        XCTAssertEqual(document.pages.joined(), source)
        XCTAssertTrue(document.pages.allSatisfy { $0.unicodeScalars.count <= 16_384 })
    }

    func testLongLineIsPagedWithoutTruncatingSource() throws {
        let source = "value: " + String(repeating: "😀", count: 100_000)
        let document = try YAMLPreviewDocument.prepare(source)
        XCTAssertEqual(document.pages.joined(), source)
        XCTAssertGreaterThan(document.pages.count, 1)
    }

    func testEmptyAndSizeLimit() throws {
        XCTAssertEqual(try YAMLPreviewDocument.prepare("").pages, [""])
        XCTAssertThrowsError(try YAMLPreviewDocument.prepare(String(repeating: "a", count: YAMLPreviewDocument.maximumBytes + 1)))
    }

    func testColorsAndEscapesSourceWithoutExecutingIt() throws {
        let html = try YAMLPreviewDocument.html(for: "key: 42\nenabled: true\nname: \"a # quoted\" # comment\nhtml: <script>alert(1)</script>\nref: &anchor\n")
        for token in ["key", "number", "atom", "string", "comment", "meta"] {
            XCTAssertTrue(html.contains("class=\"\(token)\""), token)
        }
        XCTAssertTrue(html.contains("a # quoted"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("default-src 'none'"))
    }

    func testCancellation() async {
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try YAMLPreviewDocument.prepare("key: value")
        }
        do {
            _ = try await worker.value
            XCTFail("Cancelled preparation should stop")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
