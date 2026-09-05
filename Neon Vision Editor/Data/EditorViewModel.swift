import SwiftUI
import Observation
import UniformTypeIdentifiers
import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Text Sanitization
// Normalizes pasted and loaded text before it reaches editor state.
enum EditorTextSanitizer {
    // Converts control/marker glyphs into safe spaces/newlines and removes unsupported scalars.
    nonisolated static func sanitize(_ input: String) -> String {
        // Normalize line endings first so CRLF does not become double newlines.
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var result = String.UnicodeScalarView()
        result.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars {
            switch scalar {
            case "\n":
                result.append(scalar)
            case "\t", "\u{000B}", "\u{000C}":
                result.append(" ")
            case "\u{00A0}":
                result.append(" ")
            case "\u{00B7}", "\u{2022}", "\u{2219}", "\u{237D}", "\u{2420}", "\u{2422}", "\u{2423}", "\u{2581}":
                result.append(" ")
            case "\u{00BB}", "\u{2192}", "\u{21E5}":
                result.append(" ")
            case "\u{00B6}", "\u{21A9}", "\u{21B2}", "\u{21B5}", "\u{23CE}", "\u{2424}", "\u{2425}":
                result.append("\n")
            case "\u{240A}", "\u{240D}":
                result.append("\n")
            default:
                let cat = scalar.properties.generalCategory
                if cat == .format || cat == .control || cat == .lineSeparator || cat == .paragraphSeparator {
                    continue
                }
                if (0x2400...0x243F).contains(scalar.value) {
                    continue
                }
                if cat == .spaceSeparator && scalar != " " && scalar != "\t" {
                    result.append(" ")
                    continue
                }
                result.append(scalar)
            }
        }
        return String(result)
    }
}

enum TextLineEnding: String, Sendable {
    case lf
    case crlf

    nonisolated var displayName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        }
    }

    nonisolated static func detect(in text: String) -> TextLineEnding {
        text.contains("\r\n") ? .crlf : .lf
    }

    nonisolated func applying(to normalizedText: String) -> String {
        guard self == .crlf else { return normalizedText }
        return normalizedText.replacingOccurrences(of: "\n", with: "\r\n")
    }
}

struct DecodedFileText: Sendable {
    nonisolated let text: String
    nonisolated let encoding: TextEncodingDescriptor
    nonisolated let lineEnding: TextLineEnding

    nonisolated init(text: String, encoding: TextEncodingDescriptor) {
        self.text = text
        self.encoding = encoding
        self.lineEnding = TextLineEnding.detect(in: text)
    }

    nonisolated var encodingRawValue: UInt { encoding.encodingRawValue }
}

private enum EditorLoadHelper {
    // Sidebar-opened project files should reach the editor quickly; full scalar-by-scalar
    // sanitization is only worth the cost for smaller documents.
    nonisolated static let fastLoadSanitizeByteThreshold = 512_000
    nonisolated static let largeFileCandidateByteThreshold = 2_000_000
    // A partial read prevents multi-hundred-megabyte logs from being copied into the
    // text system. The result is intentionally read-only so it can never overwrite
    // the source with an incomplete buffer.
    nonisolated static let partialOpenByteThreshold = 100_000_000
    nonisolated static let partialOpenPreviewByteLimit = 4_000_000
    // Structured documents can make TextKit, syntax highlighting, and WebKit
    // parse the entire source repeatedly. Keep these large opens responsive by
    // showing a bounded read-only source preview first.
    nonisolated static let largeStructuredTextPreviewByteThreshold = 100_000_000
    nonisolated static let largeStructuredTextPreviewByteLimit = 1_000_000
    // Every format uses the bounded path at this size. Materializing arbitrarily
    // large text in TextKit is what makes opening appear to hang.
    nonisolated static let hugeTextPreviewByteThreshold = 100_000_000
    nonisolated static let hugeTextPreviewByteLimit = 1_000_000
    nonisolated static let structuredTextPreviewExtensions: Set<String> = [
        "css", "csv", "html", "htm", "ipynb", "json", "js", "jsx", "md",
        "markdown", "plist", "svg", "toml", "ts", "tsx", "xml", "xhtml",
        "yaml", "yml"
    ]

    nonisolated static func boundedPreviewLimit(forExtension fileExtension: String, byteCount: Int) -> Int? {
        let normalizedExtension = fileExtension.lowercased()
        if structuredTextPreviewExtensions.contains(normalizedExtension),
           byteCount >= largeStructuredTextPreviewByteThreshold {
            return largeStructuredTextPreviewByteLimit
        }
        if byteCount >= hugeTextPreviewByteThreshold {
            return hugeTextPreviewByteLimit
        }
        return nil
    }
    nonisolated static let skipFingerprintByteThreshold = 1_000_000
    nonisolated static let streamChunkBytes = 262_144

    nonisolated static func sanitizeTextForFileLoad(_ input: String, useFastPath _: Bool) -> String {
        // File contents are not pasted display markers: preserve tabs, ANSI
        // escapes and Unicode formatting. Only normalize the editor's newlines.
        guard input.contains("\r") else { return input }
        return input.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    nonisolated static func decodeFileText(
        _ data: Data,
        fileURL: URL,
        preferredLanguageHint: String?,
        isLargeCandidate: Bool,
        preferredEncoding: TextEncodingDescriptor? = nil,
        allowsFullFileFallback: Bool = true
    ) -> DecodedFileText {
        if let preferredEncoding,
           let decoded = preferredEncoding.decode(data) {
            return DecodedFileText(text: decoded, encoding: preferredEncoding)
        }
        let lowerHint = preferredLanguageHint?.lowercased() ?? ""
        let prefersJSONFastDecode = isLargeCandidate &&
            (lowerHint == "json" || lowerHint == "jsonc" || lowerHint == "json5" || lowerHint == "ipynb")
        let likelyUTF16 = looksLikeUTF16(data)

        if prefersJSONFastDecode && !likelyUTF16 {
            // Large JSON payloads are overwhelmingly UTF-8 in practice; decode directly to
            // avoid extra validation/fallback passes before first render.
            return DecodedFileText(
                text: String(decoding: data, as: UTF8.self),
                encoding: .utf8
            )
        }

        let utf8Encoding = data.starts(with: [0xEF, 0xBB, 0xBF])
            ? TextEncodingDescriptor(identifier: .utf8WithBOM)
            : .utf8
        if let utf8 = utf8Encoding.decode(data) {
            return DecodedFileText(text: utf8, encoding: utf8Encoding)
        }

        if likelyUTF16 {
            let utf16Candidates: [TextEncodingDescriptor] = [
                TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM),
                TextEncodingDescriptor(identifier: .utf16BigEndianWithBOM),
                TextEncodingDescriptor(identifier: .utf16LittleEndian),
                TextEncodingDescriptor(identifier: .utf16BigEndian)
            ]
            for encoding in utf16Candidates {
                if let decoded = encoding.decode(data) {
                    return DecodedFileText(text: decoded, encoding: encoding)
                }
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
        for encoding in legacyCandidates {
            if let decoded = encoding.decode(data) {
                return DecodedFileText(text: decoded, encoding: encoding)
            }
        }

        if allowsFullFileFallback,
           let fallback = try? String(contentsOf: fileURL, encoding: .utf8) {
            return DecodedFileText(text: fallback, encoding: .utf8)
        }
        return DecodedFileText(
            text: String(decoding: data, as: UTF8.self),
            encoding: .utf8
        )
    }

    nonisolated private static func looksLikeUTF16(_ data: Data) -> Bool {
        if data.count >= 2 {
            let b0 = data[data.startIndex]
            let b1 = data[data.startIndex + 1]
            if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF) {
                return true
            }
        }

        guard data.count >= 8 else { return false }
        let sampleCount = min(1024, data.count - (data.count % 2))
        if sampleCount <= 0 { return false }

        var evenNuls = 0
        var oddNuls = 0
        var idx = 0
        while idx < sampleCount {
            if data[data.startIndex + idx] == 0 { evenNuls += 1 }
            if data[data.startIndex + idx + 1] == 0 { oddNuls += 1 }
            idx += 2
        }

        let pairs = sampleCount / 2
        let evenRatio = Double(evenNuls) / Double(pairs)
        let oddRatio = Double(oddNuls) / Double(pairs)
        let totalRatio = Double(evenNuls + oddNuls) / Double(sampleCount)
        return totalRatio > 0.20 && (evenRatio > 0.35 || oddRatio > 0.35)
    }

    nonisolated static func streamFileData(from url: URL) throws -> Data {
        guard let input = InputStream(url: url) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        input.open()
        defer { input.close() }

        var aggregate = Data()
        if let expectedSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           expectedSize > 0 {
            aggregate.reserveCapacity(expectedSize)
        }
        var buffer = [UInt8](repeating: 0, count: streamChunkBytes)

        while true {
            let bytesRead = input.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                throw input.streamError ?? CocoaError(.fileReadUnknown)
            }
            if bytesRead == 0 {
                if input.streamStatus == .atEnd || input.streamStatus == .closed {
                    break
                }
                continue
            }
            aggregate.append(buffer, count: bytesRead)
        }

        if let expectedSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           expectedSize > 0,
           aggregate.count < expectedSize {
            // Fallback for rare short-read stream behavior.
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }

        return aggregate
    }

    nonisolated static func partialFileData(from url: URL, maximumByteCount: Int) throws -> Data {
        guard let input = InputStream(url: url) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        input.open()
        defer { input.close() }

        var data = Data()
        data.reserveCapacity(maximumByteCount)
        var buffer = [UInt8](repeating: 0, count: min(streamChunkBytes, maximumByteCount))
        while data.count < maximumByteCount {
            let remaining = maximumByteCount - data.count
            let bytesRead = input.read(&buffer, maxLength: min(buffer.count, remaining))
            if bytesRead < 0 {
                throw input.streamError ?? CocoaError(.fileReadUnknown)
            }
            if bytesRead == 0 { break }
            data.append(buffer, count: bytesRead)
        }
        return data
    }

    nonisolated static func partialPreviewText(_ text: String, totalByteCount: Int) -> String {
        let lineBoundedText: String
        if let lastLineBreak = text.lastIndex(of: "\n") {
            lineBoundedText = String(text[..<lastLineBreak])
        } else {
            lineBoundedText = text
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(totalByteCount), countStyle: .file)
        return "\(lineBoundedText)\n\n[Partial read-only preview: first \(ByteCountFormatter.string(fromByteCount: Int64(partialOpenPreviewByteLimit), countStyle: .file)) of \(size). Open a smaller range or split the file to edit it.]"
    }
}

private struct EditorFileLoadResult: Sendable {
    let content: String
    let fileEncodingRawValue: UInt
    let fileEncoding: TextEncodingDescriptor
    let lineEnding: TextLineEnding
    let detectedLanguage: String
    let languageLocked: Bool
    let fingerprint: UInt64?
    let fileModificationDate: Date?
    let isLargeCandidate: Bool
    let byteCount: Int
    let isPartialPreview: Bool
    let fileBackedEncoding: TextEncodingDescriptor?
    let fileBackedDocument: FileBackedTextDocument?
}

private struct EditorFileSavePayload: Sendable {
    let content: String
    let fingerprint: UInt64
}

// MARK: - Tab Model
// Represents one editor tab and its mutable editing state.
@MainActor
@Observable
final class TabData: Identifiable {
    let id: UUID
    fileprivate(set) var name: String
    private var contentStorage: any EditorDocument
    var fileBackedDocument: FileBackedTextDocument? {
        guard let document = contentStorage as? FileBackedTextDocument,
              document.url != nil else { return nil }
        return document
    }
    private(set) var contentRevision: Int = 0
    private(set) var externalContentRevision: Int = 0
    fileprivate(set) var language: String
    fileprivate(set) var fileURL: URL?
    fileprivate(set) var languageLocked: Bool
    fileprivate(set) var isDirty: Bool
    fileprivate(set) var lastSavedFingerprint: UInt64?
    fileprivate(set) var lastKnownFileModificationDate: Date?
    fileprivate(set) var isLoadingContent: Bool
    fileprivate(set) var isLargeFileCandidate: Bool
    fileprivate(set) var fileEncodingRawValue: UInt
    fileprivate(set) var fileEncoding: TextEncodingDescriptor
    fileprivate(set) var usesAutomaticFileEncoding: Bool
    fileprivate(set) var lineEnding: TextLineEnding
    fileprivate(set) var remotePreviewPath: String?
    fileprivate(set) var remoteRevisionToken: String?
    fileprivate(set) var isReadOnlyPreview: Bool
    fileprivate(set) var isPartialFilePreview: Bool
    fileprivate(set) var fileByteCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        language: String,
        fileURL: URL?,
        languageLocked: Bool = false,
        isDirty: Bool = false,
        lastSavedFingerprint: UInt64? = nil,
        lastKnownFileModificationDate: Date? = nil,
        isLoadingContent: Bool = false,
        isLargeFileCandidate: Bool = false,
        fileEncodingRawValue: UInt = String.Encoding.utf8.rawValue,
        fileEncoding: TextEncodingDescriptor? = nil,
        usesAutomaticFileEncoding: Bool = true,
        lineEnding: TextLineEnding = .lf,
        remotePreviewPath: String? = nil,
        remoteRevisionToken: String? = nil,
        isReadOnlyPreview: Bool = false,
        isPartialFilePreview: Bool = false,
        fileByteCount: Int = 0,
        fileBackedDocument: FileBackedTextDocument? = nil
    ) {
        self.id = id
        self.name = name
        self.contentStorage = fileBackedDocument ?? FileBackedTextDocument(content: content, encoding: fileEncoding ?? .utf8)
        self.language = language
        self.fileURL = fileURL
        self.languageLocked = languageLocked
        self.isDirty = isDirty
        self.lastSavedFingerprint = lastSavedFingerprint
        self.lastKnownFileModificationDate = lastKnownFileModificationDate
        self.isLoadingContent = isLoadingContent
        self.isLargeFileCandidate = isLargeFileCandidate
        let resolvedEncoding = fileEncoding ?? TextEncodingDescriptor.descriptor(forRawValue: fileEncodingRawValue)
        self.fileEncodingRawValue = resolvedEncoding.encodingRawValue
        self.fileEncoding = resolvedEncoding
        self.usesAutomaticFileEncoding = usesAutomaticFileEncoding
        self.lineEnding = lineEnding
        self.remotePreviewPath = remotePreviewPath
        self.remoteRevisionToken = remoteRevisionToken
        self.isReadOnlyPreview = isReadOnlyPreview
        self.isPartialFilePreview = isPartialFilePreview
        self.fileByteCount = fileByteCount
    }

    var document: any EditorDocument {
        _ = contentRevision
        return contentStorage
    }


    var isRemoteDocument: Bool { remotePreviewPath != nil }
    var usesFileBackedStorage: Bool { fileBackedDocument != nil && !isRemoteDocument }

    func attachFileBackedDocument(_ document: FileBackedTextDocument?) {
        guard !isRemoteDocument else { return }
        guard let document else { return }
        contentStorage = document
    }

    /// Installs a freshly loaded local document without replacing its piece-table
    /// source with the loader's compatibility string projection.
    @discardableResult
    func installLoadedFileBackedDocument(_ document: FileBackedTextDocument) -> Bool {
        guard !isRemoteDocument else { return false }
        contentStorage = document
        document.markClean()
        isDirty = false
        contentRevision &+= 1
        return true
    }


    @discardableResult
    func replaceContentStorage(
        with text: String,
        markDirty: Bool = false,
        compareIfLengthAtMost equalityCheckUTF16Length: Int? = nil
    ) -> Bool {
        let previousLength = contentStorage.utf16Length
        let newLength = (text as NSString).length
        if let equalityCheckUTF16Length,
           previousLength == newLength,
           newLength <= equalityCheckUTF16Length,
           contentStorage.string() == text {
            return false
        }
        do {
            try contentStorage.replaceAll(with: text)
        } catch {
            return false
        }
        contentStorage.markClean()
        contentRevision &+= 1
        if markDirty && !isDirty {
            isDirty = true
        }
        return true
    }

    @discardableResult
    func replaceContent(in range: NSRange, with replacement: String, markDirty: Bool = false) -> Bool {
        let totalLength = contentStorage.utf16Length
        let safeLocation = min(max(0, range.location), totalLength)
        let maxLength = max(0, totalLength - safeLocation)
        let safeLength = min(max(0, range.length), maxLength)
        if safeLength == 0, replacement.isEmpty {
            return false
        }
        do {
            try contentStorage.replace(
                utf16Range: NSRange(location: safeLocation, length: safeLength),
                with: replacement
            )
        } catch {
            return false
        }
        contentRevision &+= 1
        if markDirty && !isDirty {
            isDirty = true
        }
        return true
    }

    @discardableResult
    func replaceContent(in viewport: EditorDocumentViewport, range: NSRange, with replacement: String) -> Bool {
        do {
            try contentStorage.replace(in: viewport, utf16Range: range, with: replacement)
        } catch {
            return false
        }
        contentRevision &+= 1
        isDirty = true
        return true
    }

    func markClean(withFingerprint fingerprint: UInt64?) {
        isDirty = false
        lastSavedFingerprint = fingerprint
    }

    func updateLastKnownFileModificationDate(_ date: Date?) {
        lastKnownFileModificationDate = date
    }

    func updateFileEncodingRawValue(_ rawValue: UInt) {
        updateFileEncoding(TextEncodingDescriptor.descriptor(forRawValue: rawValue), usesAutomatic: true)
    }

    func updateFileEncoding(_ encoding: TextEncodingDescriptor, usesAutomatic: Bool) {
        fileEncoding = encoding
        fileEncodingRawValue = encoding.encodingRawValue
        usesAutomaticFileEncoding = usesAutomatic
    }

    func updateLineEnding(_ lineEnding: TextLineEnding) {
        self.lineEnding = lineEnding
    }

    func updateRemoteRevisionToken(_ token: String?) {
        remoteRevisionToken = token
    }

    func resetContentRevision() {
        contentRevision = 0
    }

    func noteExternalContentRefresh() {
        externalContentRevision &+= 1
    }

    func updateFileByteCount(_ byteCount: Int) {
        fileByteCount = max(0, byteCount)
    }
}

nonisolated private final class OpenDocumentFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    private let observedURL: URL
    private let operationQueue: OperationQueue
    private let changeHandler: @Sendable (URL) -> Void
    private var didStartScopedAccess = false

    var presentedItemURL: URL? { observedURL }
    var presentedItemOperationQueue: OperationQueue { operationQueue }

    init(url: URL, changeHandler: @escaping @Sendable (URL) -> Void) {
        observedURL = url.standardizedFileURL
        self.changeHandler = changeHandler
        operationQueue = OperationQueue()
        operationQueue.name = "h3p.Neon-Vision-Editor.open-file-presenter.\(UUID().uuidString)"
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .utility
        super.init()
        didStartScopedAccess = observedURL.startAccessingSecurityScopedResource()
        NSFileCoordinator.addFilePresenter(self)
    }

    func invalidate() {
        NSFileCoordinator.removeFilePresenter(self)
        if didStartScopedAccess {
            observedURL.stopAccessingSecurityScopedResource()
            didStartScopedAccess = false
        }
    }

    func presentedItemDidChange() {
        changeHandler(observedURL)
    }

    func presentedItemDidMove(to newURL: URL) {
        // Atomic-save implementations commonly move the old inode aside before
        // replacing the original path. Recheck the represented document path.
        changeHandler(observedURL)
        changeHandler(newURL)
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        changeHandler(observedURL)
        completionHandler(nil)
    }
}

nonisolated private final class OpenDocumentObservationCenter: @unchecked Sendable {
    private var presentersByPath: [String: OpenDocumentFilePresenter] = [:]
    private let changeHandler: @Sendable (URL) -> Void

    init(changeHandler: @escaping @Sendable (URL) -> Void) {
        self.changeHandler = changeHandler
    }

    func updateObservedURLs(_ urls: [URL]) {
        let urlsByPath = Dictionary(
            urls.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        for path in Array(presentersByPath.keys) where urlsByPath[path] == nil {
            presentersByPath.removeValue(forKey: path)?.invalidate()
        }
        for (path, url) in urlsByPath where presentersByPath[path] == nil {
            presentersByPath[path] = OpenDocumentFilePresenter(url: url, changeHandler: changeHandler)
        }
    }

    deinit {
        for presenter in presentersByPath.values {
            presenter.invalidate()
        }
    }
}

// MARK: - Editor View Model
// Owns tab lifecycle, file IO, and language-detection behavior.
@MainActor
@Observable
class EditorViewModel {
    // MARK: - Conflict and Snapshot Types

    struct ExternalFileConflictState: Sendable {
        let tabID: UUID
        let fileURL: URL
        let diskModifiedAt: Date?
    }

    struct PendingEncodingReopen: Sendable {
        let tabID: UUID
        let encoding: TextEncodingDescriptor?
    }

    enum ExternalFileRefreshStatusKind: Equatable, Sendable {
        case refreshing
        case refreshed
        case needsReview
    }

    struct ExternalFileRefreshStatus: Equatable, Sendable {
        let kind: ExternalFileRefreshStatusKind
        let message: String
    }

    enum ExternalSyncChangeKind: Equatable, Sendable {
        case refreshed
        case needsReview
    }

    struct ExternalSyncChange: Equatable, Identifiable, Sendable {
        let id: UUID
        let tabID: UUID
        let fileName: String
        let timestamp: Date
        let kind: ExternalSyncChangeKind
    }

    private struct LocalFileMetadata: Equatable, Sendable {
        let modificationDate: Date?
        let byteCount: Int
    }

    struct RemoteSaveIssueState: Sendable {
        let tabID: UUID
        let remotePath: String
        let detail: String
        let isConflict: Bool
        let requiresReconnect: Bool

        var recoveryGuidance: String {
            guard requiresReconnect else { return detail }
            return "\(detail) Detach this device from the broker, then attach again from Settings > Remote using the current Mac attach code."
        }
    }

    struct ExternalFileComparisonSnapshot: Sendable {
        let fileName: String
        let localContent: String
        let diskContent: String
    }

    struct RemoteConflictComparisonSnapshot: Sendable {
        let tabID: UUID
        let fileName: String
        let localContent: String
        let remoteContent: String
    }

    struct DocumentComparisonSnapshot: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let leftTitle: String
        let rightTitle: String
        let leftContent: String
        let rightContent: String
    }

    // MARK: - Tab Command Serialization

    private actor TabCommandQueue {
        private var isLocked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            guard isLocked else {
                isLocked = true
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            if waiters.isEmpty {
                isLocked = false
                return
            }
            let next = waiters.removeFirst()
            next.resume()
        }
    }

    private static let saveSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "FileIO")
    private static let largeContentLanguageBypassUTF16Length = 1_000_000
    private static let deferredLanguageDetectionUTF16Length = 180_000
    private static let deferredLanguageDetectionDelayNanos: UInt64 = 220_000_000
    private static let deferredLanguageDetectionSampleUTF16Length = 180_000
    private static let networkVolumePollingIntervalNanos: UInt64 = 3_000_000_000

    // MARK: - Observable State and Indexes

    private(set) var tabs: [TabData] = []
    private(set) var selectedTabID: UUID?
    var pendingExternalFileConflict: ExternalFileConflictState?
    private(set) var pendingEncodingReopen: PendingEncodingReopen?
    private(set) var externalFileRefreshStatus: ExternalFileRefreshStatus?
    private(set) var recentExternalSyncChanges: [ExternalSyncChange] = []
    private(set) var hasReceivedExternalFileOpenRequest: Bool = false
    var pendingRemoteSaveIssue: RemoteSaveIssueState?
    var fileEncodingErrorMessage: String?
    var showSidebar: Bool = true
    var isBrainDumpMode: Bool = false
    var showingRename: Bool = false
    var renameText: String = ""
    var isLineWrapEnabled: Bool = true
    @ObservationIgnored private let tabCommandQueue = TabCommandQueue()
    @ObservationIgnored private var pendingLanguageDetectionTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var localSaveTasks: [UUID: (id: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var pendingExternalFileRefreshTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingExternalRefreshTabIDs: Set<UUID> = []
    @ObservationIgnored private var refreshedExternalTabIDs: Set<UUID> = []
    @ObservationIgnored private var reviewExternalTabIDs: Set<UUID> = []
    @ObservationIgnored private var externalRefreshStatusClearTask: Task<Void, Never>?
    @ObservationIgnored private var networkVolumePollingTask: Task<Void, Never>?
    @ObservationIgnored private var networkVolumePollingCandidatePaths: Set<String> = []
    @ObservationIgnored private lazy var openDocumentObservationCenter = OpenDocumentObservationCenter { [weak self] url in
        Task { @MainActor [weak self] in
            self?.handleObservedLocalFileChange(at: url)
        }
    }
    @ObservationIgnored private var tabIndexByID: [UUID: Int] = [:]
    @ObservationIgnored private var tabIDByStandardizedFilePath: [String: UUID] = [:]
    private var tabStructureVersion: Int = 0
    private var tabContentVersion: Int = 0
    private var tabMetadataVersion: Int = 0
    private var tabPersistenceVersion: Int = 0
	    
    var selectedTab: TabData? {
        get {
            guard let selectedTabID, let index = tabIndexByID[selectedTabID], tabs.indices.contains(index) else {
                return nil
            }
            return tabs[index]
        }
        set { selectTab(id: newValue?.id) }
    }

    // Targeted observation revisions. Consumers select the narrowest signal that
    // represents their dependency instead of waking for every tab mutation.
    var tabsObservationToken: Int {
        tabStructureVersion
    }
    var tabContentObservationToken: Int { tabContentVersion }
    var tabMetadataObservationToken: Int { tabMetadataVersion }
    var tabPersistenceObservationToken: Int { tabPersistenceVersion }

    private func tabIndex(for tabID: UUID) -> Int? {
        guard let index = tabIndexByID[tabID], tabs.indices.contains(index) else { return nil }
        return index
    }

    private static func normalizedFilePathKey(for url: URL?) -> String? {
        guard let url else { return nil }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func fileIdentityKey(for url: URL?) -> String? {
        guard let url else { return nil }
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]),
              let fileIdentifier = values.fileResourceIdentifier,
              let volumeIdentifier = values.volumeIdentifier else {
            return nil
        }
        return "\(volumeIdentifier):\(fileIdentifier)"
    }

    private func rebuildTabIndexes() {
        tabIndexByID.removeAll(keepingCapacity: true)
        tabIDByStandardizedFilePath.removeAll(keepingCapacity: true)
        tabIndexByID.reserveCapacity(tabs.count)
        tabIDByStandardizedFilePath.reserveCapacity(tabs.count)
        for (index, tab) in tabs.enumerated() {
            tabIndexByID[tab.id] = index
            if let key = Self.normalizedFilePathKey(for: tab.fileURL), tabIDByStandardizedFilePath[key] == nil {
                tabIDByStandardizedFilePath[key] = tab.id
            }
        }
    }

    private enum TabStateChange: Equatable {
        case structure
        case content
        case metadata
    }

    // This is the single post-mutation commit point for `tabs`. Changes to a tab's
    // identity or file URL rebuild both indexes and refresh the
    // file-presenter set. Structure observers advance only for those changes;
    // content and metadata consumers receive their own targeted revisions.
    private func recordTabStateMutation(
        _ change: TabStateChange = .metadata,
        rebuildIndexes: Bool = false
    ) {
        if rebuildIndexes {
            rebuildTabIndexes()
            let observedURLs: [URL] = tabs.compactMap { tab -> URL? in
                guard !tab.isRemoteDocument,
                      let fileURL = tab.fileURL,
                      fileURL.isFileURL else { return nil }
                return fileURL
            }
            openDocumentObservationCenter.updateObservedURLs(observedURLs)
            updateNetworkVolumePolling(for: observedURLs)
        }
        if rebuildIndexes || change == .structure {
            tabStructureVersion &+= 1
        } else if change == .content {
            tabContentVersion &+= 1
        } else {
            tabMetadataVersion &+= 1
        }
        tabPersistenceVersion &+= 1
    }

    // Command pipeline for tab-state mutations.
    private enum TabContentMutation: Sendable {
        case replaceAll(text: String, markDirty: Bool, compareIfLengthAtMost: Int?)
        case replaceRange(range: NSRange, replacement: String, markDirty: Bool)
    }

    struct RestoredTabSnapshot: Sendable {
        let name: String
        let content: String
        let language: String
        let fileURL: URL?
        let languageLocked: Bool
        let isDirty: Bool
        let lastSavedFingerprint: UInt64?
        let lastKnownFileModificationDate: Date?
        let fileEncodingRawValue: UInt
        let fileEncoding: TextEncodingDescriptor?
        let usesAutomaticFileEncoding: Bool
        let lineEnding: TextLineEnding
        let fileBackedSessionState: FileBackedTextDocument.SessionState?

        init(
            name: String,
            content: String,
            language: String,
            fileURL: URL?,
            languageLocked: Bool,
            isDirty: Bool,
            lastSavedFingerprint: UInt64?,
            lastKnownFileModificationDate: Date?,
            fileEncodingRawValue: UInt,
            fileEncoding: TextEncodingDescriptor? = nil,
            usesAutomaticFileEncoding: Bool = true,
            lineEnding: TextLineEnding = .lf,
            fileBackedSessionState: FileBackedTextDocument.SessionState? = nil
        ) {
            self.name = name
            self.content = content
            self.language = language
            self.fileURL = fileURL
            self.languageLocked = languageLocked
            self.isDirty = isDirty
            self.lastSavedFingerprint = lastSavedFingerprint
            self.lastKnownFileModificationDate = lastKnownFileModificationDate
            self.fileEncodingRawValue = fileEncodingRawValue
            self.fileEncoding = fileEncoding
            self.usesAutomaticFileEncoding = usesAutomaticFileEncoding
            self.lineEnding = lineEnding
            self.fileBackedSessionState = fileBackedSessionState
        }
    }

    private enum TabCommand: Sendable {
        case updateContent(tabID: UUID, mutation: TabContentMutation)
        case markSaved(
            tabID: UUID,
            fileURL: URL?,
            fingerprint: UInt64?,
            fileModificationDate: Date?,
            fileEncodingRawValue: UInt?,
            fileByteCount: Int?
        )
        case remapFileURL(tabID: UUID, fileURL: URL)
        case setLanguage(tabID: UUID, language: String, lock: Bool)
        case closeTab(tabID: UUID)
        case addNewTab(name: String, language: String)
        case addPlaceholderTab(
            tabID: UUID,
            name: String,
            language: String,
            fileURL: URL?,
            languageLocked: Bool,
            isLargeCandidate: Bool
        )
        case replaceCleanTabWithPlaceholder(
            tabID: UUID,
            name: String,
            language: String,
            fileURL: URL?,
            languageLocked: Bool,
            isLargeCandidate: Bool
        )
        case replaceTabWithPlaceholder(
            tabID: UUID,
            name: String,
            language: String,
            fileURL: URL?,
            languageLocked: Bool,
            isLargeCandidate: Bool
        )
        case selectTab(tabID: UUID?)
        case moveTabBefore(tabID: UUID, beforeTabID: UUID)
        case moveTabAfter(tabID: UUID, afterTabID: UUID)
        case resetTabs
        case restoreTabs(snapshots: [RestoredTabSnapshot], selectedIndex: Int?)
        case renameTab(tabID: UUID, name: String)
        case setLoading(tabID: UUID, isLoading: Bool)
        case setLargeFileCandidate(tabID: UUID, isLargeCandidate: Bool)
        case resetContentRevision(tabID: UUID)
        case applyLoadedTabState(
            tabID: UUID,
            content: String,
            fileEncodingRawValue: UInt,
            fileEncoding: TextEncodingDescriptor,
            lineEnding: TextLineEnding,
            language: String,
            languageLocked: Bool,
            fingerprint: UInt64?,
            fileModificationDate: Date?,
            isLargeCandidate: Bool,
            isPartialPreview: Bool,
            byteCount: Int,
            isExternalRefresh: Bool,
            fileBackedDocument: FileBackedTextDocument?
        )
    }

    private struct TabCommandOutcome: Sendable {
        var index: Int?
        var tabID: UUID?
        var didChangeContent: Bool = false
        var contentRevision: Int?
    }

    private func dispatchTabCommandSerialized(_ command: TabCommand) async -> TabCommandOutcome {
        await tabCommandQueue.acquire()
        let outcome = applyTabCommand(command)
        await tabCommandQueue.release()
        return outcome
    }

    @discardableResult
    private func applyTabCommand(_ command: TabCommand) -> TabCommandOutcome {
        switch command {
        case let .updateContent(tabID, mutation):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            var outcome = applyContentMutation(mutation, to: tabs[index])
            outcome.index = index
            if outcome.didChangeContent {
                recordTabStateMutation(.content)
            }
            return outcome

        case let .markSaved(tabID, fileURL, fingerprint, fileModificationDate, _, fileByteCount):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            let outcome = TabCommandOutcome(index: index)
            if let fileURL {
                tabs[index].fileURL = fileURL
                tabs[index].name = fileURL.lastPathComponent
                if let mapped = LanguageDetector.shared.preferredLanguage(for: fileURL) ??
                    languageMap[fileURL.pathExtension.lowercased()] {
                    tabs[index].language = mapped
                    tabs[index].languageLocked = true
                }
            }
            tabs[index].markClean(withFingerprint: fingerprint)
            tabs[index].updateLastKnownFileModificationDate(fileModificationDate)
            // Save operations already use the tab's selected descriptor. Do not collapse a
            // deliberate BOM or explicit encoding choice back to an unqualified raw value.
            if let fileByteCount {
                tabs[index].updateFileByteCount(fileByteCount)
            }
            recordTabStateMutation(.structure, rebuildIndexes: true)
            NotificationCenter.default.post(name: .neonPulseDocumentDidSave, object: nil)
            return outcome

        case let .remapFileURL(tabID, fileURL):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            let standardizedTarget = fileURL.standardizedFileURL
            let currentPath = tabs[index].fileURL?.standardizedFileURL.path
            if currentPath == standardizedTarget.path, tabs[index].name == standardizedTarget.lastPathComponent {
                return TabCommandOutcome(index: index)
            }
            tabs[index].fileURL = standardizedTarget
            tabs[index].name = standardizedTarget.lastPathComponent
            if let mapped = LanguageDetector.shared.preferredLanguage(for: standardizedTarget) ??
                languageMap[standardizedTarget.pathExtension.lowercased()] {
                tabs[index].language = mapped
                tabs[index].languageLocked = true
            }
            let fileDate = (try? standardizedTarget.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            tabs[index].updateLastKnownFileModificationDate(fileDate)
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome(index: index)

        case let .setLanguage(tabID, language, lock):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            if tabs[index].language == language, tabs[index].languageLocked == lock {
                return TabCommandOutcome(index: index)
            }
            tabs[index].language = language
            tabs[index].languageLocked = lock
            recordTabStateMutation(.metadata)
            return TabCommandOutcome(index: index)

        case let .closeTab(tabID):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            cancelPendingLanguageDetection(for: tabID)
            pendingExternalFileRefreshTasks.removeValue(forKey: tabID)?.cancel()
            clearExternalRefreshActivity(tabID: tabID)
            tabs.remove(at: index)
            if tabs.isEmpty {
                let newTab = TabData(
                    name: nextUntitledTabName(),
                    content: "",
                    language: defaultNewTabLanguage(),
                    fileURL: nil,
                    languageLocked: false
                )
                tabs.append(newTab)
                selectedTabID = newTab.id
            } else if selectedTabID == tabID {
                selectedTabID = tabs.first?.id
            }
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome()

        case let .addNewTab(name, language):
            let newTab = TabData(
                name: name,
                content: "",
                language: language,
                fileURL: nil,
                languageLocked: false
            )
            tabs.append(newTab)
            selectedTabID = newTab.id
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome(index: tabs.count - 1, tabID: newTab.id)

        case let .addPlaceholderTab(tabID, name, language, fileURL, languageLocked, isLargeCandidate):
            let tab = TabData(
                id: tabID,
                name: name,
                content: "",
                language: language,
                fileURL: fileURL,
                languageLocked: languageLocked,
                isDirty: false,
                lastSavedFingerprint: nil,
                isLoadingContent: true,
                isLargeFileCandidate: isLargeCandidate,
                isReadOnlyPreview: Self.isPreviewOnlyFileURL(fileURL)
            )
            tabs.append(tab)
            selectedTabID = tab.id
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome(index: tabs.count - 1, tabID: tab.id)

        case let .replaceCleanTabWithPlaceholder(tabID, name, language, fileURL, languageLocked, isLargeCandidate):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            cancelPendingLanguageDetection(for: tabID)
            let tab = tabs[index]
            tab.name = name
            tab.language = language
            tab.fileURL = fileURL
            tab.languageLocked = languageLocked
            tab.isLoadingContent = true
            tab.isLargeFileCandidate = isLargeCandidate
            tab.remotePreviewPath = nil
            tab.remoteRevisionToken = nil
            tab.isReadOnlyPreview = Self.isPreviewOnlyFileURL(fileURL)
            tab.isPartialFilePreview = false
            tab.fileByteCount = 0
            _ = tab.replaceContentStorage(with: "", markDirty: false, compareIfLengthAtMost: nil)
            tab.markClean(withFingerprint: nil)
            tab.updateLastKnownFileModificationDate(nil)
            selectedTabID = tabID
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome(index: index, tabID: tabID)

        case let .replaceTabWithPlaceholder(tabID, name, language, fileURL, languageLocked, isLargeCandidate):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            cancelPendingLanguageDetection(for: tabID)
            let tab = tabs[index]
            tab.name = name
            tab.language = language
            tab.fileURL = fileURL
            tab.languageLocked = languageLocked
            tab.isLoadingContent = true
            tab.isLargeFileCandidate = isLargeCandidate
            tab.remotePreviewPath = nil
            tab.remoteRevisionToken = nil
            tab.isReadOnlyPreview = Self.isPreviewOnlyFileURL(fileURL)
            tab.isPartialFilePreview = false
            tab.fileByteCount = 0
            _ = tab.replaceContentStorage(with: "", markDirty: false, compareIfLengthAtMost: nil)
            tab.markClean(withFingerprint: nil)
            tab.updateLastKnownFileModificationDate(nil)
            selectedTabID = tabID
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome(index: index, tabID: tabID)

        case let .selectTab(tabID):
            if selectedTabID == tabID {
                return TabCommandOutcome()
            }
            selectedTabID = tabID
            if let tabID {
                EditorPerformanceMonitor.shared.beginTabSwitch(tabID: tabID)
            }
            return TabCommandOutcome()

        case let .moveTabBefore(tabID, beforeTabID):
            guard tabID != beforeTabID,
                  let sourceIndex = tabIndex(for: tabID),
                  let destinationIndex = tabIndex(for: beforeTabID) else {
                return TabCommandOutcome()
            }
            guard sourceIndex + 1 != destinationIndex else {
                return TabCommandOutcome(index: sourceIndex, tabID: tabID)
            }
            let tab = tabs.remove(at: sourceIndex)
            let adjustedDestinationIndex = sourceIndex < destinationIndex
                ? destinationIndex - 1
                : destinationIndex
            tabs.insert(tab, at: adjustedDestinationIndex)
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome(index: adjustedDestinationIndex, tabID: tabID)

        case let .moveTabAfter(tabID, afterTabID):
            guard tabID != afterTabID,
                  let sourceIndex = tabIndex(for: tabID),
                  let destinationIndex = tabIndex(for: afterTabID) else {
                return TabCommandOutcome()
            }
            guard sourceIndex != destinationIndex + 1 else {
                return TabCommandOutcome(index: sourceIndex, tabID: tabID)
            }
            let tab = tabs.remove(at: sourceIndex)
            let adjustedDestinationIndex = sourceIndex < destinationIndex
                ? destinationIndex
                : destinationIndex + 1
            tabs.insert(tab, at: adjustedDestinationIndex)
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome(index: adjustedDestinationIndex, tabID: tabID)

        case .resetTabs:
            for tab in tabs {
                cancelPendingLanguageDetection(for: tab.id)
                pendingExternalFileRefreshTasks.removeValue(forKey: tab.id)?.cancel()
                clearExternalRefreshActivity(tabID: tab.id)
            }
            tabs.removeAll(keepingCapacity: true)
            selectedTabID = nil
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome()

        case let .restoreTabs(snapshots, selectedIndex):
            for tab in tabs {
                cancelPendingLanguageDetection(for: tab.id)
                pendingExternalFileRefreshTasks.removeValue(forKey: tab.id)?.cancel()
                clearExternalRefreshActivity(tabID: tab.id)
            }
            tabs.removeAll(keepingCapacity: true)
            tabs.reserveCapacity(snapshots.count)
            for snapshot in snapshots {
                let restoredFileLanguage = LanguageDetector.shared.preferredLanguage(for: snapshot.fileURL)
                tabs.append(
                    TabData(
                        name: snapshot.name,
                        content: snapshot.content,
                        language: restoredFileLanguage ?? snapshot.language,
                        fileURL: snapshot.fileURL,
                        languageLocked: restoredFileLanguage != nil || snapshot.languageLocked,
                        isDirty: snapshot.isDirty,
                        lastSavedFingerprint: snapshot.lastSavedFingerprint,
                        lastKnownFileModificationDate: snapshot.lastKnownFileModificationDate,
                        fileEncodingRawValue: snapshot.fileEncodingRawValue,
                        fileEncoding: snapshot.fileEncoding,
                        usesAutomaticFileEncoding: snapshot.usesAutomaticFileEncoding,
                        lineEnding: snapshot.lineEnding,
                        fileBackedDocument: snapshot.fileBackedSessionState.flatMap {
                            try? FileBackedTextDocument(restoring: $0)
                        }
                    )
                )
            }
            if let selectedIndex, tabs.indices.contains(selectedIndex) {
                selectedTabID = tabs[selectedIndex].id
            } else {
                selectedTabID = tabs.first?.id
            }
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome()

        case let .renameTab(tabID, name):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            if tabs[index].name == name {
                return TabCommandOutcome(index: index)
            }
            tabs[index].name = name
            recordTabStateMutation(.metadata)
            return TabCommandOutcome(index: index)

        case let .setLoading(tabID, isLoading):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            if tabs[index].isLoadingContent == isLoading {
                return TabCommandOutcome(index: index)
            }
            tabs[index].isLoadingContent = isLoading
            recordTabStateMutation(.metadata)
            return TabCommandOutcome(index: index)

        case let .setLargeFileCandidate(tabID, isLargeCandidate):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            if tabs[index].isLargeFileCandidate == isLargeCandidate {
                return TabCommandOutcome(index: index)
            }
            tabs[index].isLargeFileCandidate = isLargeCandidate
            recordTabStateMutation()
            return TabCommandOutcome(index: index)

        case let .resetContentRevision(tabID):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            if tabs[index].contentRevision == 0 {
                return TabCommandOutcome(index: index)
            }
            tabs[index].resetContentRevision()
            recordTabStateMutation()
            return TabCommandOutcome(index: index)

        case let .applyLoadedTabState(tabID, content, _, fileEncoding, lineEnding, language, languageLocked, fingerprint, fileModificationDate, isLargeCandidate, isPartialPreview, byteCount, isExternalRefresh, fileBackedDocument):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            tabs[index].language = language
            tabs[index].languageLocked = languageLocked
            tabs[index].markClean(withFingerprint: fingerprint)
            tabs[index].updateLastKnownFileModificationDate(fileModificationDate)
            tabs[index].updateFileEncoding(fileEncoding, usesAutomatic: true)
            tabs[index].updateLineEnding(lineEnding)
            tabs[index].isLargeFileCandidate = isLargeCandidate
            tabs[index].isPartialFilePreview = isPartialPreview
            tabs[index].fileByteCount = byteCount
            tabs[index].isReadOnlyPreview = isPartialPreview
            let didChange: Bool
            if let fileBackedDocument {
                didChange = tabs[index].installLoadedFileBackedDocument(fileBackedDocument)
            } else {
                didChange = tabs[index].replaceContentStorage(
                    with: content,
                    markDirty: false,
                    compareIfLengthAtMost: nil
                )
            }
            tabs[index].isLoadingContent = false
            if isExternalRefresh {
                tabs[index].noteExternalContentRefresh()
            }
            recordTabStateMutation(.content)
            return TabCommandOutcome(index: index, didChangeContent: didChange)
        }
    }

    private func applyContentMutation(_ mutation: TabContentMutation, to tab: TabData) -> TabCommandOutcome {
        switch mutation {
        case let .replaceAll(text, markDirty, compareIfLengthAtMost):
            let didChange = tab.replaceContentStorage(
                with: text,
                markDirty: markDirty,
                compareIfLengthAtMost: compareIfLengthAtMost
            )
            return TabCommandOutcome(
                didChangeContent: didChange,
                contentRevision: didChange ? tab.contentRevision : nil
            )

        case let .replaceRange(range, replacement, markDirty):
            let totalLength = tab.document.utf16Length
            let safeLocation = min(max(0, range.location), totalLength)
            let maxLength = max(0, totalLength - safeLocation)
            let safeLength = min(max(0, range.length), maxLength)
            let safeRange = NSRange(location: safeLocation, length: safeLength)
            if safeRange.length == 0, replacement.isEmpty {
                return TabCommandOutcome()
            }
            let didChange = tab.replaceContent(in: safeRange, with: replacement, markDirty: markDirty)
            return TabCommandOutcome(
                didChangeContent: didChange,
                contentRevision: didChange ? tab.contentRevision : nil
            )
        }
    }
    
    private let languageMap: [String: String] = [
        "swift": "swift",
        "ada": "ada",
        "adb": "ada",
        "ads": "ada",
        "py": "python",
        "pyi": "python",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "php": "php",
        "phtml": "php",
        "bak": "plain",
        "csv": "csv",
        "tsv": "csv",
        "txt": "plain",
        "toml": "toml",
        "nix": "nix",
        "eml": "eml",
        "ini": "ini",
        "yaml": "yaml",
        "yml": "yaml",
        "xml": "xml",
        "svg": "xml",
        "crash": "crashlog",
        "ips": "crashlog",
        "sql": "sql",
        "log": "log",
        "vim": "vim",
        "ipynb": "ipynb",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "go": "go",
        "rb": "ruby",
        "rs": "rust",
        "ps1": "powershell",
        "psm1": "powershell",
        "html": "html",
        "htm": "html",
        "xhtml": "html",
        "ee": "expressionengine",
        "exp": "expressionengine",
        "tmpl": "expressionengine",
        "css": "css",
        "c": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "hpp": "cpp",
        "hh": "cpp",
        "h": "cpp",
        "cs": "csharp",
        "m": "objective-c",
        "mm": "objective-c",
        "json": "json",
        "jsonc": "json",
        "json5": "json",
        "md": "markdown",
        "markdown": "markdown",
        "mdown": "markdown",
        "mkdn": "markdown",
        "mdx": "markdown",
        "typ": "typst",
        "tex": "tex",
        "latex": "tex",
        "bib": "tex",
        "sty": "tex",
        "cls": "tex",
        "env": "dotenv",
        "proto": "proto",
        "graphql": "graphql",
        "gql": "graphql",
        "rst": "rst",
        "conf": "nginx",
        "nginx": "nginx",
        "cob": "cobol",
        "cbl": "cobol",
        "cobol": "cobol",
        "sh": "bash",
        "bash": "bash",
        "zsh": "zsh"
    ]
    
    init() {
        addNewTab()
    }

    // MARK: - Tab Lifecycle

    private func nextUntitledTabName() -> String {
        "Untitled \(tabs.count + 1)"
    }

    // Creates and selects a new untitled tab.
    func addNewTab() {
        _ = applyTabCommand(
            .addNewTab(
                name: nextUntitledTabName(),
                language: defaultNewTabLanguage()
            )
        )
    }

    /// Creates a Markdown tab for an attached PDF note. An unsaved note keeps
    /// a nil file URL until it receives content, so it cannot participate in
    /// Save As or close confirmation before the user writes anything.
    @discardableResult
    func addPDFNoteTab(name: String, fileURL: URL? = nil, content: String = "") -> UUID {
        let tab = TabData(name: name, content: content, language: "markdown", fileURL: fileURL, languageLocked: true)
        tab.markClean(withFingerprint: fileURL == nil ? nil : contentFingerprint(content))
        tabs.append(tab)
        selectedTabID = tab.id
        recordTabStateMutation(rebuildIndexes: true)
        return tab.id
    }

    /// Reuses the selected editor tab for an attached PDF note. The PDF source
    /// is retained by ContentView so its preview can remain visible while this
    /// tab becomes the editable Markdown note.
    @discardableResult
    func useSelectedTabForPDFNote(
        name: String,
        fileURL: URL?,
        content: String
    ) -> UUID? {
        guard let selectedTabID,
              let index = tabIndex(for: selectedTabID) else { return nil }
        let tab = tabs[index]
        tab.name = name
        tab.fileURL = fileURL
        tab.language = "markdown"
        tab.languageLocked = true
        tab.remotePreviewPath = nil
        tab.remoteRevisionToken = nil
        tab.isReadOnlyPreview = false
        tab.isPartialFilePreview = false
        tab.isLoadingContent = false
        tab.isLargeFileCandidate = false
        tab.fileByteCount = content.utf8.count
        tab.lineEnding = .lf
        _ = tab.replaceContentStorage(with: content, markDirty: false, compareIfLengthAtMost: nil)
        tab.markClean(withFingerprint: fileURL == nil ? nil : contentFingerprint(content))
        if let fileURL,
           let modificationDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            tab.updateLastKnownFileModificationDate(modificationDate)
        } else {
            tab.updateLastKnownFileModificationDate(nil)
        }
        recordTabStateMutation(rebuildIndexes: true)
        return tab.id
    }

    /// Clears the transient file attachment for a note that was emptied before
    /// its first save. Existing note files are never removed implicitly.
    func clearUnsavedEmptyPDFNote(tabID: UUID, displayName: String) {
        guard let index = tabIndex(for: tabID),
              tabs[index].document.string().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard tabs[index].fileURL != nil || tabs[index].isDirty else { return }
        if let fileURL = tabs[index].fileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            return
        }
        tabs[index].fileURL = nil
        tabs[index].name = displayName
        tabs[index].markClean(withFingerprint: nil)
        recordTabStateMutation(rebuildIndexes: true)
    }

    private func cleanUntitledTabIDForFileOpenReplacement() -> UUID? {
        guard tabs.count == 1, let tab = tabs.first else { return nil }
        guard tab.fileURL == nil,
              tab.remotePreviewPath == nil,
              !tab.isDirty,
              !tab.isLoadingContent,
              tab.document.utf16Length == 0 else {
            return nil
        }
        return tab.id
    }

    func selectTab(id: UUID?) {
        _ = applyTabCommand(.selectTab(tabID: id))
    }

    func moveTab(tabID: UUID, beforeTabID: UUID) {
        _ = applyTabCommand(.moveTabBefore(tabID: tabID, beforeTabID: beforeTabID))
    }

    func moveTab(tabID: UUID, afterTabID: UUID) {
        _ = applyTabCommand(.moveTabAfter(tabID: tabID, afterTabID: afterTabID))
    }

    func resetTabsForSessionRestore() {
        _ = applyTabCommand(.resetTabs)
    }

    func restoreTabsFromSnapshot(_ snapshots: [RestoredTabSnapshot], selectedIndex: Int?) {
        _ = applyTabCommand(.restoreTabs(snapshots: snapshots, selectedIndex: selectedIndex))
    }

    // Renames an existing tab.
    func renameTab(tabID: UUID, newName: String) {
        _ = applyTabCommand(.renameTab(tabID: tabID, name: newName))
    }

    func renameTab(tab: TabData, newName: String) {
        renameTab(tabID: tab.id, newName: newName)
    }

    // Updates tab text and applies language detection/locking heuristics.
    func updateTabContent(tab: TabData, content: String) {
        updateTabContent(tabID: tab.id, content: content)
    }

    // Tab-scoped content update API that centralizes dirty/idempotence behavior.
    func updateTabContent(tabID: UUID, content: String) {
        guard let index = tabIndex(for: tabID) else { return }
        guard !tabs[index].isReadOnlyPreview else { return }
        if tabs[index].isLoadingContent {
            // During staged file load, content updates are system-driven; do not mark dirty.
            _ = applyTabCommand(
                .updateContent(
                    tabID: tabID,
                    mutation: .replaceAll(
                        text: content,
                        markDirty: false,
                        compareIfLengthAtMost: nil
                    )
                )
            )
            return
        }

        let outcome = applyTabCommand(
            .updateContent(
                tabID: tabID,
                mutation: .replaceAll(
                    text: content,
                    markDirty: true,
                    compareIfLengthAtMost: Self.deferredLanguageDetectionUTF16Length
                )
            )
        )
        guard outcome.didChangeContent,
              let commandIndex = outcome.index,
              let contentRevision = outcome.contentRevision else { return }

        handleLanguageMetadataAfterMutation(
            tabID: tabID,
            tabIndex: commandIndex,
            contentRevision: contentRevision,
            contentSnapshot: content
        )
    }

    // Incremental piece-table mutation path used by the editor delegates for large content responsiveness.
    @discardableResult
    func applyTabContentEdit(tabID: UUID, range: NSRange, replacement: String) -> Bool {
        guard let index = tabIndex(for: tabID) else { return false }
        guard !tabs[index].isReadOnlyPreview else { return false }
        guard !tabs[index].isLoadingContent else { return false }

        let outcome = applyTabCommand(
            .updateContent(
                tabID: tabID,
                mutation: .replaceRange(
                    range: range,
                    replacement: replacement,
                    markDirty: true
                )
            )
        )
        guard outcome.didChangeContent else { return false }
        guard let commandIndex = outcome.index else { return false }
        guard let contentRevision = outcome.contentRevision else { return false }

        handleLanguageMetadataAfterMutation(
            tabID: tabID,
            tabIndex: commandIndex,
            contentRevision: contentRevision,
            contentSnapshot: nil
        )
        return true
    }

    @discardableResult
    func applyTabContentEdit(
        tabID: UUID,
        viewport: EditorDocumentViewport,
        range: NSRange,
        replacement: String
    ) -> Bool {
        guard let index = tabIndex(for: tabID),
              !tabs[index].isReadOnlyPreview,
              !tabs[index].isLoadingContent else { return false }
        guard tabs[index].replaceContent(in: viewport, range: range, with: replacement) else { return false }
        recordTabStateMutation(.content)
        handleLanguageMetadataAfterMutation(
            tabID: tabID,
            tabIndex: index,
            contentRevision: tabs[index].contentRevision,
            contentSnapshot: nil
        )
        return true
    }

    // Manually sets language and locks automatic switching.
    func updateTabLanguage(tab: TabData, language: String) {
        updateTabLanguage(tabID: tab.id, language: language)
    }

    func setTabLanguage(tabID: UUID, language: String, lock: Bool) {
        _ = applyTabCommand(.setLanguage(tabID: tabID, language: language, lock: lock))
    }

    func updateTabLanguage(tabID: UUID, language: String) {
        setTabLanguage(tabID: tabID, language: language, lock: true)
    }

    // Closes a tab while guaranteeing one tab remains open.
    func closeTab(tabID: UUID) {
        _ = applyTabCommand(.closeTab(tabID: tabID))
    }

    func closeTab(tab: TabData) {
        closeTab(tabID: tab.id)
    }

    /// Closing must wait for local writes, including writes queued while an
    /// earlier snapshot was saving. Failed saves and newer edits stay open.
    @discardableResult
    func saveAndCloseTabs(tabIDs: [UUID]) async -> Bool {
        for tabID in tabIDs {
            if let tab = tabs.first(where: { $0.id == tabID }), tab.isDirty {
                saveFile(tabID: tabID)
            }
        }
        for tabID in tabIDs {
            while let pending = localSaveTasks[tabID]?.task { await pending.value }
            guard let tab = tabs.first(where: { $0.id == tabID }),
                  !tab.isDirty, !tab.isLoadingContent else { continue }
            closeTab(tabID: tabID)
        }
        let closed = !tabs.contains(where: { tabIDs.contains($0.id) })
        if !closed, fileEncodingErrorMessage == nil, pendingExternalFileConflict == nil {
            fileEncodingErrorMessage = "Unsaved tabs were left open. Finish saving or resolve any conflicts before closing them."
        }
        return closed
    }

    // MARK: - Saving and Conflict Resolution

    // Saves tab content to the existing file URL or falls back to Save As.
    func saveFile(tabID: UUID, allowExternalOverwrite: Bool = false) {
        guard let index = tabIndex(for: tabID) else { return }
        guard !tabs[index].isReadOnlyPreview, !tabs[index].isLoadingContent else { return }
        if tabs[index].fileURL == nil, let remotePath = tabs[index].remotePreviewPath {
            enqueueRemoteSave(tabID: tabID, remotePath: remotePath, signpostName: "save_remote_file")
            return
        }
        if !tabs[index].usesFileBackedStorage, !allowExternalOverwrite, localSaveTasks[tabID] == nil,
           let conflict = detectExternalConflict(for: tabs[index]) {
            pendingExternalFileConflict = conflict
            return
        }
        if let fileBackedDocument = tabs[index].fileBackedDocument,
           let url = tabs[index].fileURL {
            enqueueFileBackedSave(tabID: tabID, document: fileBackedDocument, to: url,
                                  saveAs: false, allowExternalOverwrite: allowExternalOverwrite)
            return
        }
        if let url = tabs[index].fileURL {
            enqueueSave(tabID: tabID, to: url, updateFileURLOnSuccess: nil, signpostName: "save_file", allowExternalOverwrite: allowExternalOverwrite)
        } else {
            saveFileAs(tabID: tabID)
        }
    }

    func saveFile(tab: TabData) {
        saveFile(tabID: tab.id)
    }

    /// Immediately transcodes the document. The persistent descriptor changes only after
    /// the atomic write succeeds, so failed conversions leave both disk and tab state intact.
    func saveFile(tabID: UUID, using encoding: TextEncodingDescriptor) {
        guard let index = tabIndex(for: tabID),
              !tabs[index].isReadOnlyPreview,
              !tabs[index].isLoadingContent else { return }
        let tab = tabs[index]
        guard !tab.usesFileBackedStorage else {
            fileEncodingErrorMessage = "Changing text encoding is not available for large virtual documents yet. Save using the original UTF-8 encoding."
            return
        }
        guard encoding.encodedData(for: tab.lineEnding.applying(to: tab.document.string())) != nil else {
            fileEncodingErrorMessage =
                "\(encoding.displayName) cannot represent every character in this document. Choose a Unicode encoding to avoid data loss."
            return
        }
        guard let url = tab.fileURL else {
            setFileEncoding(tabID: tabID, encoding: encoding, usesAutomatic: false)
            saveFileAs(tabID: tabID)
            return
        }
        if let conflict = detectExternalConflict(for: tab) {
            pendingExternalFileConflict = conflict
            return
        }
        enqueueSave(
            tabID: tabID,
            to: url,
            updateFileURLOnSuccess: nil,
            signpostName: "save_file_encoding",
            encodingOverride: encoding
        )
    }

    func setFileEncoding(tabID: UUID, encoding: TextEncodingDescriptor, usesAutomatic: Bool = false) {
        guard let index = tabIndex(for: tabID),
              !tabs[index].isReadOnlyPreview,
              !tabs[index].isLoadingContent else { return }
        tabs[index].updateFileEncoding(encoding, usesAutomatic: usesAutomatic)
        recordTabStateMutation()
    }

    func setLineEnding(tabID: UUID, lineEnding: TextLineEnding) {
        guard let index = tabIndex(for: tabID),
              !tabs[index].isReadOnlyPreview,
              !tabs[index].isLoadingContent else { return }
        tabs[index].updateLineEnding(lineEnding)
        recordTabStateMutation()
    }

    func reopenFileWithSelectedEncoding(tabID: UUID) {
        guard let index = tabIndex(for: tabID) else { return }
        requestEncodingReopen(tabID: tabID, encoding: tabs[index].fileEncoding)
    }

    func reopenFileWithAutomaticEncoding(tabID: UUID) {
        requestEncodingReopen(tabID: tabID, encoding: nil)
    }

    private func requestEncodingReopen(tabID: UUID, encoding: TextEncodingDescriptor?) {
        guard let index = tabIndex(for: tabID),
              !tabs[index].isReadOnlyPreview,
              !tabs[index].isLoadingContent,
              let url = tabs[index].fileURL else { return }
        if tabs[index].isDirty {
            pendingEncodingReopen = PendingEncodingReopen(tabID: tabID, encoding: encoding)
            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            pendingExternalFileConflict = ExternalFileConflictState(
                tabID: tabID,
                fileURL: url,
                diskModifiedAt: modifiedAt
            )
            return
        }
        performEncodingReopen(tabID: tabID, encoding: encoding)
    }

    private func performEncodingReopen(tabID: UUID, encoding: TextEncodingDescriptor?) {
        guard let index = tabIndex(for: tabID),
              !tabs[index].isReadOnlyPreview,
              let url = tabs[index].fileURL else { return }
        let extLangHint = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
        let isLargeCandidate = tabs[index].isLargeFileCandidate
        _ = applyTabCommand(.setLoading(tabID: tabID, isLoading: true))
        Task { [weak self] in
            guard let self else { return }
            do {
                let loadResult = try await Self.loadFileResult(
                    from: url,
                    extLangHint: extLangHint,
                    isLargeCandidate: isLargeCandidate,
                    preferredEncoding: encoding
                )
                await self.applyLoadedContent(tabID: tabID, result: loadResult)
                if let encoding {
                    self.setFileEncoding(tabID: tabID, encoding: encoding, usesAutomatic: false)
                }
            } catch {
                await self.markTabLoadFailed(tabID: tabID)
                self.debugLog(
                    encoding.map { "Could not reopen file with \($0.displayName)." }
                        ?? "Could not automatically detect the file encoding."
                )
            }
        }
    }

    func dismissExternalFileConflict() {
        pendingExternalFileConflict = nil
        pendingEncodingReopen = nil
    }

    func resolveExternalConflictByKeepingLocal(tabID: UUID) {
        pendingExternalFileConflict = nil
        clearExternalRefreshActivity(tabID: tabID)
        if pendingEncodingReopen?.tabID != tabID {
            pendingEncodingReopen = nil
        }
        saveFile(tabID: tabID, allowExternalOverwrite: true)
    }

    func resolveExternalConflictByReloadingDisk(tabID: UUID) {
        pendingExternalFileConflict = nil
        if let requested = pendingEncodingReopen, requested.tabID == tabID {
            pendingEncodingReopen = nil
            clearExternalRefreshActivity(tabID: tabID)
            performEncodingReopen(tabID: tabID, encoding: requested.encoding)
            return
        }
        pendingEncodingReopen = nil
        clearExternalRefreshActivity(tabID: tabID)
        guard let index = tabIndex(for: tabID),
              let url = tabs[index].fileURL else { return }
        let isLargeCandidate = tabs[index].isLargeFileCandidate
        let preferredEncoding = tabs[index].usesAutomaticFileEncoding ? nil : tabs[index].fileEncoding
        let extLangHint = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
        _ = applyTabCommand(.setLoading(tabID: tabID, isLoading: true))
        EditorPerformanceMonitor.shared.beginFileOpen(tabID: tabID)
        Task { [weak self] in
            guard let self else { return }
            do {
                let loadResult = try await Self.loadFileResult(
                    from: url,
                    extLangHint: extLangHint,
                    isLargeCandidate: isLargeCandidate,
                    preferredEncoding: preferredEncoding
                )
                await self.applyLoadedContent(tabID: tabID, result: loadResult)
                if let preferredEncoding {
                    self.setFileEncoding(tabID: tabID, encoding: preferredEncoding)
                }
            } catch {
                await self.markTabLoadFailed(tabID: tabID)
            }
        }
    }

    func dismissRemoteSaveIssue() {
        pendingRemoteSaveIssue = nil
    }

    func detachRemoteBrokerAfterSaveIssue() {
        pendingRemoteSaveIssue = nil
        RemoteSessionStore.shared.detachBrokerClient()
    }

    func retryRemoteSave(tabID: UUID) {
        pendingRemoteSaveIssue = nil
        saveFile(tabID: tabID)
    }

    func reloadRemoteDocumentAfterConflict(tabID: UUID) {
        guard let index = tabIndex(for: tabID),
              let remotePath = tabs[index].remotePreviewPath else {
            pendingRemoteSaveIssue = nil
            return
        }

        pendingRemoteSaveIssue = nil

        Task { [weak self] in
            guard let self else { return }
            guard let document = await RemoteSessionStore.shared.openRemoteDocument(path: remotePath) else {
                self.pendingRemoteSaveIssue = RemoteSaveIssueState(
                    tabID: tabID,
                    remotePath: remotePath,
                    detail: RemoteSessionStore.shared.remoteBrowserStatusDetail,
                    isConflict: false,
                    requiresReconnect: true
                )
                return
            }

            self.openRemoteDocument(
                name: document.name,
                remotePath: document.path,
                content: document.content,
                isReadOnly: document.isReadOnly,
                revisionToken: document.revisionToken
            )
        }
    }

    func externalConflictComparisonSnapshot(tabID: UUID) async -> ExternalFileComparisonSnapshot? {
        guard let index = tabIndex(for: tabID),
              let url = tabs[index].fileURL else { return nil }
        guard !tabs[index].usesFileBackedStorage else { return nil }
        let fileName = tabs[index].name
        let languageHint = tabs[index].language
        let isLargeCandidate = tabs[index].isLargeFileCandidate
        let localContent = tabs[index].document.string()
        let requestedEncoding = pendingEncodingReopen?.tabID == tabID
            ? pendingEncodingReopen?.encoding
            : (tabs[index].usesAutomaticFileEncoding ? nil : tabs[index].fileEncoding)
        return await Task.detached(priority: .utility) {
            let data = (try? Data(contentsOf: url, options: [.mappedIfSafe])) ?? Data()
            let diskContent = EditorLoadHelper.decodeFileText(
                data,
                fileURL: url,
                preferredLanguageHint: languageHint,
                isLargeCandidate: isLargeCandidate,
                preferredEncoding: requestedEncoding
            )
            return ExternalFileComparisonSnapshot(
                fileName: fileName,
                localContent: localContent,
                diskContent: diskContent.text
            )
        }.value
    }

    func compareCurrentTabAgainstDiskSnapshot(tabID: UUID) async -> DocumentComparisonSnapshot? {
        guard let index = tabIndex(for: tabID),
              let url = tabs[index].fileURL else { return nil }
        guard !tabs[index].usesFileBackedStorage else { return nil }
        let tab = tabs[index]
        let tabName = tab.name
        let localContent = tab.document.string()
        let languageHint = tab.language
        let isLargeCandidate = tab.isLargeFileCandidate
        let diskName = url.lastPathComponent
        return await Task.detached(priority: .utility) {
            let data = (try? Data(contentsOf: url, options: [.mappedIfSafe])) ?? Data()
            let diskContent = EditorLoadHelper.decodeFileText(
                data,
                fileURL: url,
                preferredLanguageHint: languageHint,
                isLargeCandidate: isLargeCandidate
            )
            return DocumentComparisonSnapshot(
                title: "Compare Local vs Disk",
                leftTitle: "Local: \(tabName)",
                rightTitle: "Disk: \(diskName)",
                leftContent: localContent,
                rightContent: diskContent.text
            )
        }.value
    }

    func compareTabsSnapshot(leftTabID: UUID, rightTabID: UUID) -> DocumentComparisonSnapshot? {
        guard let leftIndex = tabIndex(for: leftTabID),
              let rightIndex = tabIndex(for: rightTabID),
              leftTabID != rightTabID else { return nil }
        let left = tabs[leftIndex]
        let right = tabs[rightIndex]
        guard !left.usesFileBackedStorage, !right.usesFileBackedStorage else { return nil }
        return DocumentComparisonSnapshot(
            title: "Compare Open Tabs",
            leftTitle: left.name,
            rightTitle: right.name,
            leftContent: left.document.string(),
            rightContent: right.document.string()
        )
    }

    func remoteConflictComparisonSnapshot(tabID: UUID) async -> RemoteConflictComparisonSnapshot? {
        guard let index = tabIndex(for: tabID),
              let remotePath = tabs[index].remotePreviewPath else { return nil }
        let fileName = tabs[index].name
        let localContent = tabs[index].document.string()

        guard let document = await RemoteSessionStore.shared.openRemoteDocument(path: remotePath) else {
            return nil
        }

        return RemoteConflictComparisonSnapshot(
            tabID: tabID,
            fileName: fileName,
            localContent: localContent,
            remoteContent: document.content
        )
    }

    // Saves tab content to a user-selected path on macOS.
    func saveFileAs(tabID: UUID) {
        guard let index = tabIndex(for: tabID) else { return }
        guard !tabs[index].isReadOnlyPreview, !tabs[index].isLoadingContent else { return }
        if tabs[index].fileURL == nil, let remotePath = tabs[index].remotePreviewPath {
            enqueueRemoteSave(tabID: tabID, remotePath: remotePath, signpostName: "save_remote_file")
            return
        }
#if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedInitialSaveName(for: tabs[index])
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        let cssType = UTType(filenameExtension: "css") ?? .text
        panel.allowedContentTypes = [
            .text,
            .swiftSource,
            .pythonScript,
            .javaScript,
            .html,
            cssType,
            .cSource,
            .json,
            mdType
        ]

        if panel.runModal() == .OK, let url = panel.url {
            if let document = tabs[index].fileBackedDocument {
                saveFileBackedAs(tabID: tabID, document: document, to: url)
            } else {
                enqueueSave(tabID: tabID, to: url, updateFileURLOnSuccess: url, signpostName: "save_file_as")
            }
        }
#else
        // iOS/iPadOS: explicit Save As panel is not available here yet.
        // Keep document dirty so user can export/share via future document APIs.
        debugLog("Save As is currently only available on macOS.")
#endif
    }

    private func saveFileBackedAs(tabID: UUID, document: FileBackedTextDocument, to destinationURL: URL) {
        enqueueFileBackedSave(tabID: tabID, document: document, to: destinationURL, saveAs: true)
    }

    private func enqueueFileBackedSave(tabID: UUID, document: FileBackedTextDocument, to destinationURL: URL,
                                      saveAs: Bool, allowExternalOverwrite: Bool = false) {
        guard let index = tabIndex(for: tabID), tabs[index].fileBackedDocument === document else { return }
        let predecessor = localSaveTasks[tabID]?.task
        let saveID = UUID()
        let task = Task { [weak self] in
            await predecessor?.value
            guard let self else { return }
            defer { if self.localSaveTasks[tabID]?.id == saveID { self.localSaveTasks[tabID] = nil } }
            guard let index = self.tabIndex(for: tabID), let document = self.tabs[index].fileBackedDocument else { return }
            let revision = self.tabs[index].contentRevision
            let snapshot = document.makeSaveSnapshot()
            do {
                let receipt = try await Task.detached(priority: .utility) {
                    try snapshot.write(to: saveAs ? destinationURL : nil, allowExternalOverwrite: allowExternalOverwrite)
                }.value
                guard let finalIndex = self.tabIndex(for: tabID), self.tabs[finalIndex].fileBackedDocument === document else { return }
                if !saveAs {
                    document.acceptSave(receipt)
                    self.tabs[finalIndex].lastKnownFileModificationDate = receipt.modificationDate
                    self.tabs[finalIndex].updateFileByteCount(receipt.byteCount)
                }
                guard self.tabs[finalIndex].contentRevision == revision else {
                    if saveAs { self.fileEncodingErrorMessage = "A copy was saved, but newer edits remain in the original tab. Save again to include them." }
                    return
                }
                if let replacement = receipt.replacement {
                    _ = self.tabs[finalIndex].installLoadedFileBackedDocument(replacement)
                }
                _ = self.applyTabCommand(.markSaved(tabID: tabID, fileURL: saveAs ? destinationURL : nil,
                                                   fingerprint: nil, fileModificationDate: receipt.modificationDate,
                                                   fileEncodingRawValue: document.encodingDescriptor.encodingRawValue,
                                                   fileByteCount: receipt.byteCount))
                self.pendingExternalFileConflict = nil
            } catch FileBackedTextDocument.Error.externalConflict {
                self.pendingExternalFileConflict = ExternalFileConflictState(tabID: tabID, fileURL: destinationURL, diskModifiedAt: nil)
            } catch {
                self.fileEncodingErrorMessage = "Couldn’t save \(destinationURL.lastPathComponent). \(error.localizedDescription)"
            }
        }
        localSaveTasks[tabID] = (saveID, task)
    }

    func saveFileAs(tab: TabData) {
        saveFileAs(tabID: tab.id)
    }

    private func suggestedInitialSaveName(for tab: TabData) -> String {
        let trimmedName = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tab.fileURL == nil else { return trimmedName.isEmpty ? "Untitled" : tab.name }
        guard !trimmedName.isEmpty else {
            return "Untitled.\(Self.preferredSaveExtension(for: tab.language))"
        }
        let existingExtension = URL(fileURLWithPath: trimmedName).pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard existingExtension.isEmpty else { return tab.name }
        return "\(trimmedName).\(Self.preferredSaveExtension(for: tab.language))"
    }

    private static func preferredSaveExtension(for language: String) -> String {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "swift": return "swift"
        case "python": return "py"
        case "javascript": return "js"
        case "typescript": return "ts"
        case "php": return "php"
        case "java": return "java"
        case "kotlin": return "kt"
        case "go": return "go"
        case "ruby": return "rb"
        case "rust": return "rs"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        case "xml": return "xml"
        case "yaml": return "yml"
        case "toml": return "toml"
        case "nix": return "nix"
        case "eml": return "eml"
        case "ini": return "ini"
        case "sql": return "sql"
        case "markdown": return "md"
        case "tex": return "tex"
        case "graphql": return "graphql"
        case "proto": return "proto"
        case "dotenv": return "env"
        case "shell", "bash", "zsh": return "sh"
        case "powershell": return "ps1"
        case "c": return "c"
        case "cpp": return "cpp"
        case "objective-c": return "m"
        case "csharp": return "cs"
        case "csv": return "csv"
        case "vim": return "vim"
        case "log": return "log"
        default: return "txt"
        }
    }

    private func enqueueSave(
        tabID: UUID,
        to destinationURL: URL,
        updateFileURLOnSuccess: URL?,
        signpostName: StaticString,
        encodingOverride: TextEncodingDescriptor? = nil,
        allowExternalOverwrite: Bool = false
    ) {
        guard let index = tabIndex(for: tabID) else { return }
        let snapshotContent = tabs[index].document.string()
        let snapshotRevision = tabs[index].contentRevision
        let snapshotLineEnding = tabs[index].lineEnding
        let trimTrailingWhitespace = UserDefaults.standard.bool(forKey: "SettingsTrimTrailingWhitespace")

        let predecessor = localSaveTasks[tabID]?.task
        let saveID = UUID()
        let task = Task { [weak self] in
            await predecessor?.value
            guard let self else { return }
            defer {
                if self.localSaveTasks[tabID]?.id == saveID { self.localSaveTasks[tabID] = nil }
            }
            let saveInterval = Self.saveSignposter.beginInterval(signpostName)
            defer { Self.saveSignposter.endInterval(signpostName, saveInterval) }

            let payload = await Self.prepareSavePayload(
                from: snapshotContent,
                trimTrailingWhitespace: trimTrailingWhitespace
            )

            guard let preflightIndex = self.tabIndex(for: tabID),
                  self.tabs[preflightIndex].contentRevision == snapshotRevision
                    || self.tabs[preflightIndex].document.string() == payload.content else {
                return
            }
            let expectedMetadata = updateFileURLOnSuccess == nil && !allowExternalOverwrite
                ? LocalFileMetadata(modificationDate: self.tabs[preflightIndex].lastKnownFileModificationDate,
                                    byteCount: self.tabs[preflightIndex].fileByteCount) : nil
            let snapshotEncoding = encodingOverride ?? self.tabs[preflightIndex].fileEncoding

            let normalizationOutcome = self.applyTabCommand(
                .updateContent(
                    tabID: tabID,
                    mutation: .replaceAll(
                        text: payload.content,
                        markDirty: false,
                        compareIfLengthAtMost: Int.max
                    )
                )
            )
            let expectedRevision = normalizationOutcome.contentRevision ?? self.tabs[preflightIndex].contentRevision

            do {
                let (actualEncoding, fileMetadata) = try await Self.writeFileContent(
                    payload.content,
                    to: destinationURL,
                    encoding: snapshotEncoding,
                    lineEnding: snapshotLineEnding,
                    expectedMetadata: expectedMetadata
                )
                if let writtenIndex = self.tabIndex(for: tabID),
                   self.tabs[writtenIndex].fileURL?.standardizedFileURL == destinationURL.standardizedFileURL {
                    // A later edit remains dirty, but the next queued save must
                    // compare against our just-completed write, not the old file.
                    self.tabs[writtenIndex].lastKnownFileModificationDate = fileMetadata.modificationDate
                    self.tabs[writtenIndex].updateFileByteCount(fileMetadata.byteCount)
                }
                guard let finalIndex = self.tabIndex(for: tabID),
                      self.tabs[finalIndex].contentRevision == expectedRevision else {
                    return
                }

                _ = self.applyTabCommand(
                    .markSaved(
                        tabID: tabID,
                        fileURL: updateFileURLOnSuccess,
                        fingerprint: payload.fingerprint,
                        fileModificationDate: fileMetadata.modificationDate,
                        fileEncodingRawValue: actualEncoding.encodingRawValue,
                        fileByteCount: fileMetadata.byteCount
                    )
                )
                if encodingOverride != nil {
                    self.setFileEncoding(
                        tabID: tabID,
                        encoding: actualEncoding,
                        usesAutomatic: false
                    )
                }
                self.pendingExternalFileConflict = nil
                self.completePendingEncodingReopenAfterSave(tabID: tabID)
            } catch {
                if self.pendingEncodingReopen?.tabID == tabID {
                    self.pendingEncodingReopen = nil
                }
                let message: String
                if let cocoaError = error as? CocoaError,
                   cocoaError.code == .fileWriteInapplicableStringEncoding {
                    message = "Couldn’t save using \(snapshotEncoding.displayName). The document was left unchanged; choose another text encoding if it contains unsupported characters."
                } else {
                    message = "Couldn’t save \(destinationURL.lastPathComponent). The document was left unchanged. \(error.localizedDescription)"
                }
                if (error as? CocoaError)?.code == .fileWriteFileExists {
                    self.pendingExternalFileConflict = ExternalFileConflictState(
                        tabID: tabID, fileURL: destinationURL, diskModifiedAt: nil)
                }
                self.fileEncodingErrorMessage = message
                self.debugLog(message)
                return
            }
        }
        localSaveTasks[tabID] = (saveID, task)
    }

    private func completePendingEncodingReopenAfterSave(tabID: UUID) {
        guard let requested = pendingEncodingReopen, requested.tabID == tabID else { return }
        pendingEncodingReopen = nil
        performEncodingReopen(tabID: tabID, encoding: requested.encoding)
    }

    private func enqueueRemoteSave(tabID: UUID, remotePath: String, signpostName: StaticString) {
        guard let index = tabIndex(for: tabID) else { return }
        let snapshotContent = tabs[index].document.string()
        let snapshotRevision = tabs[index].contentRevision
        let snapshotRemoteRevisionToken = tabs[index].remoteRevisionToken
        let snapshotLineEnding = tabs[index].lineEnding
        let trimTrailingWhitespace = UserDefaults.standard.bool(forKey: "SettingsTrimTrailingWhitespace")

        Task { [weak self] in
            guard let self else { return }
            let saveInterval = Self.saveSignposter.beginInterval(signpostName)
            defer { Self.saveSignposter.endInterval(signpostName, saveInterval) }

            let payload = await Self.prepareSavePayload(
                from: snapshotContent,
                trimTrailingWhitespace: trimTrailingWhitespace
            )

            guard let preflightIndex = self.tabIndex(for: tabID),
                  self.tabs[preflightIndex].contentRevision == snapshotRevision else {
                return
            }

            let normalizationOutcome = self.applyTabCommand(
                .updateContent(
                    tabID: tabID,
                    mutation: .replaceAll(
                        text: payload.content,
                        markDirty: false,
                        compareIfLengthAtMost: Self.deferredLanguageDetectionUTF16Length
                    )
                )
            )
            let expectedRevision = normalizationOutcome.contentRevision ?? snapshotRevision

            let saveResult = await RemoteSessionStore.shared.saveRemoteDocument(
                path: remotePath,
                content: snapshotLineEnding.applying(to: payload.content),
                expectedRevision: snapshotRemoteRevisionToken
            )

            guard saveResult.didSave else {
                self.pendingRemoteSaveIssue = RemoteSaveIssueState(
                    tabID: tabID,
                    remotePath: remotePath,
                    detail: saveResult.detail,
                    isConflict: saveResult.hasConflict,
                    requiresReconnect: self.remoteSaveLikelyNeedsReconnect(saveResult.detail)
                )
                self.debugLog(saveResult.detail)
                return
            }

            guard let postflightIndex = self.tabIndex(for: tabID),
                  self.tabs[postflightIndex].contentRevision == expectedRevision else {
                return
            }

            _ = self.applyTabCommand(
                .markSaved(
                    tabID: tabID,
                    fileURL: nil,
                    fingerprint: self.contentFingerprint(self.tabs[postflightIndex].document.string()),
                    fileModificationDate: nil,
                    fileEncodingRawValue: nil,
                    fileByteCount: nil
                )
            )
            self.tabs[postflightIndex].updateRemoteRevisionToken(saveResult.revisionToken)
            self.pendingRemoteSaveIssue = nil
        }
    }

    private func remoteSaveLikelyNeedsReconnect(_ detail: String) -> Bool {
        let normalized = detail.localizedLowercase
        return normalized.contains("waiting for broker")
            || normalized.contains("broker attach failed")
            || normalized.contains("broker connection cancelled")
            || normalized.contains("broker request timed out")
            || normalized.contains("no active ssh target")
            || normalized.contains("attach to an active mac broker session")
    }

    func refreshExternalConflictForTab(tabID: UUID) {
        guard let index = tabIndex(for: tabID) else { return }
        let conflict = detectExternalConflict(for: tabs[index])
        pendingExternalFileConflict = conflict
        if let conflict {
            markExternalRefreshNeedsReview(
                tabID: tabID,
                modifiedAt: conflict.diskModifiedAt
            )
        }
    }

    private func detectExternalConflict(for tab: TabData) -> ExternalFileConflictState? {
        guard tab.isDirty, var fileURL = tab.fileURL else { return nil }
        fileURL.removeAllCachedResourceValues()
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return ExternalFileConflictState(tabID: tab.id, fileURL: fileURL, diskModifiedAt: nil)
        }
        let metadata = LocalFileMetadata(
            modificationDate: values.contentModificationDate,
            byteCount: values.fileSize ?? 0
        )
        guard Self.hasLocalFileMetadataChanged(
            knownModificationDate: tab.lastKnownFileModificationDate,
            knownByteCount: tab.fileByteCount,
            current: metadata
        ) else { return nil }
        return ExternalFileConflictState(
            tabID: tab.id,
            fileURL: fileURL,
            diskModifiedAt: metadata.modificationDate
        )
    }

    private func markExternalRefreshPending(tabID: UUID) {
        if reviewExternalTabIDs.contains(tabID) {
            publishExternalRefreshStatus()
            return
        }
        externalRefreshStatusClearTask?.cancel()
        externalRefreshStatusClearTask = nil
        pendingExternalRefreshTabIDs.insert(tabID)
        publishExternalRefreshStatus()
    }

    private func markExternalRefreshUnchanged(tabID: UUID) {
        pendingExternalRefreshTabIDs.remove(tabID)
        publishExternalRefreshStatus()
    }

    private func markExternalRefreshCompleted(tabID: UUID, modifiedAt: Date?) {
        pendingExternalRefreshTabIDs.remove(tabID)
        reviewExternalTabIDs.remove(tabID)
        refreshedExternalTabIDs.insert(tabID)
        recordExternalSyncChange(tabID: tabID, modifiedAt: modifiedAt, kind: .refreshed)
        publishExternalRefreshStatus()
        externalRefreshStatusClearTask?.cancel()
        externalRefreshStatusClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.refreshedExternalTabIDs.removeAll(keepingCapacity: true)
            self.publishExternalRefreshStatus()
            self.externalRefreshStatusClearTask = nil
        }
    }

    private func markExternalRefreshNeedsReview(tabID: UUID, modifiedAt: Date?) {
        let isNewReview = !reviewExternalTabIDs.contains(tabID)
        pendingExternalRefreshTabIDs.remove(tabID)
        refreshedExternalTabIDs.remove(tabID)
        reviewExternalTabIDs.insert(tabID)
        if isNewReview {
            recordExternalSyncChange(tabID: tabID, modifiedAt: modifiedAt, kind: .needsReview)
        }
        publishExternalRefreshStatus()
    }

    private func recordExternalSyncChange(
        tabID: UUID,
        modifiedAt: Date?,
        kind: ExternalSyncChangeKind
    ) {
        guard let index = tabIndex(for: tabID) else { return }
        recentExternalSyncChanges.append(
            ExternalSyncChange(
                id: UUID(),
                tabID: tabID,
                fileName: tabs[index].name,
                timestamp: modifiedAt ?? Date(),
                kind: kind
            )
        )
        recentExternalSyncChanges.sort { $0.timestamp > $1.timestamp }
        if recentExternalSyncChanges.count > 10 {
            recentExternalSyncChanges.removeLast(recentExternalSyncChanges.count - 10)
        }
    }

    func clearRecentExternalSyncChanges() {
        recentExternalSyncChanges.removeAll()
    }

    private func clearExternalRefreshActivity(tabID: UUID) {
        pendingExternalRefreshTabIDs.remove(tabID)
        refreshedExternalTabIDs.remove(tabID)
        reviewExternalTabIDs.remove(tabID)
        publishExternalRefreshStatus()
    }

    private func publishExternalRefreshStatus() {
        if !reviewExternalTabIDs.isEmpty {
            externalFileRefreshStatus = ExternalFileRefreshStatus(
                kind: .needsReview,
                message: externalRefreshStatusMessage(for: reviewExternalTabIDs, kind: .needsReview)
            )
        } else if !pendingExternalRefreshTabIDs.isEmpty {
            externalFileRefreshStatus = ExternalFileRefreshStatus(
                kind: .refreshing,
                message: externalRefreshStatusMessage(for: pendingExternalRefreshTabIDs, kind: .refreshing)
            )
        } else if !refreshedExternalTabIDs.isEmpty {
            externalFileRefreshStatus = ExternalFileRefreshStatus(
                kind: .refreshed,
                message: externalRefreshStatusMessage(for: refreshedExternalTabIDs, kind: .refreshed)
            )
        } else {
            externalFileRefreshStatus = nil
        }
    }

    private func externalRefreshStatusMessage(
        for tabIDs: Set<UUID>,
        kind: ExternalFileRefreshStatusKind
    ) -> String {
        if tabIDs.count == 1,
           let tabID = tabIDs.first,
           let index = tabIndex(for: tabID) {
            switch kind {
            case .refreshing: return "Refreshing \(tabs[index].name)…"
            case .refreshed: return "Refreshed \(tabs[index].name)"
            case .needsReview: return "External change: \(tabs[index].name) needs review"
            }
        }
        switch kind {
        case .refreshing: return "Refreshing \(tabIDs.count) tabs…"
        case .refreshed: return "Refreshed \(tabIDs.count) tabs"
        case .needsReview: return "External changes: \(tabIDs.count) tabs need review"
        }
    }

    // NSFilePresenter callbacks arrive only for filesystem/provider events. The
    // debounce keeps atomic-save rename/write sequences to one metadata check.
    func handleObservedLocalFileChange(at url: URL) {
        guard let index = indexOfOpenTab(for: url) else { return }
        let tabID = tabs[index].id
        markExternalRefreshPending(tabID: tabID)
        pendingExternalFileRefreshTasks.removeValue(forKey: tabID)?.cancel()
        pendingExternalFileRefreshTasks[tabID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            await self.refreshObservedLocalFile(tabID: tabID, expectedURL: url.standardizedFileURL)
            if !Task.isCancelled {
                self.pendingExternalFileRefreshTasks[tabID] = nil
            }
        }
    }

    private func updateNetworkVolumePolling(for urls: [URL]) {
        let uniqueURLs = Dictionary(
            urls.compactMap { url in
                Self.normalizedFilePathKey(for: url).map { ($0, url.standardizedFileURL) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let candidatePaths = Set(uniqueURLs.keys)
        guard candidatePaths != networkVolumePollingCandidatePaths else { return }

        networkVolumePollingCandidatePaths = candidatePaths
        networkVolumePollingTask?.cancel()
        networkVolumePollingTask = nil
        guard !uniqueURLs.isEmpty else { return }

        let candidates = Array(uniqueURLs.values)
        networkVolumePollingTask = Task { @MainActor [weak self] in
            let polledURLs = await Task.detached(priority: .utility) {
                candidates.filter { Self.requiresExternalChangePolling(at: $0) }
            }.value
            guard !Task.isCancelled, !polledURLs.isEmpty else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.networkVolumePollingIntervalNanos)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                _ = await self?.pollOpenDocumentsForExternalChanges(at: polledURLs)
            }
        }
    }

    @discardableResult
    func pollOpenDocumentsForExternalChanges(at urls: [URL]) async -> [UUID] {
        let uniqueURLs = Dictionary(
            urls.compactMap { url in
                Self.normalizedFilePathKey(for: url).map { ($0, url.standardizedFileURL) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let metadataByPath = await Task.detached(priority: .utility) {
            uniqueURLs.reduce(into: [String: LocalFileMetadata]()) { result, entry in
                if let metadata = Self.readLocalFileMetadata(at: entry.value) {
                    result[entry.key] = metadata
                }
            }
        }.value
        guard !Task.isCancelled else { return [] }

        var detectedTabIDs: [UUID] = []
        for (path, metadata) in metadataByPath {
            guard let tabID = tabIDByStandardizedFilePath[path],
                  let index = tabIndex(for: tabID),
                  !tabs[index].isLoadingContent,
                  !reviewExternalTabIDs.contains(tabID),
                  Self.hasLocalFileMetadataChanged(
                      knownModificationDate: tabs[index].lastKnownFileModificationDate,
                      knownByteCount: tabs[index].fileByteCount,
                      current: metadata
                  ),
                  let fileURL = tabs[index].fileURL else { continue }
            detectedTabIDs.append(tabID)
            handleObservedLocalFileChange(at: fileURL)
        }
        return detectedTabIDs
    }

    private func refreshObservedLocalFile(tabID: UUID, expectedURL: URL) async {
        guard !Task.isCancelled else { return }
        guard let initialIndex = tabIndex(for: tabID),
              let currentURL = tabs[initialIndex].fileURL?.standardizedFileURL,
              currentURL.path == expectedURL.path,
              !tabs[initialIndex].isLoadingContent else {
            clearExternalRefreshActivity(tabID: tabID)
            return
        }

        let metadata = await Task.detached(priority: .utility) {
            Self.readLocalFileMetadata(at: expectedURL)
        }.value
        guard !Task.isCancelled else { return }
        guard let metadata,
              let metadataIndex = tabIndex(for: tabID),
              tabs[metadataIndex].fileURL?.standardizedFileURL.path == expectedURL.path else {
            clearExternalRefreshActivity(tabID: tabID)
            return
        }
        guard Self.hasLocalFileMetadataChanged(
            knownModificationDate: tabs[metadataIndex].lastKnownFileModificationDate,
            knownByteCount: tabs[metadataIndex].fileByteCount,
            current: metadata
        ) else {
            markExternalRefreshUnchanged(tabID: tabID)
            return
        }

        if tabs[metadataIndex].isDirty {
            markExternalRefreshNeedsReview(
                tabID: tabID,
                modifiedAt: metadata.modificationDate
            )
            pendingExternalFileConflict = ExternalFileConflictState(
                tabID: tabID,
                fileURL: expectedURL,
                diskModifiedAt: metadata.modificationDate
            )
            return
        }

        let expectedContentRevision = tabs[metadataIndex].contentRevision
        let isLargeCandidate = metadata.byteCount >= EditorLoadHelper.largeFileCandidateByteThreshold
        let preferredEncoding = tabs[metadataIndex].usesAutomaticFileEncoding ? nil : tabs[metadataIndex].fileEncoding
        let languageHint = LanguageDetector.shared.preferredLanguage(for: expectedURL)
            ?? languageMap[expectedURL.pathExtension.lowercased()]

        do {
            let loadResult = try await Self.loadFileResult(
                from: expectedURL,
                extLangHint: languageHint,
                isLargeCandidate: isLargeCandidate,
                preferredEncoding: preferredEncoding,
                priority: .utility
            )
            guard !Task.isCancelled,
                  let finalIndex = tabIndex(for: tabID),
                  tabs[finalIndex].fileURL?.standardizedFileURL.path == expectedURL.path else { return }
            guard !tabs[finalIndex].isDirty,
                  tabs[finalIndex].contentRevision == expectedContentRevision else {
                if tabs[finalIndex].isDirty {
                    markExternalRefreshNeedsReview(
                        tabID: tabID,
                        modifiedAt: loadResult.fileModificationDate
                    )
                    pendingExternalFileConflict = ExternalFileConflictState(
                        tabID: tabID,
                        fileURL: expectedURL,
                        diskModifiedAt: loadResult.fileModificationDate
                    )
                } else {
                    clearExternalRefreshActivity(tabID: tabID)
                }
                return
            }

            let postflightMetadata = await Task.detached(priority: .utility) {
                Self.readLocalFileMetadata(at: expectedURL)
            }.value
            guard postflightMetadata == LocalFileMetadata(
                modificationDate: loadResult.fileModificationDate,
                byteCount: loadResult.byteCount
            ) else {
                handleObservedLocalFileChange(at: expectedURL)
                return
            }
            await applyLoadedContent(tabID: tabID, result: loadResult, isExternalRefresh: true)
            if let preferredEncoding {
                setFileEncoding(tabID: tabID, encoding: preferredEncoding)
            }
            markExternalRefreshCompleted(
                tabID: tabID,
                modifiedAt: loadResult.fileModificationDate
            )
        } catch {
            // Providers may transiently remove the original during an atomic replace.
            // A subsequent presenter event retries; the current editor buffer stays intact.
            if !Task.isCancelled {
                clearExternalRefreshActivity(tabID: tabID)
            }
        }
    }

    private nonisolated static func readLocalFileMetadata(at url: URL) -> LocalFileMetadata? {
        let didStartScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
              values.isRegularFile != false else { return nil }
        return LocalFileMetadata(
            modificationDate: values.contentModificationDate,
            byteCount: values.fileSize ?? 0
        )
    }

    private nonisolated static func requiresExternalChangePolling(at url: URL) -> Bool {
        let didStartScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
        return values?.volumeIsLocal != true
    }

    private nonisolated static func hasLocalFileMetadataChanged(
        knownModificationDate: Date?,
        knownByteCount: Int,
        current: LocalFileMetadata
    ) -> Bool {
        if knownByteCount != current.byteCount { return true }
        guard let knownModificationDate else { return true }
        guard let currentModificationDate = current.modificationDate else { return true }
        return abs(currentModificationDate.timeIntervalSince(knownModificationDate)) > 0.001
    }

    // MARK: - File Opening

    @discardableResult
    func openFileFromExternalRequest(url: URL) -> Bool {
        hasReceivedExternalFileOpenRequest = true
        return openFile(url: url)
    }

    // Opens file-picker UI on macOS.
    func openFile() {
#if os(macOS)
        let panel = NSOpenPanel()
        // Allow opening any file type, including hidden dotfiles like .zshrc
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK {
            let urls = panel.urls
            for url in urls {
                if !openFile(url: url) {
                    presentUnsupportedFileAlertOnMac(for: url)
                }
            }
        }
#else
        // iOS/iPadOS: document picker flow can be added here.
        debugLog("Open File panel is currently only available on macOS.")
#endif
    }

    // Loads a file into a new tab unless the file is already open.
    @discardableResult
    func openFile(
        url: URL,
        preferredEncoding: TextEncodingDescriptor? = nil,
        usesAutomaticEncoding: Bool = true
    ) -> Bool {
        guard Self.isSupportedEditorFileURL(url) else {
            debugLog("Unsupported file type skipped: \(url.lastPathComponent)")
            return false
        }
        if focusTabIfOpen(for: url) { return true }
        let extLangHint = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let isLargeCandidate = fileSize >= EditorLoadHelper.largeFileCandidateByteThreshold
        let cleanTabID = cleanUntitledTabIDForFileOpenReplacement()
        let tabID = cleanTabID ?? UUID()
        if cleanTabID != nil {
            _ = applyTabCommand(
                .replaceCleanTabWithPlaceholder(
                    tabID: tabID,
                    name: url.lastPathComponent,
                    language: extLangHint ?? "plain",
                    fileURL: url,
                    languageLocked: extLangHint != nil,
                    isLargeCandidate: isLargeCandidate
                )
            )
        } else {
            _ = applyTabCommand(
                .addPlaceholderTab(
                    tabID: tabID,
                    name: url.lastPathComponent,
                    language: extLangHint ?? "plain",
                    fileURL: url,
                    languageLocked: extLangHint != nil,
                    isLargeCandidate: isLargeCandidate
                )
            )
        }
        EditorPerformanceMonitor.shared.beginFileOpen(tabID: tabID)
        Task { [weak self] in
            guard let self else { return }
            do {
                let loadResult = try await Self.loadFileResult(
                    from: url,
                    extLangHint: extLangHint,
                    isLargeCandidate: isLargeCandidate,
                    preferredEncoding: usesAutomaticEncoding ? nil : preferredEncoding
                )
                await self.applyLoadedContent(tabID: tabID, result: loadResult)
                if !usesAutomaticEncoding, let preferredEncoding {
                    self.setFileEncoding(
                        tabID: tabID,
                        encoding: preferredEncoding,
                        usesAutomatic: false
                    )
                }
            } catch {
                await self.markTabLoadFailed(tabID: tabID)
            }
        }
        return true
    }

    @discardableResult
    func replaceSelectedTabWithFile(url: URL) -> Bool {
        guard Self.isSupportedEditorFileURL(url) else {
            debugLog("Unsupported file type skipped: \(url.lastPathComponent)")
            return false
        }
        guard let tabID = selectedTabID,
              let tab = selectedTab,
              !tab.isLoadingContent,
              tab.isReadOnlyPreview != true else {
            return false
        }

        let extLangHint = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let isLargeCandidate = fileSize >= EditorLoadHelper.largeFileCandidateByteThreshold
        _ = applyTabCommand(
            .replaceTabWithPlaceholder(
                tabID: tabID,
                name: url.lastPathComponent,
                language: extLangHint ?? "plain",
                fileURL: url,
                languageLocked: extLangHint != nil,
                isLargeCandidate: isLargeCandidate
            )
        )
        EditorPerformanceMonitor.shared.beginFileOpen(tabID: tabID)
        Task { [weak self] in
            guard let self else { return }
            do {
                let loadResult = try await Self.loadFileResult(
                    from: url,
                    extLangHint: extLangHint,
                    isLargeCandidate: isLargeCandidate
                )
                await self.applyLoadedContent(tabID: tabID, result: loadResult)
            } catch {
                await self.markTabLoadFailed(tabID: tabID)
            }
        }
        return true
    }

    func openRemotePreviewDocument(name: String, remotePath: String, content: String, revisionToken: String? = nil) {
        openRemoteDocument(name: name, remotePath: remotePath, content: content, isReadOnly: true, revisionToken: revisionToken)
    }

    func openRemoteDocument(name: String, remotePath: String, content: String, isReadOnly: Bool, revisionToken: String? = nil) {
        let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let pseudoURL = URL(fileURLWithPath: trimmedPath)
        let detectedLanguage = LanguageDetector.shared.preferredLanguage(for: pseudoURL)
            ?? languageMap[pseudoURL.pathExtension.lowercased()]
            ?? "plain"
        let languageLocked = detectedLanguage != "plain"
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? pseudoURL.lastPathComponent
            : name
        let lineEnding = TextLineEnding.detect(in: content)
        let normalizedContent = EditorLoadHelper.sanitizeTextForFileLoad(content, useFastPath: true)

        if let existingIndex = tabs.firstIndex(where: { $0.remotePreviewPath == trimmedPath }) {
            cancelPendingLanguageDetection(for: tabs[existingIndex].id)
            tabs[existingIndex].name = title
            tabs[existingIndex].fileURL = nil
            tabs[existingIndex].language = detectedLanguage
            tabs[existingIndex].languageLocked = languageLocked
            _ = tabs[existingIndex].replaceContentStorage(with: normalizedContent, markDirty: false, compareIfLengthAtMost: nil)
            tabs[existingIndex].markClean(withFingerprint: nil)
            tabs[existingIndex].updateLastKnownFileModificationDate(nil)
            tabs[existingIndex].isLoadingContent = false
            tabs[existingIndex].isLargeFileCandidate = false
            tabs[existingIndex].remotePreviewPath = trimmedPath
            tabs[existingIndex].remoteRevisionToken = revisionToken
            tabs[existingIndex].isReadOnlyPreview = isReadOnly
            tabs[existingIndex].isPartialFilePreview = false
            tabs[existingIndex].fileByteCount = content.utf8.count
            tabs[existingIndex].lineEnding = lineEnding
            selectedTabID = tabs[existingIndex].id
            recordTabStateMutation(rebuildIndexes: true)
            return
        }

        let tab = TabData(
            name: title,
            content: normalizedContent,
            language: detectedLanguage,
            fileURL: nil,
            languageLocked: languageLocked,
            isDirty: false,
            lastSavedFingerprint: nil,
            lastKnownFileModificationDate: nil,
            isLoadingContent: false,
            isLargeFileCandidate: false,
            lineEnding: lineEnding,
            remotePreviewPath: trimmedPath,
            remoteRevisionToken: revisionToken,
            isReadOnlyPreview: isReadOnly,
            fileByteCount: content.utf8.count
        )
        tabs.append(tab)
        selectedTabID = tab.id
        recordTabStateMutation(rebuildIndexes: true)
    }

    nonisolated static func isSupportedEditorFileURL(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return false }
        let fileName = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        // Executable source scripts belong in a code editor, but a binary marked
        // executable must never be decoded and shown as corrupted plain text.
        if FileManager.default.isExecutableFile(atPath: url.path) {
            let fileHandle = try? FileHandle(forReadingFrom: url)
            defer { try? fileHandle?.close() }
            if let prefix = try? fileHandle?.read(upToCount: 4_096),
               !CoordinatedDocumentAccess.isText(prefix) {
                return false
            }
        }

        let supportedFilenames: Set<String> = ["package.resolved", "dockerfile", "makefile", "gnumakefile"]
        if supportedFilenames.contains(fileName) {
            return true
        }

        if ext.isEmpty {
            return true // Unknown dotfiles and extensionless text are valid documents.
        }

        let knownSupportedExtensions: Set<String> = [
            "swift", "py", "pyi", "js", "mjs", "cjs", "ts", "tsx", "php", "phtml",
            "bak", "csv", "tsv", "cif", "mcif", "txt", "toml", "nix", "eml", "ini", "yaml", "yml", "xml", "svg", "plist", "sql",
            "log", "vim", "ipynb", "java", "kt", "kts", "go", "rb", "rs", "ps1", "psm1",
            "html", "htm", "xhtml", "ee", "exp", "tmpl", "css", "c", "cpp", "cc", "hpp", "hh", "h",
            "m", "mm", "cs", "json", "jsonc", "json5", "ndjson", "md", "markdown", "env", "proto",
            "graphql", "gql", "rst", "conf", "nginx", "cob", "cbl", "cobol", "sh", "bash", "zsh", "fish", "pl", "pm", "lua", "r",
            "tf", "tfvars", "hcl", "xcconfig", "strings", "stringsdict", "jsx",
            "typ", "tex", "latex", "bib", "sty", "cls", "vasp", "isoviz", "upf", "xyz", "xsf", "png", "pdf"
        ]
        if knownSupportedExtensions.contains(ext) {
            return true
        }

        guard let type = UTType(filenameExtension: ext) else { return true }
        if type.conforms(to: .text) || type.conforms(to: .plainText) || type.conforms(to: .sourceCode) {
            return true
        }
        return true // Type hints choose syntax; content validation happens during load.
    }

    /// Preview-only assets must be non-editable from the moment their placeholder
    /// tab is created. Loading is asynchronous, so waiting for the loaded result
    /// leaves a window where Save/Encoding can target the binary source URL.
    nonisolated static func isPreviewOnlyFileURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || ext == "png"
    }

#if os(macOS)
    private func presentUnsupportedFileAlertOnMac(for url: URL) {
        let title = NSLocalizedString("Can’t Open File", comment: "Unsupported file alert title")
        let format = NSLocalizedString("The file \"%@\" is not supported and can’t be opened.", comment: "Unsupported file alert message")
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(format: format, url.lastPathComponent)
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Alert confirmation button"))
        alert.runModal()
    }
#endif

    private nonisolated static func contentFingerprintValue(_ text: String) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(text)
        let value = hasher.finalize()
        return UInt64(bitPattern: Int64(value))
    }

    nonisolated static func largeStructuredTextPreviewLimitForTesting(
        fileExtension: String,
        byteCount: Int
    ) -> Int? {
        EditorLoadHelper.boundedPreviewLimit(forExtension: fileExtension, byteCount: byteCount)
    }

    nonisolated static func isFileBackedEligible(
        url: URL?,
        encoding: TextEncodingDescriptor,
        isRemote: Bool,
        isPartialPreview: Bool
    ) -> Bool {
        guard let url,
              url.isFileURL,
              !isRemote,
              !isPartialPreview,
              encoding.identifier == .utf8 ||
              encoding.identifier == .utf8WithBOM ||
              encoding.identifier == .utf16LittleEndian ||
              encoding.identifier == .utf16LittleEndianWithBOM ||
              encoding.identifier == .utf16BigEndian ||
              encoding.identifier == .utf16BigEndianWithBOM ||
              encoding.identifier == .isoLatin1 ||
              encoding.identifier == .isoLatin5 ||
              encoding.identifier == .windowsCP1252 ||
              encoding.identifier == .windowsCP1251 ||
              encoding.identifier == .macOSRoman ||
              encoding.identifier == .ascii else { return false }
        return true
    }

    nonisolated static func boundedUTF8Encoding(from data: Data) -> TextEncodingDescriptor? {
        guard let encoding = FileBackedTextDocument.boundedEncoding(from: data) else { return nil }
        return encoding.identifier == .utf8 || encoding.identifier == .utf8WithBOM ? encoding : nil
    }


    nonisolated static func boundedLoadEncodingForTesting(
        from url: URL,
        languageHint: String? = nil,
        preferredEncoding: TextEncodingDescriptor? = nil
    ) async throws -> TextEncodingDescriptor? {
        let result = try await loadFileResult(
            from: url,
            extLangHint: languageHint,
            isLargeCandidate: true,
            preferredEncoding: preferredEncoding
        )
        return result.fileBackedEncoding
    }

    private nonisolated static func loadFileResult(
        from url: URL,
        extLangHint: String?,
        isLargeCandidate: Bool,
        preferredEncoding: TextEncodingDescriptor? = nil,
        priority: TaskPriority = .userInitiated
    ) async throws -> EditorFileLoadResult {
        try await Task.detached(priority: priority) {
            try CoordinatedDocumentAccess.read(at: url) { url in
            let didStartScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let initialModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let totalByteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let previewOnlyExtension = url.pathExtension.lowercased()
            if previewOnlyExtension == "png" || previewOnlyExtension == "pdf" {
                return EditorFileLoadResult(
                    content: "[Preview-only \(previewOnlyExtension.uppercased()) file. Open the preview to view its contents.]\n",
                    fileEncodingRawValue: TextEncodingDescriptor.utf8.encodingRawValue,
                    fileEncoding: .utf8,
                    lineEnding: .lf,
                    detectedLanguage: "plain",
                    languageLocked: false,
                    fingerprint: nil,
                    fileModificationDate: initialModificationDate,
                    isLargeCandidate: false,
                    byteCount: totalByteCount,
                    isPartialPreview: true,
                    fileBackedEncoding: nil,
                    fileBackedDocument: nil
                )
            }
            let textProbe = try EditorLoadHelper.partialFileData(from: url, maximumByteCount: 64_000)
            guard CoordinatedDocumentAccess.isText(textProbe, encoding: preferredEncoding) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let boundedPreviewLimit = EditorLoadHelper.boundedPreviewLimit(
                forExtension: previewOnlyExtension,
                byteCount: totalByteCount
            )
            let isPartialPreview = totalByteCount >= EditorLoadHelper.partialOpenByteThreshold || boundedPreviewLimit != nil

            if isLargeCandidate, !isPartialPreview {
                let prefix = textProbe
                let encoding = preferredEncoding ?? FileBackedTextDocument.boundedEncoding(from: prefix, allowsIncompleteUTF8Sequence: totalByteCount > prefix.count)
                if let encoding,
                   Self.isFileBackedEligible(
                       url: url,
                       encoding: encoding,
                       isRemote: false,
                       isPartialPreview: false
                   ) {
                    return EditorFileLoadResult(
                        content: "",
                        fileEncodingRawValue: encoding.encodingRawValue,
                        fileEncoding: encoding,
                        lineEnding: prefix.contains(13) ? .crlf : .lf,
                        detectedLanguage: extLangHint ?? "plain",
                        languageLocked: extLangHint != nil,
                        fingerprint: nil,
                        fileModificationDate: initialModificationDate,
                        isLargeCandidate: true,
                        byteCount: totalByteCount,
                        isPartialPreview: false,
                        fileBackedEncoding: encoding,
                        fileBackedDocument: try Self.prepareFileBackedDocument(from: url, encoding: encoding)
                    )
                }
                let preview = String(decoding: prefix, as: UTF8.self)
                return EditorFileLoadResult(
                    content: preview + "\n\n[Large file preview only: encoding is not supported by the bounded editor.]\n",
                    fileEncodingRawValue: TextEncodingDescriptor.utf8.encodingRawValue,
                    fileEncoding: .utf8,
                    lineEnding: prefix.contains(13) ? .crlf : .lf,
                    detectedLanguage: "plain",
                    languageLocked: false,
                    fingerprint: nil,
                    fileModificationDate: initialModificationDate,
                    isLargeCandidate: true,
                    byteCount: totalByteCount,
                    isPartialPreview: true,
                    fileBackedEncoding: nil,
                    fileBackedDocument: nil
                )
            }

            let data: Data
            if isPartialPreview {
                data = try EditorLoadHelper.partialFileData(
                    from: url,
                    maximumByteCount: boundedPreviewLimit ?? EditorLoadHelper.partialOpenPreviewByteLimit
                )
            } else if isLargeCandidate {
                // Prefer memory-mapped IO for very large files to reduce peak memory churn.
                // Fall back to streaming if mapping is unavailable for the provider.
                if let mapped = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                    data = mapped
                } else {
                    data = try EditorLoadHelper.streamFileData(from: url)
                }
            } else {
                data = try Data(contentsOf: url, options: [.mappedIfSafe])
            }

            if let preferredEncoding, preferredEncoding.decode(data) == nil {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }

            let raw = EditorLoadHelper.decodeFileText(
                data,
                fileURL: url,
                preferredLanguageHint: extLangHint,
                isLargeCandidate: isLargeCandidate,
                preferredEncoding: preferredEncoding,
                allowsFullFileFallback: !isPartialPreview
            )
            let sanitizedContent = EditorLoadHelper.sanitizeTextForFileLoad(
                raw.text,
                useFastPath: data.count >= EditorLoadHelper.fastLoadSanitizeByteThreshold
            )
            let content = isPartialPreview
                ? EditorLoadHelper.partialPreviewText(sanitizedContent, totalByteCount: totalByteCount)
                : sanitizedContent
            let detectedLanguage = isPartialPreview ? "plain" : (extLangHint ?? "plain")
            let fingerprint: UInt64? = isPartialPreview || data.count >= EditorLoadHelper.skipFingerprintByteThreshold
                ? nil
                : Self.contentFingerprintValue(content)

            // Also handle a file that grew past the threshold after openFile's
            // metadata check. Preparation remains inside this detached loader.
            let fileBackedDocument: FileBackedTextDocument?
            if max(totalByteCount, data.count) >= EditorLoadHelper.largeFileCandidateByteThreshold,
               Self.isFileBackedEligible(url: url, encoding: raw.encoding, isRemote: false, isPartialPreview: isPartialPreview) {
                fileBackedDocument = try? Self.prepareFileBackedDocument(from: url, encoding: nil)
            } else {
                fileBackedDocument = nil
            }

            return EditorFileLoadResult(
                content: content,
                fileEncodingRawValue: raw.encodingRawValue,
                fileEncoding: raw.encoding,
                lineEnding: raw.lineEnding,
                detectedLanguage: detectedLanguage,
                languageLocked: !isPartialPreview && extLangHint != nil,
                fingerprint: fingerprint,
                fileModificationDate: initialModificationDate,
                isLargeCandidate: isPartialPreview || data.count >= EditorLoadHelper.largeFileCandidateByteThreshold,
                byteCount: max(totalByteCount, data.count),
                isPartialPreview: isPartialPreview,
                fileBackedEncoding: nil,
                fileBackedDocument: fileBackedDocument
            )
            }
        }.value
    }

    private nonisolated static func prepareFileBackedDocument(
        from url: URL,
        encoding: TextEncodingDescriptor?
    ) throws -> FileBackedTextDocument {
        let document = try encoding.map { try FileBackedTextDocument(url: url, knownEncoding: $0) }
            ?? FileBackedTextDocument(url: url)
        // Finish before transferring ownership to the main actor. The editor's
        // synchronous viewport callbacks must never extend the whole-file index.
        try document.prepareViewportIndex()
        return document
    }

    nonisolated static func normalizedSaveText(
        _ content: String,
        trimTrailingWhitespace: Bool
    ) -> String {
        let normalized = content
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard trimTrailingWhitespace else { return normalized }
        return normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    private nonisolated static func prepareSavePayload(
        from content: String,
        trimTrailingWhitespace: Bool
    ) async -> EditorFileSavePayload {
        await Task.detached(priority: .userInitiated) {
            let clean = Self.normalizedSaveText(
                content,
                trimTrailingWhitespace: trimTrailingWhitespace
            )
            return EditorFileSavePayload(
                content: clean,
                fingerprint: Self.contentFingerprintValue(clean)
            )
        }.value
    }

    private nonisolated static func writeFileContent(
        _ content: String,
        to url: URL,
        encoding: TextEncodingDescriptor,
        lineEnding: TextLineEnding,
        expectedMetadata: LocalFileMetadata? = nil
    ) async throws -> (TextEncodingDescriptor, LocalFileMetadata) {
        try await Task.detached(priority: .utility) {
            guard let data = encoding.encodedData(for: lineEnding.applying(to: content)) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            try CoordinatedDocumentAccess.preserveRecovery(data, for: url)
            return try CoordinatedDocumentAccess.write(at: url) { coordinatedURL in
                var coordinatedURL = coordinatedURL
                coordinatedURL.removeAllCachedResourceValues()
                if let expectedMetadata {
                    let metadata = try coordinatedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    guard let expectedDate = expectedMetadata.modificationDate,
                          let actualDate = metadata.contentModificationDate,
                          let actualSize = metadata.fileSize,
                          actualSize == expectedMetadata.byteCount,
                          abs(actualDate.timeIntervalSince(expectedDate)) <= 0.001 else {
                        throw CocoaError(.fileWriteFileExists)
                    }
                }
                let existingData: Data?
                if expectedMetadata != nil {
                    existingData = try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
                } else {
                    existingData = try? Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
                }
                if existingData != data {
                    try data.write(to: coordinatedURL, options: .atomic)
                }
                // URL caches metadata read before the atomic replacement.
                // The next queued save needs the new inode's revision.
                coordinatedURL.removeAllCachedResourceValues()
                let metadata = try coordinatedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return (encoding, LocalFileMetadata(modificationDate: metadata.contentModificationDate,
                                                     byteCount: metadata.fileSize ?? data.count))
            }
        }.value
    }

    // MARK: - Loaded Content and Language Detection

    private func applyLoadedContent(
        tabID: UUID,
        result: EditorFileLoadResult,
        isExternalRefresh: Bool = false
    ) async {
        cancelPendingLanguageDetection(for: tabID)

        _ = await dispatchTabCommandSerialized(
            .applyLoadedTabState(
                tabID: tabID,
                content: result.content,
                fileEncodingRawValue: result.fileEncodingRawValue,
                fileEncoding: result.fileEncoding,
                lineEnding: result.lineEnding,
                language: result.detectedLanguage,
                languageLocked: result.languageLocked,
                fingerprint: result.fingerprint,
                fileModificationDate: result.fileModificationDate,
                isLargeCandidate: result.isLargeCandidate,
                isPartialPreview: result.isPartialPreview,
                byteCount: result.byteCount,
                isExternalRefresh: isExternalRefresh,
                fileBackedDocument: result.fileBackedDocument
            )
        )
        EditorPerformanceMonitor.shared.markLoadedTabStateApplied(tabID: tabID)
        if !isExternalRefresh {
            if let fileURL = tabs.first(where: { $0.id == tabID })?.fileURL {
                RecentFilesStore.remember(fileURL)
            }
            EditorPerformanceMonitor.shared.endFileOpen(
                tabID: tabID,
                success: true,
                byteCount: result.byteCount
            )
        }
    }

    private func markTabLoadFailed(tabID: UUID) async {
        if let index = tabIndex(for: tabID), tabs[index].lastKnownFileModificationDate == nil,
           !tabs[index].isDirty {
            tabs[index].isReadOnlyPreview = true
            recordTabStateMutation()
        }
        _ = await dispatchTabCommandSerialized(.setLoading(tabID: tabID, isLoading: false))
        fileEncodingErrorMessage = "Couldn’t read the document safely. No changes were saved. Try opening it again or download a local copy first."
        EditorPerformanceMonitor.shared.endFileOpen(tabID: tabID, success: false, byteCount: nil)
        debugLog("Failed to open file.")
    }

    private func contentFingerprint(_ text: String) -> UInt64 {
        Self.contentFingerprintValue(text)
    }

    private func cancelPendingLanguageDetection(for tabID: UUID) {
        pendingLanguageDetectionTasks[tabID]?.cancel()
        pendingLanguageDetectionTasks[tabID] = nil
    }

    private func handleLanguageMetadataAfterMutation(
        tabID: UUID,
        tabIndex index: Int,
        contentRevision: Int,
        contentSnapshot: String?
    ) {
        if tabs[index].document.utf16Length >= Self.largeContentLanguageBypassUTF16Length {
            cancelPendingLanguageDetection(for: tabID)
            applyLargeContentLanguageHintIfNeeded(at: index)
            return
        }

        if tabs[index].document.utf16Length >= Self.deferredLanguageDetectionUTF16Length {
            scheduleDeferredLanguageDetection(for: tabID, expectedContentRevision: contentRevision)
            return
        }

        cancelPendingLanguageDetection(for: tabID)
        let content = contentSnapshot ?? tabs[index].document.string()
        applyLanguageDetectionHeuristics(at: index, content: content)
    }

    private func scheduleDeferredLanguageDetection(for tabID: UUID, expectedContentRevision: Int) {
        cancelPendingLanguageDetection(for: tabID)
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.deferredLanguageDetectionDelayNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.runDeferredLanguageDetection(tabID: tabID, expectedContentRevision: expectedContentRevision)
            }
        }
        pendingLanguageDetectionTasks[tabID] = task
    }

    private func runDeferredLanguageDetection(tabID: UUID, expectedContentRevision: Int) {
        guard let index = tabIndex(for: tabID) else { return }
        guard !tabs[index].isLoadingContent else { return }
        guard tabs[index].contentRevision == expectedContentRevision else { return }

        if tabs[index].document.utf16Length >= Self.largeContentLanguageBypassUTF16Length {
            applyLargeContentLanguageHintIfNeeded(at: index)
            return
        }

        let content = sampledContentForLanguageDetection(tabs[index].document.string())
        applyLanguageDetectionHeuristics(at: index, content: content)
    }

    private func sampledContentForLanguageDetection(_ content: String) -> String {
        let ns = content as NSString
        if ns.length <= Self.deferredLanguageDetectionSampleUTF16Length {
            return content
        }
        return ns.substring(to: Self.deferredLanguageDetectionSampleUTF16Length)
    }

    private func applyLargeContentLanguageHintIfNeeded(at index: Int) {
        let tabID = tabs[index].id
        let nameExt = URL(fileURLWithPath: tabs[index].name).pathExtension.lowercased()
        if !tabs[index].languageLocked,
           let mapped = LanguageDetector.shared.preferredLanguage(for: tabs[index].fileURL) ??
                        languageMap[nameExt] {
            _ = applyTabCommand(.setLanguage(tabID: tabID, language: mapped, lock: false))
        }
    }

    private func applyLanguageDetectionHeuristics(at index: Int, content: String) {
        let tabID = tabs[index].id

        // A filename-derived or user-selected language is authoritative. Content
        // heuristics are only for untyped documents; otherwise Markdown prose that
        // mentions Swift symbols (for example `@MainActor` or "extension") can be
        // incorrectly converted to Swift after an edit.
        guard !tabs[index].languageLocked else { return }

        let lower = content.lowercased()

        // A known filename is a stronger signal than document prose. This also
        // repairs restored tabs whose legacy session metadata did not retain the
        // filename-derived lock before the first edit.
        let nameExt = URL(fileURLWithPath: tabs[index].name).pathExtension.lowercased()
        if let extLang = languageMap[nameExt], !extLang.isEmpty {
            // If extension says C# but content looks Swift-ish, preserve the
            // existing compatibility behavior for misnamed Swift documents.
            if extLang == "csharp" {
                let looksSwift = lower.contains("import swiftui") ||
                    lower.contains(": view") ||
                    lower.contains("@main") ||
                    lower.contains(" final class ")
                if looksSwift {
                    _ = applyTabCommand(.setLanguage(tabID: tabID, language: "swift", lock: true))
                } else {
                    _ = applyTabCommand(.setLanguage(tabID: tabID, language: extLang, lock: true))
                }
            } else {
                _ = applyTabCommand(.setLanguage(tabID: tabID, language: extLang, lock: true))
            }
            return
        }

        // Early lock to Swift if clearly Swift-specific tokens are present.
        let swiftStrongTokens: Bool = (
            lower.contains(" import swiftui") ||
            lower.hasPrefix("import swiftui") ||
            lower.contains("@main") ||
            lower.contains(" final class ") ||
            lower.contains("public final class ") ||
            lower.contains(": view") ||
            lower.contains("@published") ||
            lower.contains("@stateobject") ||
            lower.contains("@mainactor") ||
            lower.contains("protocol ") ||
            lower.contains("extension ") ||
            lower.contains("import appkit") ||
            lower.contains("import uikit") ||
            lower.contains("import foundationmodels") ||
            lower.contains("guard ") ||
            lower.contains("if let ")
        )
        if swiftStrongTokens {
            _ = applyTabCommand(.setLanguage(tabID: tabID, language: "swift", lock: true))
            return
        }

        let result = LanguageDetector.shared.detect(text: content, name: tabs[index].name, fileURL: tabs[index].fileURL)
        let detected = result.lang
        let scores = result.scores
        let current = tabs[index].language
        if detected == "markdown" && !LanguageDetector.shared.isStrongMarkdown(text: content) {
            return
        }
        let swiftScore = scores["swift"] ?? 0
        let csharpScore = scores["csharp"] ?? 0

        let swiftStrongContext: Bool = (
            lower.contains(" final class ") ||
            lower.contains("public final class ") ||
            lower.contains(": view") ||
            lower.contains("@published") ||
            lower.contains("@stateobject") ||
            lower.contains("@mainactor") ||
            lower.contains("protocol ") ||
            lower.contains("extension ") ||
            lower.contains("import swiftui") ||
            lower.contains("import appkit") ||
            lower.contains("import uikit") ||
            lower.contains("import foundationmodels") ||
            lower.contains("guard ") ||
            lower.contains("if let ")
        )

        let hasUsingSystem = lower.contains("\nusing system;") || lower.contains("\nusing system.")
        let hasNamespace = lower.contains("\nnamespace ")
        let hasMainMethod = lower.contains("static void main(") || lower.contains("static int main(")
        let hasCSharpAttributes = (lower.contains("\n[") && lower.contains("]\n") && !lower.contains("@"))
        let csharpContext = hasUsingSystem || hasNamespace || hasMainMethod || hasCSharpAttributes

        // Avoid switching from Swift to C# unless there is very strong C# evidence and margin.
        if current == "swift" && detected == "csharp" {
            let requireMargin = 25
            if swiftStrongContext && !csharpContext {
                return
            }
            if !(csharpContext && csharpScore >= swiftScore + requireMargin) {
                return
            }
            _ = applyTabCommand(.setLanguage(tabID: tabID, language: "csharp", lock: false))
            return
        }

        // Never downgrade to plain while typing when a concrete language is already active.
        if detected == "plain" && current != "plain" {
            return
        }
        _ = applyTabCommand(.setLanguage(tabID: tabID, language: detected, lock: false))
        if detected == "swift" && (result.confidence >= 5 || swiftStrongContext) {
            _ = applyTabCommand(.setLanguage(tabID: tabID, language: detected, lock: true))
        }
    }


    func hasOpenFile(url: URL) -> Bool {
        indexOfOpenTab(for: url) != nil
    }

    // Focuses an existing tab for URL if present.
    func focusTabIfOpen(for url: URL) -> Bool {
        if let existingIndex = indexOfOpenTab(for: url) {
            let tab = tabs[existingIndex]
            if let fileLanguage = LanguageDetector.shared.preferredLanguage(for: url),
               tab.language != fileLanguage || !tab.languageLocked {
                tab.language = fileLanguage
                tab.languageLocked = true
                recordTabStateMutation()
            }
            _ = applyTabCommand(.selectTab(tabID: tab.id))
            reloadOpenTabIfContentUnavailable(tab: tab, url: url)
            return true
        }
        return false
    }

    private func reloadOpenTabIfContentUnavailable(tab: TabData, url: URL) {
        guard !tab.isLoadingContent, tab.document.utf16Length == 0 else { return }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > 0 else { return }
        let extLangHint = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
        let isLargeCandidate = fileSize >= EditorLoadHelper.largeFileCandidateByteThreshold
        _ = applyTabCommand(.setLoading(tabID: tab.id, isLoading: true))
        _ = applyTabCommand(.setLargeFileCandidate(tabID: tab.id, isLargeCandidate: isLargeCandidate))
        EditorPerformanceMonitor.shared.beginFileOpen(tabID: tab.id)
        Task { [weak self] in
            guard let self else { return }
            do {
                let loadResult = try await Self.loadFileResult(
                    from: url,
                    extLangHint: extLangHint,
                    isLargeCandidate: isLargeCandidate
                )
                await self.applyLoadedContent(tabID: tab.id, result: loadResult)
            } catch {
                await self.markTabLoadFailed(tabID: tab.id)
            }
        }
    }

    private func indexOfOpenTab(for url: URL) -> Int? {
        guard let key = Self.normalizedFilePathKey(for: url),
              let tabID = tabIDByStandardizedFilePath[key] else {
            guard let requestedIdentity = Self.fileIdentityKey(for: url) else { return nil }
            return tabs.firstIndex { tab in
                Self.fileIdentityKey(for: tab.fileURL) == requestedIdentity
            }
        }
        return tabIndex(for: tabID)
    }

    // Marks a tab clean after successful save/export and updates URL-derived metadata.
    func markTabSaved(tabID: UUID, fileURL: URL? = nil) {
        guard let index = tabIndex(for: tabID) else { return }
        let metadataURL = fileURL ?? tabs[index].fileURL
        let metadata = metadataURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        }
        _ = applyTabCommand(
            .markSaved(
                tabID: tabID,
                fileURL: fileURL,
                fingerprint: contentFingerprint(tabs[index].document.string()),
                fileModificationDate: metadata?.contentModificationDate,
                fileEncodingRawValue: tabs[index].fileEncodingRawValue,
                fileByteCount: metadata?.fileSize
            )
        )
    }

    // Remaps a tab's file URL after an external move/rename while preserving dirty state.
    func remapTabFileURL(tabID: UUID, to fileURL: URL) {
        _ = applyTabCommand(.remapFileURL(tabID: tabID, fileURL: fileURL))
    }

    // Returns whitespace-delimited word count for status display.
    func wordCount(for text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print(message)
#endif
    }

    // Reads user preference for default language of newly created tabs.
    private func defaultNewTabLanguage() -> String {
        let stored = UserDefaults.standard.string(forKey: "SettingsDefaultNewFileLanguage") ?? "plain"
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "plain" : trimmed
    }
}
