import SwiftUI
import Foundation
import Combine
import ImageIO
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum MarkdownProjectPreviewMode: String, CaseIterable, Identifiable {
    case grid
    case stack

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum MarkdownProjectPreviewSortOrder: String, CaseIterable, Identifiable, Sendable {
    case name
    case lastEdited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .lastEdited: return "Last Edited"
        }
    }
}

enum MarkdownProjectPreviewPlacement: String, CaseIterable, Identifiable {
    case leading
    case trailing

    var id: String { rawValue }
    var title: String { self == .leading ? "Left of Markdown Preview" : "Right of Markdown Preview" }
}

struct MarkdownProjectPreviewCardData: Identifiable, Sendable, Hashable {
    let id: String
    let url: URL
    let relativePath: String
    let title: String?
    let excerpt: String
    let fileSize: Int64?
    let modificationDate: Date?
    let headingCount: Int
    let imageData: Data?
    let isLargeFile: Bool

    var displayTitle: String { title?.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent }
    var sizeLabel: String {
        guard let fileSize else { return "Size unavailable" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

@MainActor
final class MarkdownProjectPreviewModel: ObservableObject {
    @Published private(set) var cards: [MarkdownProjectPreviewCardData] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingStatus = ""
    private(set) var sortOrder: MarkdownProjectPreviewSortOrder = .name
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    func setSortOrder(_ sortOrder: MarkdownProjectPreviewSortOrder) {
        guard self.sortOrder != sortOrder else { return }
        self.sortOrder = sortOrder
        sortCards()
    }

    func refresh(entries: [ProjectFileIndex.Entry], projectRoot: URL?) {
        refreshTask?.cancel()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        guard let projectRoot else {
            cards = []
            isLoading = false
            loadingStatus = ""
            return
        }

        let markdownEntries = entries.filter { entry in
            ["md", "markdown", "mdown", "mkdn", "mdx"].contains(entry.url.pathExtension.lowercased())
        }.sorted { $0.standardizedPath.localizedCaseInsensitiveCompare($1.standardizedPath) == .orderedAscending }
        cards = []
        isLoading = true
        loadingStatus = markdownEntries.isEmpty ? "No Markdown files found" : "Preparing \(markdownEntries.count) Markdown previews…"
        refreshTask = Task(priority: .utility) { [weak self] in
            var loadedCount = 0
            var loadedCards: [MarkdownProjectPreviewCardData] = []
            loadedCards.reserveCapacity(markdownEntries.count)
            await withTaskGroup(of: MarkdownProjectPreviewCardData?.self) { group in
                for entry in markdownEntries {
                    group.addTask(priority: .utility) {
                        guard !Task.isCancelled else { return nil }
                        return MarkdownProjectPreviewLoader.load(entry, projectRoot: projectRoot)
                    }
                }
                for await card in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    guard let card, let self, generation == self.refreshGeneration else {
                        group.cancelAll()
                        return
                    }
                    loadedCards.append(card)
                    loadedCount += 1
                    // Publish small batches so the first cards become visible quickly
                    // without sorting and invalidating the whole grid for every file.
                    if loadedCount == 1 || loadedCount.isMultiple(of: 8) {
                        self.cards = loadedCards
                        self.sortCards()
                    }
                    self.loadingStatus = "Preparing \(loadedCount) of \(markdownEntries.count) Markdown previews…"
                }
            }
            guard !Task.isCancelled else { return }
            guard let self, generation == self.refreshGeneration else { return }
            self.cards = loadedCards
            self.sortCards()
            self.isLoading = false
            self.loadingStatus = ""
            self.refreshTask = nil
        }
    }

    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
        cards = []
        isLoading = false
        loadingStatus = ""
    }

    private func sortCards() {
        cards.sort { lhs, rhs in
            switch sortOrder {
            case .name:
                let titleOrder = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
                return titleOrder == .orderedSame
                    ? lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
                    : titleOrder == .orderedAscending
            case .lastEdited:
                let lhsDate = lhs.modificationDate ?? .distantPast
                let rhsDate = rhs.modificationDate ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
            }
        }
    }
}

private enum MarkdownProjectPreviewLoader {
    nonisolated static let maxTextBytes = 96 * 1024
    nonisolated static let maxImageBytes = 4 * 1024 * 1024
    nonisolated static let largeFileThreshold: Int64 = 100 * 1024 * 1024

    nonisolated static func load(_ entry: ProjectFileIndex.Entry, projectRoot: URL) -> MarkdownProjectPreviewCardData {
        let textData = readPrefix(from: entry.url, maxBytes: maxTextBytes)
        let text = String(decoding: textData, as: UTF8.self)
        let headings = text.split(whereSeparator: \.isNewline).filter { line in
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            return trimmed.hasPrefix("#") && !trimmed.hasPrefix("#if")
        }
        let title = headings.first.map { heading in
            String(heading.drop { $0 == "#" || $0 == " " || $0 == "\t" })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let excerpt = text
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(5)
            .joined(separator: "\n")
        let imageData = firstLocalImageData(in: text, markdownURL: entry.url, projectRoot: projectRoot)

        return MarkdownProjectPreviewCardData(
            id: entry.standardizedPath,
            url: entry.url,
            relativePath: entry.relativePath,
            title: title,
            excerpt: excerpt.isEmpty ? "No preview text available." : excerpt,
            fileSize: entry.fileSize,
            modificationDate: entry.contentModificationDate,
            headingCount: headings.count,
            imageData: imageData,
            isLargeFile: (entry.fileSize ?? 0) >= largeFileThreshold
        )
    }

    nonisolated private static func readPrefix(from url: URL, maxBytes: Int) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: maxBytes)) ?? Data()
    }

    nonisolated private static func readImageData(from url: URL, maxBytes: Int) -> Data {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= maxBytes else { return Data() }
        return (try? Data(contentsOf: url, options: [.mappedIfSafe])) ?? Data()
    }

    nonisolated private static func firstLocalImageData(in text: String, markdownURL: URL, projectRoot: URL) -> Data? {
        let pattern = #"!\[[^\]]*\]\(([^)\s]+)(?:\s+[^)]*)?\)|<img\b[^>]*\bsrc=[\"']([^\"']+)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            for index in 1...2 {
                guard match.range(at: index).location != NSNotFound,
                      let sourceRange = Range(match.range(at: index), in: text) else { continue }
                let source = String(text[sourceRange])
                if source.lowercased().hasPrefix("data:image/"),
                   let separator = source.firstIndex(of: ","),
                   source[..<separator].lowercased().contains(";base64") {
                    let encoded = String(source[source.index(after: separator)...])
                    if let data = Data(base64Encoded: encoded), data.count <= maxImageBytes, !data.isEmpty {
                        return thumbnailData(from: data)
                    }
                    continue
                }
                guard !source.contains("://") else { continue }
                let candidate = URL(fileURLWithPath: source, relativeTo: markdownURL.deletingLastPathComponent()).standardizedFileURL
                guard candidate.path == projectRoot.standardizedFileURL.path || candidate.path.hasPrefix(projectRoot.standardizedFileURL.path + "/") else { continue }
                guard candidate.pathExtension.lowercased() != "svg" else { continue }
                let data = readImageData(from: candidate, maxBytes: maxImageBytes)
                if !data.isEmpty { return thumbnailData(from: data) }
            }
        }
        return nil
    }

    /// Decode and downsample before publishing card data so SwiftUI never has to
    /// decode a full-size project image while laying out the panel.
    nonisolated private static func thumbnailData(from data: Data) -> Data? {
        let output = NSMutableData()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 640
                  ] as CFDictionary
              ),
              let destination = CGImageDestinationCreateWithData(
                  output as CFMutableData,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              ) else { return nil }

        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

struct MarkdownProjectPreviewPanel: View {
    let cards: [MarkdownProjectPreviewCardData]
    let currentPreviewURL: URL?
    let isIndexing: Bool
    let isIndexReady: Bool
    let indexedFileCount: Int
    let isPreparingPreviews: Bool
    let previewStatus: String
    @Binding var mode: MarkdownProjectPreviewMode
    @Binding var sortOrder: MarkdownProjectPreviewSortOrder
    let onOpen: (URL) -> Void
    let onReveal: (URL) -> Void
    let onRefresh: () -> Void

    init(
        cards: [MarkdownProjectPreviewCardData],
        currentPreviewURL: URL?,
        isIndexing: Bool,
        isIndexReady: Bool = true,
        indexedFileCount: Int,
        isPreparingPreviews: Bool,
        previewStatus: String,
        mode: Binding<MarkdownProjectPreviewMode>,
        sortOrder: Binding<MarkdownProjectPreviewSortOrder>,
        onOpen: @escaping (URL) -> Void,
        onReveal: @escaping (URL) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.cards = cards
        self.currentPreviewURL = currentPreviewURL
        self.isIndexing = isIndexing
        self.isIndexReady = isIndexReady
        self.indexedFileCount = indexedFileCount
        self.isPreparingPreviews = isPreparingPreviews
        self.previewStatus = previewStatus
        self._mode = mode
        self._sortOrder = sortOrder
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onRefresh = onRefresh
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.secondary)
                Text("Project Markdown")
                    .font(.headline)
                Spacer(minLength: 0)
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh Markdown project previews")
                Menu {
                    ForEach(MarkdownProjectPreviewSortOrder.allCases) { value in
                        Button {
                            sortOrder = value
                        } label: {
                            if sortOrder == value {
                                Label(value.title, systemImage: "checkmark")
                            } else {
                                Text(value.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .help("Sort Markdown cards")
                .accessibilityLabel("Sort Markdown cards")
                Picker("Layout", selection: $mode) {
                    ForEach(MarkdownProjectPreviewMode.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 92)
                .accessibilityLabel("Markdown project preview layout")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.thinMaterial)

            let isPreparing = !isIndexReady || isIndexing || isPreparingPreviews
            if cards.isEmpty && isPreparing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(!isIndexReady || isIndexing ? "Indexing project files…" : previewStatus)
                        .font(.headline)
                    Text(!isIndexReady || isIndexing
                         ? (indexedFileCount > 0
                            ? "Using \(indexedFileCount) indexed files while the project refreshes."
                            : "Scanning the project for Markdown files…")
                         : "Preparing the first Markdown previews…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if cards.isEmpty {
                ContentUnavailableView("No Markdown files", systemImage: "doc.text", description: Text("Open a project folder containing Markdown files."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if mode == .grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                            ForEach(cards) { card in
                                MarkdownProjectPreviewCard(card: card, compact: false, isCurrentPreview: isCurrentPreview(card), onOpen: onOpen, onReveal: onReveal, onRefresh: onRefresh)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(cards) { card in
                                MarkdownProjectPreviewCard(card: card, compact: true, isCurrentPreview: isCurrentPreview(card), onOpen: onOpen, onReveal: onReveal, onRefresh: onRefresh)
                            }
                        }
                    }
                }
                .padding(10)
                .scrollIndicators(.never)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isIndexReady || isIndexing || isPreparingPreviews {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(!isIndexReady || isIndexing ? "Indexing project files…" : previewStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.thinMaterial)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(!isIndexReady || isIndexing ? "Indexing project files" : previewStatus)
            }
        }
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown files in current project")
    }

    private func isCurrentPreview(_ card: MarkdownProjectPreviewCardData) -> Bool {
        guard let currentPreviewURL else { return false }
        return card.url.standardizedFileURL == currentPreviewURL.standardizedFileURL
    }
}

private struct MarkdownProjectPreviewCard: View {
    let card: MarkdownProjectPreviewCardData
    let compact: Bool
    let isCurrentPreview: Bool
    let onOpen: (URL) -> Void
    let onReveal: (URL) -> Void
    let onRefresh: () -> Void
    @State private var isHovered = false

    private var previewIsAvailable: Bool {
        card.excerpt != "No preview text available."
    }

    var body: some View {
        Button { onOpen(card.url) } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let image = markdownPreviewImage(from: card.imageData) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: compact ? 48 : 60, maxHeight: compact ? 64 : 76)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text(card.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(card.relativePath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Group {
                    if let renderedExcerpt = try? AttributedString(markdown: card.excerpt) {
                        Text(renderedExcerpt)
                    } else {
                        Text(card.excerpt)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(compact ? 2 : 3)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    MarkdownPreviewBadge(text: "MD", color: .accentColor, systemImage: "doc.text")
                    MarkdownPreviewBadge(text: card.sizeLabel, color: .secondary, systemImage: "internaldrive")
                    MarkdownPreviewBadge(text: "\(card.headingCount) headings", color: .purple, systemImage: "text.alignleft")
                    MarkdownPreviewBadge(
                        text: previewIsAvailable ? "Ready" : "No preview",
                        color: previewIsAvailable ? .green : .secondary,
                        systemImage: previewIsAvailable ? "checkmark.circle.fill" : "minus.circle"
                    )
                    if isCurrentPreview {
                        MarkdownPreviewBadge(text: "Previewing", color: .accentColor, systemImage: "eye.fill")
                    }
                    if card.isLargeFile {
                        MarkdownPreviewBadge(text: "Large file", color: .orange, systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(
                minHeight: card.imageData == nil
                    ? (compact ? 132 : 150)
                    : (compact ? 190 : 220),
                alignment: .topLeading
            )
            .padding(10)
            .background(
                (isCurrentPreview
                    ? Color.accentColor.opacity(0.16)
                    : (isHovered ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045))),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isCurrentPreview
                            ? Color.accentColor.opacity(0.72)
                            : (isHovered ? Color.accentColor.opacity(0.48) : Color.secondary.opacity(0.14)),
                        lineWidth: isCurrentPreview || isHovered ? 1.4 : 1
                    )
            }
        }
        .buttonStyle(.plain)
#if os(macOS)
        .onHover { isHovered = $0 }
#endif
        .contextMenu {
            Button("Open") { onOpen(card.url) }
            Button("Reveal in Project") { onReveal(card.url) }
            Button("Copy Path") { copyMarkdownPath(card.url) }
            Button("Refresh Preview") { onRefresh() }
        }
        .accessibilityLabel("\(card.displayTitle), \(card.relativePath), \(card.sizeLabel), \(card.headingCount) headings, \(previewIsAvailable ? "preview ready" : "preview unavailable")\(isCurrentPreview ? ", currently previewing" : "")")
        .accessibilityHint("Opens this Markdown file in the editor")
    }
}

private struct MarkdownPreviewBadge: View {
    let text: String
    let color: Color
    let systemImage: String?

    init(text: String, color: Color, systemImage: String? = nil) {
        self.text = text
        self.color = color
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private func copyMarkdownPath(_ url: URL) {
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.path, forType: .string)
#elseif canImport(UIKit)
    UIPasteboard.general.string = url.path
#endif
}

private func markdownPreviewImage(from data: Data?) -> Image? {
    guard let data else { return nil }
#if os(macOS)
    guard let image = NSImage(data: data) else { return nil }
    return Image(nsImage: image)
#elseif canImport(UIKit)
    guard let image = UIImage(data: data) else { return nil }
    return Image(uiImage: image)
#else
    return nil
#endif
}
