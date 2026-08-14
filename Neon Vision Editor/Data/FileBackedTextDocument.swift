import Foundation

/// An encoding-aware text document whose unchanged source stays range-backed on disk.
///
/// Edits are represented as small replacement pieces. The original file is never
/// copied into a `String`, and saving streams source and edit pieces to a temporary
/// sibling before atomically replacing the source file.
final class FileBackedTextDocument: EditorDocument {
    enum Error: Swift.Error, Equatable {
        case unsupportedEncoding
        case invalidRange
        case externalConflict
    }

    private struct Piece {
        let sourceOffset: Int?
        let data: Data
        let utf16Length: Int
        let newlineOffsets: [Int]

        var length: Int { data.count }

        static func source(_ data: Data, offset: Int, encoding: TextEncodingDescriptor) -> Piece {
            make(data, sourceOffset: offset, encoding: encoding, includesByteOrderMark: offset == 0)
        }

        static func inserted(_ data: Data, encoding: TextEncodingDescriptor) -> Piece {
            make(data, sourceOffset: nil, encoding: encoding, includesByteOrderMark: false)
        }

        private static func make(
            _ data: Data,
            sourceOffset: Int?,
            encoding: TextEncodingDescriptor,
            includesByteOrderMark: Bool
        ) -> Piece {
            return Piece(
                sourceOffset: sourceOffset,
                data: data,
                utf16Length: FileBackedTextDocument.utf16Length(
                    in: data,
                    encoding: encoding,
                    includesByteOrderMark: includesByteOrderMark
                ),
                newlineOffsets: FileBackedTextDocument.newlineOffsets(
                    in: data,
                    encoding: encoding,
                    startingAt: 0,
                    includesByteOrderMark: includesByteOrderMark
                )
            )
        }
    }

    struct Window: Equatable {
        let text: String
        let startByteOffset: Int
        let lineRange: ClosedRange<Int>
    }

    enum LineEnding: String, Codable, Equatable {
        case lf
        case crlf
        case cr
    }

    /// Codable local-only state for session restoration. Remote documents retain
    /// the existing revision-token transport because this core has no range RPC.
    struct RestoreRecord: Codable, Equatable {
        let fileURL: URL
        let encodingIdentifier: TextEncodingDescriptor.Identifier
        let lineEnding: LineEnding
        let byteCount: Int
        let modificationDate: Date?
        let isRemoteEligible: Bool
    }

    struct SessionState: Codable, Equatable {
        struct Edit: Codable, Equatable {
            let location: Int
            let length: Int
            let replacement: String
        }

        let restoreRecord: RestoreRecord
        let sourceFingerprint: UInt64
        let edits: [Edit]
    }

    let url: URL?
    private var originalData: Data
    private var pieces: [Piece]
    private var lineStarts: [Int]
    private var cachedUTF16Length: Int
    private var lazyFileHandle: FileHandle?
    private var lazyFileByteCount: Int = 0
    private var lazyIndexedByteOffset: Int = 0
    private var lazyIndexedUTF16Length: Int = 0
    private var lazyLineStarts: [Int] = [0]
    private var lazyLineUTF16Starts: [Int] = [0]
    private var lazyEstimatedLineCount = 1
    private var lazyIndexComplete = false

    private var savedFileMetadata: FileMetadata?
    let encodingDescriptor: TextEncodingDescriptor
    private var edits: [SessionState.Edit] = []
    private(set) var isDirty = false
    private var viewportGeneration: UInt64 = 0

    convenience init(url: URL) throws {
        let prefix = try Self.readPrefix(from: url, maximumByteCount: 64 * 1024)
        let prefixDescriptor: TextEncodingDescriptor?
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) {
            prefixDescriptor = TextEncodingDescriptor(identifier: .utf8WithBOM)
        } else if prefix.starts(with: [0xFF, 0xFE]) || prefix.starts(with: [0xFE, 0xFF]) {
            prefixDescriptor = Self.detectEncoding(in: prefix)
        } else if !prefix.isEmpty,
                  Self.completeUTF8PrefixLength(in: prefix, maximumLength: prefix.count).map({ $0 > 0 }) == true {
            prefixDescriptor = .utf8
        } else {
            prefixDescriptor = Self.detectEncoding(in: prefix)
        }
        if let prefixDescriptor {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let byteCount = values.fileSize, byteCount >= 0 else { throw Error.invalidRange }
            try self.init(lazyURL: url, encoding: prefixDescriptor, byteCount: byteCount)
            return
        }
        try self.init(eagerURL: url)
    }

    private init(eagerURL url: URL) throws {
        let data = try Data(contentsOf: url, options: [.alwaysMapped])
        let descriptor = Self.detectEncoding(in: data)
        guard descriptor.decode(data) != nil else {
            throw Error.unsupportedEncoding
        }
        self.url = url
        self.originalData = data
        self.pieces = [.source(data, offset: 0, encoding: descriptor)]
        self.lineStarts = Self.lineStarts(in: data, encoding: descriptor)
        self.cachedUTF16Length = descriptor.decode(data)?.utf16.count ?? 0
        self.lazyFileHandle = nil

        self.savedFileMetadata = try Self.fileMetadata(at: url, fingerprint: Self.fingerprint(of: data))
        self.encodingDescriptor = descriptor
    }

    /// Opens a UTF-8 local source without producing a whole-document `String`.
    /// Callers may use this only after bounded encoding detection selected UTF-8.
    convenience init(url: URL, knownUTF8Encoding encoding: TextEncodingDescriptor) throws {
        guard encoding.identifier == .utf8 || encoding.identifier == .utf8WithBOM else {
            throw Error.unsupportedEncoding
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let byteCount = values.fileSize, byteCount >= 0 else { throw Error.invalidRange }
        try self.init(lazyURL: url, encoding: encoding, byteCount: byteCount)
    }

    convenience init(url: URL, knownEncoding encoding: TextEncodingDescriptor) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let byteCount = values.fileSize, byteCount >= 0 else { throw Error.invalidRange }
        try self.init(lazyURL: url, encoding: encoding, byteCount: byteCount)
    }


    private init(lazyURL url: URL, encoding: TextEncodingDescriptor, byteCount: Int) throws {
        let handle = try FileHandle(forReadingFrom: url)
        let prefixByteCount = min(byteCount, 256 * 1024)
        let rawPrefix = try handle.read(upToCount: prefixByteCount) ?? Data()
        try? handle.close()
        let prefixEnd = Self.completeSegmentLength(in: rawPrefix, encoding: encoding, isFinal: rawPrefix.count >= byteCount)
        guard prefixEnd > 0 || byteCount == 0 else { throw Error.unsupportedEncoding }
        let prefixData = Data(rawPrefix.prefix(prefixEnd))
        let prefixIndex = try Self.indexSegment(in: prefixData, baseByteOffset: 0, encoding: encoding, atDocumentStart: true)
        self.url = url
        self.originalData = Data()
        self.pieces = []
        self.lineStarts = prefixIndex.lineStarts
        self.cachedUTF16Length = prefixIndex.utf16Length
        self.lazyFileHandle = try FileHandle(forReadingFrom: url)
        self.lazyFileByteCount = byteCount
        self.lazyIndexedByteOffset = prefixData.count
        self.lazyIndexedUTF16Length = prefixIndex.utf16Length
        self.lazyLineStarts = prefixIndex.lineStarts
        self.lazyLineUTF16Starts = prefixIndex.lineUTF16Starts
        self.lazyEstimatedLineCount = max(1, Int(Double(prefixIndex.lineStarts.count) * Double(byteCount) / Double(max(1, prefixData.count))))
        self.lazyIndexComplete = prefixData.count >= byteCount
        self.encodingDescriptor = encoding
        self.savedFileMetadata = try? Self.fileMetadata(at: url, fingerprint: 0)
    }

    private init(
        url: URL,
        mappedData: Data,
        encoding: TextEncodingDescriptor,
        utf16Length: Int,
        lineStarts: [Int],
        newlineOffsets: [Int],
        fingerprint: UInt64
    ) {
        self.url = url
        self.originalData = mappedData
        self.pieces = [Piece(
            sourceOffset: 0,
            data: mappedData,
            utf16Length: utf16Length,
            newlineOffsets: newlineOffsets
        )]
        self.lineStarts = lineStarts
        self.cachedUTF16Length = utf16Length
        self.lazyFileHandle = nil

        self.savedFileMetadata = try? Self.fileMetadata(at: url, fingerprint: fingerprint)
        self.encodingDescriptor = encoding
    }

    init(content: String, encoding: TextEncodingDescriptor = .utf8) {
        let data = encoding.encodedData(for: content) ?? Data(content.utf8)
        self.url = nil
        self.originalData = data
        self.pieces = [.source(data, offset: 0, encoding: encoding)]
        self.lineStarts = Self.lineStarts(in: data, encoding: encoding)
        self.cachedUTF16Length = content.utf16.count
        self.lazyFileHandle = nil

        self.savedFileMetadata = nil
        self.encodingDescriptor = encoding
    }

    convenience init(restoring state: SessionState) throws {
        try self.init(url: state.restoreRecord.fileURL)
        try materializeLazyStorageIfNeeded()
        guard let savedFileMetadata,
              savedFileMetadata.byteCount == state.restoreRecord.byteCount,
              savedFileMetadata.modificationDate == state.restoreRecord.modificationDate,
              savedFileMetadata.fingerprint == state.sourceFingerprint else {
            throw Error.externalConflict
        }
        for edit in state.edits {
            try replace(byteRange: NSRange(location: edit.location, length: edit.length), with: edit.replacement)
        }
    }

    var byteCount: Int { lazyFileHandle == nil ? pieces.reduce(0) { $0 + $1.length } : lazyFileByteCount }
    var utf16Length: Int { lazyFileHandle == nil ? cachedUTF16Length : max(cachedUTF16Length, lazyIndexedUTF16Length) }
    var lineCount: Int { lazyFileHandle == nil ? lineStarts.count : max(lazyEstimatedLineCount, lazyLineStarts.count) }
    var storageKind: EditorDocumentStorageKind { .fileBacked }
    var supportsBoundedWindows: Bool { true }


    func viewport(aroundLine line: Int, maximumByteCount: Int) throws -> EditorDocumentViewport {
        if lazyFileHandle != nil {
            let window = try lazyWindow(aroundLine: line, maximumByteCount: maximumByteCount)
            viewportGeneration &+= 1
            return EditorDocumentViewport(text: window.text, startByteOffset: window.startByteOffset, startUTF16Offset: window.startUTF16Offset, lineRange: window.lineRange, generation: viewportGeneration)
        }
        let window = try self.window(aroundLine: line, maximumByteCount: maximumByteCount)
        viewportGeneration &+= 1
        return EditorDocumentViewport(
            text: window.text,
            startByteOffset: window.startByteOffset,
            startUTF16Offset: utf16Offset(atByteOffset: window.startByteOffset),
            lineRange: window.lineRange,
            generation: viewportGeneration
        )
    }

    func replace(
        in viewport: EditorDocumentViewport,
        utf16Range: NSRange,
        with replacement: String
    ) throws {
        guard viewport.generation == viewportGeneration else { throw Error.invalidRange }
        try replace(
            in: Window(
                text: viewport.text,
                startByteOffset: viewport.startByteOffset,
                lineRange: viewport.lineRange
            ),
            utf16Range: utf16Range,
            with: replacement
        )
    }


    func string() -> String {
        try? materializeLazyStorageIfNeeded()
        return (try? text(inByteRange: NSRange(location: 0, length: byteCount))) ?? ""
    }

    func replace(range: NSRange, with replacement: String) throws {
        try replace(utf16Range: range, with: replacement)
    }

    func replace(utf16Range range: NSRange, with replacement: String) throws {
        try materializeLazyStorageIfNeeded()
        guard let start = byteOffset(forUTF16Offset: range.location),
              let end = byteOffset(forUTF16Offset: range.location + range.length),
              end >= start else { throw Error.invalidRange }
        try replace(byteRange: NSRange(location: start, length: end - start), with: replacement)
    }

    func replaceAll(with text: String) throws {
        try materializeLazyStorageIfNeeded()
        let bomLength = Self.byteOrderMarkLength(for: encodingDescriptor)
        try replace(
            byteRange: NSRange(location: bomLength, length: max(0, byteCount - bomLength)),
            with: text
        )
    }

    func markClean() { isDirty = false }
    var restoreRecord: RestoreRecord {
        try? materializeLazyStorageIfNeeded()
        return RestoreRecord(
            fileURL: url!,
            encodingIdentifier: encodingDescriptor.identifier,
            lineEnding: lineEnding,
            byteCount: savedFileMetadata!.byteCount,
            modificationDate: savedFileMetadata!.modificationDate,
            isRemoteEligible: false
        )
    }

    var sessionState: SessionState {
        try? materializeLazyStorageIfNeeded()
        return SessionState(
            restoreRecord: restoreRecord,
            sourceFingerprint: savedFileMetadata!.fingerprint,
            edits: edits
        )
    }

    private var lineEnding: LineEnding {
        try? materializeLazyStorageIfNeeded()
        return Self.lineEnding(in: originalData, encoding: encodingDescriptor)
    }

    func text(inLines lines: ClosedRange<Int>) throws -> String {
        if lazyFileHandle != nil {
            try extendLazyIndex(throughLine: max(0, lines.upperBound))
            guard lines.lowerBound >= 0, lines.upperBound < lazyLineStarts.count else {
                throw Error.invalidRange
            }
            let start = lazyLineStarts[lines.lowerBound]
            let end = lines.upperBound + 1 < lazyLineStarts.count
                ? lazyLineStarts[lines.upperBound + 1]
                : lazyFileByteCount
            return try text(inByteRange: NSRange(location: start, length: end - start))
        }
        guard lines.lowerBound >= 0, lines.upperBound < lineStarts.count else {
            throw Error.invalidRange
        }
        let start = lineStarts[lines.lowerBound]
        let end = lines.upperBound + 1 < lineStarts.count
            ? lineStarts[lines.upperBound + 1]
            : byteCount
        return try text(inByteRange: NSRange(location: start, length: end - start))
    }

    func text(inByteRange range: NSRange) throws -> String {
        if lazyFileHandle != nil {
            let data = try lazyRead(range)
            guard let text = decode(data, beginsAtDocumentStart: range.location == 0) else { throw Error.unsupportedEncoding }
            return text
        }
        let data = try data(inByteRange: range)
        guard let text = decode(data, beginsAtDocumentStart: range.location == 0) else {
            throw Error.unsupportedEncoding
        }
        return text
    }

    func window(aroundLine requestedLine: Int, maximumByteCount: Int) throws -> Window {
        guard maximumByteCount > 0, !lineStarts.isEmpty else { throw Error.invalidRange }
        let centerLine = min(max(0, requestedLine), lineStarts.count - 1)
        var firstLine = centerLine
        var lastLine = centerLine
        var start = lineStarts[centerLine]
        var end = centerLine + 1 < lineStarts.count
            ? lineStarts[centerLine + 1]
            : byteCount

        // Prefer nearby preceding lines so the requested line is not pinned to the
        // top edge, but never exceed the TextKit window's byte budget.
        while firstLine > 0 {
            let candidateStart = lineStarts[firstLine - 1]
            guard end - candidateStart <= maximumByteCount else { break }
            firstLine -= 1
            start = candidateStart
        }
        while lastLine + 1 < lineStarts.count {
            let candidateEnd = lastLine + 2 < lineStarts.count
                ? lineStarts[lastLine + 2]
                : byteCount
            guard candidateEnd - start <= maximumByteCount else { break }
            lastLine += 1
            end = candidateEnd
        }
        let text = try text(inByteRange: NSRange(location: start, length: end - start))
        return Window(text: text, startByteOffset: start, lineRange: firstLine...lastLine)
    }

    private func lazyWindow(aroundLine requestedLine: Int, maximumByteCount: Int) throws -> (text: String, startByteOffset: Int, startUTF16Offset: Int, lineRange: ClosedRange<Int>) {
        guard maximumByteCount > 0 else { throw Error.invalidRange }
        try extendLazyIndex(throughLine: max(0, requestedLine))
        let center = min(max(0, requestedLine), max(0, lazyLineStarts.count - 1))
        var first = center
        var last = center
        var start = lazyLineStarts[center]
        var end = min(lazyFileByteCount, start + maximumByteCount)
        if Self.utf16Endianness(for: encodingDescriptor) != nil {
            end -= (end - start) % 2
            if end <= start { end = min(lazyFileByteCount, start + 2) }
        }
        while first > 0 && end - lazyLineStarts[first - 1] <= maximumByteCount { first -= 1; start = lazyLineStarts[first] }
        try extendLazyIndex(throughByte: end)
        while last + 1 < lazyLineStarts.count && lazyLineStarts[last + 1] < end { last += 1 }
        let data = try lazyRead(NSRange(location: start, length: end - start))
        guard let text = decode(data, beginsAtDocumentStart: start == 0) else { throw Error.unsupportedEncoding }
        return (text, start, lazyUTF16Offset(atByteOffset: start), first...max(first, last))
    }

    private func extendLazyIndex(throughLine targetLine: Int) throws {
        while !lazyIndexComplete && lazyLineStarts.count <= targetLine {
            try extendLazyIndex(throughByte: min(lazyFileByteCount, lazyIndexedByteOffset + 256 * 1024))
        }
    }

    private func extendLazyIndex(throughByte targetByte: Int) throws {
        guard !lazyIndexComplete, let handle = lazyFileHandle else { return }
        let end = min(lazyFileByteCount, max(targetByte, lazyIndexedByteOffset))
        guard end > lazyIndexedByteOffset else { lazyIndexComplete = end >= lazyFileByteCount; return }
        try handle.seek(toOffset: UInt64(lazyIndexedByteOffset))
        let data = try handle.read(upToCount: min(end - lazyIndexedByteOffset + 4, lazyFileByteCount - lazyIndexedByteOffset)) ?? Data()
        let base = lazyIndexedByteOffset
        let validLength = Self.completeSegmentLength(
            in: data,
            encoding: encodingDescriptor,
            isFinal: lazyIndexedByteOffset + data.count >= lazyFileByteCount,
            atDocumentStart: base == 0
        )
        guard validLength > 0 else { throw Error.unsupportedEncoding }
        let validData = Data(data.prefix(validLength))
        let index = try Self.indexSegment(in: validData, baseByteOffset: base, encoding: encodingDescriptor, atDocumentStart: base == 0)
        for offset in index.lineStarts.dropFirst() { lazyLineStarts.append(offset) }
        for offset in index.lineUTF16Starts.dropFirst() { lazyLineUTF16Starts.append(lazyIndexedUTF16Length + offset) }
        lazyIndexedUTF16Length += index.utf16Length
        lazyIndexedByteOffset = base + validData.count
        lazyIndexComplete = lazyIndexedByteOffset >= lazyFileByteCount
        if lazyIndexComplete { cachedUTF16Length = lazyIndexedUTF16Length }
    }

    private func lazyRead(_ range: NSRange) throws -> Data {
        guard range.location >= 0, range.length >= 0, range.location + range.length <= lazyFileByteCount,
              let handle = lazyFileHandle else { throw Error.invalidRange }
        try handle.seek(toOffset: UInt64(range.location))
        return try handle.read(upToCount: range.length) ?? Data()
    }

    private func lazyUTF16Offset(atByteOffset target: Int) -> Int {
        if target <= 0 { return 0 }
        if let index = lazyLineStarts.lastIndex(where: { $0 <= target }), index < lazyLineUTF16Starts.count {
            let lineByteStart = lazyLineStarts[index]
            let lineUTF16Start = lazyLineUTF16Starts[index]
            guard target > lineByteStart,
                  let data = try? lazyRead(NSRange(location: lineByteStart, length: target - lineByteStart)),
                  let text = String(data: data, encoding: .utf8) else { return lineUTF16Start }
            return lineUTF16Start + text.utf16.count
        }
        return lazyIndexedUTF16Length
    }

    func replace(in window: Window, utf16Range range: NSRange, with replacement: String) throws {
        try materializeLazyStorageIfNeeded()
        let windowUTF16Length = (window.text as NSString).length
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= windowUTF16Length else {
            throw Error.invalidRange
        }
        let prefix = (window.text as NSString).substring(to: range.location)
        let selected = (window.text as NSString).substring(with: range)
        guard let prefixData = data(for: prefix, includesByteOrderMark: false),
              let selectedData = data(for: selected, includesByteOrderMark: false) else {
            throw Error.unsupportedEncoding
        }
        let documentStartAdjustment = window.startByteOffset == 0
            ? Self.byteOrderMarkLength(for: encodingDescriptor)
            : 0
        try replace(
            byteRange: NSRange(
                location: window.startByteOffset + documentStartAdjustment + prefixData.count,
                length: selectedData.count
            ),
            with: replacement
        )
    }

    func replace(byteRange rawRange: NSRange, with replacement: String) throws {
        try materializeLazyStorageIfNeeded()
        let total = byteCount
        guard rawRange.location >= 0, rawRange.length >= 0,
              rawRange.location <= total, rawRange.location + rawRange.length <= total else {
            throw Error.invalidRange
        }
        let normalizedReplacement = Self.normalizedLineEndings(in: replacement, to: lineEnding)
        guard let replacementData = data(for: normalizedReplacement, includesByteOrderMark: false) else {
            throw Error.unsupportedEncoding
        }
        let removedUTF16Length = (try? text(inByteRange: rawRange).utf16.count) ?? 0
        var result: [Piece] = []
        var cursor = 0
        let replacementStart = rawRange.location
        let replacementEnd = rawRange.location + rawRange.length
        var inserted = false

        for piece in pieces {
            let pieceStart = cursor
            let pieceEnd = cursor + piece.length
            defer { cursor = pieceEnd }
            if pieceEnd <= replacementStart || pieceStart >= replacementEnd {
                if !inserted, pieceStart >= replacementEnd {
                    if !replacementData.isEmpty { result.append(.inserted(replacementData, encoding: encodingDescriptor)) }
                    inserted = true
                }
                result.append(piece)
                continue
            }
            if replacementStart > pieceStart {
                result.append(slice(piece, 0..<(replacementStart - pieceStart)))
            }
            if !inserted {
                if !replacementData.isEmpty { result.append(.inserted(replacementData, encoding: encodingDescriptor)) }
                inserted = true
            }
            if replacementEnd < pieceEnd {
                result.append(slice(piece, (replacementEnd - pieceStart)..<piece.length))
            }
        }
        if !inserted, !replacementData.isEmpty {
            result.append(.inserted(replacementData, encoding: encodingDescriptor))
        }
        pieces = result
        let insertedUTF16Length = normalizedReplacement.utf16.count
        cachedUTF16Length += insertedUTF16Length - removedUTF16Length
        updateLineStarts(replacingByteRange: rawRange, with: replacementData)
        edits.append(.init(location: rawRange.location, length: rawRange.length, replacement: replacement))
        isDirty = true
        viewportGeneration &+= 1
    }

    func saveAtomically(allowExternalOverwrite: Bool = false) throws {
        try materializeLazyStorageIfNeeded()
        guard isDirty else { return }
        guard let url, savedFileMetadata != nil else { throw Error.externalConflict }
        guard allowExternalOverwrite || !hasExternalConflict() else { throw Error.externalConflict }
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).neon-save-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: temporaryURL)
        do {
            for piece in pieces {
                output.write(piece.data)
            }
            try output.synchronize()
            try output.close()
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            isDirty = false
            lineStarts = lineStartsFromPieceMetadata()
            let savedData = try Data(contentsOf: url, options: [.alwaysMapped])
            self.savedFileMetadata = try Self.fileMetadata(at: url, fingerprint: Self.fingerprint(of: savedData))
            edits.removeAll(keepingCapacity: true)
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// Streams the existing piece table to a new destination without creating
    /// a whole-document string. Transcoding and normalization are intentionally
    /// unavailable on this virtual-document path.
    func saveAtomically(to destinationURL: URL) throws {
        try materializeLazyStorageIfNeeded()
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).neon-save-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: temporaryURL)
        do {
            for piece in pieces {
                output.write(piece.data)
            }
            try output.synchronize()
            try output.close()
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private enum UTF16Endianness {
        case littleEndian
        case bigEndian
    }

    private func decode(_ data: Data, beginsAtDocumentStart: Bool) -> String? {
        if !beginsAtDocumentStart,
           let endianness = Self.utf16Endianness(for: encodingDescriptor) {
            let encoding: String.Encoding = endianness == .littleEndian ? .utf16LittleEndian : .utf16BigEndian
            return String(data: data, encoding: encoding)
        }
        if encodingDescriptor.identifier == .utf8WithBOM, !beginsAtDocumentStart {
            return String(data: data, encoding: .utf8)
        }
        return encodingDescriptor.decode(data)
    }

    private func data(for text: String, includesByteOrderMark: Bool) -> Data? {
        guard includesByteOrderMark else {
            return text.data(using: encodingDescriptor.encoding, allowLossyConversion: false)
        }
        return encodingDescriptor.encodedData(for: text)
    }


    private static func detectEncoding(in data: Data) -> TextEncodingDescriptor {
        if data.starts(with: [0xFF, 0xFE]) {
            return TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return TextEncodingDescriptor(identifier: .utf16BigEndianWithBOM)
        }

        let utf8 = data.starts(with: [0xEF, 0xBB, 0xBF])
            ? TextEncodingDescriptor(identifier: .utf8WithBOM)
            : .utf8
        if utf8.decode(data) != nil { return utf8 }

        let utf16Candidates: [TextEncodingDescriptor] = [
            TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM),
            TextEncodingDescriptor(identifier: .utf16BigEndianWithBOM),
            TextEncodingDescriptor(identifier: .utf16LittleEndian),
            TextEncodingDescriptor(identifier: .utf16BigEndian)
        ]
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            for descriptor in utf16Candidates where descriptor.decode(data) != nil {
                return descriptor
            }
        }

        let legacyCandidates: [TextEncodingDescriptor] = [
            TextEncodingDescriptor(identifier: .windowsCP1251),
            TextEncodingDescriptor(identifier: .windowsCP1252),
            TextEncodingDescriptor(identifier: .isoLatin1),
            TextEncodingDescriptor(identifier: .isoLatin5),
            TextEncodingDescriptor(identifier: .macOSRoman),
            TextEncodingDescriptor(identifier: .ascii)
        ]
        return legacyCandidates.first(where: { $0.decode(data) != nil }) ?? .utf8
    }

    /// Performs encoding detection using only a bounded prefix. UTF-8 and
    /// UTF-16 BOM encodings are eligible for the bounded editor path.
    nonisolated static func boundedEncoding(from prefix: Data) -> TextEncodingDescriptor? {
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) {
            return TextEncodingDescriptor(identifier: .utf8WithBOM)
        }
        if prefix.starts(with: [0xFF, 0xFE]) {
            return TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM)
        }
        if prefix.starts(with: [0xFE, 0xFF]) {
            return TextEncodingDescriptor(identifier: .utf16BigEndianWithBOM)
        }
        if !prefix.isEmpty,
           completeUTF8PrefixLength(in: prefix, maximumLength: prefix.count) == prefix.count {
            return .utf8
        }
        let legacyCandidates: [TextEncodingDescriptor] = [
            TextEncodingDescriptor(identifier: .windowsCP1251),
            TextEncodingDescriptor(identifier: .windowsCP1252),
            TextEncodingDescriptor(identifier: .isoLatin1),
            TextEncodingDescriptor(identifier: .isoLatin5),
            TextEncodingDescriptor(identifier: .macOSRoman),
            TextEncodingDescriptor(identifier: .ascii)
        ]
        return legacyCandidates.first(where: { $0.decode(prefix) != nil })
    }

    private static func validUTF8UTF16Length(in data: Data, skipsBOM: Bool) -> Int? {
        var index = skipsBOM ? 3 : 0
        guard index <= data.count else { return nil }
        var utf16Length = 0
        while index < data.count {
            let first = data[index]
            if first < 0x80 {
                utf16Length += 1
                index += 1
                continue
            }
            let continuationCount: Int
            let minimumScalar: UInt32
            var scalar: UInt32
            switch first {
            case 0xC2...0xDF:
                continuationCount = 1; minimumScalar = 0x80; scalar = UInt32(first & 0x1F)
            case 0xE0...0xEF:
                continuationCount = 2; minimumScalar = 0x800; scalar = UInt32(first & 0x0F)
            case 0xF0...0xF4:
                continuationCount = 3; minimumScalar = 0x10000; scalar = UInt32(first & 0x07)
            default:
                return nil
            }
            guard index + continuationCount < data.count else { return nil }
            for offset in 1...continuationCount {
                let byte = data[index + offset]
                guard byte & 0xC0 == 0x80 else { return nil }
                scalar = (scalar << 6) | UInt32(byte & 0x3F)
            }
            guard scalar >= minimumScalar,
                  scalar <= 0x10FFFF,
                  !(0xD800...0xDFFF).contains(scalar) else { return nil }
            utf16Length += scalar >= 0x10000 ? 2 : 1
            index += continuationCount + 1
        }
        return utf16Length
    }

    private struct UTF8Index {
        let utf16Length: Int
        let lineStarts: [Int]
        let lineUTF16Starts: [Int]
        let newlineOffsets: [Int]
        let fingerprint: UInt64
    }

    private static func indexUTF8(in data: Data, skipsBOM: Bool) throws -> UTF8Index {
        let start = skipsBOM ? 3 : 0
        guard start <= data.count else { throw Error.unsupportedEncoding }
        return try data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return UTF8Index(utf16Length: 0, lineStarts: [0], lineUTF16Starts: [0], newlineOffsets: [], fingerprint: Self.fingerprint(of: data))
            }
            var index = start
            var utf16Length = 0
            var lineStarts = [0]
            var lineUTF16Starts = [0]
            var newlineOffsets: [Int] = []
            var fingerprint = UInt64(0xcbf29ce484222325)
            while index < data.count {
                let first = bytes[index]
                if first < 0x80 {
                    utf16Length += 1
                    index += 1
                    if first == 0x0A {
                        lineStarts.append(index)
                        lineUTF16Starts.append(utf16Length)
                        newlineOffsets.append(index)
                    }
                    fingerprint = (fingerprint ^ UInt64(first)) &* 0x100000001b3
                    continue
                }
                let continuationCount: Int
                let minimumScalar: UInt32
                var scalar: UInt32
                switch first {
                case 0xC2...0xDF: continuationCount = 1; minimumScalar = 0x80; scalar = UInt32(first & 0x1F)
                case 0xE0...0xEF: continuationCount = 2; minimumScalar = 0x800; scalar = UInt32(first & 0x0F)
                case 0xF0...0xF4: continuationCount = 3; minimumScalar = 0x10000; scalar = UInt32(first & 0x07)
                default: throw Error.unsupportedEncoding
                }
                guard index + continuationCount < data.count else { throw Error.unsupportedEncoding }
                for offset in 1...continuationCount {
                    let byte = bytes[index + offset]
                    guard byte & 0xC0 == 0x80 else { throw Error.unsupportedEncoding }
                    scalar = (scalar << 6) | UInt32(byte & 0x3F)
                }
                guard scalar >= minimumScalar, scalar <= 0x10FFFF, !(0xD800...0xDFFF).contains(scalar) else {
                    throw Error.unsupportedEncoding
                }
                for offset in 0...continuationCount {
                    fingerprint = (fingerprint ^ UInt64(bytes[index + offset])) &* 0x100000001b3
                }
                utf16Length += scalar >= 0x10000 ? 2 : 1
                index += continuationCount + 1
            }
            return UTF8Index(utf16Length: utf16Length, lineStarts: lineStarts, lineUTF16Starts: lineUTF16Starts, newlineOffsets: newlineOffsets, fingerprint: fingerprint)
        }
    }

    private nonisolated static func completeUTF8PrefixLength(in data: Data, maximumLength: Int) -> Int? {
        let limit = min(maximumLength, data.count)
        guard limit > 0 else { return 0 }
        if String(data: data.prefix(limit), encoding: .utf8) != nil { return limit }
        let lowerBound = max(0, limit - 4)
        for candidate in stride(from: limit - 1, through: lowerBound, by: -1) {
            if String(data: data.prefix(candidate), encoding: .utf8) != nil { return candidate }
        }
        return nil
    }



    private static func completeSegmentLength(in data: Data, encoding: TextEncodingDescriptor, isFinal: Bool, atDocumentStart: Bool = true) -> Int {
        if isFinal { return data.count }
        if let endianness = utf16Endianness(for: encoding) {
            let bom = atDocumentStart ? byteOrderMarkLength(for: encoding) : 0
            var length = bom + max(0, data.count - bom) / 2 * 2
            if !isFinal, length >= bom + 2 {
                let unitOffset = length - 2
                let first = data[unitOffset]
                let second = data[unitOffset + 1]
                let unit = endianness == .littleEndian
                    ? UInt16(first) | (UInt16(second) << 8)
                    : (UInt16(first) << 8) | UInt16(second)
                if (0xD800...0xDBFF).contains(unit) {
                    length -= 2
                }
            }
            return length
        }
        if encoding.identifier == .utf8 || encoding.identifier == .utf8WithBOM {
            let newlineEnd = data.lastIndex(of: 0x0A).map { data.distance(from: data.startIndex, to: $0) + 1 } ?? data.count
            return completeUTF8PrefixLength(in: data, maximumLength: newlineEnd) ?? 0
        }
        return data.lastIndex(of: 0x0A).map { data.distance(from: data.startIndex, to: $0) + 1 } ?? data.count
    }

    private static func indexSegment(in data: Data, baseByteOffset: Int, encoding: TextEncodingDescriptor, atDocumentStart: Bool) throws -> UTF8Index {
        if encoding.identifier == .utf8 || encoding.identifier == .utf8WithBOM {
            let index = try indexUTF8(in: data, skipsBOM: atDocumentStart && encoding.identifier == .utf8WithBOM)
            return UTF8Index(utf16Length: index.utf16Length, lineStarts: index.lineStarts.map { baseByteOffset + $0 }, lineUTF16Starts: index.lineUTF16Starts, newlineOffsets: index.newlineOffsets.map { baseByteOffset + $0 }, fingerprint: index.fingerprint)
        }
        let bom = atDocumentStart ? byteOrderMarkLength(for: encoding) : 0
        let payload = Data(data.dropFirst(min(bom, data.count)))
        guard let text = String(data: payload, encoding: encoding.encoding) else { throw Error.unsupportedEncoding }
        var starts = [baseByteOffset]
        var utf16Starts = [0]
        var newlines: [Int] = []
        var utf16 = 0
        var byteOffset = bom
        for scalar in text.unicodeScalars {
            byteOffset += (String(scalar).data(using: encoding.encoding) ?? Data()).count
            utf16 += scalar.utf16.count
            if scalar.value == 10 {
                let absolute = baseByteOffset + byteOffset
                starts.append(absolute)
                utf16Starts.append(utf16)
                newlines.append(absolute)
            }
        }
        return UTF8Index(utf16Length: utf16, lineStarts: starts, lineUTF16Starts: utf16Starts, newlineOffsets: newlines, fingerprint: fingerprint(of: data))
    }

    private static func readPrefix(from url: URL, maximumByteCount: Int) throws -> Data {
        guard let input = InputStream(url: url) else { throw Error.invalidRange }
        input.open()
        defer { input.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(64 * 1024, maximumByteCount))
        while result.count < maximumByteCount {
            let amount = input.read(&buffer, maxLength: min(buffer.count, maximumByteCount - result.count))
            if amount < 0 { throw input.streamError ?? Error.invalidRange }
            if amount == 0 { break }
            result.append(buffer, count: amount)
        }
        return result
    }

    private func data(inByteRange range: NSRange) throws -> Data {
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= byteCount else { throw Error.invalidRange }
        var result = Data()
        result.reserveCapacity(range.length)
        var cursor = 0
        let requestedStart = range.location
        let requestedEnd = range.location + range.length
        for piece in pieces {
            let pieceEnd = cursor + piece.length
            let overlapStart = max(cursor, requestedStart)
            let overlapEnd = min(pieceEnd, requestedEnd)
            if overlapStart < overlapEnd {
                result.append(piece.data.subdata(in: (overlapStart - cursor)..<(overlapEnd - cursor)))
            }
            cursor = pieceEnd
            if cursor >= requestedEnd { break }
        }
        return result
    }

    private func slice(_ piece: Piece, _ range: Range<Int>) -> Piece {
        let data = Data(piece.data[range])
        if let sourceOffset = piece.sourceOffset {
            return .source(data, offset: sourceOffset + range.lowerBound, encoding: encodingDescriptor)
        }
        return .inserted(data, encoding: encodingDescriptor)
    }

    func hasExternalConflict() -> Bool {
        try? materializeLazyStorageIfNeeded()
        guard let url,
              let currentValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let savedFileMetadata else { return false }
        guard (currentValues.fileSize ?? 0) == savedFileMetadata.byteCount,
              currentValues.contentModificationDate == savedFileMetadata.modificationDate else {
            return true
        }
        guard let currentData = try? Data(contentsOf: url, options: [.alwaysMapped]) else { return true }
        return Self.fingerprint(of: currentData) != savedFileMetadata.fingerprint
    }

    /// Global operations require the piece-table representation. Opening and
    /// viewport rendering never call this method; they stay range-backed for all
    /// supported encodings. Promotion is deliberately explicit for mutation,
    /// save, conflict, and session operations.
    private func materializeLazyStorageIfNeeded() throws {
        guard let handle = lazyFileHandle else { return }
        do {
            try handle.seek(toOffset: 0)
            let data = try handle.readToEnd() ?? Data()
            let index = try Self.indexSegment(in: data, baseByteOffset: 0, encoding: encodingDescriptor, atDocumentStart: true)
            originalData = data
            pieces = [Piece.source(data, offset: 0, encoding: encodingDescriptor)]
            lineStarts = index.lineStarts
            cachedUTF16Length = index.utf16Length
            if savedFileMetadata?.fingerprint == 0 {
                savedFileMetadata = try? Self.fileMetadata(at: url!, fingerprint: Self.fingerprint(of: data))
            }
        } catch {
            throw error
        }
        try handle.close()
        lazyFileHandle = nil
        lazyFileByteCount = 0
        lazyIndexedByteOffset = 0
        lazyIndexedUTF16Length = 0
        lazyLineStarts = [0]
        lazyLineUTF16Starts = [0]
        lazyEstimatedLineCount = 1
        lazyIndexComplete = true
    }

    private func lineStartsAcrossPieces() -> [Int] {
        guard let endianness = Self.utf16Endianness(for: encodingDescriptor) else {
            var starts = [0]
            var absoluteOffset = 0
            for piece in pieces {
                for (relativeOffset, byte) in piece.data.enumerated() where byte == 0x0A {
                    starts.append(absoluteOffset + relativeOffset + 1)
                }
                absoluteOffset += piece.length
            }
            return starts
        }

        var starts = [0]
        var absoluteOffset = 0
        var pendingByte: UInt8?
        for piece in pieces {
            for byte in piece.data {
                if let firstByte = pendingByte {
                    let unit = endianness == .littleEndian
                        ? UInt16(firstByte) | (UInt16(byte) << 8)
                        : (UInt16(firstByte) << 8) | UInt16(byte)
                    if unit == 0x000A { starts.append(absoluteOffset + 1) }
                    pendingByte = nil
                } else {
                    pendingByte = byte
                }
                absoluteOffset += 1
            }
        }
        return starts
    }

    private func lineStartsFromPieceMetadata() -> [Int] {
        var starts = [0]
        var absoluteOffset = 0
        for piece in pieces {
            starts.append(contentsOf: piece.newlineOffsets.map { absoluteOffset + $0 })
            absoluteOffset += piece.length
        }
        return starts
    }

    /// Updates only the line-index segment touched by an edit. Unchanged suffix
    /// offsets are shifted by the byte delta instead of rescanning all pieces.
    private func updateLineStarts(replacingByteRange range: NSRange, with replacement: Data) {
        let oldEnd = range.location + range.length
        let delta = replacement.count - range.length
        let prefixEnd = firstLineStart(after: range.location)
        let suffixStart = firstLineStart(after: oldEnd)
        var updated = Array(lineStarts[..<prefixEnd])
        updated.append(contentsOf: Self.newlineOffsets(in: replacement, encoding: encodingDescriptor, startingAt: range.location))
        updated.append(contentsOf: lineStarts[suffixStart...].map { $0 + delta })
        lineStarts = updated.isEmpty ? [0] : updated
    }

    private func byteOffset(forUTF16Offset target: Int) -> Int? {
        guard target >= 0 else { return nil }
        var utf16 = 0
        var byteOffset = 0
        for piece in pieces {
            let length = piece.utf16Length
            if target <= utf16 + length {
                let local = target - utf16
                return byteOffset + Self.byteOffset(forUTF16Offset: local, in: piece.data, encoding: encodingDescriptor, includesByteOrderMark: byteOffset == 0)
            }
            utf16 += length
            byteOffset += piece.length
        }
        return target == utf16 ? byteOffset : nil
    }

    private func utf16Offset(atByteOffset target: Int) -> Int {
        guard target > 0 else { return 0 }
        var remaining = target
        var offset = 0
        for piece in pieces {
            if remaining >= piece.length {
                remaining -= piece.length
                offset += piece.utf16Length
            } else {
                guard remaining > 0 else { return offset }
                return offset + Self.utf16Length(in: piece.data.prefix(remaining), encoding: encodingDescriptor, includesByteOrderMark: offset == 0)
            }
        }
        return offset
    }

    private static func newlineOffsets(
        in data: Data,
        encoding: TextEncodingDescriptor,
        startingAt start: Int,
        includesByteOrderMark: Bool = false
    ) -> [Int] {
        if let endian = utf16Endianness(for: encoding) {
            var result: [Int] = []
            var offset = includesByteOrderMark ? utf16BOMLength(for: encoding, data: data) : 0
            while offset + 1 < data.count {
                let unit = endian == .littleEndian
                    ? UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                    : (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
                if unit == 0x000A { result.append(start + offset + 2) }
                offset += 2
            }
            return result
        }
        return data.enumerated().compactMap { offset, byte in
            byte == 0x0A ? start + offset + 1 : nil
        }
    }

    private static func utf16Length(
        in data: Data,
        encoding: TextEncodingDescriptor,
        includesByteOrderMark: Bool
    ) -> Int {
        if utf16Endianness(for: encoding) != nil {
            let bomLength = includesByteOrderMark ? utf16BOMLength(for: encoding, data: data) : 0
            return max(0, data.count - bomLength) / 2
        }
        return encoding.decode(data)?.utf16.count ?? String(decoding: data, as: UTF8.self).utf16.count
    }

    private static func byteOffset(
        forUTF16Offset target: Int,
        in data: Data,
        encoding: TextEncodingDescriptor,
        includesByteOrderMark: Bool
    ) -> Int {
        let bom = includesByteOrderMark ? byteOrderMarkLength(for: encoding) : 0
        guard target > 0 else { return bom }
        if let endian = utf16Endianness(for: encoding) {
            var units = 0
            var offset = bom
            while offset + 1 < data.count {
                let unit = endian == .littleEndian
                    ? UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                    : (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
                let width = (unit >= 0xD800 && unit <= 0xDBFF && offset + 3 < data.count) ? 2 : 1
                if units + width > target { return offset }
                units += width
                offset += 2
                if units == target { return offset }
            }
            return data.count
        }
        guard encoding.identifier == .utf8 || encoding.identifier == .utf8WithBOM else {
            return min(data.count, bom + target)
        }
        var units = 0
        var offset = bom
        while offset < data.count {
            let first = data[offset]
            let width = first < 0x80 ? 1 : (first < 0xE0 ? 2 : (first < 0xF0 ? 3 : 4))
            let unitWidth = width == 4 ? 2 : 1
            if units + unitWidth > target { return offset }
            units += unitWidth
            offset += min(width, data.count - offset)
            if units == target { return offset }
        }
        return data.count
    }

    private func firstLineStart(after offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private static func lineStarts(in data: Data, encoding: TextEncodingDescriptor) -> [Int] {
        guard let utf16Endianness = utf16Endianness(for: encoding) else {
            return byteLineStarts(in: data)
        }
        let bomLength = utf16BOMLength(for: encoding, data: data)
        var starts = [0]
        var offset = bomLength
        while offset + 1 < data.count {
            let unit: UInt16
            if utf16Endianness == .littleEndian {
                unit = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            } else {
                unit = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
            }
            if unit == 0x000A { starts.append(offset + 2) }
            offset += 2
        }
        return starts
    }

    private static func byteLineStarts(in data: Data) -> [Int] {
        var starts = [0]
        for (offset, byte) in data.enumerated() where byte == 0x0A {
            starts.append(offset + 1)
        }
        return starts
    }

    private static func byteOrderMarkLength(for descriptor: TextEncodingDescriptor) -> Int {
        switch descriptor.identifier {
        case .utf8WithBOM: return 3
        case .utf16LittleEndianWithBOM, .utf16BigEndianWithBOM: return 2
        default: return 0
        }
    }

    private static func utf16Endianness(for descriptor: TextEncodingDescriptor) -> UTF16Endianness? {
        switch descriptor.identifier {
        case .utf16LittleEndian, .utf16LittleEndianWithBOM:
            return .littleEndian
        case .utf16BigEndian, .utf16BigEndianWithBOM:
            return .bigEndian
        default:
            return nil
        }
    }

    private static func utf16BOMLength(for descriptor: TextEncodingDescriptor, data: Data) -> Int {
        switch descriptor.identifier {
        case .utf16LittleEndianWithBOM where data.starts(with: [0xFF, 0xFE]),
             .utf16BigEndianWithBOM where data.starts(with: [0xFE, 0xFF]):
            return 2
        default:
            return 0
        }
    }

    private static func lineEnding(in data: Data, encoding: TextEncodingDescriptor) -> LineEnding {
        guard let endianness = utf16Endianness(for: encoding) else {
            for index in data.indices where data[index] == 0x0A {
                if index > data.startIndex, data[data.index(before: index)] == 0x0D {
                    return .crlf
                }
                return .lf
            }
            return data.contains(0x0D) ? .cr : .lf
        }

        var sawCarriageReturn = false
        var offset = utf16BOMLength(for: encoding, data: data)
        while offset + 1 < data.count {
            let unit = endianness == .littleEndian
                ? UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                : (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
            if unit == 0x000A { return sawCarriageReturn ? .crlf : .lf }
            sawCarriageReturn = unit == 0x000D
            offset += 2
        }
        return sawCarriageReturn ? .cr : .lf
    }

    private static func normalizedLineEndings(in text: String, to lineEnding: LineEnding) -> String {
        let lfText = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        switch lineEnding {
        case .lf: return lfText
        case .crlf: return lfText.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr: return lfText.replacingOccurrences(of: "\n", with: "\r")
        }
    }

    private struct FileMetadata: Equatable {
        let byteCount: Int
        let modificationDate: Date?
        let fingerprint: UInt64
    }

    private static func fileMetadata(at url: URL, fingerprint: UInt64) throws -> FileMetadata {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileMetadata(
            byteCount: values.fileSize ?? 0,
            modificationDate: values.contentModificationDate,
            fingerprint: fingerprint
        )
    }

    private static func fingerprint(of data: Data) -> UInt64 {
        data.reduce(UInt64(0xcbf29ce484222325)) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x100000001b3
        }
    }
}
