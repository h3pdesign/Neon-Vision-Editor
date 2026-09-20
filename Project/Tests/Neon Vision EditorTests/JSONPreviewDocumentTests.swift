import XCTest
@testable import Neon_Vision_Editor

final class JSONPreviewDocumentTests: XCTestCase {
    func testTypesOrderDuplicateKeysAndExactNumbers() throws {
        let parsed = try JSONPreviewDocument.parse(#"{"z":9007199254740993,"a":-1.2300e+100,"z":true,"nil":null,"text":"hello","list":[]}"#)
        let children = parsed.nodes[0].children.map { parsed.nodes[$0] }
        XCTAssertEqual(children.map(\.name), ["z", "a", "z", "nil", "text", "list"])
        XCTAssertEqual(children.map(\.kind), [.number, .number, .boolean, .null, .string, .array])
        XCTAssertEqual(children[0].value, "9007199254740993")
        XCTAssertEqual(children[1].value, "-1.2300e+100")
    }

    func testFragmentsAndEmptyContainers() throws {
        for text in ["null", "true", "false", "0", "-0", "1.5e-2", "\"hello\"", "{}", "[]"] {
            XCTAssertEqual(try JSONPreviewDocument.parse(text).nodes.count, 1, text)
        }
    }

    func testUnicodeAndEscapes() throws {
        let parsed = try JSONPreviewDocument.parse(#"{"emoji":"\uD83D\uDE00","quote":"a\"b","slash":"a\\b"}"#)
        XCTAssertEqual(parsed.nodes[1].value, "\"😀\"")
        XCTAssertEqual(parsed.nodes[2].value, "\"a\"b\"")
        XCTAssertEqual(parsed.nodes[3].value, "\"a\\b\"")
    }

    func testInvalidSyntaxIsRejected() {
        for text in ["", "[1,]", "{\"a\":}", "{a:1}", "[01]", "+1", "1.", "1e", "--1", "true false", "NaN", "[", "{", #""\q""#, "\"line\nfeed\""] {
            XCTAssertThrowsError(try JSONPreviewDocument.parse(text), text)
        }
    }

    func testValidationIncludesLineAndColumn() {
        XCTAssertThrowsError(try JSONPreviewDocument.parse("{\n  \"a\": ?\n}")) { error in
            XCTAssertTrue(error.localizedDescription.contains("line 2, column 8"))
        }
    }

    func testLongUnicodeValuesAreBoundedAndSourceUnchanged() throws {
        let source = "\"" + String(repeating: "😀", count: 500_000) + "\""
        let parsed = try JSONPreviewDocument.parse(source)
        XCTAssertLessThan(parsed.nodes[0].value.count, 520)
        XCTAssertTrue(parsed.nodes[0].value.contains("…"))
        XCTAssertEqual(source.count, 500_002)
    }

    func testLargeArrayUsesPagedVisibleRows() throws {
        let source = "[" + Array(repeating: "123456789012345678901234567890", count: 90_000).joined(separator: ",") + "]"
        let parsed = try JSONPreviewDocument.parse(source)
        XCTAssertEqual(parsed.nodes[0].children.count, 90_000)
        let first = parsed.rows(expanded: [0], pages: [:])
        XCTAssertEqual(first.count, 102)
        XCTAssertTrue(first.last!.isPager)
        let second = parsed.rows(expanded: [0], pages: [0: 1])
        XCTAssertEqual(parsed.nodes[second[1].nodeID].name, "[100]")
        XCTAssertEqual(parsed.rows(expanded: [], pages: [:]).count, 1)
    }

    func testVisibleRowBudgetAndStableIDs() throws {
        let branch = "[" + Array(repeating: "0", count: 100).joined(separator: ",") + "]"
        let parsed = try JSONPreviewDocument.parse("[" + Array(repeating: branch, count: 100).joined(separator: ",") + "]")
        let rows = parsed.rows(expanded: Set(parsed.nodes.indices), pages: [:])
        XCTAssertEqual(rows.count, 2_000)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testDepthAndSizeLimits() {
        XCTAssertThrowsError(try JSONPreviewDocument.parse(String(repeating: "[", count: 130) + "0" + String(repeating: "]", count: 130)))
        XCTAssertThrowsError(try JSONPreviewDocument.parse(String(repeating: " ", count: JSONPreviewDocument.maximumBytes + 1)))
    }

    func testCancellation() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try JSONPreviewDocument.parse("[1,2,3]")
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled parsing must not publish a document")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected cancellation error")
        }
    }

    @MainActor
    func testJSONPreviewModeToggle() {
        XCTAssertEqual(ContentView.PreviewMode.none.toggled(for: .json), .json)
        XCTAssertEqual(ContentView.PreviewMode.json.toggled(for: .json), .none)
        XCTAssertEqual(ContentView.PreviewMode.markdown.toggled(for: .json), .json)
    }
}
