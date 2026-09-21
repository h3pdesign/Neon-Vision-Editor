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

    func testBlockScalarsDoNotReinterpretTheirContents() throws {
        for header in ["|", ">-", "|2+", ">+2"] {
            let html = try YAMLPreviewDocument.html(for: "value: \(header)\r\n  true # literal\r\n  inner: 123\r\nnext: false\r\n")
            XCTAssertTrue(html.contains("class=\"string\">  true # literal\r\n"), header)
            XCTAssertTrue(html.contains("class=\"string\">  inner: 123\r\n"), header)
            XCTAssertTrue(html.contains("class=\"key\">next</span>"), header)
            XCTAssertTrue(html.contains("class=\"atom\">false</span>"), header)
        }
    }

    func testScalarClassificationUsesWholeValues() throws {
        let html = try YAMLPreviewDocument.html(for: "message: turn off now\nother: true story\nurl: https://example.com/#part\nname: it's fine\nlegacy: off\nflag: TRUE\nhex: 0x2a\n")
        for value in ["turn off now", "true story", "https://example.com/#part", "it's fine", "off"] {
            XCTAssertTrue(html.contains("class=\"string\">\(ContentView.escapedHTML(value))</span>"), value)
        }
        XCTAssertTrue(html.contains("class=\"atom\">TRUE</span>"))
        XCTAssertTrue(html.contains("class=\"number\">0x2a</span>"))
    }

    func testQuotedScalarContextSurvivesPaginationIncludingEscapes() throws {
        for source in [
            "key: \"" + String(repeating: "a", count: 16_377) + "\\\"true # text\"\nnext: false",
            "key: '" + String(repeating: "a", count: 16_377) + "''true # text'\nnext: false"
        ] {
            let document = try YAMLPreviewDocument.prepare(source)
            XCTAssertEqual(document.pages.joined(), source)
            let html = try document.html(forPage: 1)
            XCTAssertTrue(html.contains("true # text"))
            XCTAssertFalse(html.contains("class=\"atom\">true"))
            XCTAssertFalse(html.contains("class=\"comment\"># text"))
            XCTAssertTrue(html.contains("class=\"atom\">false</span>"))
        }
    }

    func testBlockScalarContextSurvivesLineAndScalarPageBoundaries() throws {
        for source in [
            "value: |\n" + String(repeating: "  literal\n", count: 205) + "  true # literal\nnext: 42\n",
            "value: |\n  " + String(repeating: "😀", count: 16_384) + "true # literal\nnext: 42\n"
        ] {
            let document = try YAMLPreviewDocument.prepare(source)
            XCTAssertEqual(document.pages.joined(), source)
            let html = try document.html(forPage: 1)
            XCTAssertTrue(html.contains("true # literal"))
            XCTAssertFalse(html.contains("class=\"atom\">true"))
            XCTAssertFalse(html.contains("class=\"comment\"># literal"))
            XCTAssertTrue(html.contains("class=\"number\">42</span>"))
        }
    }

    func testFlowCollectionsAndMultilinePlainScalars() throws {
        let html = try YAMLPreviewDocument.html(for: "values: [true, false, turn off, 123]\nmessage: plain text\n  another 123 # comment\nnext: null\n")
        XCTAssertTrue(html.contains("class=\"atom\">true</span>"))
        XCTAssertTrue(html.contains("class=\"string\">turn off</span>"))
        XCTAssertTrue(html.contains("class=\"string\">  another 123 </span>"))
        XCTAssertTrue(html.contains("class=\"comment\"># comment</span>"))
        XCTAssertTrue(html.contains("class=\"atom\">null</span>"))
        let continued = try YAMLPreviewDocument.html(for: "value: true\n  story\nnumber: 123\n  words\n")
        XCTAssertFalse(continued.contains("class=\"atom\""))
        XCTAssertFalse(continued.contains("class=\"number\""))
        let flow = try YAMLPreviewDocument.html(for: "values: [true\n  story, 123\n  words, false]\n")
        XCTAssertTrue(flow.contains("class=\"string\">true</span>"))
        XCTAssertTrue(flow.contains("class=\"string\">123</span>"))
        XCTAssertTrue(flow.contains("class=\"atom\">false</span>"))
    }
}
