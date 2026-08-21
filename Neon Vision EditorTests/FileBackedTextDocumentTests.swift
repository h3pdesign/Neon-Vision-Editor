import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class FileBackedTextDocumentTests: XCTestCase {
    nonisolated(unsafe) private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testIndexesAndReadsOnlyRequestedLinesFromUTF8File() throws {
        let url = directory.appendingPathComponent("large.txt")
        try "zero\none\ntwo\nthree\n".write(to: url, atomically: true, encoding: .utf8)

        let document = try FileBackedTextDocument(url: url)

        let lineCount = document.lineCount
        let middleLines = try document.text(inLines: 1...2)
        let finalLine = try document.text(inLines: 3...3)
        let byteCount = document.byteCount
        XCTAssertEqual(lineCount, 5)
        XCTAssertEqual(middleLines, "one\ntwo\n")
        XCTAssertEqual(finalLine, "three\n")
        XCTAssertEqual(byteCount, 19)
    }

    func testLineWindowIsBoundedAndCarriesAbsoluteByteOffset() throws {
        let url = directory.appendingPathComponent("windowed.txt")
        let source = (0..<2_000).map { "line-\($0)\n" }.joined()
        try source.write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)

        let window = try document.window(aroundLine: 1_000, maximumByteCount: 256)

        XCTAssertLessThanOrEqual(window.text.utf8.count, 256)
        XCTAssertGreaterThan(window.startByteOffset, 0)
        XCTAssertTrue(window.text.contains("line-1000"))
        XCTAssertGreaterThan(window.lineRange.lowerBound, 0)
    }

    func testTwoHundredKilobyteMarkdownSupportsEditsAcrossTheDocument() throws {
        let line = "The editor must keep a large Markdown document responsive while the user edits it.\n"
        let source = String(repeating: line, count: 3_000)
        XCTAssertGreaterThan(source.utf8.count, 200_000)

        let url = directory.appendingPathComponent("large-markdown.md")
        try source.write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url, knownUTF8Encoding: .utf8)
        try document.prepareViewportIndex()

        var viewport = try document.viewport(aroundLine: 0, maximumByteCount: 128_000)
        try document.replace(in: viewport, utf16Range: NSRange(location: 0, length: 0), with: "# Edited at the beginning\n")

        viewport = try document.viewport(aroundLine: document.lineCount / 2, maximumByteCount: 128_000)
        try document.replace(in: viewport, utf16Range: NSRange(location: 0, length: 0), with: "edited ")

        let finalViewport = try document.viewport(aroundLine: document.lineCount - 1, maximumByteCount: 128_000)
        XCTAssertLessThanOrEqual(finalViewport.text.utf8.count, 128_000)
        XCTAssertTrue(finalViewport.text.contains("The editor must keep"))
    }

    func testViewportCarriesAbsoluteUTF16OffsetForVirtualRendererEdits() throws {
        let document = FileBackedTextDocument(content: "zero\n😀 one\ntwo\nthree\n")

        let viewport = try document.viewport(aroundLine: 2, maximumByteCount: 8)

        XCTAssertEqual(viewport.lineRange.lowerBound, 2)
        XCTAssertEqual(viewport.startUTF16Offset, "zero\n😀 one\n".utf16.count)
    }

    func testViewportGenerationRejectsEditsAgainstAnOlderWindow() throws {
        let url = directory.appendingPathComponent("viewport-generation.txt")
        try (0..<100).map { "line-\($0)\n" }.joined().write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)

        let first = try document.viewport(aroundLine: 10, maximumByteCount: 64)
        _ = try document.viewport(aroundLine: 80, maximumByteCount: 64)

        XCTAssertThrowsError(try document.replace(in: first, utf16Range: NSRange(location: 0, length: 1), with: "X"))
    }

    func testUTF16LengthAndLineIndexStayCorrectAfterIncrementalEdits() throws {
        let document = FileBackedTextDocument(content: "alpha\nbeta\ngamma")
        XCTAssertEqual(document.utf16Length, "alpha\nbeta\ngamma".utf16.count)
        try document.replace(byteRange: NSRange(location: 5, length: 1), with: "\ninserted\n")
        XCTAssertEqual(document.utf16Length, "alpha\ninserted\nbeta\ngamma".utf16.count)
        XCTAssertEqual(document.lineCount, 4)
        XCTAssertEqual(try document.text(inLines: 1...2), "inserted\nbeta\n")
        try document.replace(byteRange: NSRange(location: 6, length: 9), with: "")
        XCTAssertEqual(document.utf16Length, "alpha\nbeta\ngamma".utf16.count)
        XCTAssertEqual(document.lineCount, 3)
    }

    func testUTF16EditSurfacesUnsupportedEncodingWithoutMutatingDocument() throws {
        let encoding = TextEncodingDescriptor(identifier: .windowsCP1252)
        let document = FileBackedTextDocument(content: "plain", encoding: encoding)

        XCTAssertThrowsError(
            try document.replace(
                utf16Range: NSRange(location: 0, length: 0),
                with: "😀"
            )
        ) { error in
            XCTAssertEqual(error as? FileBackedTextDocument.Error, .unsupportedEncoding)
        }
        XCTAssertEqual(document.string(), "plain")
        XCTAssertFalse(document.isDirty)
    }

    func testUTF16EditUsesDocumentCoordinatesWithoutWholeStringProjection() throws {
        let document = FileBackedTextDocument(content: String(repeating: "x\n", count: 20_000))
        let location = "x\n".utf16.count * 15_000

        try document.replace(utf16Range: NSRange(location: location, length: 1), with: "Y")

        XCTAssertEqual(document.utf16Length, 40_000)
        let viewport = try document.viewport(aroundLine: 15_000, maximumByteCount: 128)
        XCTAssertTrue(viewport.text.contains("Y"))
    }

    func testKnownUTF8LazyViewportHandlesMultibyteDataAcrossIndexSegments() throws {
        let url = directory.appendingPathComponent("segmented-emoji.txt")
        let line = String(repeating: "prefix 😀 café ", count: 128) + "\n"
        try String(repeating: line, count: 30_000).write(to: url, atomically: true, encoding: .utf8)

        let document = try FileBackedTextDocument(url: url, knownUTF8Encoding: .utf8)
        XCTAssertFalse(document.isViewportIndexReady)
        XCTAssertThrowsError(try document.viewport(aroundLine: 20_000, maximumByteCount: 64 * 1024))
        try document.prepareViewportIndex()
        XCTAssertTrue(document.isViewportIndexReady)
        let viewport = try document.viewport(aroundLine: 20_000, maximumByteCount: 64 * 1024)

        XCTAssertTrue(viewport.text.contains("😀"))
        XCTAssertTrue(viewport.text.contains("café"))
        XCTAssertGreaterThan(viewport.startUTF16Offset, 0)
        XCTAssertLessThanOrEqual(viewport.text.utf8.count, 64 * 1024)
    }

    func testKnownUTF8LazyDocumentPromotesOnlyForMutationAndKeepsAbsoluteCoordinates() throws {
        let url = directory.appendingPathComponent("lazy-edit.txt")
        let source = (0..<40_000).map { "line-\($0) 😀\n" }.joined()
        try source.write(to: url, atomically: true, encoding: .utf8)

        let document = try FileBackedTextDocument(url: url, knownUTF8Encoding: .utf8)
        try document.prepareViewportIndex()
        let viewport = try document.viewport(aroundLine: 32_000, maximumByteCount: 4096)
        let localEmoji = (viewport.text as NSString).range(of: "😀")
        XCTAssertNotEqual(localEmoji.location, NSNotFound)

        try document.replace(
            in: viewport,
            utf16Range: localEmoji,
            with: "🚀"
        )

        let edited = try document.viewport(aroundLine: 32_000, maximumByteCount: 4096)
        XCTAssertTrue(edited.text.contains("🚀"))
        XCTAssertTrue(document.isDirty)
    }

    func testKnownUTF16LazyViewportPreservesAbsoluteCoordinatesAndDecodesWindows() throws {
        let url = directory.appendingPathComponent("segmented-utf16le.txt")
        let encoding = TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM)
        let source = (0..<40_000).map { "line-\($0) 😀\n" }.joined()
        try XCTUnwrap(encoding.encodedData(for: source)).write(to: url)

        let document = try FileBackedTextDocument(url: url, knownEncoding: encoding)
        try document.prepareViewportIndex()
        let viewport = try document.viewport(aroundLine: 32_000, maximumByteCount: 4096)

        XCTAssertTrue(viewport.text.contains("line-32000"))
        XCTAssertTrue(viewport.text.contains("😀"))
        XCTAssertGreaterThan(viewport.startUTF16Offset, 0)
        XCTAssertLessThanOrEqual(viewport.text.utf8.count, 4096)
    }


    func testAutomaticUTF16AndLegacyOpenUseBoundedWindows() throws {
        let utf16URL = directory.appendingPathComponent("automatic-utf16.txt")
        let utf16 = TextEncodingDescriptor(identifier: .utf16BigEndianWithBOM)
        let utf16Source = (0..<40_000).map { "utf16-\($0) 😀\n" }.joined()
        try XCTUnwrap(utf16.encodedData(for: utf16Source)).write(to: utf16URL)

        let utf16Document = try FileBackedTextDocument(url: utf16URL)
        try utf16Document.prepareViewportIndex()
        let utf16Viewport = try utf16Document.viewport(aroundLine: 32_000, maximumByteCount: 4096)
        XCTAssertEqual(utf16Document.encodingDescriptor.identifier, .utf16BigEndianWithBOM)
        XCTAssertTrue(utf16Viewport.text.contains("utf16-32000"))


    }

    func testLazyUTF16MutationSavesBOMAndRejectsExternalConflict() throws {
        let url = directory.appendingPathComponent("lazy-utf16-save.txt")
        let encoding = TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM)
        let source = (0..<30_000).map { "utf16-\($0) 😀\n" }.joined()
        try XCTUnwrap(encoding.encodedData(for: source)).write(to: url)

        let document = try FileBackedTextDocument(url: url, knownEncoding: encoding)
        try document.prepareViewportIndex()
        let viewport = try document.viewport(aroundLine: 20_000, maximumByteCount: 4096)
        let range = (viewport.text as NSString).range(of: "😀")
        XCTAssertNotEqual(range.location, NSNotFound)
        try document.replace(in: viewport, utf16Range: range, with: "🚀")

        try source.replacingOccurrences(of: "utf16-20000 😀", with: "utf16-20000 🚀").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try document.saveAtomically()) { error in
            XCTAssertEqual(error as? FileBackedTextDocument.Error, .externalConflict)
        }

        try XCTUnwrap(encoding.encodedData(for: source)).write(to: url)
        try document.saveAtomically()
        let saved = try Data(contentsOf: url)
        XCTAssertEqual(Array(saved.prefix(2)), [0xFF, 0xFE])
        XCTAssertTrue(encoding.decode(saved)?.contains("utf16-20000 🚀") == true)
    }



    func testEightMegabyteUTF8DocumentOpensAndReadsBoundedViewport() throws {
        let url = directory.appendingPathComponent("eight-megabytes.txt")
        let line = String(repeating: "0123456789abcdef", count: 32) + "\n"
        try String(repeating: line, count: 128_000).write(to: url, atomically: true, encoding: .utf8)

        measure(metrics: [XCTClockMetric()]) {
            let document = try? FileBackedTextDocument(url: url, knownUTF8Encoding: .utf8)
            XCTAssertNotNil(document)
            try? document?.prepareViewportIndex()
            XCTAssertEqual(document?.byteCount, line.utf8.count * 128_000)
            XCTAssertLessThanOrEqual(
                (try? document?.viewport(aroundLine: 64_000, maximumByteCount: 64 * 1024).text.utf8.count) ?? 0,
                64 * 1024
            )
        }
    }

    func testRepresentativeEncodingsOpenAndReadBoundedViewportsWithoutWholeStringProjection() throws {
        let cases: [(String, TextEncodingDescriptor)] = [
            ("utf8-performance.txt", .utf8),
            ("utf16-performance.txt", TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM))
        ]
        for (name, encoding) in cases {
            let url = directory.appendingPathComponent(name)
            let source = (0..<160_000).map { "line-\($0) 😀 привет\n" }.joined()
            try XCTUnwrap(encoding.encodedData(for: source)).write(to: url)

            let document = try XCTUnwrap(try? FileBackedTextDocument(url: url, knownEncoding: encoding), encoding.identifier.rawValue)
            try document.prepareViewportIndex()
            XCTAssertEqual(document.encodingDescriptor.identifier, encoding.identifier, encoding.identifier.rawValue)
            do {
                let viewport = try document.viewport(aroundLine: 120_000, maximumByteCount: 64 * 1024)
                XCTAssertTrue(viewport.text.contains("line-120000"), encoding.identifier.rawValue)
                XCTAssertLessThanOrEqual(
                    document.encodingDescriptor.identifier == .utf8 || document.encodingDescriptor.identifier == .utf8WithBOM
                        ? viewport.text.utf8.count
                        : viewport.text.utf16.count * (document.encodingDescriptor.identifier == .utf16LittleEndian || document.encodingDescriptor.identifier == .utf16LittleEndianWithBOM || document.encodingDescriptor.identifier == .utf16BigEndian || document.encodingDescriptor.identifier == .utf16BigEndianWithBOM ? 2 : 1),
                    64 * 1024,
                    encoding.identifier.rawValue
                )
            } catch {
                XCTFail("bounded viewport failed for \(encoding.identifier.rawValue): \(error)")
            }
        }
    }

    func testWindowReflectsEditsBeforeSave() throws {
        let url = directory.appendingPathComponent("edited-window.txt")
        try "zero\none\ntwo\nthree\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)

        try document.replace(byteRange: NSRange(location: 5, length: 3), with: "ONE\nINSERTED")
        let window = try document.window(aroundLine: 2, maximumByteCount: 64)

        XCTAssertEqual(window.text, "zero\nONE\nINSERTED\ntwo\nthree\n")
        // The editor retains the terminal empty line after a trailing newline.
        XCTAssertEqual(window.lineRange, 0...5)
    }

    func testEditsAreAppliedWithoutMutatingSourceUntilStreamingSave() throws {
        let url = directory.appendingPathComponent("editable.txt")
        try "alpha\nbeta\ngamma\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)

        try document.replace(byteRange: NSRange(location: 6, length: 4), with: "BETA")

        let isDirtyAfterEdit = document.isDirty
        let editedByteCount = document.byteCount
        let editedText = try document.text(inByteRange: NSRange(location: 0, length: editedByteCount))
        let sourceBeforeSave = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(isDirtyAfterEdit)
        XCTAssertEqual(editedText, "alpha\nBETA\ngamma\n")
        XCTAssertEqual(sourceBeforeSave, "alpha\nbeta\ngamma\n")

        try document.saveAtomically()

        let isDirtyAfterSave = document.isDirty
        let sourceAfterSave = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(isDirtyAfterSave)
        XCTAssertEqual(sourceAfterSave, "alpha\nBETA\ngamma\n")
    }

    func testKnownUTF8OpenAndSaveAsStreamPiecesWithoutStringProjection() throws {
        let sourceURL = directory.appendingPathComponent("source.txt")
        let destinationURL = directory.appendingPathComponent("destination.txt")
        try "alpha\nbeta\ngamma\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let document = try FileBackedTextDocument(url: sourceURL, knownUTF8Encoding: .utf8)
        try document.replace(byteRange: NSRange(location: 6, length: 4), with: "BETA")
        try document.saveAtomically(to: destinationURL)

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "alpha\nbeta\ngamma\n")
        XCTAssertEqual(try String(contentsOf: destinationURL, encoding: .utf8), "alpha\nBETA\ngamma\n")
    }

    func testLifecycleMetadataSupportsSessionRestoreAndDetectsExternalChanges() throws {
        let url = directory.appendingPathComponent("metadata.txt")
        try "first\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)

        let record = document.restoreRecord
        let roundTripped = try JSONDecoder().decode(
            FileBackedTextDocument.RestoreRecord.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertEqual(roundTripped, record)
        XCTAssertEqual(roundTripped.encodingIdentifier, .utf8)
        XCTAssertEqual(roundTripped.lineEnding, .lf)
        XCTAssertFalse(roundTripped.isRemoteEligible)
        XCTAssertFalse(document.hasExternalConflict())

        try "second\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(document.hasExternalConflict())
    }

    func testStreamingSavePreservesSourceCRLFLineEndings() throws {
        let url = directory.appendingPathComponent("crlf.txt")
        try Data("first\r\nsecond\r\n".utf8).write(to: url)
        let document = try FileBackedTextDocument(url: url)

        try document.replace(byteRange: NSRange(location: 7, length: 6), with: "SECOND\nTHIRD")
        try document.saveAtomically()

        XCTAssertEqual(document.restoreRecord.lineEnding, .crlf)
        XCTAssertEqual(try Data(contentsOf: url), Data("first\r\nSECOND\r\nTHIRD\r\n".utf8))
    }

    func testViewportAdapterTranslatesUTF16WindowEditToDocumentBytes() throws {
        let url = directory.appendingPathComponent("adapter.txt")
        try "before\nvisible line\nafter\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)
        let adapter = FileBackedTextViewportAdapter(document: document, maximumByteCount: 128)

        let window = try adapter.window(aroundLine: 1)
        try adapter.replace(in: window, utf16Range: NSRange(location: 7, length: 7), with: "updated")

        XCTAssertEqual(try document.text(inByteRange: NSRange(location: 0, length: document.byteCount)), "before\nupdated line\nafter\n")
    }

    func testDirtySessionStateRestoresEditsOnlyWhenSourceRevisionMatches() throws {
        let url = directory.appendingPathComponent("session.txt")
        try "zero\none\ntwo\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)
        try document.replace(byteRange: NSRange(location: 5, length: 3), with: "ONE\nINSERTED")

        let state = document.sessionState
        let restored = try FileBackedTextDocument(restoring: state)
        XCTAssertEqual(try restored.text(inByteRange: NSRange(location: 0, length: restored.byteCount)), "zero\nONE\nINSERTED\ntwo\n")

        try "zero\nchanged\ntwo\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try FileBackedTextDocument(restoring: state)) { error in
            XCTAssertEqual(error as? FileBackedTextDocument.Error, .externalConflict)
        }
    }

    func testAtomicSaveRefusesAnExternalChangeAfterOpening() throws {
        let url = directory.appendingPathComponent("save-conflict.txt")
        try "local\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)
        try document.replace(byteRange: NSRange(location: 0, length: 5), with: "edited")
        try "other\n".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try document.saveAtomically()) { error in
            XCTAssertEqual(error as? FileBackedTextDocument.Error, .externalConflict)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "other\n")
    }

    func testUTF8BOMDocumentPreservesDescriptorAndBOMWhenSaving() throws {
        let url = directory.appendingPathComponent("bom.txt")
        try Data([0xEF, 0xBB, 0xBF] + Array("alpha\n".utf8)).write(to: url)

        let document = try FileBackedTextDocument(url: url)
        try document.replace(byteRange: NSRange(location: 3, length: 5), with: "BETA")
        try document.saveAtomically()

        XCTAssertEqual(document.encodingDescriptor.identifier, .utf8WithBOM)
        XCTAssertEqual(
            try Data(contentsOf: url),
            Data([0xEF, 0xBB, 0xBF] + Array("BETA\n".utf8))
        )
    }

    func testReplaceAllPreservesUTF8BOMForEditorContentRefresh() throws {
        let url = directory.appendingPathComponent("replace-all-bom.txt")
        try Data([0xEF, 0xBB, 0xBF] + Array("before\n".utf8)).write(to: url)

        let document = try FileBackedTextDocument(url: url)
        try document.replaceAll(with: "after\n")
        try document.saveAtomically()

        let saved = try Data(contentsOf: url)
        XCTAssertEqual(Array(saved.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(String(data: saved.dropFirst(3), encoding: .utf8), "after\n")
    }

    func testWindowsCP1251DocumentPreservesEncodingWhenSaving() throws {
        let url = directory.appendingPathComponent("cp1251.txt")
        let encoding = TextEncodingDescriptor(identifier: .windowsCP1251)
        try XCTUnwrap(encoding.encodedData(for: "Привет\n")).write(to: url)

        let document = try FileBackedTextDocument(url: url)
        try document.replace(byteRange: NSRange(location: 0, length: 6), with: "Мир")
        try document.saveAtomically()

        XCTAssertEqual(document.encodingDescriptor.identifier, .windowsCP1251)
        XCTAssertEqual(try String(contentsOf: url, encoding: .windowsCP1251), "Мир\n")
    }

    func testUTF16LEBOMDocumentIndexesLinesAndPreservesEncodingWhenSaving() throws {
        let url = directory.appendingPathComponent("utf16le.txt")
        let encoding = TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM)
        try XCTUnwrap(encoding.encodedData(for: "alpha\nbeta\n")).write(to: url)

        let document = try FileBackedTextDocument(url: url)
        XCTAssertEqual(document.lineCount, 3)
        XCTAssertEqual(try document.text(inLines: 1...1), "beta\n")

        // 2-byte BOM + UTF-16LE "alpha\n" (12 bytes).
        try document.replace(byteRange: NSRange(location: 14, length: 8), with: "BETA")
        try document.saveAtomically()

        XCTAssertEqual(document.encodingDescriptor.identifier, .utf16LittleEndianWithBOM)
        XCTAssertEqual(encoding.decode(try Data(contentsOf: url)), "alpha\nBETA\n")
    }

    func testUTF16LEBOMDocumentPreservesCRLFLineEndingsWhenEditing() throws {
        let url = directory.appendingPathComponent("utf16le-crlf.txt")
        let encoding = TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM)
        try XCTUnwrap(encoding.encodedData(for: "first\r\nsecond\r\n")).write(to: url)
        let document = try FileBackedTextDocument(url: url)

        try document.replace(byteRange: NSRange(location: 16, length: 12), with: "SECOND\nTHIRD")
        try document.saveAtomically()

        XCTAssertEqual(document.restoreRecord.lineEnding, .crlf)
        XCTAssertEqual(encoding.decode(try Data(contentsOf: url)), "first\r\nSECOND\r\nTHIRD\r\n")
    }

    func testUTF16BEBOMDocumentIndexesAndSavesEdits() throws {
        let url = directory.appendingPathComponent("utf16be.txt")
        let encoding = TextEncodingDescriptor(identifier: .utf16BigEndianWithBOM)
        try XCTUnwrap(encoding.encodedData(for: "one\ntwo\n")).write(to: url)
        let document = try FileBackedTextDocument(url: url)

        XCTAssertEqual(try document.text(inLines: 1...1), "two\n")
        try document.replace(byteRange: NSRange(location: 10, length: 6), with: "TWO")
        try document.saveAtomically()

        XCTAssertEqual(document.encodingDescriptor.identifier, .utf16BigEndianWithBOM)
        XCTAssertEqual(encoding.decode(try Data(contentsOf: url)), "one\nTWO\n")
    }

    func testUTF16CoordinateEditMapsOnlyTheRequestedWindow() throws {
        let url = directory.appendingPathComponent("coordinates.txt")
        try "alpha\nβeta\ngamma\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try FileBackedTextDocument(url: url)

        let window = try document.window(aroundLine: 1, maximumByteCount: 64)
        // The virtual editor reports a UTF-16 selection relative to its loaded window.
        try document.replace(in: window, utf16Range: NSRange(location: 6, length: 1), with: "B")

        XCTAssertEqual(
            try document.text(inByteRange: NSRange(location: 0, length: document.byteCount)),
            "alpha\nBeta\ngamma\n"
        )
    }

    func testRecognizesUTF16SourceWithoutTreatingItAsUTF8() throws {
        let url = directory.appendingPathComponent("utf16.txt")
        try Data([0xFF, 0xFE, 0x61, 0x00]).write(to: url)

        let document = try FileBackedTextDocument(url: url)
        XCTAssertEqual(document.encodingDescriptor.identifier, .utf16LittleEndianWithBOM)
        XCTAssertEqual(try document.text(inByteRange: NSRange(location: 0, length: document.byteCount)), "a")
    }
}
