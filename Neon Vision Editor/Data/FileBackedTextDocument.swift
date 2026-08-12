import Foundation

/// A UTF-8 text document whose unchanged source stays memory-mapped on disk.
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
    private let originalData: Data
    private var pieces: [Piece]
    private var lineStarts: [Int]
    private var cachedUTF16Length: Int
    private var savedFileMetadata: FileMetadata?
    let encodingDescriptor: TextEncodingDescriptor
    private var edits: [SessionState.Edit] = []
    private(set) var isDirty = false
    private var viewportGeneration: UInt64 = 0

    init(url: URL) throws {
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

        self.savedFileMetadata = try Self.fileMetadata(at: url)
        self.encodingDescriptor = descriptor
    }

    init(content: String, encoding: TextEncodingDescriptor = .utf8) {
        let data = encoding.encodedData(for: content) ?? Data(content.utf8)
        self.url = nil
        self.originalData = data
        self.pieces = [.source(data, offset: 0, encoding: encoding)]
        self.lineStarts = Self.lineStarts(in: data, encoding: encoding)
        self.cachedUTF16Length = content.utf16.count

        self.savedFileMetadata = nil
        self.encodingDescriptor = encoding
    }

    convenience init(restoring state: SessionState) throws {
        try self.init(url: state.restoreRecord.fileURL)
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

    var byteCount: Int { pieces.reduce(0) { $0 + $1.length } }
    var utf16Length: Int { cachedUTF16Length }
    var lineCount: Int { lineStarts.count }
    var storageKind: EditorDocumentStorageKind { .fileBacked }
    var supportsBoundedWindows: Bool { true }


    func viewport(aroundLine line: Int, maximumByteCount: Int) throws -> EditorDocumentViewport {
        let window = try self.window(aroundLine: line, maximumByteCount: maximumByteCount)
        viewportGeneration &+= 1
        return EditorDocumentViewport(
            text: window.text,
            startByteOffset: window.startByteOffset,
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
        (try? text(inByteRange: NSRange(location: 0, length: byteCount))) ?? ""
    }

    func replace(range: NSRange, with replacement: String) {
        replace(utf16Range: range, with: replacement)
    }

    func replace(utf16Range range: NSRange, with replacement: String) {
        guard let start = byteOffset(forUTF16Offset: range.location),
              let end = byteOffset(forUTF16Offset: range.location + range.length),
              end >= start else { return }
        try? replace(byteRange: NSRange(location: start, length: end - start), with: replacement)
    }

    func replaceAll(with text: String) {
        let bomLength = Self.byteOrderMarkLength(for: encodingDescriptor)
        try? replace(
            byteRange: NSRange(location: bomLength, length: max(0, byteCount - bomLength)),
            with: text
        )
    }

    func markClean() { isDirty = false }
    var restoreRecord: RestoreRecord {
        RestoreRecord(
            fileURL: url!,
            encodingIdentifier: encodingDescriptor.identifier,
            lineEnding: lineEnding,
            byteCount: savedFileMetadata!.byteCount,
            modificationDate: savedFileMetadata!.modificationDate,
            isRemoteEligible: false
        )
    }

    var sessionState: SessionState {
        SessionState(
            restoreRecord: restoreRecord,
            sourceFingerprint: savedFileMetadata!.fingerprint,
            edits: edits
        )
    }

    private var lineEnding: LineEnding {
        Self.lineEnding(in: originalData, encoding: encodingDescriptor)
    }

    func text(inLines lines: ClosedRange<Int>) throws -> String {
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

    func replace(in window: Window, utf16Range range: NSRange, with replacement: String) throws {
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
            self.savedFileMetadata = try Self.fileMetadata(at: url)
            edits.removeAll(keepingCapacity: true)
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
        guard let url, let savedFileMetadata else { return false }
        guard let currentMetadata = try? Self.fileMetadata(at: url) else { return true }
        return currentMetadata != savedFileMetadata
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
        if let endianness = Self.utf16Endianness(for: encodingDescriptor) {
            let bom = Self.byteOrderMarkLength(for: encodingDescriptor)
            return min(byteCount, bom + target * 2)
        }
        var utf16 = 0
        var byteOffset = 0
        for piece in pieces {
            let length = piece.utf16Length
            if target <= utf16 + length {
                let local = target - utf16
                guard let text = decode(piece.data, beginsAtDocumentStart: byteOffset == 0) else { return nil }
                let prefix = String(decoding: text.utf16.prefix(local), as: UTF16.self)
                let prefixByteOffset = prefix.data(using: encodingDescriptor.encoding)?.count ?? 0
                let documentStartAdjustment = byteOffset == 0
                    ? Self.byteOrderMarkLength(for: encodingDescriptor)
                    : 0
                return byteOffset + documentStartAdjustment + prefixByteOffset
            }
            utf16 += length
            byteOffset += piece.length
        }
        return target == utf16 ? byteOffset : nil
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

    private static func fileMetadata(at url: URL) throws -> FileMetadata {
        let data = try Data(contentsOf: url, options: [.alwaysMapped])
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileMetadata(
            byteCount: values.fileSize ?? 0,
            modificationDate: values.contentModificationDate,
            fingerprint: fingerprint(of: data)
        )
    }

    private static func fingerprint(of data: Data) -> UInt64 {
        data.reduce(UInt64(0xcbf29ce484222325)) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x100000001b3
        }
    }
}
