import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class FileBackedTextDocumentCheckpointTests: XCTestCase {
    /// A deterministic generator so failures reproduce.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }

    private func source(minimumUTF8Count: Int) -> String {
        var lines: [String] = []
        var count = 0
        var index = 0
        while count < minimumUTF8Count {
            let line = "  {\"id\": \(index), \"name\": \"é😀 \(index)\", \"tags\": [\"ü\", \"ß\"]},"
            lines.append(line)
            count += line.utf8.count + 1
            index += 1
        }
        return "[\n" + lines.joined(separator: "\n") + "\n]\n"
    }

    /// A UTF-16 offset that does not split a composed character.
    private func boundary(_ offset: Int, in text: NSString) -> Int {
        guard offset < text.length else { return text.length }
        return text.rangeOfComposedCharacterSequence(at: offset).location
    }

    private func lineStarts(_ text: NSString) -> [Int] {
        var starts = [0]
        for index in 0..<text.length where text.character(at: index) == 10 { starts.append(index + 1) }
        return starts
    }

    private func line(of offset: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return low - 1
    }

    func testLargeUTF8PiecesConvertOffsetsExactlyAcrossEdits() throws {
        let original = source(minimumUTF8Count: 6 * FileBackedTextDocument.utf16CheckpointStride)
        for identifier in [TextEncodingDescriptor.Identifier.utf8, .utf8WithBOM] {
            let document = FileBackedTextDocument(content: original, encoding: TextEncodingDescriptor(identifier: identifier))
            let expected = NSMutableString(string: original)
            var random = SplitMix64(state: 42)
            let replacements = ["X", "é", "😀\n", "", "{\n}", "ab\ncd"]
            for step in 0..<40 {
                let location = boundary(Int.random(in: 0...expected.length, using: &random), in: expected)
                let end = boundary(min(expected.length, location + Int.random(in: 0...40, using: &random)), in: expected)
                let range = NSRange(location: location, length: end - location)
                let replacement = replacements[step % replacements.count]
                try document.replace(utf16Range: range, with: replacement)
                expected.replaceCharacters(in: range, with: replacement)
                XCTAssertEqual(document.utf16Length, expected.length, "\(identifier.rawValue) step \(step)")

                let starts = lineStarts(expected)
                XCTAssertEqual(document.lineCount, starts.count)
                for _ in 0..<12 {
                    let offset = boundary(Int.random(in: 0...expected.length, using: &random), in: expected)
                    let length = boundary(min(expected.length, offset + 30), in: expected) - offset
                    let probe = NSRange(location: offset, length: length)
                    XCTAssertEqual(try document.text(inUTF16Range: probe), expected.substring(with: probe))
                    let position = try document.position(atUTF16Offset: offset)
                    let expectedLine = line(of: offset, in: starts)
                    XCTAssertEqual(position.line, expectedLine)
                    XCTAssertEqual(position.column, offset - starts[expectedLine])
                }
                let anchor = Int.random(in: 0..<starts.count, using: &random)
                let viewport = try document.viewport(aroundLine: anchor, maximumByteCount: 4_096, maximumLineCount: 24)
                XCTAssertEqual(viewport.startUTF16Offset, starts[viewport.lineRange.lowerBound])
                XCTAssertEqual(viewport.text, expected.substring(with: NSRange(
                    location: viewport.startUTF16Offset, length: (viewport.text as NSString).length
                )))
            }
            XCTAssertEqual(document.string(), expected as String)
        }
    }

    func testMaterializedLazyDocumentConvertsOffsetsExactly() throws {
        let original = source(minimumUTF8Count: 3 * FileBackedTextDocument.utf16CheckpointStride)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("checkpoints-\(UUID().uuidString).json")
        try Data(original.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try FileBackedTextDocument(url: url)
        try document.prepareViewportIndex()
        let expected = NSMutableString(string: original)
        let middle = boundary(expected.length / 2, in: expected)
        try document.replace(utf16Range: NSRange(location: middle, length: 0), with: "😀")
        expected.replaceCharacters(in: NSRange(location: middle, length: 0), with: "😀")
        let starts = lineStarts(expected)
        for offset in stride(from: 0, to: expected.length, by: 997) {
            let safe = boundary(offset, in: expected)
            let position = try document.position(atUTF16Offset: safe)
            XCTAssertEqual(position.line, line(of: safe, in: starts))
            XCTAssertEqual(position.column, safe - starts[position.line])
        }
        XCTAssertEqual(document.string(), expected as String)
    }

    /// After the first edit the document is one large in-memory piece. Offset
    /// lookups must not decode the prefix of that piece on every call.
    func testEditedLargeDocumentKeepsViewportAndPositionLookupsBounded() throws {
        let original = source(minimumUTF8Count: 24 * 1024 * 1024)
        let document = FileBackedTextDocument(content: original)
        try document.replace(utf16Range: NSRange(location: 2, length: 0), with: " ")
        let lineCount = document.lineCount
        var random = SplitMix64(state: 7)
        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<200 {
            let anchor = Int.random(in: 0..<lineCount, using: &random)
            let viewport = try document.viewport(aroundLine: anchor, maximumByteCount: 64 * 1024, maximumLineCount: 512)
            let caret = viewport.startUTF16Offset + (viewport.text as NSString).length / 2
            _ = try document.position(atUTF16Offset: caret)
            _ = try document.text(inUTF16Range: NSRange(location: viewport.startUTF16Offset, length: 16))
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        print("Edited 24 MB document: 200 viewport/position/text lookups in \(String(format: "%.3f", elapsed)) s")
        XCTAssertLessThan(elapsed, 2.0)
    }
}
