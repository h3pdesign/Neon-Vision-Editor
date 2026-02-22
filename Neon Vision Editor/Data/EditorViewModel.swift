import SwiftUI
import Combine
import UniformTypeIdentifiers
import Foundation
import OSLog
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
    nonisolated static let fastLoadSanitizeByteThreshold = 2_000_000
    nonisolated static let largeFileCandidateByteThreshold = 2_000_000
    nonisolated static let skipFingerprintByteThreshold = 4_000_000
    nonisolated static let stagedAttachByteThreshold = 1_500_000
    nonisolated static let stagedFirstChunkUTF16Length = 180_000
    nonisolated static let streamChunkBytes = 262_144
    nonisolated static let streamFirstPaintBytes = 512_000

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

    nonisolated static func streamFileData(
        from url: URL,
        onFirstPaint: @escaping @Sendable (Data) async -> Void
    ) throws -> Data {
        guard let input = InputStream(url: url) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        input.open()
        defer { input.close() }

        var aggregate = Data()
        aggregate.reserveCapacity(streamFirstPaintBytes)
        var buffer = [UInt8](repeating: 0, count: streamChunkBytes)
        var dispatchedFirstPaint = false

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

            if !dispatchedFirstPaint && aggregate.count >= streamFirstPaintBytes {
                dispatchedFirstPaint = true
                let previewData = Data(aggregate.prefix(streamFirstPaintBytes))
                Task {
                    await onFirstPaint(previewData)
                }
            }
        }

        if !dispatchedFirstPaint && !aggregate.isEmpty {
            let previewData = Data(aggregate.prefix(min(streamFirstPaintBytes, aggregate.count)))
            Task {
                await onFirstPaint(previewData)
            }
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
struct TabData: Identifiable {
    let id = UUID()
    var name: String
    private var contentStorage: PieceTableDocument
    var content: String {
        get { contentStorage.string() }
        set { contentStorage.replaceAll(with: newValue) }
    }
    var language: String
    var fileURL: URL?
    var languageLocked: Bool = false
    var isDirty: Bool = false
    var lastSavedFingerprint: UInt64?
    var isLoadingContent: Bool = false
    var isLargeFileCandidate: Bool = false

    init(
        name: String,
        content: String,
        language: String,
        fileURL: URL?,
        languageLocked: Bool = false,
        isDirty: Bool = false,
        lastSavedFingerprint: UInt64? = nil,
        isLoadingContent: Bool = false,
        isLargeFileCandidate: Bool = false
    ) {
        self.name = name
        self.contentStorage = PieceTableDocument(content)
        self.language = language
        self.fileURL = fileURL
        self.languageLocked = languageLocked
        self.isDirty = isDirty
        self.lastSavedFingerprint = lastSavedFingerprint
        self.isLoadingContent = isLoadingContent
        self.isLargeFileCandidate = isLargeFileCandidate
    }

    var contentUTF16Length: Int { contentStorage.utf16Length }

    mutating func replaceContent(in range: NSRange, with replacement: String) {
        contentStorage.replace(range: range, with: replacement)
    }

    mutating func replaceContentStorage(with text: String) {
        contentStorage.replaceAll(with: text)
    }
}

///MARK: - Editor View Model
// Owns tab lifecycle, file IO, and language-detection behavior.
@MainActor
class EditorViewModel: ObservableObject {
    private static let saveSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "FileIO")
    @Published var tabs: [TabData] = []
    @Published var selectedTabID: UUID?
    @Published var showSidebar: Bool = true
    @Published var isBrainDumpMode: Bool = false
    @Published var showingRename: Bool = false
    @Published var renameText: String = ""
    @Published var isLineWrapEnabled: Bool = true
    
    var selectedTab: TabData? {
        get { tabs.first(where: { $0.id == selectedTabID }) }
        set { selectedTabID = newValue?.id }
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
        "toml": "toml",
        "ini": "ini",
        "yaml": "yaml",
        "yml": "yaml",
        "xml": "xml",
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

    // Creates and selects a new untitled tab.
    func addNewTab() {
        // Keep language discovery active for new untitled tabs.
        let newTab = TabData(name: "Untitled \(tabs.count + 1)", content: "", language: defaultNewTabLanguage(), fileURL: nil, languageLocked: false)
        tabs.append(newTab)
        selectedTabID = newTab.id
    }

    // Renames an existing tab.
    func renameTab(tab: TabData, newName: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].name = newName
        }
    }

    // Updates tab text and applies language detection/locking heuristics.
    func updateTabContent(tab: TabData, content: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            if tabs[index].isLoadingContent {
                // During staged file load, content updates are system-driven; do not mark dirty
                // and do not run language detection on partial content.
                tabs[index].content = content
                return
            }
            let previousLength = tabs[index].contentUTF16Length
            let newLength = (content as NSString).length
            if previousLength == newLength, newLength <= 200_000 {
                // Avoid re-running language detection and view updates when the text is unchanged.
                if tabs[index].content == content {
                    return
                }
            }
            tabs[index].content = content
            if !tabs[index].isDirty {
                tabs[index].isDirty = true
            }

            let isLargeContent = (content as NSString).length >= 1_000_000
            if isLargeContent {
                let nameExt = URL(fileURLWithPath: tabs[index].name).pathExtension.lowercased()
                if !tabs[index].languageLocked,
                   let mapped = LanguageDetector.shared.preferredLanguage(for: tabs[index].fileURL) ??
                                languageMap[nameExt] {
                    tabs[index].language = mapped
                }
                return
            }
            
            // Early lock to Swift if clearly Swift-specific tokens are present
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
                tabs[index].language = "swift"
                tabs[index].languageLocked = true
                return
            }
            
            if !tabs[index].languageLocked {
                // If the tab name has a known extension, honor it and lock
                let nameExt = URL(fileURLWithPath: tabs[index].name).pathExtension.lowercased()
                if let extLang = languageMap[nameExt], !extLang.isEmpty {
                    // If the extension suggests C# but content looks like Swift, prefer Swift and do not lock.
                    if extLang == "csharp" {
                        let looksSwift = lower.contains("import swiftui") || lower.contains(": view") || lower.contains("@main") || lower.contains(" final class ")
                        if looksSwift {
                            tabs[index].language = "swift"
                            tabs[index].languageLocked = true
                        } else {
                            tabs[index].language = extLang
                            tabs[index].languageLocked = true
                        }
                    } else {
                        tabs[index].language = extLang
                        tabs[index].languageLocked = true
                    }
                } else {
                    let result = LanguageDetector.shared.detect(text: content, name: tabs[index].name, fileURL: tabs[index].fileURL)
                    let detected = result.lang
                    let scores = result.scores
                    let current = tabs[index].language
                    let swiftScore = scores["swift"] ?? 0
                    let csharpScore = scores["csharp"] ?? 0

                    // Derive strong Swift tokens and C# context similar to the detector to control switching behavior
                    // (let lower = content.lowercased()) -- removed duplicate since defined above
                    let swiftStrongTokens: Bool = (
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

                    // Avoid switching from Swift to C# unless there is very strong C# evidence and margin
                    if current == "swift" && detected == "csharp" {
                        let requireMargin = 25
                        if swiftStrongTokens && !csharpContext {
                            // Keep Swift when Swift-only tokens are present and no C# context exists
                        } else if !(csharpContext && csharpScore >= swiftScore + requireMargin) {
                            // Not enough evidence to switch away from Swift
                        } else {
                            tabs[index].language = "csharp"
                            tabs[index].languageLocked = false
                        }
                    } else {
                        // Never downgrade an already-detected language to plain while editing.
                        // This avoids syntax-highlight flicker when detector confidence drops temporarily.
                        if detected == "plain" && current != "plain" {
                            return
                        }
                        // For all other cases, accept the detection
                        tabs[index].language = detected
                        // If Swift is confidently detected or Swift-only tokens are present, lock to prevent flip-flops
                        if detected == "swift" && (result.confidence >= 5 || swiftStrongTokens) {
                            tabs[index].languageLocked = true
                        }
                    }
                }
            }
        }
    }

    // Manually sets language and locks automatic switching.
    func updateTabLanguage(tab: TabData, language: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].language = language
            tabs[index].languageLocked = true
        }
    }

    // Closes a tab while guaranteeing one tab remains open.
    func closeTab(tab: TabData) {
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty {
            addNewTab()
        } else if selectedTabID == tab.id {
            selectedTabID = tabs.first?.id
        }
    }

    // Saves tab content to the existing file URL or falls back to Save As.
    func saveFile(tab: TabData) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let url = tabs[index].fileURL {
            do {
                AppLogger.shared.info("Saving file: \(url.lastPathComponent)", category: "Editor")
                let saveInterval = Self.saveSignposter.beginInterval("save_file")
                defer { Self.saveSignposter.endInterval("save_file", saveInterval) }
                let clean = sanitizeTextForEditor(tabs[index].content)
                tabs[index].content = clean
                let fingerprint = contentFingerprint(clean)
                if tabs[index].lastSavedFingerprint == fingerprint, FileManager.default.fileExists(atPath: url.path) {
                    tabs[index].isDirty = false
                    return
                }
                try clean.write(to: url, atomically: true, encoding: .utf8)
                tabs[index].isDirty = false
                AppLogger.shared.info("File saved successfully: \(url.lastPathComponent)", category: "Editor")
                tabs[index].lastSavedFingerprint = fingerprint
            } catch {
                AppLogger.shared.error("Failed to save file: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
            }
        } else {
            saveFileAs(tab: tab)
        }
    }

    // Saves tab content to a user-selected path on macOS.
    func saveFileAs(tab: TabData) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
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
            do {
                AppLogger.shared.info("Saving file as: \(url.lastPathComponent)", category: "Editor")
                let saveAsInterval = Self.saveSignposter.beginInterval("save_file_as")
                defer { Self.saveSignposter.endInterval("save_file_as", saveAsInterval) }
                let clean = sanitizeTextForEditor(tabs[index].content)
                tabs[index].content = clean
                try clean.write(to: url, atomically: true, encoding: .utf8)
                tabs[index].fileURL = url
                tabs[index].name = url.lastPathComponent
                if let mapped = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()] {
                    tabs[index].language = mapped
                    tabs[index].languageLocked = true
                }
                tabs[index].isDirty = false
                tabs[index].lastSavedFingerprint = contentFingerprint(clean)
                AppLogger.shared.info("File saved as: \(url.lastPathComponent)", category: "Editor")
            } catch {
                AppLogger.shared.error("Failed to save file as: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
            }
        }
#else
        // iOS/iPadOS: explicit Save As panel is not available here yet.
        // Keep document dirty so user can export/share via future document APIs.
        AppLogger.shared.warning("Save As is currently only available on macOS.", category: "Editor")
#endif
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
                openFile(url: url)
            }
        }
#else
        // iOS/iPadOS: document picker flow can be added here.
        AppLogger.shared.warning("Open File panel is currently only available on macOS.", category: "Editor")
#endif
    }

    // Loads a file into a new tab unless the file is already open.
    func openFile(url: URL) {
        if focusTabIfOpen(for: url) { return }
        let extLangHint = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let isLargeCandidate = fileSize >= EditorLoadHelper.largeFileCandidateByteThreshold
        let placeholderTab = TabData(
            name: url.lastPathComponent,
            content: "",
            language: extLangHint ?? "plain",
            fileURL: url,
            languageLocked: extLangHint != nil,
            isDirty: false,
            lastSavedFingerprint: nil,
            isLoadingContent: true,
            isLargeFileCandidate: isLargeCandidate
        )
        tabs.append(placeholderTab)
        selectedTabID = placeholderTab.id

        let tabID = placeholderTab.id
        Task.detached(priority: .userInitiated) { [url, extLangHint, tabID, isLargeCandidate] in
            let didStartScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data: Data
                if isLargeCandidate {
                    data = try EditorLoadHelper.streamFileData(from: url) { previewData in
                        let previewRaw = String(decoding: previewData, as: UTF8.self)
                        let preview = EditorLoadHelper.sanitizeTextForFileLoad(previewRaw, useFastPath: true)
                        await self.applyStreamingPreview(tabID: tabID, preview: preview)
                    }
                } else {
                    data = try Data(contentsOf: url, options: [.mappedIfSafe])
                }
                let raw = String(decoding: data, as: UTF8.self)
                let content = EditorLoadHelper.sanitizeTextForFileLoad(
                    raw,
                    useFastPath: data.count >= EditorLoadHelper.fastLoadSanitizeByteThreshold
                )
                let detectedLang: String
                if let extLangHint {
                    detectedLang = extLangHint
                } else {
                    detectedLang = "plain"
                }
                let fingerprint: UInt64? = data.count >= EditorLoadHelper.skipFingerprintByteThreshold
                    ? nil
                    : Self.contentFingerprintValue(content)
                await self.applyLoadedContent(
                    tabID: tabID,
                    content: content,
                    language: detectedLang,
                    languageLocked: extLangHint != nil,
                    fingerprint: fingerprint,
                    isLargeCandidate: data.count >= EditorLoadHelper.largeFileCandidateByteThreshold
                )
            } catch {
                await MainActor.run {
                    if let index = self.tabs.firstIndex(where: { $0.id == tabID }) {
                        self.tabs[index].isLoadingContent = false
                    }
                    self.debugLog("Failed to open file.")
                }
            }
        
        // Start security-scoped resource access (important for bookmarked URLs)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            AppLogger.shared.info("Opening file: \(url.lastPathComponent)", category: "Editor")
            let raw = try String(contentsOf: url, encoding: .utf8)
            let content = sanitizeTextForEditor(raw)
            let extLang = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
            let detectedLang = extLang ?? LanguageDetector.shared.detect(text: content, name: url.lastPathComponent, fileURL: url).lang
            let newTab = TabData(name: url.lastPathComponent,
                                 content: content,
                                 language: detectedLang,
                                 fileURL: url,
                                 languageLocked: extLang != nil,
                                 isDirty: false)
            tabs.append(newTab)
            selectedTabID = newTab.id
            
            // Add to recent files
            RecentFilesManager.shared.addRecentFile(url)
            
            AppLogger.shared.info("File opened successfully: \(url.lastPathComponent) (\(detectedLang))", category: "Editor")
        } catch {
            AppLogger.shared.error("Failed to open file: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
        }
    }

    private func sanitizeTextForEditor(_ input: String) -> String {
        EditorTextSanitizer.sanitize(input)
    }

    private nonisolated static func contentFingerprintValue(_ text: String) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(text)
        let value = hasher.finalize()
        return UInt64(bitPattern: Int64(value))
    }

    private func applyLoadedContent(
        tabID: UUID,
        content: String,
        language: String,
        languageLocked: Bool,
        fingerprint: UInt64?,
        isLargeCandidate: Bool
    ) async {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        tabs[index].language = language
        tabs[index].languageLocked = languageLocked
        tabs[index].isDirty = false
        tabs[index].lastSavedFingerprint = fingerprint
        tabs[index].isLargeFileCandidate = isLargeCandidate
        tabs[index].content = content
        tabs[index].isLoadingContent = false
    }

    private func applyStreamingPreview(tabID: UUID, preview: String) async {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard tabs[index].isLoadingContent, !tabs[index].isDirty else { return }
        if tabs[index].content.utf16.count < preview.utf16.count {
            tabs[index].content = preview
        }
    }

    private func contentFingerprint(_ text: String) -> UInt64 {
        Self.contentFingerprintValue(text)
    }


    func hasOpenFile(url: URL) -> Bool {
        indexOfOpenTab(for: url) != nil
    }

    // Focuses an existing tab for URL if present.
    func focusTabIfOpen(for url: URL) -> Bool {
        if let existingIndex = indexOfOpenTab(for: url) {
            selectedTabID = tabs[existingIndex].id
            return true
        }
        return false
    }

    private func indexOfOpenTab(for url: URL) -> Int? {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        return tabs.firstIndex { tab in
            guard let fileURL = tab.fileURL else { return false }
            return fileURL.resolvingSymlinksInPath().standardizedFileURL == target
        }
    }

    // Marks a tab clean after successful save/export and updates URL-derived metadata.
    func markTabSaved(tabID: UUID, fileURL: URL? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if let fileURL {
            tabs[index].fileURL = fileURL
            tabs[index].name = fileURL.lastPathComponent
            if let mapped = LanguageDetector.shared.preferredLanguage(for: fileURL) ?? languageMap[fileURL.pathExtension.lowercased()] {
                tabs[index].language = mapped
                tabs[index].languageLocked = true
            }
        }
        tabs[index].isDirty = false
        tabs[index].lastSavedFingerprint = contentFingerprint(tabs[index].content)
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
