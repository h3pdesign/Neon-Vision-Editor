import Foundation
import SwiftUI
import Synchronization
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Markdown Preview Render Cache

private struct MarkdownPreviewHTMLCache {
    private var signature: String = ""
    private var html: String = ""

    func html(for signature: String) -> String? {
        self.signature == signature ? html : nil
    }

    mutating func store(_ html: String, for signature: String) {
        self.signature = signature
        self.html = html
    }
}

// MARK: - Markdown Preview Export and Rendering

extension ContentView {
    nonisolated private static let markdownHeadingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$")
    nonisolated private static let markdownUnorderedListRegex = try! NSRegularExpression(pattern: "^[-*+]\\s+(.+)$")
    nonisolated private static let markdownOrderedListRegex = try! NSRegularExpression(pattern: "^\\d+[\\.)]\\s+(.+)$")
    nonisolated private static let markdownCodeSpanRegex = try! NSRegularExpression(pattern: "`([^`]+)`")
    nonisolated private static let markdownImageRegex = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^\\)\\s]+)\\)")
    nonisolated private static let markdownLinkRegex = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)\\s]+)\\)")
    nonisolated private static let markdownBoldAsteriskRegex = try! NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*")
    nonisolated private static let markdownBoldUnderscoreRegex = try! NSRegularExpression(pattern: "__([^_]+)__")
    nonisolated private static let markdownItalicAsteriskRegex = try! NSRegularExpression(pattern: "\\*([^*]+)\\*")
    nonisolated private static let markdownItalicUnderscoreRegex = try! NSRegularExpression(pattern: "_([^_]+)_")
    nonisolated private static let markdownStrikethroughRegex = try! NSRegularExpression(pattern: "~~([^~]+)~~")
    nonisolated private static let markdownPreviewHTMLCache = Mutex(MarkdownPreviewHTMLCache())
    nonisolated private static let markdownPDFExportSourceByteLimit = 25_000_000

    enum MarkdownPreviewDialect: String, CaseIterable, Identifiable {
        case gfm = "gfm"
        case commonMark = "commonmark"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gfm:
                return "GitHub Flavored Markdown"
            case .commonMark:
                return "CommonMark"
            }
        }
    }

    enum MarkdownPDFExportMode: String {
        case paginatedFit = "paginated-fit"
        case onePageFit = "one-page-fit"
    }

    enum MarkdownPreviewBackgroundStyle: String, CaseIterable, Identifiable {
        case automatic
        case template
        case translucent
        case neutral

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic:
                return "Automatic"
            case .template:
                return "Template"
            case .translucent:
                return "Translucent"
            case .neutral:
                return "Neutral"
            }
        }
    }

    // MARK: - Preview Configuration

    struct MarkdownPreviewTemplateOption: Identifiable {
        let id: String
        let title: String
    }

    static let markdownPreviewTemplateOptions: [MarkdownPreviewTemplateOption] = [
        MarkdownPreviewTemplateOption(id: "default", title: "Default"),
        MarkdownPreviewTemplateOption(id: "docs", title: "Docs"),
        MarkdownPreviewTemplateOption(id: "article", title: "Article"),
        MarkdownPreviewTemplateOption(id: "compact", title: "Compact"),
        MarkdownPreviewTemplateOption(id: "github-docs", title: "GitHub Docs"),
        MarkdownPreviewTemplateOption(id: "academic-paper", title: "Academic Paper"),
        MarkdownPreviewTemplateOption(id: "terminal-notes", title: "Terminal Notes"),
        MarkdownPreviewTemplateOption(id: "magazine", title: "Magazine"),
        MarkdownPreviewTemplateOption(id: "minimal-reader", title: "Minimal Reader"),
        MarkdownPreviewTemplateOption(id: "presentation", title: "Presentation"),
        MarkdownPreviewTemplateOption(id: "night-contrast", title: "Night Contrast"),
        MarkdownPreviewTemplateOption(id: "warm-sepia", title: "Warm Sepia"),
        MarkdownPreviewTemplateOption(id: "dense-compact", title: "Dense Compact"),
        MarkdownPreviewTemplateOption(id: "developer-spec", title: "Developer Spec"),
        MarkdownPreviewTemplateOption(id: "api-reference", title: "API Reference"),
        MarkdownPreviewTemplateOption(id: "changelog", title: "Changelog"),
        MarkdownPreviewTemplateOption(id: "focus-writing", title: "Focus Writing"),
        MarkdownPreviewTemplateOption(id: "lab-notes", title: "Lab Notes"),
        MarkdownPreviewTemplateOption(id: "editorial-review", title: "Editorial Review"),
        MarkdownPreviewTemplateOption(id: "neon-paper", title: "Neon Paper")
    ]

    var markdownPDFExportMode: MarkdownPDFExportMode {
        MarkdownPDFExportMode(rawValue: markdownPDFExportModeRaw) ?? .paginatedFit
    }

    var markdownPDFRendererMode: MarkdownPreviewPDFRenderer.ExportMode {
        switch markdownPDFExportMode {
        case .onePageFit:
            return .onePageFit
        case .paginatedFit:
            return .paginatedFit
        }
    }

    var markdownPreviewTemplate: String {
        if Self.markdownPreviewTemplateOptions.contains(where: { $0.id == markdownPreviewTemplateRaw }) {
            return markdownPreviewTemplateRaw
        }
        return "default"
    }

    var markdownPreviewBackgroundStyle: MarkdownPreviewBackgroundStyle {
        MarkdownPreviewBackgroundStyle(rawValue: markdownPreviewBackgroundStyleRaw) ?? .automatic
    }

    var markdownPreviewDialect: MarkdownPreviewDialect {
        MarkdownPreviewDialect(rawValue: markdownPreviewDialectRaw) ?? .gfm
    }

    var markdownPreviewPreferDarkMode: Bool {
        if let forcedScheme = ReleaseRuntimePolicy.preferredColorScheme(for: appearance) {
            return forcedScheme == .dark
        }
        return colorScheme == .dark
    }

    // MARK: - PDF and Clipboard Actions

    @MainActor
    func exportMarkdownPreviewPDF() {
        Task { @MainActor in
            do {
                let exportSource = await markdownExportSourceText()
                let exportByteCount = exportSource.lengthOfBytes(using: .utf8)
                guard exportByteCount <= Self.markdownPDFExportSourceByteLimit else {
                    throw NSError(
                        domain: "MarkdownPreviewExport",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Markdown PDF export is skipped for very large files (\(exportByteCount) bytes). Use Markdown preview or split the document before exporting."
                        ]
                    )
                }
                let html = markdownPreviewExportHTML(from: exportSource, mode: markdownPDFExportMode)
                guard markdownExportHasContrastContract(html) else {
                    throw NSError(
                        domain: "MarkdownPreviewExport",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "PDF export contrast guard failed."]
                    )
                }
                let pdfData = try await MarkdownPreviewPDFRenderer.render(
                    html: html,
                    mode: markdownPDFRendererMode
                )
                let filename = suggestedMarkdownPDFFilename()
#if os(macOS)
                try saveMarkdownPreviewPDFOnMac(pdfData, suggestedFilename: filename)
                showMarkdownPreviewActionStatus(
                    String(
                        format: NSLocalizedString("Markdown Preview Exported PDF: %@", comment: ""),
                        filename
                    )
                )
#else
                markdownPDFExportDocument = PDFExportDocument(data: pdfData)
                markdownPDFExportFilename = filename
                showMarkdownPDFExporter = true
                showMarkdownPreviewActionStatus(
                    String(
                        format: NSLocalizedString("Markdown Preview Ready PDF: %@", comment: ""),
                        filename
                    )
                )
#endif
            } catch {
                markdownPDFExportErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    func markdownExportSourceText() async -> String {
        guard let fileURL = viewModel.selectedTab?.fileURL else { return currentContent }
        let fallback = currentContent
        return await Task.detached(priority: .userInitiated) {
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
                return fallback
            }
            if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
            if let utf16LE = String(data: data, encoding: .utf16LittleEndian) { return utf16LE }
            if let utf16BE = String(data: data, encoding: .utf16BigEndian) { return utf16BE }
            if let utf32LE = String(data: data, encoding: .utf32LittleEndian) { return utf32LE }
            if let utf32BE = String(data: data, encoding: .utf32BigEndian) { return utf32BE }
            return String(decoding: data, as: UTF8.self)
        }.value
    }

    func suggestedMarkdownPDFFilename() -> String {
        let tabName = viewModel.selectedTab?.name ?? "Markdown-Preview"
        let rawName = URL(fileURLWithPath: tabName).deletingPathExtension().lastPathComponent
        let safeBase = rawName.isEmpty ? "Markdown-Preview" : rawName
        return "\(safeBase)-Preview.pdf"
    }

    func suggestedMarkdownPreviewBaseName() -> String {
        let tabName = viewModel.selectedTab?.name ?? "Markdown-Preview"
        let rawName = URL(fileURLWithPath: tabName).deletingPathExtension().lastPathComponent
        return rawName.isEmpty ? "Markdown-Preview" : rawName
    }

    var markdownPreviewShareHTML: String {
        markdownPreviewExportHTML(from: currentContent, mode: markdownPDFExportMode)
    }

    @MainActor
    func showMarkdownPreviewActionStatus(_ message: String, duration: TimeInterval = 2.0) {
        let token = UUID()
        markdownPreviewActionStatusToken = token
        markdownPreviewActionStatusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            Task { @MainActor in
                guard markdownPreviewActionStatusToken == token else { return }
                markdownPreviewActionStatusMessage = ""
            }
        }
    }

    @MainActor
    func copyMarkdownPreviewHTML() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdownPreviewShareHTML, forType: .string)
#elseif os(iOS)
        UIPasteboard.general.setValue(markdownPreviewShareHTML, forPasteboardType: UTType.html.identifier)
        UIPasteboard.general.string = markdownPreviewShareHTML
#endif
        showMarkdownPreviewActionStatus(NSLocalizedString("Markdown Preview Copied HTML", comment: ""))
    }

    @MainActor
    func copyMarkdownPreviewMarkdown() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentContent, forType: .string)
#elseif os(iOS)
        UIPasteboard.general.string = currentContent
#endif
        showMarkdownPreviewActionStatus(NSLocalizedString("Markdown Preview Copied Markdown", comment: ""))
    }

#if os(macOS)
    @MainActor
    func saveMarkdownPreviewPDFOnMac(_ data: Data, suggestedFilename: String) throws {
        let panel = NSSavePanel()
        panel.title = "Export Markdown Preview as PDF"
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK else { return }
        guard let destinationURL = panel.url else { return }
        try data.write(to: destinationURL, options: .atomic)
    }
#endif

    // MARK: - Async Preview Rendering

    var markdownPreviewCurrentRenderSignature: String {
        let contentSignature: String
        if let tab = viewModel.selectedTab {
            contentSignature = [
                tab.id.uuidString,
                String(tab.contentRevision),
                String(tab.contentUTF16Length)
            ].joined(separator: ":")
        } else {
            contentSignature = [
                "single",
                String(singleContent.count),
                String(singleContent.hashValue)
            ].joined(separator: ":")
        }
        return [
            contentSignature,
            markdownPreviewTemplate,
            String(markdownPreviewPreferDarkMode),
            markdownPreviewBackgroundStyle.rawValue,
            markdownPreviewDialect.rawValue,
            String(enableTranslucentWindow),
            String(Int(markdownPreviewRuntimeFontSize.rounded()))
        ].joined(separator: "|")
    }

    func scheduleMarkdownPreviewRender(immediate: Bool = false) {
        guard showMarkdownPreviewPane else { return }
        let signature = markdownPreviewCurrentRenderSignature
        guard immediate || signature != markdownPreviewRenderSignature else { return }

        markdownPreviewRenderTask?.cancel()
        isMarkdownPreviewRendering = true

        if let cachedHTML = Self.markdownPreviewHTMLCache.withLock({ $0.html(for: signature) }) {
            markdownPreviewRenderedHTML = cachedHTML
            markdownPreviewRenderSignature = signature
            isMarkdownPreviewRendering = false
            markdownPreviewRenderTask = nil
            return
        }

        let preferDarkMode = markdownPreviewPreferDarkMode
        let template = markdownPreviewTemplate
        let backgroundStyle = markdownPreviewBackgroundStyle
        let dialect = markdownPreviewDialect
        let translucentBackgroundEnabled = enableTranslucentWindow
        let runtimeFontSize = markdownPreviewRuntimeFontSize

        markdownPreviewRenderTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: markdownPreviewRenderDebounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard signature == markdownPreviewCurrentRenderSignature else { return }
            let source = currentContent
            let bodyHTML = await Task.detached(priority: .utility) {
                ContentView.markdownPreviewBodyHTML(from: source, dialect: dialect, useRenderLimits: true)
            }.value
            guard !Task.isCancelled else { return }
            let html = markdownPreviewHTML(
                bodyHTML: bodyHTML,
                template: template,
                preferDarkMode: preferDarkMode,
                backgroundStyle: backgroundStyle,
                translucentBackgroundEnabled: translucentBackgroundEnabled,
                runtimeFontSize: runtimeFontSize
            )
            Self.markdownPreviewHTMLCache.withLock { cache in
                cache.store(html, for: signature)
            }
            markdownPreviewRenderedHTML = html
            markdownPreviewRenderSignature = signature
            isMarkdownPreviewRendering = false
            markdownPreviewRenderTask = nil
        }
    }

    private var markdownPreviewRenderDebounceNanoseconds: UInt64 {
        let contentLength = currentDocumentUTF16Length
        if contentLength >= 250_000 { return 360_000_000 }
        if contentLength >= 80_000 { return 240_000_000 }
        return 140_000_000
    }

    func markdownPreviewLoadingHTML(preferDarkMode: Bool) -> String {
        markdownPreviewHTML(
            bodyHTML: """
            <section class="preview-warning">
              <p><strong>Markdown Preview</strong></p>
              <p class="preview-warning-meta">Preparing preview…</p>
            </section>
            """,
            template: markdownPreviewTemplate,
            preferDarkMode: preferDarkMode,
            backgroundStyle: markdownPreviewBackgroundStyle,
            translucentBackgroundEnabled: enableTranslucentWindow,
            runtimeFontSize: markdownPreviewRuntimeFontSize
        )
    }

    // MARK: - HTML Shell and Export HTML

    func markdownPreviewHTML(from markdownText: String, preferDarkMode: Bool) -> String {
        let bodyHTML = Self.markdownPreviewBodyHTML(from: markdownText, dialect: markdownPreviewDialect, useRenderLimits: true)
        return markdownPreviewHTML(
            bodyHTML: bodyHTML,
            template: markdownPreviewTemplate,
            preferDarkMode: preferDarkMode,
            backgroundStyle: markdownPreviewBackgroundStyle,
            translucentBackgroundEnabled: enableTranslucentWindow,
            runtimeFontSize: markdownPreviewRuntimeFontSize
        )
    }

    func markdownPreviewHTML(
        bodyHTML: String,
        template: String,
        preferDarkMode: Bool,
        backgroundStyle: MarkdownPreviewBackgroundStyle,
        translucentBackgroundEnabled: Bool,
        runtimeFontSize: CGFloat? = nil
    ) -> String {
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(markdownPreviewCSS(
            template: template,
            preferDarkMode: preferDarkMode,
            backgroundStyle: backgroundStyle,
            translucentBackgroundEnabled: translucentBackgroundEnabled,
            runtimeFontSize: runtimeFontSize
        ))
        \(markdownPreviewRuntimePreviewScaleCSS())
        </style>
        </head>
        <body class="\(template)">
        <main class="content">
        \(bodyHTML)
        </main>
        </body>
        </html>
        """
    }

    private var markdownPreviewRuntimeFontSize: CGFloat {
        CGFloat(min(28, max(10, editorFontSize)))
    }

    func markdownPreviewRuntimePreviewScaleCSS() -> String {
        let previewLayoutCSS = """
        * {
          box-sizing: border-box;
        }
        html, body {
          min-height: 100%;
          width: 100%;
          min-width: 0;
          max-width: 100%;
          overflow-x: hidden;
        }
        body {
          background: var(--md-content-background);
        }
        .content {
          width: 100%;
          min-width: 0;
          max-width: none !important;
          min-height: 100vh;
          margin: 0 !important;
          padding: clamp(14px, 2.2vw, 24px);
          overflow-x: hidden;
          word-break: normal;
          background: transparent !important;
          border: none !important;
          border-radius: 0 !important;
          box-shadow: none !important;
          -webkit-backdrop-filter: none !important;
          backdrop-filter: none !important;
        }
        .content > * {
          max-width: 100%;
        }
        h1, h2, h3, h4, h5, h6, p, li, blockquote {
          max-width: 100%;
          overflow-wrap: break-word;
        }
        a, code, figcaption, td, th {
          overflow-wrap: anywhere;
        }
        pre, table {
          max-width: 100%;
        }
        table {
          display: block;
          overflow-x: auto;
          -webkit-overflow-scrolling: touch;
        }
        img, video, svg {
          max-width: 100%;
          height: auto;
        }
        """
#if os(iOS)
        return """
        \(previewLayoutCSS)
        html {
          -webkit-text-size-adjust: 100%;
        }
        body {
          font-size: 1em !important;
        }
        @media (max-width: 480px) {
          html, body {
            max-width: 100%;
          }
          .content {
            width: 100%;
            max-width: 100% !important;
            padding-left: calc(max(18px, env(safe-area-inset-left)) + 1px);
            padding-right: calc(max(18px, env(safe-area-inset-right)) + 1px);
          }
          h1 {
            font-size: clamp(1.45em, 8vw, 1.7em);
          }
          h2 {
            font-size: clamp(1.24em, 6.5vw, 1.45em);
          }
          pre {
            white-space: pre-wrap;
            word-break: break-word;
          }
        }
        """
#else
        return """
        \(previewLayoutCSS)
        body {
          font-size: 0.96em;
        }
        """
#endif
    }

    func markdownPreviewExportHTML(from markdownText: String, mode: MarkdownPDFExportMode) -> String {
        let bodyHTML = Self.markdownPreviewBodyHTML(from: markdownText, dialect: markdownPreviewDialect, useRenderLimits: false)
        let modeClass = mode == .onePageFit ? " pdf-one-page" : ""
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(markdownPreviewCSS(
            template: markdownPreviewTemplate,
            backgroundStyle: .template,
            translucentBackgroundEnabled: false
        ))
        </style>
        </head>
        <body class="\(markdownPreviewTemplate) pdf-export\(modeClass)">
        <main class="content">
        \(bodyHTML)
        </main>
        </body>
        </html>
        """
    }

    func markdownExportHasContrastContract(_ html: String) -> Bool {
        html.contains("body.pdf-export") &&
        html.contains("background: #ffffff") &&
        html.contains("-webkit-text-fill-color: #111827")
    }

    // MARK: - Markdown Body Rendering

    nonisolated static func markdownPreviewBodyHTML(
        from markdownText: String,
        dialect: MarkdownPreviewDialect = .gfm,
        useRenderLimits: Bool
    ) -> String {
        let byteCount = markdownText.lengthOfBytes(using: .utf8)
        if useRenderLimits && byteCount > 180_000 {
            return largeMarkdownFallbackHTML(from: markdownText, byteCount: byteCount)
        }
        if !useRenderLimits && byteCount > 180_000 {
            return "<pre>\(escapedHTML(markdownText))</pre>"
        }
        return renderedMarkdownBodyHTML(from: markdownText, dialect: dialect) ?? "<pre>\(escapedHTML(markdownText))</pre>"
    }

    nonisolated static func largeMarkdownFallbackHTML(from markdownText: String, byteCount: Int) -> String {
        let previewText = String(markdownText.prefix(120_000))
        let truncated = previewText.count < markdownText.count
        let statusSuffix = truncated ? " (truncated preview)" : ""
        return """
        <section class="preview-warning">
          <p><strong>Large Markdown file</strong></p>
          <p class="preview-warning-meta">Rendering full Markdown is skipped for stability (\(byteCount) bytes)\(statusSuffix).</p>
        </section>
        <pre>\(escapedHTML(previewText))</pre>
        """
    }

    nonisolated static func renderedMarkdownBodyHTML(
        from markdownText: String,
        dialect: MarkdownPreviewDialect = .gfm
    ) -> String? {
        let html = simpleMarkdownToHTML(markdownText, dialect: dialect).trimmingCharacters(in: .whitespacesAndNewlines)
        return html.isEmpty ? nil : html
    }

    nonisolated static func simpleMarkdownToHTML(
        _ markdown: String,
        dialect: MarkdownPreviewDialect = .gfm
    ) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [String] = []
        var paragraphLines: [String] = []
        var codeFenceMarker: Character?
        var codeFenceLength = 0
        var codeFenceLanguage: String?
        var codeFenceLines: [String] = []
        var insideUnorderedList = false
        var insideOrderedList = false
        var insideBlockquote = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = paragraphLines.map { inlineMarkdownToHTML($0, dialect: dialect) }.joined(separator: "<br/>")
            result.append("<p>\(paragraph)</p>")
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func closeLists() {
            if insideUnorderedList {
                result.append("</ul>")
                insideUnorderedList = false
            }
            if insideOrderedList {
                result.append("</ol>")
                insideOrderedList = false
            }
        }

        func closeBlockquote() {
            if insideBlockquote {
                flushParagraph()
                closeLists()
                result.append("</blockquote>")
                insideBlockquote = false
            }
        }

        func closeParagraphAndInlineContainers() {
            flushParagraph()
            closeLists()
        }

        func flushCodeFence() {
            guard let marker = codeFenceMarker else { return }
            let code = codeFenceLines.joined(separator: "\n")
            result.append(fencedCodeHTML(code, language: codeFenceLanguage, marker: marker, dialect: dialect))
            codeFenceMarker = nil
            codeFenceLength = 0
            codeFenceLanguage = nil
            codeFenceLines.removeAll(keepingCapacity: true)
        }

        var lineIndex = 0
        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if let closing = markdownCodeFence(from: trimmed), codeFenceMarker != nil {
                if closing.marker == codeFenceMarker && closing.length >= codeFenceLength {
                    flushCodeFence()
                    lineIndex += 1
                    continue
                }
            }

            if codeFenceMarker != nil {
                codeFenceLines.append(rawLine)
                lineIndex += 1
                continue
            }

            if let opening = markdownCodeFence(from: trimmed) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                codeFenceMarker = opening.marker
                codeFenceLength = opening.length
                codeFenceLanguage = opening.info.isEmpty ? nil : opening.info
                codeFenceLines.removeAll(keepingCapacity: true)
                lineIndex += 1
                continue
            }

            if dialect == .gfm,
               lineIndex + 1 < lines.count,
               let table = markdownTableHTML(headerLine: rawLine, separatorLine: lines[lineIndex + 1]) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                var tableRows: [String] = []
                var bodyIndex = lineIndex + 2
                while bodyIndex < lines.count {
                    let candidate = lines[bodyIndex]
                    let candidateTrimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !candidateTrimmed.isEmpty, candidate.contains("|") else { break }
                    tableRows.append(candidate)
                    bodyIndex += 1
                }
                result.append(markdownTableHTML(table: table, bodyRows: tableRows))
                lineIndex = bodyIndex
                continue
            }

            if trimmed.isEmpty {
                closeParagraphAndInlineContainers()
                closeBlockquote()
                lineIndex += 1
                continue
            }

            if isMarkdownRawHTMLLine(trimmed) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                result.append(safeMarkdownRawHTML(trimmed))
                lineIndex += 1
                continue
            }

            if let heading = markdownHeading(from: trimmed) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                result.append("<h\(heading.level)>\(inlineMarkdownToHTML(heading.text, dialect: dialect))</h\(heading.level)>")
                lineIndex += 1
                continue
            }

            if isMarkdownHorizontalRule(trimmed) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                result.append("<hr/>")
                lineIndex += 1
                continue
            }

            var workingLine = trimmed
            let isBlockquoteLine = workingLine.hasPrefix(">")
            if isBlockquoteLine {
                if !insideBlockquote {
                    closeParagraphAndInlineContainers()
                    result.append("<blockquote>")
                    insideBlockquote = true
                }
                workingLine = workingLine.dropFirst().trimmingCharacters(in: .whitespaces)
            } else {
                closeBlockquote()
            }

            if let unordered = markdownUnorderedListItem(from: workingLine) {
                flushParagraph()
                if insideOrderedList {
                    result.append("</ol>")
                    insideOrderedList = false
                }
                if !insideUnorderedList {
                    result.append("<ul>")
                    insideUnorderedList = true
                }
                result.append(markdownListItemHTML(unordered, dialect: dialect))
                lineIndex += 1
                continue
            }

            if let ordered = markdownOrderedListItem(from: workingLine) {
                flushParagraph()
                if insideUnorderedList {
                    result.append("</ul>")
                    insideUnorderedList = false
                }
                if !insideOrderedList {
                    result.append("<ol>")
                    insideOrderedList = true
                }
                result.append("<li>\(inlineMarkdownToHTML(ordered, dialect: dialect))</li>")
                lineIndex += 1
                continue
            }

            closeLists()
            paragraphLines.append(workingLine)
            lineIndex += 1
        }

        closeBlockquote()
        closeParagraphAndInlineContainers()
        flushCodeFence()
        return result.joined(separator: "\n")
    }

    nonisolated static func markdownCodeFence(from line: String) -> (marker: Character, length: Int, info: String)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let info = String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        return (first, count, info)
    }

    nonisolated static func fencedCodeHTML(
        _ code: String,
        language: String?,
        marker _: Character,
        dialect: MarkdownPreviewDialect
    ) -> String {
        let languageToken = language?.split(separator: " ").first.map(String.init)
        let normalizedLanguage = languageToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if dialect == .gfm, normalizedLanguage == "mermaid" {
            return mermaidDiagramHTML(from: code)
        }
        let safeLanguage = languageToken.flatMap { $0.isEmpty ? nil : $0 }
        let classAttribute = safeLanguage.map { " class=\"language-\(escapedHTML($0))\"" } ?? ""
        return "<pre><code\(classAttribute)>\(escapedHTML(code))\n</code></pre>"
    }

    nonisolated static func markdownListItemHTML(_ text: String, dialect: MarkdownPreviewDialect) -> String {
        guard dialect == .gfm,
              let task = markdownTaskListItem(from: text) else {
            return "<li>\(inlineMarkdownToHTML(text, dialect: dialect))</li>"
        }
        let checked = task.checked ? " checked" : ""
        return "<li class=\"task-list-item\"><input type=\"checkbox\" disabled\(checked)/> \(inlineMarkdownToHTML(task.text, dialect: dialect))</li>"
    }

    nonisolated static func markdownTaskListItem(from text: String) -> (checked: Bool, text: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4,
              trimmed.hasPrefix("["),
              let closing = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let marker = trimmed[trimmed.index(after: trimmed.startIndex)..<closing].lowercased()
        guard marker == "x" || marker == " " else { return nil }
        let rest = trimmed[trimmed.index(after: closing)...].trimmingCharacters(in: .whitespaces)
        return (marker == "x", rest)
    }

    nonisolated static func markdownTableHTML(
        headerLine: String,
        separatorLine: String
    ) -> (headers: [String], alignments: [String?])? {
        let headers = splitMarkdownTableRow(headerLine)
        guard headers.count >= 2 else { return nil }
        guard let alignments = markdownTableSeparatorAlignments(from: separatorLine),
              alignments.count == headers.count else {
            return nil
        }
        return (headers, alignments)
    }

    nonisolated static func markdownTableHTML(
        table: (headers: [String], alignments: [String?]),
        bodyRows: [String]
    ) -> String {
        let headerHTML = table.headers.enumerated().map { index, header in
            markdownTableCellHTML(
                tag: "th",
                text: header,
                alignment: table.alignments[index]
            )
        }.joined()
        let rowsHTML = bodyRows.map { row in
            let cells = splitMarkdownTableRow(row)
            let cellHTML = table.headers.indices.map { index in
                let cell = index < cells.count ? cells[index] : ""
                return markdownTableCellHTML(
                    tag: "td",
                    text: cell,
                    alignment: table.alignments[index]
                )
            }.joined()
            return "<tr>\(cellHTML)</tr>"
        }.joined(separator: "\n")
        return """
        <table>
        <thead><tr>\(headerHTML)</tr></thead>
        <tbody>
        \(rowsHTML)
        </tbody>
        </table>
        """
    }

    nonisolated static func markdownTableCellHTML(
        tag: String,
        text: String,
        alignment: String?
    ) -> String {
        let alignAttribute = alignment.map { " style=\"text-align: \($0);\"" } ?? ""
        return "<\(tag)\(alignAttribute)>\(inlineMarkdownToHTML(text, dialect: .gfm))</\(tag)>"
    }

    nonisolated static func markdownTableSeparatorAlignments(from line: String) -> [String?]? {
        let cells = splitMarkdownTableRow(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [String?] = []
        for rawCell in cells {
            let cell = rawCell.trimmingCharacters(in: .whitespaces)
            guard markdownPreviewRegexMatches(cell, pattern: #"^:?-{3,}:?$"#) else { return nil }
            if cell.hasPrefix(":") && cell.hasSuffix(":") {
                alignments.append("center")
            } else if cell.hasSuffix(":") {
                alignments.append("right")
            } else if cell.hasPrefix(":") {
                alignments.append("left")
            } else {
                alignments.append(nil)
            }
        }
        return alignments
    }

    nonisolated static func splitMarkdownTableRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        var cells: [String] = []
        var current = ""
        var isEscaped = false
        for character in row {
            if isEscaped {
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    nonisolated static func mermaidDiagramHTML(from source: String) -> String {
        if let svg = simpleMermaidFlowchartSVG(from: source) {
            return """
            <figure class="mermaid-diagram">
            \(svg)
            <figcaption>Mermaid diagram</figcaption>
            </figure>
            """
        }
        return """
        <figure class="mermaid-diagram mermaid-diagram-source">
        <figcaption>Mermaid diagram source</figcaption>
        <pre><code class="language-mermaid">\(escapedHTML(source))\n</code></pre>
        </figure>
        """
    }

    nonisolated static func simpleMermaidFlowchartSVG(from source: String) -> String? {
        let lines = source
            .replacingOccurrences(of: ";", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
        guard lines.first?.lowercased().hasPrefix("graph ") == true ||
              lines.first?.lowercased().hasPrefix("flowchart ") == true else {
            return nil
        }

        var nodeLabels: [String: String] = [:]
        var nodeOrder: [String] = []
        var edges: [(from: String, to: String, label: String?)] = []

        func register(_ token: String) -> String {
            let parsed = parseMermaidNodeToken(token)
            if nodeLabels[parsed.id] == nil {
                nodeLabels[parsed.id] = parsed.label
                nodeOrder.append(parsed.id)
            }
            return parsed.id
        }

        for line in lines.dropFirst() {
            guard let edge = parseMermaidEdge(line) else { continue }
            let from = register(edge.from)
            let to = register(edge.to)
            edges.append((from, to, edge.label))
        }
        guard !nodeOrder.isEmpty, !edges.isEmpty, nodeOrder.count <= 24 else { return nil }

        let nodeWidth = 190
        let nodeHeight = 46
        let verticalSpacing = 92
        let margin = 28
        let width = nodeWidth + margin * 2
        let height = margin * 2 + max(1, nodeOrder.count) * nodeHeight + max(0, nodeOrder.count - 1) * verticalSpacing
        let positions = Dictionary(uniqueKeysWithValues: nodeOrder.enumerated().map { index, id in
            (id, (x: margin, y: margin + index * (nodeHeight + verticalSpacing)))
        })

        let edgeHTML = edges.compactMap { edge -> String? in
            guard let from = positions[edge.from], let to = positions[edge.to] else { return nil }
            let x1 = from.x + nodeWidth / 2
            let y1 = from.y + nodeHeight
            let x2 = to.x + nodeWidth / 2
            let y2 = to.y
            let label = edge.label.map {
                "<text class=\"mermaid-edge-label\" x=\"\(x1)\" y=\"\((y1 + y2) / 2 - 6)\" text-anchor=\"middle\">\(escapedHTML($0))</text>"
            } ?? ""
            return """
            <path class="mermaid-edge" d="M \(x1) \(y1) C \(x1) \(y1 + 36), \(x2) \(y2 - 36), \(x2) \(y2)" marker-end="url(#arrow)"/>
            \(label)
            """
        }.joined(separator: "\n")

        let nodeHTML = nodeOrder.compactMap { id -> String? in
            guard let position = positions[id] else { return nil }
            let label = nodeLabels[id] ?? id
            return """
            <g class="mermaid-node">
              <rect x="\(position.x)" y="\(position.y)" width="\(nodeWidth)" height="\(nodeHeight)" rx="10"/>
              <text x="\(position.x + nodeWidth / 2)" y="\(position.y + nodeHeight / 2 + 5)" text-anchor="middle">\(escapedHTML(label))</text>
            </g>
            """
        }.joined(separator: "\n")

        return """
        <svg class="mermaid-svg" viewBox="0 0 \(width) \(height)" role="img" aria-label="Mermaid flowchart" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto" markerUnits="strokeWidth">
              <path d="M0,0 L0,6 L9,3 z" class="mermaid-arrow"/>
            </marker>
          </defs>
          \(edgeHTML)
          \(nodeHTML)
        </svg>
        """
    }

    nonisolated static func parseMermaidEdge(_ line: String) -> (from: String, to: String, label: String?)? {
        let operators = ["-->", "---", "-.->", "==>"]
        for op in operators {
            guard let range = line.range(of: op) else { continue }
            let lhs = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            var rhs = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            var label: String?
            if rhs.hasPrefix("|"), let close = rhs.dropFirst().firstIndex(of: "|") {
                label = String(rhs[rhs.index(after: rhs.startIndex)..<close])
                rhs = String(rhs[rhs.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            guard !lhs.isEmpty, !rhs.isEmpty else { return nil }
            return (lhs, rhs, label)
        }
        return nil
    }

    nonisolated static func parseMermaidNodeToken(_ token: String) -> (id: String, label: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let shapeStart = trimmed.firstIndex(where: { "[({".contains($0) }),
              let shapeEnd = trimmed.lastIndex(where: { "])}".contains($0) }),
              shapeEnd > shapeStart else {
            return (trimmed, trimmed)
        }
        let id = String(trimmed[..<shapeStart]).trimmingCharacters(in: .whitespacesAndNewlines)
        let label = String(trimmed[trimmed.index(after: shapeStart)..<shapeEnd])
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return (id.isEmpty ? trimmed : id, label.isEmpty ? id : label)
    }

    // MARK: - Markdown Inline Helpers

    nonisolated static func markdownHeading(from line: String) -> (level: Int, text: String)? {
        let regex = markdownHeadingRegex
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let hashesRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (line[hashesRange].count, String(line[textRange]))
    }

    nonisolated static func isMarkdownHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact == "***" || compact == "---" || compact == "___"
    }

    nonisolated static func markdownUnorderedListItem(from line: String) -> String? {
        let regex = markdownUnorderedListRegex
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let textRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[textRange])
    }

    nonisolated static func markdownOrderedListItem(from line: String) -> String? {
        let regex = markdownOrderedListRegex
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let textRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[textRange])
    }

    nonisolated static func inlineMarkdownToHTML(_ text: String, dialect: MarkdownPreviewDialect = .gfm) -> String {
        var html = restoreSafeInlineHTML(in: escapedHTML(text))
        var codeSpans: [String] = []
        let codeSpanTokenPrefix = "%%CODESPAN"
        let codeSpanTokenSuffix = "%%"

        html = replacingRegex(in: html, pattern: "`([^`]+)`") { match in
            let content = String(match.dropFirst().dropLast())
            let token = "\(codeSpanTokenPrefix)\(codeSpans.count)\(codeSpanTokenSuffix)"
            codeSpans.append("<code>\(content)</code>")
            return token
        }

        html = replacingRegex(in: html, pattern: "!\\[([^\\]]*)\\]\\(([^\\)\\s]+)\\)") { match in
            let parts = captureGroups(in: match, pattern: "!\\[([^\\]]*)\\]\\(([^\\)\\s]+)\\)")
            guard parts.count == 2 else { return match }
            if isRemoteHTTPURLString(parts[1]) {
                let label = parts[0].isEmpty ? "Remote image" : "Remote image: \(parts[0])"
                return "<a class=\"remote-image-placeholder\" href=\"\(parts[1])\">\(label)</a>"
            }
            return "<img src=\"\(parts[1])\" alt=\"\(parts[0])\"/>"
        }

        html = replacingRegex(in: html, pattern: "\\[([^\\]]+)\\]\\(([^\\)\\s]+)\\)") { match in
            let parts = captureGroups(in: match, pattern: "\\[([^\\]]+)\\]\\(([^\\)\\s]+)\\)")
            guard parts.count == 2 else { return match }
            return "<a href=\"\(parts[1])\">\(parts[0])</a>"
        }

        html = replacingRegex(in: html, pattern: "&lt;(https?://[^\\s&]+)&gt;") { match in
            let url = String(match.dropFirst(4).dropLast(4))
            return "<a href=\"\(url)\">\(url)</a>"
        }
        if dialect == .gfm {
            html = replacingBareAutolinksOutsideTags(in: html)
            html = replacingRegex(in: html, pattern: "~~([^~]+)~~") { "<del>\(String($0.dropFirst(2).dropLast(2)))</del>" }
        }

        html = replacingRegex(in: html, pattern: "\\*\\*([^*]+)\\*\\*") { "<strong>\(String($0.dropFirst(2).dropLast(2)))</strong>" }
        html = replacingRegex(in: html, pattern: "__([^_]+)__") { "<strong>\(String($0.dropFirst(2).dropLast(2)))</strong>" }
        html = replacingRegex(in: html, pattern: "\\*([^*]+)\\*") { "<em>\(String($0.dropFirst().dropLast()))</em>" }
        html = replacingRegex(in: html, pattern: "_([^_]+)_") { "<em>\(String($0.dropFirst().dropLast()))</em>" }

        for (index, codeHTML) in codeSpans.enumerated() {
            html = html.replacingOccurrences(
                of: "\(codeSpanTokenPrefix)\(index)\(codeSpanTokenSuffix)",
                with: codeHTML
            )
        }
        return html
    }

    nonisolated static func replacingBareAutolinksOutsideTags(in html: String) -> String {
        var output = ""
        var buffer = ""
        var insideTag = false

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            output += replacingRegex(in: buffer, pattern: #"(?<!["'=])\bhttps?://[^\s<>()]+"#) { match in
                "<a href=\"\(match)\">\(match)</a>"
            }
            buffer = ""
        }

        for character in html {
            if character == "<" {
                flushBuffer()
                insideTag = true
                output.append(character)
            } else if character == ">" {
                insideTag = false
                output.append(character)
            } else if insideTag {
                output.append(character)
            } else {
                buffer.append(character)
            }
        }
        flushBuffer()
        return output
    }

    nonisolated static func isMarkdownRawHTMLLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<") && trimmed.contains(">")
    }

    nonisolated static func safeMarkdownRawHTML(_ html: String) -> String {
        isSafePassiveMarkdownHTML(html) ? html : escapedHTML(html)
    }

    nonisolated static func restoreSafeInlineHTML(in escapedText: String) -> String {
        replacingRegex(in: escapedText, pattern: "&lt;(/?[A-Za-z][A-Za-z0-9:-]*(?:\\s+[^&<>]*?)?/?)&gt;") { match in
            let tagBody = String(match.dropFirst(4).dropLast(4))
            let decodedTag = "<\(htmlUnescapedAttributeText(tagBody))>"
            return isSafePassiveMarkdownHTML(decodedTag) ? decodedTag : match
        }
    }

    nonisolated static func isSafePassiveMarkdownHTML(_ html: String) -> Bool {
        let lower = html.lowercased()
        let blockedTagPattern = #"(?i)<\s*/?\s*(script|iframe|object|embed|link|meta|form|input|button|textarea|select|option|style|base|frame|frameset)\b"#
        if markdownPreviewRegexMatches(html, pattern: blockedTagPattern) { return false }
        if markdownPreviewRegexMatches(html, pattern: #"(?i)\s+on[a-z0-9_-]+\s*="#) { return false }
        if markdownPreviewRegexMatches(html, pattern: #"(?i)\s+(src|poster|xlink:href)\s*=\s*['"]?\s*(https?:|//|file:)"#) {
            return false
        }
        if lower.contains("javascript:") || lower.contains("data:text/html") {
            return false
        }
        if lower.contains("url(http") || lower.contains("url(//") || lower.contains("url(file:") {
            return false
        }
        return true
    }

    nonisolated static func markdownPreviewRegexMatches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    nonisolated static func htmlUnescapedAttributeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    nonisolated static func replacingRegex(in text: String, pattern: String, transform: (String) -> String) -> String {
        guard let regex = markdownInlineRegex(pattern) else { return text }
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let segment = String(output[range])
            output.replaceSubrange(range, with: transform(segment))
        }
        return output
    }

    nonisolated static func isRemoteHTTPURLString(_ text: String) -> Bool {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }

    nonisolated private static func markdownInlineRegex(_ pattern: String) -> NSRegularExpression? {
        switch pattern {
        case "`([^`]+)`":
            return markdownCodeSpanRegex
        case "!\\[([^\\]]*)\\]\\(([^\\)\\s]+)\\)":
            return markdownImageRegex
        case "\\[([^\\]]+)\\]\\(([^\\)\\s]+)\\)":
            return markdownLinkRegex
        case "\\*\\*([^*]+)\\*\\*":
            return markdownBoldAsteriskRegex
        case "__([^_]+)__":
            return markdownBoldUnderscoreRegex
        case "\\*([^*]+)\\*":
            return markdownItalicAsteriskRegex
        case "_([^_]+)_":
            return markdownItalicUnderscoreRegex
        case "~~([^~]+)~~":
            return markdownStrikethroughRegex
        default:
            return try? NSRegularExpression(pattern: pattern)
        }
    }

    nonisolated static func captureGroups(in text: String, pattern: String) -> [String] {
        guard let regex = markdownInlineRegex(pattern),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
            return []
        }
        var groups: [String] = []
        for idx in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: idx), in: text) {
                groups.append(String(text[range]))
            }
        }
        return groups
    }

    // MARK: - Preview CSS

    func markdownPreviewCSS(
        template: String,
        preferDarkMode: Bool = false,
        backgroundStyle: MarkdownPreviewBackgroundStyle = .template,
        translucentBackgroundEnabled: Bool = false,
        runtimeFontSize: CGFloat? = nil
    ) -> String {
        let basePadding: String
        let fontSize: String
        let lineHeight: String
        let maxWidth: String
        var bodyBackground: String
        var contentBackground: String
        var contentBorder: String
        let textColor: String
        let mutedTextColor: String
        let linkColor: String
        let codeBackground: String
        let codeBorder: String
        let quoteBackground: String
        let quoteBorder: String
        let tableHeaderBackground: String
        let horizontalRuleColor: String
        var shadowColor: String
        let bodyFontFamily: String
        var contentBackdropFilter = "none"
        switch template {
        case "docs":
            basePadding = "22px 30px"
            fontSize = "15px"
            lineHeight = "1.7"
            maxWidth = "900px"
            bodyBackground = preferDarkMode ? "#0f172a" : "#f8fafc"
            contentBackground = preferDarkMode ? "#111827" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #1f2937" : "1px solid #e5e7eb"
            textColor = preferDarkMode ? "#e5e7eb" : "#111827"
            mutedTextColor = preferDarkMode ? "#94a3b8" : "#6b7280"
            linkColor = preferDarkMode ? "#93c5fd" : "#2563eb"
            codeBackground = preferDarkMode ? "#0b1220" : "#f3f4f6"
            codeBorder = preferDarkMode ? "#334155" : "#d1d5db"
            quoteBackground = preferDarkMode ? "#0b1220" : "#f8fafc"
            quoteBorder = preferDarkMode ? "#3b82f6" : "#2563eb"
            tableHeaderBackground = preferDarkMode ? "#172033" : "#f3f4f6"
            horizontalRuleColor = preferDarkMode ? "#334155" : "#d1d5db"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.25)" : "rgba(15, 23, 42, 0.06)"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        case "article":
            basePadding = "32px 48px"
            fontSize = "17px"
            lineHeight = "1.8"
            maxWidth = "760px"
            bodyBackground = preferDarkMode ? "#111827" : "#f9fafb"
            contentBackground = preferDarkMode ? "#0f172a" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #1f2937" : "1px solid #e5e7eb"
            textColor = preferDarkMode ? "#f3f4f6" : "#111827"
            mutedTextColor = preferDarkMode ? "#9ca3af" : "#6b7280"
            linkColor = preferDarkMode ? "#c4b5fd" : "#7c3aed"
            codeBackground = preferDarkMode ? "#111827" : "#f3f4f6"
            codeBorder = preferDarkMode ? "#374151" : "#d1d5db"
            quoteBackground = preferDarkMode ? "#111827" : "#faf5ff"
            quoteBorder = preferDarkMode ? "#8b5cf6" : "#7c3aed"
            tableHeaderBackground = preferDarkMode ? "#172033" : "#f5f3ff"
            horizontalRuleColor = preferDarkMode ? "#374151" : "#d1d5db"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.28)" : "rgba(15, 23, 42, 0.07)"
            bodyFontFamily = "Charter, \"Iowan Old Style\", \"Palatino Linotype\", serif"
        case "compact", "dense-compact":
            basePadding = "14px 16px"
            fontSize = "13px"
            lineHeight = "1.5"
            maxWidth = "none"
            bodyBackground = preferDarkMode ? "#0f172a" : "#f8fafc"
            contentBackground = preferDarkMode ? "#111827" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #1f2937" : "1px solid #e5e7eb"
            textColor = preferDarkMode ? "#e5e7eb" : "#111827"
            mutedTextColor = preferDarkMode ? "#94a3b8" : "#6b7280"
            linkColor = preferDarkMode ? "#7dd3fc" : "#0284c7"
            codeBackground = preferDarkMode ? "#0b1220" : "#eef2ff"
            codeBorder = preferDarkMode ? "#334155" : "#c7d2fe"
            quoteBackground = preferDarkMode ? "#111827" : "#f8fafc"
            quoteBorder = preferDarkMode ? "#38bdf8" : "#0284c7"
            tableHeaderBackground = preferDarkMode ? "#172033" : "#f3f4f6"
            horizontalRuleColor = preferDarkMode ? "#334155" : "#d1d5db"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.22)" : "rgba(15, 23, 42, 0.05)"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        case "github-docs":
            basePadding = "24px 28px"
            fontSize = "14px"
            lineHeight = "1.65"
            maxWidth = "920px"
            bodyBackground = preferDarkMode ? "#0d1117" : "#f6f8fa"
            contentBackground = preferDarkMode ? "#161b22" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #30363d" : "1px solid #d0d7de"
            textColor = preferDarkMode ? "#c9d1d9" : "#1f2328"
            mutedTextColor = preferDarkMode ? "#8b949e" : "#57606a"
            linkColor = preferDarkMode ? "#58a6ff" : "#0969da"
            codeBackground = preferDarkMode ? "#0d1117" : "#f6f8fa"
            codeBorder = preferDarkMode ? "#30363d" : "#d0d7de"
            quoteBackground = preferDarkMode ? "#0d1117" : "#f6f8fa"
            quoteBorder = preferDarkMode ? "#30363d" : "#d0d7de"
            tableHeaderBackground = preferDarkMode ? "#21262d" : "#f6f8fa"
            horizontalRuleColor = preferDarkMode ? "#30363d" : "#d8dee4"
            shadowColor = preferDarkMode ? "rgba(1, 4, 9, 0.28)" : "rgba(31, 35, 40, 0.04)"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif"
        case "academic-paper":
            basePadding = "40px 54px"
            fontSize = "16px"
            lineHeight = "1.85"
            maxWidth = "780px"
            bodyBackground = preferDarkMode ? "#161311" : "#f6f1e8"
            contentBackground = preferDarkMode ? "#1f1a17" : "#fffdf8"
            contentBorder = preferDarkMode ? "1px solid #3a312b" : "1px solid #e7dccb"
            textColor = preferDarkMode ? "#f5efe4" : "#2f241c"
            mutedTextColor = preferDarkMode ? "#c2b4a3" : "#7a6755"
            linkColor = preferDarkMode ? "#fbbf24" : "#9a6700"
            codeBackground = preferDarkMode ? "#191512" : "#f3eadc"
            codeBorder = preferDarkMode ? "#4b3f36" : "#dbcab0"
            quoteBackground = preferDarkMode ? "#191512" : "#f8efe0"
            quoteBorder = preferDarkMode ? "#c08457" : "#b7791f"
            tableHeaderBackground = preferDarkMode ? "#2b241f" : "#efe3d3"
            horizontalRuleColor = preferDarkMode ? "#4b3f36" : "#d6c3aa"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.24)" : "rgba(120, 103, 85, 0.08)"
            bodyFontFamily = "\"New York\", Georgia, \"Times New Roman\", serif"
        case "terminal-notes":
            basePadding = "18px 20px"
            fontSize = "14px"
            lineHeight = "1.55"
            maxWidth = "940px"
            bodyBackground = preferDarkMode ? "#08110c" : "#f3fbf5"
            contentBackground = preferDarkMode ? "#0b1510" : "#fbfffc"
            contentBorder = preferDarkMode ? "1px solid #173022" : "1px solid #cfe7d5"
            textColor = preferDarkMode ? "#c8facc" : "#16301f"
            mutedTextColor = preferDarkMode ? "#7bcf90" : "#4b6b55"
            linkColor = preferDarkMode ? "#5eead4" : "#0f766e"
            codeBackground = preferDarkMode ? "#07100c" : "#e8f6eb"
            codeBorder = preferDarkMode ? "#214433" : "#b9d8c0"
            quoteBackground = preferDarkMode ? "#09130e" : "#eef8f0"
            quoteBorder = preferDarkMode ? "#22c55e" : "#15803d"
            tableHeaderBackground = preferDarkMode ? "#102119" : "#e5f3e8"
            horizontalRuleColor = preferDarkMode ? "#214433" : "#b9d8c0"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.18)" : "rgba(22, 48, 31, 0.05)"
            bodyFontFamily = "\"SF Mono\", Menlo, Monaco, monospace"
        case "magazine":
            basePadding = "34px 42px"
            fontSize = "17px"
            lineHeight = "1.75"
            maxWidth = "900px"
            bodyBackground = preferDarkMode ? "#111827" : "#fff7ed"
            contentBackground = preferDarkMode ? "#1f2937" : "#fffdf8"
            contentBorder = preferDarkMode ? "1px solid #374151" : "1px solid #fed7aa"
            textColor = preferDarkMode ? "#f9fafb" : "#231815"
            mutedTextColor = preferDarkMode ? "#d1d5db" : "#7c5e54"
            linkColor = preferDarkMode ? "#fda4af" : "#c2410c"
            codeBackground = preferDarkMode ? "#111827" : "#fff1e6"
            codeBorder = preferDarkMode ? "#4b5563" : "#fdba74"
            quoteBackground = preferDarkMode ? "#172033" : "#ffedd5"
            quoteBorder = preferDarkMode ? "#fb7185" : "#ea580c"
            tableHeaderBackground = preferDarkMode ? "#243044" : "#ffedd5"
            horizontalRuleColor = preferDarkMode ? "#4b5563" : "#fdba74"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.26)" : "rgba(194, 65, 12, 0.07)"
            bodyFontFamily = "\"Avenir Next\", \"Helvetica Neue\", sans-serif"
        case "minimal-reader":
            basePadding = "26px 28px"
            fontSize = "15px"
            lineHeight = "1.72"
            maxWidth = "720px"
            bodyBackground = preferDarkMode ? "#0f172a" : "#ffffff"
            contentBackground = preferDarkMode ? "#111827" : "#ffffff"
            contentBorder = "none"
            textColor = preferDarkMode ? "#e5e7eb" : "#111827"
            mutedTextColor = preferDarkMode ? "#9ca3af" : "#6b7280"
            linkColor = preferDarkMode ? "#a5b4fc" : "#4338ca"
            codeBackground = preferDarkMode ? "#111827" : "#f3f4f6"
            codeBorder = preferDarkMode ? "#374151" : "#e5e7eb"
            quoteBackground = preferDarkMode ? "#111827" : "#f9fafb"
            quoteBorder = preferDarkMode ? "#6366f1" : "#4338ca"
            tableHeaderBackground = preferDarkMode ? "#1f2937" : "#f9fafb"
            horizontalRuleColor = preferDarkMode ? "#374151" : "#e5e7eb"
            shadowColor = "transparent"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif"
        case "presentation":
            basePadding = "40px 48px"
            fontSize = "18px"
            lineHeight = "1.7"
            maxWidth = "1040px"
            bodyBackground = preferDarkMode ? "#0b1020" : "#eef4ff"
            contentBackground = preferDarkMode ? "#0f172a" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #1e293b" : "1px solid #c7d2fe"
            textColor = preferDarkMode ? "#f8fafc" : "#0f172a"
            mutedTextColor = preferDarkMode ? "#cbd5e1" : "#64748b"
            linkColor = preferDarkMode ? "#93c5fd" : "#1d4ed8"
            codeBackground = preferDarkMode ? "#111827" : "#eef2ff"
            codeBorder = preferDarkMode ? "#334155" : "#c7d2fe"
            quoteBackground = preferDarkMode ? "#111827" : "#eff6ff"
            quoteBorder = preferDarkMode ? "#60a5fa" : "#2563eb"
            tableHeaderBackground = preferDarkMode ? "#172033" : "#dbeafe"
            horizontalRuleColor = preferDarkMode ? "#334155" : "#bfdbfe"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.32)" : "rgba(37, 99, 235, 0.08)"
            bodyFontFamily = "\"SF Pro Display\", -apple-system, BlinkMacSystemFont, sans-serif"
        case "night-contrast":
            basePadding = "22px 26px"
            fontSize = "15px"
            lineHeight = "1.68"
            maxWidth = "920px"
            bodyBackground = preferDarkMode ? "linear-gradient(180deg, #020617 0%, #050816 100%)" : "#eff6ff"
            contentBackground = preferDarkMode ? "#020617" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #1e293b" : "1px solid #bfdbfe"
            textColor = preferDarkMode ? "#f8fafc" : "#0f172a"
            mutedTextColor = preferDarkMode ? "#cbd5e1" : "#64748b"
            linkColor = preferDarkMode ? "#7dd3fc" : "#0369a1"
            codeBackground = preferDarkMode ? "#0f172a" : "#eff6ff"
            codeBorder = preferDarkMode ? "#334155" : "#bfdbfe"
            quoteBackground = preferDarkMode ? "#0b1220" : "#e0f2fe"
            quoteBorder = preferDarkMode ? "#38bdf8" : "#0284c7"
            tableHeaderBackground = preferDarkMode ? "#172033" : "#dbeafe"
            horizontalRuleColor = preferDarkMode ? "#334155" : "#bfdbfe"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.34)" : "rgba(3, 105, 161, 0.07)"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif"
        case "warm-sepia":
            basePadding = "24px 28px"
            fontSize = "16px"
            lineHeight = "1.74"
            maxWidth = "820px"
            bodyBackground = preferDarkMode ? "#221b16" : "#f8f1e3"
            contentBackground = preferDarkMode ? "#2c241d" : "#fffaf0"
            contentBorder = preferDarkMode ? "1px solid #4a3c30" : "1px solid #e6d4b8"
            textColor = preferDarkMode ? "#f4e7d3" : "#3f2d1f"
            mutedTextColor = preferDarkMode ? "#d8c1a1" : "#7c6247"
            linkColor = preferDarkMode ? "#fbbf24" : "#b45309"
            codeBackground = preferDarkMode ? "#201913" : "#f3e7d4"
            codeBorder = preferDarkMode ? "#5a493b" : "#dec5a0"
            quoteBackground = preferDarkMode ? "#241d17" : "#f5ead9"
            quoteBorder = preferDarkMode ? "#f59e0b" : "#b45309"
            tableHeaderBackground = preferDarkMode ? "#332920" : "#efe0c6"
            horizontalRuleColor = preferDarkMode ? "#5a493b" : "#dec5a0"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.22)" : "rgba(126, 98, 71, 0.08)"
            bodyFontFamily = "Charter, Georgia, serif"
        case "developer-spec":
            basePadding = "22px 24px"
            fontSize = "14px"
            lineHeight = "1.62"
            maxWidth = "980px"
            bodyBackground = preferDarkMode ? "#0f172a" : "#f5f7fb"
            contentBackground = preferDarkMode ? "#111827" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #334155" : "1px solid #dbe1ea"
            textColor = preferDarkMode ? "#e2e8f0" : "#0f172a"
            mutedTextColor = preferDarkMode ? "#94a3b8" : "#64748b"
            linkColor = preferDarkMode ? "#60a5fa" : "#2563eb"
            codeBackground = preferDarkMode ? "#0b1220" : "#eff3f8"
            codeBorder = preferDarkMode ? "#334155" : "#cbd5e1"
            quoteBackground = preferDarkMode ? "#101826" : "#f8fafc"
            quoteBorder = preferDarkMode ? "#38bdf8" : "#2563eb"
            tableHeaderBackground = preferDarkMode ? "#172033" : "#eef2f7"
            horizontalRuleColor = preferDarkMode ? "#334155" : "#cbd5e1"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.24)" : "rgba(15, 23, 42, 0.05)"
            bodyFontFamily = "\"SF Mono\", Menlo, Monaco, monospace"
        case "api-reference":
            basePadding = "20px 24px"
            fontSize = "14px"
            lineHeight = "1.58"
            maxWidth = "980px"
            bodyBackground = preferDarkMode ? "#08111f" : "#f4f8fb"
            contentBackground = preferDarkMode ? "#0d1726" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #24364d" : "1px solid #d9e4ee"
            textColor = preferDarkMode ? "#e6edf6" : "#122033"
            mutedTextColor = preferDarkMode ? "#93a8c0" : "#63758a"
            linkColor = preferDarkMode ? "#7dd3fc" : "#0369a1"
            codeBackground = preferDarkMode ? "#08111f" : "#eef5fa"
            codeBorder = preferDarkMode ? "#2c445f" : "#c9d9e6"
            quoteBackground = preferDarkMode ? "#0a1422" : "#f7fbff"
            quoteBorder = preferDarkMode ? "#38bdf8" : "#0ea5e9"
            tableHeaderBackground = preferDarkMode ? "#132238" : "#e9f2f8"
            horizontalRuleColor = preferDarkMode ? "#2c445f" : "#c9d9e6"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.24)" : "rgba(18, 32, 51, 0.05)"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        case "changelog":
            basePadding = "22px 28px"
            fontSize = "14px"
            lineHeight = "1.64"
            maxWidth = "860px"
            bodyBackground = preferDarkMode ? "#101418" : "#f7f7f4"
            contentBackground = preferDarkMode ? "#171c22" : "#fffffb"
            contentBorder = preferDarkMode ? "1px solid #303841" : "1px solid #deded6"
            textColor = preferDarkMode ? "#e7ecef" : "#1f2933"
            mutedTextColor = preferDarkMode ? "#a6b0b8" : "#6b7280"
            linkColor = preferDarkMode ? "#86efac" : "#15803d"
            codeBackground = preferDarkMode ? "#101418" : "#f0f2ec"
            codeBorder = preferDarkMode ? "#3a444e" : "#d4d8cf"
            quoteBackground = preferDarkMode ? "#11191f" : "#f3f6ef"
            quoteBorder = preferDarkMode ? "#4ade80" : "#16a34a"
            tableHeaderBackground = preferDarkMode ? "#20272f" : "#eef1e8"
            horizontalRuleColor = preferDarkMode ? "#3a444e" : "#d4d8cf"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.22)" : "rgba(31, 41, 51, 0.05)"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif"
        case "focus-writing":
            basePadding = "34px 44px"
            fontSize = "17px"
            lineHeight = "1.82"
            maxWidth = "740px"
            bodyBackground = preferDarkMode ? "#121416" : "#fbfaf7"
            contentBackground = preferDarkMode ? "#181b1f" : "#fffefd"
            contentBorder = preferDarkMode ? "1px solid #2b3138" : "1px solid #ece7df"
            textColor = preferDarkMode ? "#f0ede8" : "#24211d"
            mutedTextColor = preferDarkMode ? "#b5aea5" : "#716b63"
            linkColor = preferDarkMode ? "#fca5a5" : "#b91c1c"
            codeBackground = preferDarkMode ? "#121416" : "#f4f0eb"
            codeBorder = preferDarkMode ? "#343a42" : "#e1d9cf"
            quoteBackground = preferDarkMode ? "#15181b" : "#f8f4ef"
            quoteBorder = preferDarkMode ? "#f87171" : "#dc2626"
            tableHeaderBackground = preferDarkMode ? "#22272e" : "#f2eee8"
            horizontalRuleColor = preferDarkMode ? "#343a42" : "#e1d9cf"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.2)" : "rgba(36, 33, 29, 0.045)"
            bodyFontFamily = "\"New York\", Charter, Georgia, serif"
        case "lab-notes":
            basePadding = "20px 24px"
            fontSize = "14px"
            lineHeight = "1.66"
            maxWidth = "920px"
            bodyBackground = preferDarkMode ? "#0b1014" : "#f3f8f7"
            contentBackground = preferDarkMode ? "#11181d" : "#fcfffe"
            contentBorder = preferDarkMode ? "1px solid #27363b" : "1px solid #cfe1de"
            textColor = preferDarkMode ? "#dcefed" : "#18302e"
            mutedTextColor = preferDarkMode ? "#92aaa6" : "#617774"
            linkColor = preferDarkMode ? "#67e8f9" : "#0f766e"
            codeBackground = preferDarkMode ? "#0b1014" : "#e9f4f2"
            codeBorder = preferDarkMode ? "#31484d" : "#bdd7d2"
            quoteBackground = preferDarkMode ? "#0e1519" : "#eef8f6"
            quoteBorder = preferDarkMode ? "#2dd4bf" : "#0d9488"
            tableHeaderBackground = preferDarkMode ? "#1a272b" : "#e3f0ed"
            horizontalRuleColor = preferDarkMode ? "#31484d" : "#bdd7d2"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.22)" : "rgba(24, 48, 46, 0.05)"
            bodyFontFamily = "\"SF Mono\", Menlo, Monaco, monospace"
        case "editorial-review":
            basePadding = "30px 38px"
            fontSize = "16px"
            lineHeight = "1.76"
            maxWidth = "820px"
            bodyBackground = preferDarkMode ? "#181219" : "#fbf6fa"
            contentBackground = preferDarkMode ? "#211824" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #3d2d42" : "1px solid #eadcea"
            textColor = preferDarkMode ? "#f5eef6" : "#2a1e2d"
            mutedTextColor = preferDarkMode ? "#cbb9cf" : "#756579"
            linkColor = preferDarkMode ? "#f0abfc" : "#a21caf"
            codeBackground = preferDarkMode ? "#181219" : "#f8eef8"
            codeBorder = preferDarkMode ? "#4a3551" : "#e7cfe7"
            quoteBackground = preferDarkMode ? "#1b1420" : "#fbf0fb"
            quoteBorder = preferDarkMode ? "#e879f9" : "#c026d3"
            tableHeaderBackground = preferDarkMode ? "#2a2030" : "#f6e8f6"
            horizontalRuleColor = preferDarkMode ? "#4a3551" : "#e7cfe7"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.24)" : "rgba(162, 28, 175, 0.05)"
            bodyFontFamily = "\"Avenir Next\", -apple-system, BlinkMacSystemFont, sans-serif"
        case "neon-paper":
            basePadding = "24px 30px"
            fontSize = "15px"
            lineHeight = "1.68"
            maxWidth = "900px"
            bodyBackground = preferDarkMode ? "#070b12" : "#f7fbff"
            contentBackground = preferDarkMode ? "#0b1220" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #243044" : "1px solid #d9e8ff"
            textColor = preferDarkMode ? "#edf6ff" : "#102033"
            mutedTextColor = preferDarkMode ? "#9fb5cb" : "#64748b"
            linkColor = preferDarkMode ? "#80ffdb" : "#0f76a8"
            codeBackground = preferDarkMode ? "#07101c" : "#edf7ff"
            codeBorder = preferDarkMode ? "#2e4059" : "#c6dfff"
            quoteBackground = preferDarkMode ? "#091521" : "#eff9ff"
            quoteBorder = preferDarkMode ? "#38bdf8" : "#0ea5e9"
            tableHeaderBackground = preferDarkMode ? "#132033" : "#e6f3ff"
            horizontalRuleColor = preferDarkMode ? "#2e4059" : "#c6dfff"
            shadowColor = preferDarkMode ? "rgba(56, 189, 248, 0.08)" : "rgba(14, 165, 233, 0.06)"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        default:
            basePadding = "18px 22px"
            fontSize = "14px"
            lineHeight = "1.6"
            maxWidth = "860px"
            bodyBackground = preferDarkMode ? "#0f172a" : "#f8fafc"
            contentBackground = preferDarkMode ? "#111827" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #1f2937" : "1px solid #e5e7eb"
            textColor = preferDarkMode ? "#e5e7eb" : "#111827"
            mutedTextColor = preferDarkMode ? "#94a3b8" : "#6b7280"
            linkColor = preferDarkMode ? "#7FB0FF" : "#2F7CF6"
            codeBackground = preferDarkMode ? "#0b1220" : "#f3f4f6"
            codeBorder = preferDarkMode ? "#334155" : "#d1d5db"
            quoteBackground = preferDarkMode ? "#111827" : "#f8fafc"
            quoteBorder = preferDarkMode ? "#3b82f6" : "#2563eb"
            tableHeaderBackground = preferDarkMode ? "#172033" : "#f3f4f6"
            horizontalRuleColor = preferDarkMode ? "#334155" : "#d1d5db"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.25)" : "rgba(15, 23, 42, 0.06)"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        }

        let resolvedBackgroundStyle: MarkdownPreviewBackgroundStyle = {
            switch backgroundStyle {
            case .automatic:
                return translucentBackgroundEnabled ? .translucent : .template
            case .template, .translucent, .neutral:
                return backgroundStyle
            }
        }()

        switch resolvedBackgroundStyle {
        case .template:
            break
        case .translucent:
            bodyBackground = "transparent"
            contentBackground = preferDarkMode ? "rgba(15, 23, 42, 0.34)" : "rgba(255, 255, 255, 0.38)"
            contentBorder = preferDarkMode ? "1px solid rgba(148, 163, 184, 0.18)" : "1px solid rgba(148, 163, 184, 0.26)"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.16)" : "rgba(15, 23, 42, 0.05)"
            contentBackdropFilter = "saturate(1.15) blur(18px)"
        case .neutral:
            bodyBackground = preferDarkMode ? "#10131a" : "#f3f5f8"
            contentBackground = preferDarkMode ? "#161b24" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #242b38" : "1px solid #dde3ea"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.22)" : "rgba(15, 23, 42, 0.06)"
        case .automatic:
            break
        }

        let resolvedFontSize = runtimeFontSize.map { "\(Int($0.rounded()))px" } ?? fontSize

        return """
        :root {
          color-scheme: light dark;
          --md-text-color: \(textColor);
          --md-link-color: \(linkColor);
          --md-muted-color: \(mutedTextColor);
          --md-body-background: \(bodyBackground);
          --md-content-background: \(contentBackground);
          --md-content-border: \(contentBorder);
          --md-code-background: \(codeBackground);
          --md-code-border: \(codeBorder);
          --md-quote-background: \(quoteBackground);
          --md-quote-border: \(quoteBorder);
          --md-table-header-background: \(tableHeaderBackground);
          --md-hr-color: \(horizontalRuleColor);
          --md-shadow-color: \(shadowColor);
          --md-content-backdrop-filter: \(contentBackdropFilter);
        }
        html, body {
          margin: 0;
          padding: 0;
          width: 100%;
          min-width: 0;
          max-width: 100%;
          overflow-x: hidden;
          background: var(--md-body-background);
          color: var(--md-text-color);
          font-family: \(bodyFontFamily);
          font-size: \(resolvedFontSize);
          line-height: \(lineHeight);
        }
        *, *::before, *::after {
          box-sizing: border-box;
        }
        .content {
          width: 100%;
          min-width: 0;
          max-width: \(maxWidth);
          padding: \(basePadding);
          margin: 0 auto;
          background: var(--md-content-background);
          border: var(--md-content-border);
          border-radius: 14px;
          box-shadow: 0 10px 30px var(--md-shadow-color);
          -webkit-backdrop-filter: var(--md-content-backdrop-filter);
          backdrop-filter: var(--md-content-backdrop-filter);
        }
        .preview-warning {
          margin: 0.5em 0 0.8em;
          padding: 0.75em 0.9em;
          border-radius: 9px;
          border: 1px solid color-mix(in srgb, #f59e0b 45%, transparent);
          background: color-mix(in srgb, #f59e0b 12%, transparent);
        }
        .preview-warning p {
          margin: 0;
        }
        .preview-warning-meta {
          margin-top: 0.4em !important;
          font-size: 0.92em;
          opacity: 0.9;
        }
        h1, h2, h3, h4, h5, h6 {
          line-height: 1.25;
          margin: 1.1em 0 0.55em;
          font-weight: 700;
          max-width: 100%;
          overflow-wrap: break-word;
        }
        h1 { font-size: 1.85em; border-bottom: 1px solid color-mix(in srgb, currentColor 18%, transparent); padding-bottom: 0.25em; }
        h2 { font-size: 1.45em; border-bottom: 1px solid color-mix(in srgb, currentColor 13%, transparent); padding-bottom: 0.2em; }
        h3 { font-size: 1.2em; }
        p, li, td, th { color: var(--md-text-color); }
        .preview-warning-meta, figcaption { color: var(--md-muted-color); }
        p, ul, ol, blockquote, table, pre { margin: 0.65em 0; }
        p, li, blockquote {
          max-width: 100%;
          overflow-wrap: break-word;
        }
        ul, ol { padding-left: 1.3em; }
        li { margin: 0.2em 0; }
        .task-list-item {
          list-style: none;
          margin-left: -1.15em;
        }
        .task-list-item input {
          width: 1em;
          height: 1em;
          margin: 0 0.45em 0 0;
          vertical-align: -0.12em;
          accent-color: var(--md-link-color);
        }
        del {
          color: var(--md-muted-color);
        }
        blockquote {
          margin-left: 0;
          padding: 0.45em 0.9em;
          border-left: 3px solid var(--md-quote-border);
          background: var(--md-quote-background);
          border-radius: 6px;
        }
        code {
          font-family: "SF Mono", "Menlo", "Monaco", monospace;
          font-size: 0.9em;
          padding: 0.12em 0.35em;
          border-radius: 5px;
          background: var(--md-code-background);
          border: 1px solid var(--md-code-border);
          overflow-wrap: anywhere;
        }
        pre {
          max-width: 100%;
          overflow-x: auto;
          padding: 0.8em 0.95em;
          border-radius: 9px;
          background: var(--md-code-background);
          border: 1px solid var(--md-code-border);
          line-height: 1.35;
          white-space: pre;
        }
        pre code {
          display: block;
          padding: 0;
          background: transparent;
          border-radius: 0;
          font-size: 0.88em;
          line-height: 1.35;
          white-space: pre;
        }
        table {
          display: block;
          max-width: 100%;
          overflow-x: auto;
          border-collapse: collapse;
          width: 100%;
          border: 1px solid color-mix(in srgb, currentColor 16%, transparent);
          border-radius: 8px;
          overflow: hidden;
        }
        th, td {
          text-align: left;
          padding: 0.45em 0.55em;
          border-bottom: 1px solid color-mix(in srgb, currentColor 10%, transparent);
          overflow-wrap: anywhere;
        }
        th {
          background: var(--md-table-header-background);
          font-weight: 600;
        }
        .mermaid-diagram {
          margin: 0.9em 0;
          padding: 0.75em;
          border-radius: 10px;
          border: 1px solid color-mix(in srgb, currentColor 14%, transparent);
          background: color-mix(in srgb, var(--md-code-background) 82%, transparent);
          overflow-x: auto;
        }
        .mermaid-svg {
          display: block;
          width: 100%;
          max-width: 620px;
          height: auto;
          margin: 0 auto;
        }
        .mermaid-node rect {
          fill: var(--md-content-background);
          stroke: var(--md-link-color);
          stroke-width: 1.6;
        }
        .mermaid-node text,
        .mermaid-edge-label {
          fill: var(--md-text-color);
          font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        }
        .mermaid-edge {
          fill: none;
          stroke: var(--md-link-color);
          stroke-width: 1.5;
        }
        .mermaid-arrow {
          fill: var(--md-link-color);
        }
        .mermaid-diagram figcaption {
          margin-top: 0.5em;
          text-align: center;
          font-size: 0.82em;
        }
        .mermaid-diagram-source pre {
          margin-bottom: 0;
        }
        a {
          color: var(--md-link-color);
          text-decoration: none;
          border-bottom: 1px solid color-mix(in srgb, var(--md-link-color) 45%, transparent);
          overflow-wrap: anywhere;
        }
        .remote-image-placeholder {
          display: inline-flex;
          align-items: center;
          max-width: 100%;
          padding: 0.22em 0.55em;
          border: 1px solid color-mix(in srgb, var(--md-link-color) 35%, transparent);
          border-radius: 6px;
          background: color-mix(in srgb, var(--md-link-color) 9%, transparent);
          overflow-wrap: anywhere;
        }
        img {
          max-width: 100%;
          height: auto;
          border-radius: 8px;
        }
        hr {
          border: 0;
          border-top: 1px solid var(--md-hr-color);
          margin: 1.1em 0;
        }
        body.pdf-export {
          background: #ffffff !important;
          color: #111827 !important;
        }
        body.pdf-export .content {
          background: #ffffff !important;
          border: none !important;
          box-shadow: none !important;
        }
        body.pdf-export.pdf-one-page .content {
          max-width: none !important;
          width: auto !important;
        }
        body.pdf-export, body.pdf-export * {
          opacity: 1 !important;
          text-shadow: none !important;
          -webkit-text-fill-color: #111827 !important;
        }
        body.pdf-export a {
          color: #1d4ed8 !important;
          border-bottom-color: color-mix(in srgb, #1d4ed8 45%, transparent) !important;
          -webkit-text-fill-color: #1d4ed8 !important;
        }
        body.pdf-export code,
        body.pdf-export pre,
        body.pdf-export pre code {
          color: #111827 !important;
          background: #f3f4f6 !important;
          border-color: #d1d5db !important;
          -webkit-text-fill-color: #111827 !important;
        }
        @media print {
          :root {
            color-scheme: light;
            --md-text-color: #111827;
            --md-link-color: #1d4ed8;
          }
          @page {
            size: A4;
            margin: 0;
          }
          html, body {
            height: auto !important;
            overflow: visible !important;
            background: #ffffff !important;
            color: var(--md-text-color) !important;
          }
          body * {
            color: inherit !important;
            text-shadow: none !important;
          }
          a {
            color: var(--md-link-color) !important;
          }
          code, pre {
            color: #111827 !important;
          }
          .content {
            max-width: none !important;
            margin: 0 !important;
            padding: 0 !important;
            border: none !important;
            box-shadow: none !important;
            border-radius: 0 !important;
            background: transparent !important;
          }
          h1, h2, h3 {
            break-after: avoid-page;
          }
          blockquote, figure {
            break-inside: avoid;
          }
        }
        """
    }

    nonisolated static func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
