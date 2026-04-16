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

///MARK: - Text Sanitization
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

private enum EditorLoadHelper {
    // Sidebar-opened project files should reach the editor quickly; full scalar-by-scalar
    // sanitization is only worth the cost for smaller documents.
    nonisolated static let fastLoadSanitizeByteThreshold = 512_000
    nonisolated static let largeFileCandidateByteThreshold = 2_000_000
    nonisolated static let skipFingerprintByteThreshold = 1_000_000
    nonisolated static let streamChunkBytes = 262_144

    nonisolated static func sanitizeTextForFileLoad(_ input: String, useFastPath: Bool) -> String {
        if useFastPath {
            // Fast path for large files: preserve visible content, normalize line endings,
            // and only strip NUL which frequently breaks text system behavior.
            if !input.contains("\0") && !input.contains("\r") {
                return input
            }
            return input
                .replacingOccurrences(of: "\0", with: "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }
        return EditorTextSanitizer.sanitize(input)
    }

    nonisolated static func decodeFileText(
        _ data: Data,
        fileURL: URL,
        preferredLanguageHint: String?,
        isLargeCandidate: Bool
    ) -> String {
        let lowerHint = preferredLanguageHint?.lowercased() ?? ""
        let prefersJSONFastDecode = isLargeCandidate &&
            (lowerHint == "json" || lowerHint == "jsonc" || lowerHint == "json5" || lowerHint == "ipynb")
        let likelyUTF16 = looksLikeUTF16(data)

        if prefersJSONFastDecode && !likelyUTF16 {
            // Large JSON payloads are overwhelmingly UTF-8 in practice; decode directly to
            // avoid extra validation/fallback passes before first render.
            return String(decoding: data, as: UTF8.self)
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        if likelyUTF16 {
            let utf16Candidates: [String.Encoding] = [.utf16, .utf16LittleEndian, .utf16BigEndian]
            for encoding in utf16Candidates {
                if let decoded = String(data: data, encoding: encoding) {
                    return decoded
                }
            }
        }

        if let cp1252 = String(data: data, encoding: .windowsCP1252) {
            return cp1252
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        if let fallback = try? String(contentsOf: fileURL, encoding: .utf8) {
            return fallback
        }
        return String(decoding: data, as: UTF8.self)
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
}

private struct EditorFileLoadResult: Sendable {
    let content: String
    let detectedLanguage: String
    let languageLocked: Bool
    let fingerprint: UInt64?
    let fileModificationDate: Date?
    let isLargeCandidate: Bool
    let byteCount: Int
}

private struct EditorFileSavePayload: Sendable {
    let content: String
    let fingerprint: UInt64
}

///MARK: - Piece Table Storage
// Mutable text buffer using original/add buffers and piece spans.
final class PieceTableDocument {
    private enum Source {
        case original
        case add
    }

    private struct Piece {
        let source: Source
        let startUTF16: Int
        let lengthUTF16: Int
    }

    private var originalBuffer: String
    private var addBuffer: String = ""
    private var pieces: [Piece] = []
    private var cachedString: String?

    init(_ text: String) {
        originalBuffer = text
        let len = (text as NSString).length
        if len > 0 {
            pieces = [Piece(source: .original, startUTF16: 0, lengthUTF16: len)]
        }
    }

    var utf16Length: Int {
        pieces.reduce(0) { $0 + $1.lengthUTF16 }
    }

    func string() -> String {
        if let cachedString {
            return cachedString
        }
        if pieces.isEmpty {
            cachedString = ""
            return ""
        }
        let originalNSString = originalBuffer as NSString
        let addNSString = addBuffer as NSString
        var out = String()
        out.reserveCapacity(max(0, utf16Length))
        for piece in pieces {
            guard piece.lengthUTF16 > 0 else { continue }
            let ns = piece.source == .original ? originalNSString : addNSString
            out += ns.substring(with: NSRange(location: piece.startUTF16, length: piece.lengthUTF16))
        }
        cachedString = out
        return out
    }

    func replaceAll(with text: String) {
        originalBuffer = text
        addBuffer = ""
        cachedString = text
        pieces.removeAll(keepingCapacity: true)
        let len = (text as NSString).length
        if len > 0 {
            pieces.append(Piece(source: .original, startUTF16: 0, lengthUTF16: len))
        }
    }

    func replace(range: NSRange, with replacement: String) {
        let total = utf16Length
        let clampedLocation = min(max(0, range.location), total)
        let maxLen = max(0, total - clampedLocation)
        let clampedLength = min(max(0, range.length), maxLen)
        let lower = clampedLocation
        let upper = clampedLocation + clampedLength

        var newPieces: [Piece] = []
        newPieces.reserveCapacity(pieces.count + 2)

        var cursor = 0
        for piece in pieces {
            let pieceStart = cursor
            let pieceEnd = pieceStart + piece.lengthUTF16
            defer { cursor = pieceEnd }

            if piece.lengthUTF16 == 0 {
                continue
            }
            if pieceEnd <= lower || pieceStart >= upper {
                newPieces.append(piece)
                continue
            }

            if lower > pieceStart {
                let leftLen = lower - pieceStart
                if leftLen > 0 {
                    newPieces.append(Piece(source: piece.source, startUTF16: piece.startUTF16, lengthUTF16: leftLen))
                }
            }
            if upper < pieceEnd {
                let rightOffset = upper - pieceStart
                let rightLen = pieceEnd - upper
                if rightLen > 0 {
                    newPieces.append(Piece(source: piece.source, startUTF16: piece.startUTF16 + rightOffset, lengthUTF16: rightLen))
                }
            }
        }

        if !replacement.isEmpty {
            let addStart = (addBuffer as NSString).length
            addBuffer.append(replacement)
            let addLen = (replacement as NSString).length
            if addLen > 0 {
                let insertIndex: Int = {
                    if clampedLength > 0 {
                        return indexForUTF16Location(in: newPieces, location: lower)
                    }
                    return insertionIndexForUTF16Location(in: newPieces, location: lower)
                }()
                newPieces.insert(Piece(source: .add, startUTF16: addStart, lengthUTF16: addLen), at: insertIndex)
            }
        }

        pieces = coalescedPieces(newPieces)
        cachedString = nil
    }

    private func indexForUTF16Location(in pieces: [Piece], location: Int) -> Int {
        var cursor = 0
        for (idx, piece) in pieces.enumerated() {
            let end = cursor + piece.lengthUTF16
            if location < end {
                return idx
            }
            cursor = end
        }
        return pieces.count
    }

    private func insertionIndexForUTF16Location(in pieces: [Piece], location: Int) -> Int {
        var cursor = 0
        for (idx, piece) in pieces.enumerated() {
            let end = cursor + piece.lengthUTF16
            if location <= cursor {
                return idx
            }
            if location < end {
                return idx + 1
            }
            cursor = end
        }
        return pieces.count
    }

    private func coalescedPieces(_ items: [Piece]) -> [Piece] {
        var result: [Piece] = []
        result.reserveCapacity(items.count)
        for piece in items where piece.lengthUTF16 > 0 {
            if let last = result.last,
               last.source == piece.source,
               last.startUTF16 + last.lengthUTF16 == piece.startUTF16 {
                result[result.count - 1] = Piece(
                    source: last.source,
                    startUTF16: last.startUTF16,
                    lengthUTF16: last.lengthUTF16 + piece.lengthUTF16
                )
            } else {
                result.append(piece)
            }
        }
        return result
    }
}

///MARK: - Tab Model
// Represents one editor tab and its mutable editing state.
@MainActor
@Observable
final class TabData: Identifiable {
    let id: UUID
    fileprivate(set) var name: String
    private var contentStorage: PieceTableDocument
    private(set) var contentRevision: Int = 0
    fileprivate(set) var language: String
    fileprivate(set) var fileURL: URL?
    fileprivate(set) var languageLocked: Bool
    fileprivate(set) var isDirty: Bool
    fileprivate(set) var lastSavedFingerprint: UInt64?
    fileprivate(set) var lastKnownFileModificationDate: Date?
    fileprivate(set) var isLoadingContent: Bool
    fileprivate(set) var isLargeFileCandidate: Bool
    fileprivate(set) var remotePreviewPath: String?
    fileprivate(set) var remoteRevisionToken: String?
    fileprivate(set) var isReadOnlyPreview: Bool

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
        remotePreviewPath: String? = nil,
        remoteRevisionToken: String? = nil,
        isReadOnlyPreview: Bool = false
    ) {
        self.id = id
        self.name = name
        self.contentStorage = PieceTableDocument(content)
        self.language = language
        self.fileURL = fileURL
        self.languageLocked = languageLocked
        self.isDirty = isDirty
        self.lastSavedFingerprint = lastSavedFingerprint
        self.lastKnownFileModificationDate = lastKnownFileModificationDate
        self.isLoadingContent = isLoadingContent
        self.isLargeFileCandidate = isLargeFileCandidate
        self.remotePreviewPath = remotePreviewPath
        self.remoteRevisionToken = remoteRevisionToken
        self.isReadOnlyPreview = isReadOnlyPreview
    }

    var content: String { contentStorage.string() }
    var contentUTF16Length: Int { contentStorage.utf16Length }
    var isRemoteDocument: Bool { remotePreviewPath != nil }

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
        contentStorage.replaceAll(with: text)
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
        contentStorage.replace(range: NSRange(location: safeLocation, length: safeLength), with: replacement)
        contentRevision &+= 1
        if markDirty && !isDirty {
            isDirty = true
        }
        return true
    }

    func markClean(withFingerprint fingerprint: UInt64?) {
        isDirty = false
        lastSavedFingerprint = fingerprint
    }

    func updateLastKnownFileModificationDate(_ date: Date?) {
        lastKnownFileModificationDate = date
    }

    func updateRemoteRevisionToken(_ token: String?) {
        remoteRevisionToken = token
    }

    func resetContentRevision() {
        contentRevision = 0
    }
}

///MARK: - Editor View Model
// Owns tab lifecycle, file IO, and language-detection behavior.
@MainActor
@Observable
class EditorViewModel {
    struct ExternalFileConflictState: Sendable {
        let tabID: UUID
        let fileURL: URL
        let diskModifiedAt: Date?
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
    private(set) var tabs: [TabData] = []
    private(set) var selectedTabID: UUID?
    var pendingExternalFileConflict: ExternalFileConflictState?
    var pendingRemoteSaveIssue: RemoteSaveIssueState?
    var showSidebar: Bool = true
    var isBrainDumpMode: Bool = false
    var showingRename: Bool = false
    var renameText: String = ""
    var isLineWrapEnabled: Bool = true
    @ObservationIgnored private let tabCommandQueue = TabCommandQueue()
    @ObservationIgnored private var pendingLanguageDetectionTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var tabIndexByID: [UUID: Int] = [:]
    @ObservationIgnored private var tabIDByStandardizedFilePath: [String: UUID] = [:]
    @ObservationIgnored private var tabStateVersion: Int = 0
	    
    var selectedTab: TabData? {
        get {
            guard let selectedTabID, let index = tabIndexByID[selectedTabID], tabs.indices.contains(index) else {
                return nil
            }
            return tabs[index]
        }
        set { selectTab(id: newValue?.id) }
    }

    // Observable token for tab-array and tab-state changes when Combine publishers are unavailable.
    var tabsObservationToken: Int {
        tabStateVersion
    }

    private func tabIndex(for tabID: UUID) -> Int? {
        guard let index = tabIndexByID[tabID], tabs.indices.contains(index) else { return nil }
        return index
    }

    private static func normalizedFilePathKey(for url: URL?) -> String? {
        guard let url else { return nil }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
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

    private func recordTabStateMutation(rebuildIndexes: Bool = false) {
        if rebuildIndexes {
            rebuildTabIndexes()
        }
        tabStateVersion &+= 1
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
    }

    private enum TabCommand: Sendable {
        case updateContent(tabID: UUID, mutation: TabContentMutation)
        case markSaved(tabID: UUID, fileURL: URL?, fingerprint: UInt64?, fileModificationDate: Date?)
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
        case selectTab(tabID: UUID?)
        case resetTabs
        case restoreTabs(snapshots: [RestoredTabSnapshot], selectedIndex: Int?)
        case renameTab(tabID: UUID, name: String)
        case setLoading(tabID: UUID, isLoading: Bool)
        case setLargeFileCandidate(tabID: UUID, isLargeCandidate: Bool)
        case resetContentRevision(tabID: UUID)
        case applyLoadedTabState(
            tabID: UUID,
            content: String,
            language: String,
            languageLocked: Bool,
            fingerprint: UInt64?,
            fileModificationDate: Date?,
            isLargeCandidate: Bool
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
                recordTabStateMutation()
            }
            return outcome

        case let .markSaved(tabID, fileURL, fingerprint, fileModificationDate):
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
            recordTabStateMutation(rebuildIndexes: true)
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
            recordTabStateMutation()
            return TabCommandOutcome(index: index)

        case let .closeTab(tabID):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            cancelPendingLanguageDetection(for: tabID)
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
                isLargeFileCandidate: isLargeCandidate
            )
            tabs.append(tab)
            selectedTabID = tab.id
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome(index: tabs.count - 1, tabID: tab.id)

        case let .selectTab(tabID):
            if selectedTabID == tabID {
                return TabCommandOutcome()
            }
            selectedTabID = tabID
            recordTabStateMutation()
            return TabCommandOutcome()

        case .resetTabs:
            for tab in tabs {
                cancelPendingLanguageDetection(for: tab.id)
            }
            tabs.removeAll(keepingCapacity: true)
            selectedTabID = nil
            recordTabStateMutation(rebuildIndexes: true)
            return TabCommandOutcome()

        case let .restoreTabs(snapshots, selectedIndex):
            for tab in tabs {
                cancelPendingLanguageDetection(for: tab.id)
            }
            tabs.removeAll(keepingCapacity: true)
            tabs.reserveCapacity(snapshots.count)
            for snapshot in snapshots {
                tabs.append(
                    TabData(
                        name: snapshot.name,
                        content: snapshot.content,
                        language: snapshot.language,
                        fileURL: snapshot.fileURL,
                        languageLocked: snapshot.languageLocked,
                        isDirty: snapshot.isDirty,
                        lastSavedFingerprint: snapshot.lastSavedFingerprint,
                        lastKnownFileModificationDate: snapshot.lastKnownFileModificationDate
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
            recordTabStateMutation()
            return TabCommandOutcome(index: index)

        case let .setLoading(tabID, isLoading):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            if tabs[index].isLoadingContent == isLoading {
                return TabCommandOutcome(index: index)
            }
            tabs[index].isLoadingContent = isLoading
            recordTabStateMutation()
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

        case let .applyLoadedTabState(tabID, content, language, languageLocked, fingerprint, fileModificationDate, isLargeCandidate):
            guard let index = tabIndex(for: tabID) else { return TabCommandOutcome() }
            tabs[index].language = language
            tabs[index].languageLocked = languageLocked
            tabs[index].markClean(withFingerprint: fingerprint)
            tabs[index].updateLastKnownFileModificationDate(fileModificationDate)
            tabs[index].isLargeFileCandidate = isLargeCandidate
            let didChange = tabs[index].replaceContentStorage(
                with: content,
                markDirty: false,
                compareIfLengthAtMost: nil
            )
            tabs[index].resetContentRevision()
            tabs[index].isLoadingContent = false
            recordTabStateMutation()
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
            let totalLength = tab.contentUTF16Length
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
        "py": "python",
        "pyi": "python",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "php": "php",
        "phtml": "php",
        "csv": "csv",
        "tsv": "csv",
        "txt": "plain",
        "toml": "toml",
        "ini": "ini",
        "yaml": "yaml",
        "yml": "yaml",
        "xml": "xml",
        "svg": "xml",
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

    func selectTab(id: UUID?) {
        _ = applyTabCommand(.selectTab(tabID: id))
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
    func applyTabContentEdit(tabID: UUID, range: NSRange, replacement: String) {
        guard let index = tabIndex(for: tabID) else { return }
        guard !tabs[index].isReadOnlyPreview else { return }
        guard !tabs[index].isLoadingContent else { return }

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
        guard outcome.didChangeContent,
              let commandIndex = outcome.index,
              let contentRevision = outcome.contentRevision else { return }

        handleLanguageMetadataAfterMutation(
            tabID: tabID,
            tabIndex: commandIndex,
            contentRevision: contentRevision,
            contentSnapshot: nil
        )
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

    // Saves tab content to the existing file URL or falls back to Save As.
    func saveFile(tabID: UUID, allowExternalOverwrite: Bool = false) {
        guard let index = tabIndex(for: tabID) else { return }
        guard !tabs[index].isReadOnlyPreview else { return }
        if tabs[index].fileURL == nil, let remotePath = tabs[index].remotePreviewPath {
            enqueueRemoteSave(tabID: tabID, remotePath: remotePath, signpostName: "save_remote_file")
            return
        }
        if !allowExternalOverwrite,
           let conflict = detectExternalConflict(for: tabs[index]) {
            pendingExternalFileConflict = conflict
            return
        }
        if let url = tabs[index].fileURL {
            enqueueSave(tabID: tabID, to: url, updateFileURLOnSuccess: nil, signpostName: "save_file")
        } else {
            saveFileAs(tabID: tabID)
        }
    }

    func saveFile(tab: TabData) {
        saveFile(tabID: tab.id)
    }

    func resolveExternalConflictByKeepingLocal(tabID: UUID) {
        pendingExternalFileConflict = nil
        saveFile(tabID: tabID, allowExternalOverwrite: true)
    }

    func resolveExternalConflictByReloadingDisk(tabID: UUID) {
        pendingExternalFileConflict = nil
        guard let index = tabIndex(for: tabID),
              let url = tabs[index].fileURL else { return }
        let isLargeCandidate = tabs[index].isLargeFileCandidate
        let extLangHint = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
        _ = applyTabCommand(.setLoading(tabID: tabID, isLoading: true))
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
        let fileName = tabs[index].name
        let languageHint = tabs[index].language
        let isLargeCandidate = tabs[index].isLargeFileCandidate
        let localContent = tabs[index].content
        return await Task.detached(priority: .utility) {
            let data = (try? Data(contentsOf: url, options: [.mappedIfSafe])) ?? Data()
            let diskContent = EditorLoadHelper.decodeFileText(
                data,
                fileURL: url,
                preferredLanguageHint: languageHint,
                isLargeCandidate: isLargeCandidate
            )
            return ExternalFileComparisonSnapshot(
                fileName: fileName,
                localContent: localContent,
                diskContent: diskContent
            )
        }.value
    }

    func refreshExternalConflictForTab(tabID: UUID) {
        guard let index = tabIndex(for: tabID) else { return }
        pendingExternalFileConflict = detectExternalConflict(for: tabs[index])
    }

    func remoteConflictComparisonSnapshot(tabID: UUID) async -> RemoteConflictComparisonSnapshot? {
        guard let index = tabIndex(for: tabID),
              let remotePath = tabs[index].remotePreviewPath else { return nil }
        let fileName = tabs[index].name
        let localContent = tabs[index].content

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
        guard !tabs[index].isReadOnlyPreview else { return }
        if tabs[index].fileURL == nil, let remotePath = tabs[index].remotePreviewPath {
            enqueueRemoteSave(tabID: tabID, remotePath: remotePath, signpostName: "save_remote_file")
            return
        }
#if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tabs[index].name
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [
            .text,
            .swiftSource,
            .pythonScript,
            .javaScript,
            .html,
            .css,
            .cSource,
            .json,
            mdType
        ]

        if panel.runModal() == .OK, let url = panel.url {
            enqueueSave(tabID: tabID, to: url, updateFileURLOnSuccess: url, signpostName: "save_file_as")
        }
#else
        // iOS/iPadOS: explicit Save As panel is not available here yet.
        // Keep document dirty so user can export/share via future document APIs.
        debugLog("Save As is currently only available on macOS.")
#endif
    }

    func saveFileAs(tab: TabData) {
        saveFileAs(tabID: tab.id)
    }

    private func enqueueSave(tabID: UUID, to destinationURL: URL, updateFileURLOnSuccess: URL?, signpostName: StaticString) {
        guard let index = tabIndex(for: tabID) else { return }
        let snapshotContent = tabs[index].content
        let snapshotRevision = tabs[index].contentRevision
        let snapshotLastSavedFingerprint = tabs[index].lastSavedFingerprint

        Task { [weak self] in
            guard let self else { return }
            let saveInterval = Self.saveSignposter.beginInterval(signpostName)
            defer { Self.saveSignposter.endInterval(signpostName, saveInterval) }

            let payload = await Self.prepareSavePayload(from: snapshotContent)

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

            if snapshotLastSavedFingerprint == payload.fingerprint,
               FileManager.default.fileExists(atPath: destinationURL.path) {
                if let finalIndex = self.tabIndex(for: tabID),
                   self.tabs[finalIndex].contentRevision == expectedRevision {
                    let fileModificationDate = try? destinationURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    _ = self.applyTabCommand(
                        .markSaved(
                            tabID: tabID,
                            fileURL: updateFileURLOnSuccess,
                            fingerprint: payload.fingerprint,
                            fileModificationDate: fileModificationDate
                        )
                    )
                    self.pendingExternalFileConflict = nil
                }
                return
            }

            do {
                try await Self.writeFileContent(payload.content, to: destinationURL)
            } catch {
                self.debugLog("Failed to save file.")
                return
            }

            guard let finalIndex = self.tabIndex(for: tabID),
                  self.tabs[finalIndex].contentRevision == expectedRevision else {
                return
            }

            let fileModificationDate = try? destinationURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            _ = self.applyTabCommand(
                .markSaved(
                    tabID: tabID,
                    fileURL: updateFileURLOnSuccess,
                    fingerprint: payload.fingerprint,
                    fileModificationDate: fileModificationDate
                )
            )
            self.pendingExternalFileConflict = nil
        }
    }

    private func enqueueRemoteSave(tabID: UUID, remotePath: String, signpostName: StaticString) {
        guard let index = tabIndex(for: tabID) else { return }
        let snapshotContent = tabs[index].content
        let snapshotRevision = tabs[index].contentRevision
        let snapshotRemoteRevisionToken = tabs[index].remoteRevisionToken

        Task { [weak self] in
            guard let self else { return }
            let saveInterval = Self.saveSignposter.beginInterval(signpostName)
            defer { Self.saveSignposter.endInterval(signpostName, saveInterval) }

            let payload = await Self.prepareSavePayload(from: snapshotContent)

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
                content: payload.content,
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
                    fingerprint: self.contentFingerprint(self.tabs[postflightIndex].content),
                    fileModificationDate: nil
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

    private func detectExternalConflict(for tab: TabData) -> ExternalFileConflictState? {
        guard tab.isDirty, let fileURL = tab.fileURL else { return nil }
        guard let diskModifiedAt = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return nil
        }
        guard let known = tab.lastKnownFileModificationDate else { return nil }
        if diskModifiedAt.timeIntervalSince(known) > 0.5 {
            return ExternalFileConflictState(tabID: tab.id, fileURL: fileURL, diskModifiedAt: diskModifiedAt)
        }
        return nil
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
    func openFile(url: URL) -> Bool {
        guard Self.isSupportedEditorFileURL(url) else {
            debugLog("Unsupported file type skipped: \(url.lastPathComponent)")
            return false
        }
        if focusTabIfOpen(for: url) { return true }
        let extLangHint = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let isLargeCandidate = fileSize >= EditorLoadHelper.largeFileCandidateByteThreshold
        let tabID = UUID()
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

        if let existingIndex = tabs.firstIndex(where: { $0.remotePreviewPath == trimmedPath }) {
            cancelPendingLanguageDetection(for: tabs[existingIndex].id)
            tabs[existingIndex].name = title
            tabs[existingIndex].fileURL = nil
            tabs[existingIndex].language = detectedLanguage
            tabs[existingIndex].languageLocked = languageLocked
            _ = tabs[existingIndex].replaceContentStorage(with: content, markDirty: false, compareIfLengthAtMost: nil)
            tabs[existingIndex].markClean(withFingerprint: nil)
            tabs[existingIndex].updateLastKnownFileModificationDate(nil)
            tabs[existingIndex].isLoadingContent = false
            tabs[existingIndex].isLargeFileCandidate = false
            tabs[existingIndex].remotePreviewPath = trimmedPath
            tabs[existingIndex].remoteRevisionToken = revisionToken
            tabs[existingIndex].isReadOnlyPreview = isReadOnly
            selectedTabID = tabs[existingIndex].id
            recordTabStateMutation(rebuildIndexes: true)
            return
        }

        let tab = TabData(
            name: title,
            content: content,
            language: detectedLanguage,
            fileURL: nil,
            languageLocked: languageLocked,
            isDirty: false,
            lastSavedFingerprint: nil,
            lastKnownFileModificationDate: nil,
            isLoadingContent: false,
            isLargeFileCandidate: false,
            remotePreviewPath: trimmedPath,
            remoteRevisionToken: revisionToken,
            isReadOnlyPreview: isReadOnly
        )
        tabs.append(tab)
        selectedTabID = tab.id
        recordTabStateMutation(rebuildIndexes: true)
    }

    nonisolated static func isSupportedEditorFileURL(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return false }
        let fileName = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if ext.isEmpty {
            let supportedDotfiles: Set<String> = [
                ".zshrc", ".zprofile", ".zlogin", ".zlogout",
                ".bashrc", ".bash_profile", ".bash_login", ".bash_logout",
                ".profile", ".vimrc", ".env", ".envrc", ".gitconfig"
            ]
            return supportedDotfiles.contains(fileName) || fileName.hasPrefix(".env")
        }

        let knownSupportedExtensions: Set<String> = [
            "swift", "py", "pyi", "js", "mjs", "cjs", "ts", "tsx", "php", "phtml",
            "csv", "tsv", "txt", "toml", "ini", "yaml", "yml", "xml", "svg", "plist", "sql",
            "log", "vim", "ipynb", "java", "kt", "kts", "go", "rb", "rs", "ps1", "psm1",
            "html", "htm", "ee", "exp", "tmpl", "css", "c", "cpp", "cc", "hpp", "hh", "h",
            "m", "mm", "cs", "json", "jsonc", "json5", "md", "markdown", "env", "proto",
            "graphql", "gql", "rst", "conf", "nginx", "cob", "cbl", "cobol", "sh", "bash", "zsh",
            "tex", "latex", "bib", "sty", "cls"
        ]
        if knownSupportedExtensions.contains(ext) {
            return true
        }

        guard let type = UTType(filenameExtension: ext) else { return false }
        if type.conforms(to: .text) || type.conforms(to: .plainText) || type.conforms(to: .sourceCode) {
            return true
        }
        return false
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

    private nonisolated static func loadFileResult(
        from url: URL,
        extLangHint: String?,
        isLargeCandidate: Bool
    ) async throws -> EditorFileLoadResult {
        try await Task.detached(priority: .userInitiated) {
            let didStartScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let initialModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

            let data: Data
            if isLargeCandidate {
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

            let raw = EditorLoadHelper.decodeFileText(
                data,
                fileURL: url,
                preferredLanguageHint: extLangHint,
                isLargeCandidate: isLargeCandidate
            )
            let content = EditorLoadHelper.sanitizeTextForFileLoad(
                raw,
                useFastPath: data.count >= EditorLoadHelper.fastLoadSanitizeByteThreshold
            )
            let detectedLanguage = extLangHint ?? "plain"
            let fingerprint: UInt64? = data.count >= EditorLoadHelper.skipFingerprintByteThreshold
                ? nil
                : Self.contentFingerprintValue(content)

            return EditorFileLoadResult(
                content: content,
                detectedLanguage: detectedLanguage,
                languageLocked: extLangHint != nil,
                fingerprint: fingerprint,
                fileModificationDate: initialModificationDate,
                isLargeCandidate: data.count >= EditorLoadHelper.largeFileCandidateByteThreshold,
                byteCount: data.count
            )
        }.value
    }

    private nonisolated static func prepareSavePayload(from content: String) async -> EditorFileSavePayload {
        await Task.detached(priority: .userInitiated) {
            // Keep save path non-destructive: only normalize line endings and strip NUL.
            let clean = content
                .replacingOccurrences(of: "\0", with: "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            return EditorFileSavePayload(
                content: clean,
                fingerprint: Self.contentFingerprintValue(clean)
            )
        }.value
    }

    private nonisolated static func writeFileContent(_ content: String, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }

    private func applyLoadedContent(
        tabID: UUID,
        result: EditorFileLoadResult
    ) async {
        cancelPendingLanguageDetection(for: tabID)

        _ = await dispatchTabCommandSerialized(
            .applyLoadedTabState(
                tabID: tabID,
                content: result.content,
                language: result.detectedLanguage,
                languageLocked: result.languageLocked,
                fingerprint: result.fingerprint,
                fileModificationDate: result.fileModificationDate,
                isLargeCandidate: result.isLargeCandidate
            )
        )
        if let fileURL = tabs.first(where: { $0.id == tabID })?.fileURL {
            RecentFilesStore.remember(fileURL)
        }
        EditorPerformanceMonitor.shared.endFileOpen(
            tabID: tabID,
            success: true,
            byteCount: result.byteCount
        )
    }

    private func markTabLoadFailed(tabID: UUID) async {
        _ = await dispatchTabCommandSerialized(.setLoading(tabID: tabID, isLoading: false))
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
        if tabs[index].contentUTF16Length >= Self.largeContentLanguageBypassUTF16Length {
            cancelPendingLanguageDetection(for: tabID)
            applyLargeContentLanguageHintIfNeeded(at: index)
            return
        }

        if tabs[index].contentUTF16Length >= Self.deferredLanguageDetectionUTF16Length {
            scheduleDeferredLanguageDetection(for: tabID, expectedContentRevision: contentRevision)
            return
        }

        cancelPendingLanguageDetection(for: tabID)
        let content = contentSnapshot ?? tabs[index].content
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

        if tabs[index].contentUTF16Length >= Self.largeContentLanguageBypassUTF16Length {
            applyLargeContentLanguageHintIfNeeded(at: index)
            return
        }

        let content = sampledContentForLanguageDetection(tabs[index].content)
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

        // Early lock to Swift if clearly Swift-specific tokens are present.
        let lower = content.lowercased()
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

        guard !tabs[index].languageLocked else { return }
        let nameExt = URL(fileURLWithPath: tabs[index].name).pathExtension.lowercased()
        if let extLang = languageMap[nameExt], !extLang.isEmpty {
            // If extension says C# but content looks Swift-ish, prefer Swift.
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

        let result = LanguageDetector.shared.detect(text: content, name: tabs[index].name, fileURL: tabs[index].fileURL)
        let detected = result.lang
        let scores = result.scores
        let current = tabs[index].language
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
            _ = applyTabCommand(.selectTab(tabID: tab.id))
            reloadOpenTabIfContentUnavailable(tab: tab, url: url)
            return true
        }
        return false
    }

    private func reloadOpenTabIfContentUnavailable(tab: TabData, url: URL) {
        guard !tab.isLoadingContent, tab.contentUTF16Length == 0 else { return }
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
            return nil
        }
        return tabIndex(for: tabID)
    }

    // Marks a tab clean after successful save/export and updates URL-derived metadata.
    func markTabSaved(tabID: UUID, fileURL: URL? = nil) {
        guard let index = tabIndex(for: tabID) else { return }
        _ = applyTabCommand(
            .markSaved(
                tabID: tabID,
                fileURL: fileURL,
                fingerprint: contentFingerprint(tabs[index].content),
                fileModificationDate: fileURL.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
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
