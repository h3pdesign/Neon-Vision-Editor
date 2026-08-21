import Foundation
import SwiftUI
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

private struct MarkdownPreviewLocalImageCache {
    nonisolated private static let maximumImageByteCount = 3_000_000
    nonisolated private static let maximumEntryCount = 12

    private struct Entry {
        let modificationDate: Date?
        let fileSize: Int
        let dataURL: String
    }

    private var entries: [String: Entry] = [:]

    nonisolated mutating func dataURL(for url: URL) -> String? {
        let key = url.standardizedFileURL.path
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let fileSize = values.fileSize else { return nil }
        if let entry = entries[key],
           entry.modificationDate == values.contentModificationDate,
           entry.fileSize == fileSize {
            return entry.dataURL
        }
        guard let mimeType = Self.mimeType(for: url),
              let data = try? Data(contentsOf: url),
              data.count <= Self.maximumImageByteCount else { return nil }
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        if entries.count >= Self.maximumEntryCount, let oldestKey = entries.keys.first {
            entries.removeValue(forKey: oldestKey)
        }
        entries[key] = Entry(
            modificationDate: values.contentModificationDate,
            fileSize: fileSize,
            dataURL: dataURL
        )
        return dataURL
    }

    private nonisolated static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        default: return nil
        }
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
    nonisolated private static let markdownPreviewHTMLCache = NVELock(MarkdownPreviewHTMLCache())
    nonisolated private static let markdownPreviewLocalImageCache = NVELock(MarkdownPreviewLocalImageCache())
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
        case paper
        case slate
        case ink

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
            case .paper:
                return "Paper"
            case .slate:
                return "Slate"
            case .ink:
                return "Ink"
            }
        }
    }

    static let standardMarkdownPreviewBackgroundStyles: [MarkdownPreviewBackgroundStyle] = [
        .automatic, .template, .translucent, .neutral
    ]

#if os(visionOS)
    enum VisionMarkdownPreviewReaderStyle: String, CaseIterable, Identifiable {
        case systemGlass
        case paper
        case slate
        case ink

        var id: String { rawValue }

        var title: String {
            switch self {
            case .systemGlass: return "System Glass"
            case .paper: return "Paper"
            case .slate: return "Slate"
            case .ink: return "Ink"
            }
        }

        var backgroundStyle: MarkdownPreviewBackgroundStyle {
            switch self {
            case .systemGlass: return .automatic
            case .paper: return .paper
            case .slate: return .slate
            case .ink: return .ink
            }
        }

        var editorSurfaceColor: Color? {
            switch self {
            case .systemGlass:
                return nil
            case .paper:
                return Color(red: 1.0, green: 0.992, blue: 0.969)
            case .slate:
                return Color(red: 0.965, green: 0.973, blue: 0.980)
            case .ink:
                return Color(red: 0.043, green: 0.043, blue: 0.051)
            }
        }
    }
#endif

    // MARK: - Preview Configuration

    struct MarkdownPreviewTemplateOption: Identifiable {
        let id: String
        let title: String
    }

    static let markdownPreviewTemplateOptions: [MarkdownPreviewTemplateOption] = [
        MarkdownPreviewTemplateOption(id: "default", title: "Default"),
        MarkdownPreviewTemplateOption(id: "neon-editorial", title: "Neon Editorial"),
        MarkdownPreviewTemplateOption(id: "developer-slate", title: "Developer Slate"),
        MarkdownPreviewTemplateOption(id: "nordic-light", title: "Nordic Light"),
        MarkdownPreviewTemplateOption(id: "solarized", title: "Solarized"),
        MarkdownPreviewTemplateOption(id: "article", title: "Article"),
        MarkdownPreviewTemplateOption(id: "notebook", title: "Notebook"),
        MarkdownPreviewTemplateOption(id: "high-contrast", title: "High Contrast"),
        MarkdownPreviewTemplateOption(id: "terminal-notes", title: "Terminal Notes"),
        MarkdownPreviewTemplateOption(id: "warm-sepia", title: "Warm Sepia"),
        MarkdownPreviewTemplateOption(id: "electric-pop", title: "Electric Pop"),
        MarkdownPreviewTemplateOption(id: "aurora", title: "Aurora"),
        MarkdownPreviewTemplateOption(id: "citrus", title: "Citrus"),
        MarkdownPreviewTemplateOption(id: "plasma", title: "Plasma"),
        MarkdownPreviewTemplateOption(id: "deep-ocean", title: "Deep Ocean"),
        MarkdownPreviewTemplateOption(id: "ember-glow", title: "Ember Glow"),
        MarkdownPreviewTemplateOption(id: "forest-canopy", title: "Forest Canopy"),
        MarkdownPreviewTemplateOption(id: "ultraviolet", title: "Ultraviolet"),
        MarkdownPreviewTemplateOption(id: "cobalt", title: "Cobalt"),
        MarkdownPreviewTemplateOption(id: "mint-paper", title: "Mint Paper")
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
#if os(visionOS)
        return "default"
#else
        if Self.markdownPreviewTemplateOptions.contains(where: { $0.id == markdownPreviewTemplateRaw }) {
            return markdownPreviewTemplateRaw
        }
        return "default"
#endif
    }

    var markdownPreviewBackgroundStyle: MarkdownPreviewBackgroundStyle {
#if os(visionOS)
        return VisionMarkdownPreviewReaderStyle(rawValue: markdownPreviewReaderStyleVisionRaw)?.backgroundStyle ?? .automatic
#else
        MarkdownPreviewBackgroundStyle(rawValue: markdownPreviewBackgroundStyleRaw) ?? .automatic
#endif
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
                String(tab.document.utf16Length)
            ].joined(separator: ":")
        } else {
            contentSignature = [
                "single",
                String(singleContent.count),
                String(singleContent.hashValue)
            ].joined(separator: ":")
        }
        let documentPath = viewModel.selectedTab?.fileURL?.standardizedFileURL.path ?? ""
        return [
            "renderer-5",
            contentSignature,
            documentPath,
            markdownPreviewTemplate,
            String(markdownPreviewPreferDarkMode),
            markdownPreviewBackgroundStyle.rawValue,
            markdownPreviewDialect.rawValue,
            String(enableTranslucentWindow),
            String(Int(markdownPreviewRuntimeFontSize.rounded()))
        ].joined(separator: "|")
    }

    func scheduleMarkdownPreviewRender(immediate: Bool = false) {
        // A detached preview remains a live consumer even after the inline pane
        // is closed. Its render pipeline must therefore not depend on the
        // inline preview's visibility.
        guard showMarkdownPreviewPane || isPDFNoteMarkdownPreviewVisible || showDetachedPreviewWindow else { return }
        // The virtual editor must not be promoted to a whole-document String by
        // the preview pipeline. Preview rendering is intentionally unavailable
        // for file-backed documents until it has a bounded source adapter.
        guard viewModel.selectedTab?.usesFileBackedStorage != true else {
            markdownPreviewRenderTask?.cancel()
            markdownPreviewRenderTask = nil
            isMarkdownPreviewRendering = false
            markdownPreviewRenderedHTML = ""
            return
        }
        let signature = markdownPreviewCurrentRenderSignature
        // Local images are embedded from disk. Do not reuse HTML that could have been
        // generated before the document URL or its sibling assets were available.
        let containsLocalImageReference = Self.markdownMayReferenceLocalImage(currentContent)
        guard immediate || signature != markdownPreviewRenderSignature else { return }

        markdownPreviewRenderTask?.cancel()
        isMarkdownPreviewRendering = true

        if !containsLocalImageReference,
           let cachedHTML = Self.markdownPreviewHTMLCache.withLock({ $0.html(for: signature) }) {
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
        let documentURL = viewModel.selectedTab?.fileURL
        let projectAccessURL = projectFolderSecurityURL

        markdownPreviewRenderTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: markdownPreviewRenderDebounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard signature == markdownPreviewCurrentRenderSignature else {
                guard !Task.isCancelled else { return }
                scheduleMarkdownPreviewRender(immediate: true)
                return
            }
            let source = currentContent
            let bodyHTML = await Task.detached(priority: .utility) {
                let bodyHTML = ContentView.markdownPreviewBodyHTML(from: source, dialect: dialect, useRenderLimits: true)
                return ContentView.embeddingLocalImages(
                    in: bodyHTML,
                    relativeTo: documentURL,
                    accessing: projectAccessURL
                )
            }.value
            guard !Task.isCancelled else { return }
            guard signature == markdownPreviewCurrentRenderSignature else {
                scheduleMarkdownPreviewRender(immediate: true)
                return
            }
            let html = markdownPreviewHTML(
                bodyHTML: bodyHTML,
                template: template,
                preferDarkMode: preferDarkMode,
                backgroundStyle: backgroundStyle,
                translucentBackgroundEnabled: translucentBackgroundEnabled,
                runtimeFontSize: runtimeFontSize
            )
            if !containsLocalImageReference {
                Self.markdownPreviewHTMLCache.withLock { cache in
                    cache.store(html, for: signature)
                }
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
        return 220_000_000
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
            bodyHTML: Self.embeddingLocalImages(
                in: bodyHTML,
                relativeTo: viewModel.selectedTab?.fileURL,
                accessing: projectFolderSecurityURL
            ),
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
        \(Self.markdownPreviewCodeBlockScript())
        </body>
        </html>
        """
    }

    nonisolated static func markdownPreviewCodeBlockScript() -> String {
        #"""
        <script>
        (() => {
          window.addEventListener("error", (event) => {
            event.preventDefault();
          });
          window.addEventListener("unhandledrejection", (event) => {
            event.preventDefault();
          });
          const languageNames = {
            plaintext: "Plain Text",
            swift: "Swift",
            javascript: "JavaScript",
            typescript: "TypeScript",
            python: "Python",
            json: "JSON",
            html: "HTML",
            css: "CSS",
            shell: "Shell",
            markdown: "Markdown",
            yaml: "YAML",
            ruby: "Ruby",
            go: "Go",
            java: "Java",
            kotlin: "Kotlin",
            php: "PHP",
            mermaid: "Mermaid"
          };
          const aliases = {
            js: "javascript",
            jsx: "javascript",
            mjs: "javascript",
            ts: "typescript",
            tsx: "typescript",
            py: "python",
            sh: "shell",
            bash: "shell",
            zsh: "shell",
            md: "markdown",
            yml: "yaml",
            rb: "ruby",
            kt: "kotlin"
          };
          const maxHighlightedCodeUnits = 120000;
          const pickerStoragePrefix = "neon-markdown-preview-code-language:";
          const codeBlockKey = (text, index) => {
            let hash = 2166136261;
            for (let i = 0; i < text.length; i += 1) {
              hash ^= text.charCodeAt(i);
              hash = Math.imul(hash, 16777619);
            }
            return `${pickerStoragePrefix}${index}:${(hash >>> 0).toString(16)}:${text.length}`;
          };
          const storedLanguage = (key) => {
            try {
              return window.localStorage.getItem(key);
            } catch (_) {
              return null;
            }
          };
          const storeLanguage = (key, language) => {
            try {
              window.localStorage.setItem(key, language);
            } catch (_) {
              // Private browsing and PDF renderers may reject localStorage.
            }
          };
          const escapeHTML = (value) => value
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
          const normalizeLanguage = (language) => {
            const normalized = String(language || "plaintext").trim().toLowerCase();
            return aliases[normalized] || (languageNames[normalized] ? normalized : "plaintext");
          };
          const highlightPatterns = {
            swift: [
              [/(&quot;[^&]*?&quot;)/g, "str"],
              [/\b(import|func|let|var|struct|class|enum|extension|protocol|return|guard|if|else|switch|case|for|while|in|try|catch|throw|throws|async|await|actor|nonisolated|private|public|static)\b/g, "kw"],
              [/(\/\/.*$)/gm, "comment"]
            ],
            javascript: [
              [/(&quot;[^&]*?&quot;|&#39;[^&]*?&#39;|`[^`]*?`)/g, "str"],
              [/\b(import|export|const|let|var|function|return|if|else|for|while|class|new|await|async|try|catch|throw|switch|case|from)\b/g, "kw"],
              [/(\/\/.*$)/gm, "comment"]
            ],
            typescript: [
              [/(&quot;[^&]*?&quot;|&#39;[^&]*?&#39;|`[^`]*?`)/g, "str"],
              [/\b(import|export|const|let|var|function|return|if|else|for|while|class|interface|type|enum|implements|await|async|try|catch|throw|switch|case|from)\b/g, "kw"],
              [/(\/\/.*$)/gm, "comment"]
            ],
            python: [
              [/(&quot;[^&]*?&quot;|&#39;[^&]*?&#39;)/g, "str"],
              [/\b(import|from|def|class|return|if|elif|else|for|while|try|except|raise|with|as|async|await|lambda|None|True|False)\b/g, "kw"],
              [/(#.*$)/gm, "comment"]
            ],
            json: [
              [/(&quot;[^&]*?&quot;)(\s*:)/g, "key"],
              [/(:\s*)(&quot;[^&]*?&quot;)/g, "str"],
              [/\b(true|false|null)\b/g, "kw"],
              [/\b-?\d+(\.\d+)?\b/g, "num"]
            ],
            html: [
              [/(&lt;\/?[A-Za-z][^&]*?&gt;)/g, "kw"],
              [/(&quot;[^&]*?&quot;|&#39;[^&]*?&#39;)/g, "str"]
            ],
            css: [
              [/([.#]?[A-Za-z_-][\w-]*)(\s*\{)/g, "key"],
              [/(:\s*)([^;\n]+)(;?)/g, "str"],
              [/\/\*[\s\S]*?\*\//g, "comment"]
            ],
            shell: [
              [/(&quot;[^&]*?&quot;|&#39;[^&]*?&#39;)/g, "str"],
              [/\b(cd|cp|mv|rm|git|npm|swift|xcodebuild|curl|grep|rg|find|mkdir|export|if|then|fi|for|do|done)\b/g, "kw"],
              [/(#.*$)/gm, "comment"]
            ],
            markdown: [
              [/^(#{1,6}\s.*)$/gm, "kw"],
              [/(`[^`]+`)/g, "str"],
              [/(\[[^\]]+\]\([^)]+\))/g, "key"]
            ],
            yaml: [
              [/^(\s*[\w.-]+)(\s*:)/gm, "key"],
              [/(#.*$)/gm, "comment"]
            ],
            ruby: [
              [/(&quot;[^&]*?&quot;|&#39;[^&]*?&#39;)/g, "str"],
              [/\b(def|class|module|end|do|if|else|elsif|while|require|return|nil|true|false)\b/g, "kw"],
              [/(#.*$)/gm, "comment"]
            ],
            go: [
              [/(&quot;[^&]*?&quot;|`[^`]*?`)/g, "str"],
              [/\b(package|import|func|var|const|type|struct|interface|return|if|else|for|range|go|defer|nil|true|false)\b/g, "kw"],
              [/(\/\/.*$)/gm, "comment"]
            ],
            java: [
              [/(&quot;[^&]*?&quot;)/g, "str"],
              [/\b(import|package|public|private|protected|class|interface|enum|static|final|void|new|return|if|else|for|while|try|catch|throw|throws|null|true|false)\b/g, "kw"],
              [/(\/\/.*$)/gm, "comment"]
            ],
            kotlin: [
              [/(&quot;[^&]*?&quot;)/g, "str"],
              [/\b(import|package|fun|val|var|class|object|interface|return|if|else|for|while|when|is|null|true|false)\b/g, "kw"],
              [/(\/\/.*$)/gm, "comment"]
            ],
            php: [
              [/(&quot;[^&]*?&quot;|&#39;[^&]*?&#39;)/g, "str"],
              [/\b(namespace|use|function|class|public|private|protected|return|if|else|foreach|while|try|catch|throw|null|true|false)\b/g, "kw"],
              [/(\/\/.*$|#.*$)/gm, "comment"]
            ]
          };
          const applyPatterns = (escaped, language) => {
            let highlighted = escaped;
            for (const [pattern, token] of highlightPatterns[language] || []) {
              highlighted = highlighted.replace(pattern, (match) => `<span class="syntax-${token}">${match}</span>`);
            }
            return highlighted;
          };
          const highlightBlock = (figure, language) => {
            const code = figure.querySelector("pre code");
            if (!code) return;
            if (!code.dataset.rawText) code.dataset.rawText = code.textContent || "";
            const resolved = normalizeLanguage(language);
            figure.dataset.codeLanguage = resolved;
            code.className = resolved === "plaintext" ? "" : `language-${resolved}`;
            const escaped = escapeHTML(code.dataset.rawText);
            code.innerHTML = code.dataset.rawText.length > maxHighlightedCodeUnits
              ? escaped
              : applyPatterns(escaped, resolved);
            const label = figure.querySelector(".code-block-language-label");
            if (label) label.textContent = languageNames[resolved] || "Plain Text";
          };
          const copyCode = async (button, code) => {
            const text = code.dataset.rawText || code.textContent || "";
            try {
              if (navigator.clipboard && window.isSecureContext) {
                await navigator.clipboard.writeText(text);
              } else {
                const helper = document.createElement("textarea");
                helper.value = text;
                helper.setAttribute("readonly", "");
                helper.style.position = "fixed";
                helper.style.opacity = "0";
                document.body.appendChild(helper);
                helper.select();
                document.execCommand("copy");
                helper.remove();
              }
              const original = button.textContent;
              button.textContent = "Copied";
              window.setTimeout(() => { button.textContent = original; }, 1200);
            } catch (_) {
              button.textContent = "Copy failed";
              window.setTimeout(() => { button.textContent = "Copy"; }, 1200);
            }
          };
          const enhanceCodeBlocks = () => {
            document.querySelectorAll(".code-block").forEach((figure, index) => {
              try {
                const code = figure.querySelector("pre code");
                const rawText = code ? code.textContent || "" : "";
                const storageKey = codeBlockKey(rawText, index);
                const selected = normalizeLanguage(storedLanguage(storageKey) || figure.dataset.codeLanguage);
                const select = figure.querySelector("select.code-block-language-picker");
                if (select) {
                  select.value = selected;
                  select.addEventListener("change", () => {
                    const nextLanguage = normalizeLanguage(select.value);
                    storeLanguage(storageKey, nextLanguage);
                    highlightBlock(figure, nextLanguage);
                  });
                }
                const copy = figure.querySelector(".code-block-copy");
                if (copy && !copy.dataset.bound) {
                  copy.dataset.bound = "true";
                  copy.addEventListener("click", (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    if (code) copyCode(copy, code);
                  });
                }
                highlightBlock(figure, selected);
              } catch (_) {
                const code = figure.querySelector("pre code");
                if (code && code.dataset.rawText) {
                  code.textContent = code.dataset.rawText;
                }
              }
            });
          };
          try {
            enhanceCodeBlocks();
          } catch (_) {
            // Markdown preview must remain readable even if enhancement code fails.
          }
        })();
        </script>
        """#
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
          padding: clamp(10px, 1.5vw, 16px);
          overflow-x: hidden;
          word-break: normal;
          background: transparent !important;
          border: none !important;
          border-radius: 0 !important;
          box-shadow: none !important;
          -webkit-backdrop-filter: none !important;
          backdrop-filter: none !important;
        }
        .content > :first-child {
          margin-top: 0 !important;
        }
        .content > * {
          max-width: 100%;
        }
        h1, h2, h3, h4, h5, h6, p, li, blockquote {
          max-width: 100%;
          overflow-wrap: break-word;
        }
        a, code, figcaption {
          overflow-wrap: anywhere;
        }
        pre, .table-scroll {
          max-width: 100%;
        }
        pre, pre code {
          white-space: pre;
          overflow-wrap: normal;
          word-break: normal;
          overflow-x: auto;
        }
        .table-scroll {
          overflow-x: auto;
          -webkit-overflow-scrolling: touch;
        }
        .table-scroll table {
          width: max-content;
          min-width: 100%;
        }
        .table-scroll th, .table-scroll td {
          overflow-wrap: break-word;
          word-break: normal;
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
            white-space: pre;
            word-break: normal;
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
        let bodyHTML = Self.embeddingLocalImages(
            in: Self.markdownPreviewBodyHTML(from: markdownText, dialect: markdownPreviewDialect, useRenderLimits: false),
            relativeTo: viewModel.selectedTab?.fileURL,
            accessing: projectFolderSecurityURL
        )
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
        let resolvedLanguage = markdownPreviewCodeLanguage(for: code, explicitLanguage: languageToken)
        let classAttribute = resolvedLanguage == "plaintext" ? "" : " class=\"language-\(escapedHTML(resolvedLanguage))\""
        return """
        <figure class="code-block" data-code-language="\(escapedHTML(resolvedLanguage))">
        <figcaption class="code-block-toolbar">
          <span class="code-block-language-label">\(escapedHTML(markdownPreviewCodeLanguageTitle(resolvedLanguage)))</span>
          <span class="code-block-actions">
            <label class="code-block-language-control">
              <span class="code-block-language-caption">Language</span>
              \(markdownPreviewCodeLanguagePickerHTML(selectedLanguage: resolvedLanguage))
            </label>
            <button type="button" class="code-block-copy" aria-label="Copy code">Copy</button>
          </span>
        </figcaption>
        <pre><code\(classAttribute)>\(markdownPreviewHighlightedCodeHTML(code, language: resolvedLanguage))\n</code></pre>
        </figure>
        """
    }

    nonisolated static func markdownPreviewHighlightedCodeHTML(_ code: String, language: String) -> String {
        let escaped = escapedHTML(code)
        guard code.count <= 120_000 else { return escaped }
        let patterns = markdownPreviewSyntaxPatterns(for: language)
        guard !patterns.isEmpty else { return escaped }
        return applyingMarkdownPreviewSyntaxPatterns(patterns, to: escaped)
    }

    nonisolated private static func markdownPreviewSyntaxPatterns(for language: String) -> [(pattern: String, token: String)] {
        switch language {
        case "swift":
            return [
                (#"//.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;"#, "str"),
                (#"\b(import|func|let|var|struct|class|enum|extension|protocol|return|guard|if|else|switch|case|for|while|in|try|catch|throw|throws|async|await|actor|nonisolated|private|public|static)\b"#, "kw")
            ]
        case "javascript":
            return [
                (#"//.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;|&#39;[^&]*?&#39;|`[^`]*?`"#, "str"),
                (#"\b(import|export|const|let|var|function|return|if|else|for|while|class|new|await|async|try|catch|throw|switch|case|from)\b"#, "kw")
            ]
        case "typescript":
            return [
                (#"//.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;|&#39;[^&]*?&#39;|`[^`]*?`"#, "str"),
                (#"\b(import|export|const|let|var|function|return|if|else|for|while|class|interface|type|enum|implements|await|async|try|catch|throw|switch|case|from)\b"#, "kw")
            ]
        case "python":
            return [
                (#"#.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;|&#39;[^&]*?&#39;"#, "str"),
                (#"\b(import|from|def|class|return|if|elif|else|for|while|try|except|raise|with|as|async|await|lambda|None|True|False)\b"#, "kw")
            ]
        case "json":
            return [
                (#"&quot;[^&]*?&quot;(?=\s*:)"#, "key"),
                (#"(?<=:\s)&quot;[^&]*?&quot;"#, "str"),
                (#"\b(true|false|null)\b"#, "kw"),
                (#"\b-?\d+(\.\d+)?\b"#, "num")
            ]
        case "html":
            return [
                (#"&lt;\/?[A-Za-z][^&]*?&gt;"#, "kw"),
                (#"&quot;[^&]*?&quot;|&#39;[^&]*?&#39;"#, "str")
            ]
        case "css":
            return [
                (#"\/\*[\s\S]*?\*\/"#, "comment"),
                (#"[.#]?[A-Za-z_-][\w-]*(?=\s*\{)"#, "key"),
                (#"(?<=:\s)[^;\n]+(?=;?)"#, "str")
            ]
        case "shell":
            return [
                (#"#.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;|&#39;[^&]*?&#39;"#, "str"),
                (#"\b(cd|cp|mv|rm|git|npm|swift|xcodebuild|curl|grep|rg|find|mkdir|export|if|then|fi|for|do|done)\b"#, "kw")
            ]
        case "markdown":
            return [
                (#"^#{1,6}\s.*$"#, "kw"),
                (#"`[^`]+`"#, "str"),
                (#"\[[^\]]+\]\([^)]+\)"#, "key")
            ]
        case "yaml":
            return [
                (#"#.*$"#, "comment"),
                (#"^\s*[\w.-]+(?=\s*:)"#, "key")
            ]
        case "ruby":
            return [
                (#"#.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;|&#39;[^&]*?&#39;"#, "str"),
                (#"\b(def|class|module|end|do|if|else|elsif|while|require|return|nil|true|false)\b"#, "kw")
            ]
        case "go":
            return [
                (#"//.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;|`[^`]*?`"#, "str"),
                (#"\b(package|import|func|var|const|type|struct|interface|return|if|else|for|range|go|defer|nil|true|false)\b"#, "kw")
            ]
        case "java":
            return [
                (#"//.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;"#, "str"),
                (#"\b(import|package|public|private|protected|class|interface|enum|static|final|void|new|return|if|else|for|while|try|catch|throw|throws|null|true|false)\b"#, "kw")
            ]
        case "kotlin":
            return [
                (#"//.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;"#, "str"),
                (#"\b(import|package|fun|val|var|class|object|interface|return|if|else|for|while|when|is|null|true|false)\b"#, "kw")
            ]
        case "php":
            return [
                (#"//.*$|#.*$"#, "comment"),
                (#"&quot;[^&]*?&quot;|&#39;[^&]*?&#39;"#, "str"),
                (#"\b(namespace|use|function|class|public|private|protected|return|if|else|foreach|while|try|catch|throw|null|true|false)\b"#, "kw")
            ]
        default:
            return []
        }
    }

    nonisolated private static func applyingMarkdownPreviewSyntaxPatterns(
        _ patterns: [(pattern: String, token: String)],
        to escaped: String
    ) -> String {
        struct HighlightRange {
            let range: NSRange
            let token: String
        }
        let fullRange = NSRange(escaped.startIndex..., in: escaped)
        var selected: [HighlightRange] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: [.anchorsMatchLines]) else { continue }
            for match in regex.matches(in: escaped, options: [], range: fullRange) {
                guard match.range.location != NSNotFound,
                      match.range.length > 0,
                      !selected.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else {
                    continue
                }
                selected.append(HighlightRange(range: match.range, token: pattern.token))
            }
        }
        guard !selected.isEmpty else { return escaped }

        var output = escaped
        for highlight in selected.sorted(by: { $0.range.location > $1.range.location }) {
            guard let range = Range(highlight.range, in: output) else { continue }
            let segment = String(output[range])
            output.replaceSubrange(range, with: "<span class=\"syntax-\(highlight.token)\">\(segment)</span>")
        }
        return output
    }

    nonisolated static func markdownPreviewCodeLanguage(for code: String, explicitLanguage: String?) -> String {
        let explicit = normalizedMarkdownPreviewCodeLanguage(explicitLanguage)
        if explicit != "plaintext" {
            return explicit
        }
        return inferredMarkdownPreviewCodeLanguage(from: code)
    }

    nonisolated static func normalizedMarkdownPreviewCodeLanguage(_ language: String?) -> String {
        let token = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map { String($0).lowercased() } ?? ""
        switch token {
        case "swift", "javascript", "typescript", "python", "json", "html", "css", "shell", "markdown", "yaml", "ruby", "go", "java", "kotlin", "php", "mermaid":
            return token
        case "js", "jsx", "mjs":
            return "javascript"
        case "ts", "tsx":
            return "typescript"
        case "py":
            return "python"
        case "sh", "bash", "zsh":
            return "shell"
        case "md":
            return "markdown"
        case "yml":
            return "yaml"
        case "rb":
            return "ruby"
        case "kt":
            return "kotlin"
        default:
            return "plaintext"
        }
    }

    nonisolated static func inferredMarkdownPreviewCodeLanguage(from code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty else { return "plaintext" }
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return "json"
        }
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") || lower.contains("</") {
            return "html"
        }
        if lower.hasPrefix("<?php") {
            return "php"
        }
        if lower.hasPrefix("graph ") || lower.hasPrefix("flowchart ") {
            return "mermaid"
        }
        if trimmed.contains("import SwiftUI") ||
            trimmed.contains("import Foundation") ||
            (trimmed.contains("struct ") && trimmed.contains(": View")) ||
            (trimmed.contains("func ") && trimmed.contains("->")) {
            return "swift"
        }
        if lower.contains("function ") || lower.contains("const ") || lower.contains("=>") || lower.contains("console.log") {
            return lower.contains(": ") || lower.contains("interface ") || lower.contains("type ") ? "typescript" : "javascript"
        }
        if lower.contains("def ") && lower.contains("end") {
            return "ruby"
        }
        if lower.contains("def ") || lower.contains("import ") && lower.contains(":") || lower.contains("print(") {
            return "python"
        }
        if lower.contains("package main") || lower.contains("func main()") {
            return "go"
        }
        if lower.contains("public class ") || lower.contains("system.out.println") {
            return "java"
        }
        if lower.contains("fun main(") || lower.contains("val ") || (lower.contains("var ") && lower.contains("kotlin")) {
            return "kotlin"
        }
        if lower.contains("cd ") || lower.contains("git ") || lower.hasPrefix("#!/bin/") {
            return "shell"
        }
        if lower.contains("{") && lower.contains(":") && lower.contains(";") {
            return "css"
        }
        if lower.contains("---") && lower.contains(":") {
            return "yaml"
        }
        if lower.hasPrefix("# ") || lower.contains("\n## ") || lower.contains("```") {
            return "markdown"
        }
        return "plaintext"
    }

    nonisolated static func markdownPreviewCodeLanguageTitle(_ language: String) -> String {
        switch language {
        case "swift": return "Swift"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "python": return "Python"
        case "json": return "JSON"
        case "html": return "HTML"
        case "css": return "CSS"
        case "shell": return "Shell"
        case "markdown": return "Markdown"
        case "yaml": return "YAML"
        case "ruby": return "Ruby"
        case "go": return "Go"
        case "java": return "Java"
        case "kotlin": return "Kotlin"
        case "php": return "PHP"
        case "mermaid": return "Mermaid"
        default: return "Plain Text"
        }
    }

    nonisolated static func markdownPreviewCodeLanguagePickerHTML(selectedLanguage: String) -> String {
        let languages = [
            "plaintext", "swift", "javascript", "typescript", "python", "json", "html", "css",
            "shell", "markdown", "yaml", "ruby", "go", "java", "kotlin", "php", "mermaid"
        ]
        let options = languages.map { language in
            let selected = language == selectedLanguage ? " selected" : ""
            return "<option value=\"\(language)\"\(selected)>\(escapedHTML(markdownPreviewCodeLanguageTitle(language)))</option>"
        }.joined()
        return "<select class=\"code-block-language-picker\" aria-label=\"Code block language\">\(options)</select>"
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
        <div class="table-scroll">
        <table>
        <thead><tr>\(headerHTML)</tr></thead>
        <tbody>
        \(rowsHTML)
        </tbody>
        </table>
        </div>
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
            <div class="mermaid-diagram-scroll" tabindex="0" role="region" aria-label="Scrollable Mermaid diagram">
            \(svg)
            </div>
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
            let caption = parts[0].isEmpty ? "" : "<figcaption>\(parts[0])</figcaption>"
            return "<figure class=\"markdown-image\"><img src=\"\(parts[1])\" alt=\"\(parts[0])\"/>\(caption)</figure>"
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

    // WKWebView can reject relative file URLs in HTML strings. Embed only allowlisted
    // local image assets beneath the opened document's folder for offline preview.
    nonisolated static func embeddingLocalImages(in html: String, relativeTo documentURL: URL?) -> String {
        embeddingLocalImages(in: html, relativeTo: documentURL, accessing: nil)
    }

    nonisolated static func embeddingLocalSVGImages(in html: String, relativeTo documentURL: URL?) -> String {
        embeddingLocalImages(in: html, relativeTo: documentURL)
    }

    nonisolated static func embeddingLocalImages(
        in html: String,
        relativeTo documentURL: URL?,
        accessing accessURL: URL?
    ) -> String {
        guard let documentURL, documentURL.isFileURL else { return html }
        let scopedAccessURL = accessURL ?? documentURL
        let didAccess = scopedAccessURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                scopedAccessURL.stopAccessingSecurityScopedResource()
            }
        }
        let baseDirectory = documentURL
            .deletingLastPathComponent()
            .appendingPathComponent("", isDirectory: true)
            .standardizedFileURL
        let basePath = baseDirectory.path.hasSuffix("/") ? baseDirectory.path : baseDirectory.path + "/"
        let pattern = #"(?i)(<(?:img|source)\b[^>]*\b(?:src|srcset)\s*=\s*[\"'])([^\"']+\.(?:svg|png|jpe?g|gif|webp|avif)(?:[?#][^\"']*)?)([\"'])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !matches.isEmpty else { return html }

        var output = html
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let sourceRange = Range(match.range(at: 2), in: html) else { continue }
            let source = String(html[sourceRange])
            guard !source.contains("://"),
                  !source.hasPrefix("/"),
                  let sourceURL = URL(string: source.removingPercentEncoding ?? source, relativeTo: baseDirectory),
                  var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: true) else { continue }
            components.query = nil
            components.fragment = nil
            guard let resolvedURL = components.url?.standardizedFileURL,
                  resolvedURL.path.hasPrefix(basePath),
                  let dataURL = Self.markdownPreviewLocalImageCache.withLock({ $0.dataURL(for: resolvedURL) }),
                  let replacementRange = Range(match.range(at: 2), in: output) else { continue }
            output.replaceSubrange(replacementRange, with: dataURL)
        }
        return output
    }

    nonisolated static func markdownMayReferenceLocalImage(_ markdown: String) -> Bool {
        let pattern = #"(?i)(?:src\s*=\s*[\"']|!\[[^\]]*\]\()(?!(?:https?:)?//|/)[^\"'\s)]+\.(?:svg|png|jpe?g|gif|webp|avif)(?:[?#][^\"'\s)]*)?"#
        return markdownPreviewRegexMatches(markdown, pattern: pattern)
    }

    nonisolated static func markdownMayReferenceLocalSVG(_ markdown: String) -> Bool {
        markdownMayReferenceLocalImage(markdown)
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
        let remoteSourcePattern = #"(?i)\s+(src|poster|xlink:href)\s*=\s*['"]?\s*(https?:|//|file:)"#
        let remoteNonImageSourcePattern = #"(?i)<\s*(?!img\b)[^>]*\s+(src|poster|xlink:href)\s*=\s*['"]?\s*(https?:|//|file:)"#
        if markdownPreviewRegexMatches(html, pattern: remoteSourcePattern),
           markdownPreviewRegexMatches(html, pattern: remoteNonImageSourcePattern) {
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

    struct MarkdownPreviewSemanticPalette: Equatable, Sendable {
        let bodyBackground: String
        let contentBackground: String
        let contentBorder: String
        let text: String
        let heading: String
        let muted: String
        let accent: String
        let link: String
        let codeBackground: String
        let codeText: String
        let codeBorder: String
        let quoteBackground: String
        let quoteBorder: String
        let tableHeader: String
        let tableRow: String
        let divider: String
        let shadow: String

        static func make(template: String, dark: Bool) -> Self {
            switch (template, dark) {
            case ("neon-editorial", true):
                return Self(bodyBackground: "#16091d", contentBackground: "#24102f", contentBorder: "#703b84", text: "#fff0ff", heading: "#ffffff", muted: "#d3a8dc", accent: "#ff6bd6", link: "#78f0ff", codeBackground: "#190b22", codeText: "#ffeaff", codeBorder: "#8b4da1", quoteBackground: "#35143f", quoteBorder: "#ff9f43", tableHeader: "#492052", tableRow: "#2e1739", divider: "#824894", shadow: "rgba(24, 3, 32, 0.50)")
            case ("default", true), ("neon-paper", true):
                return Self(bodyBackground: "#090b14", contentBackground: "#101426", contentBorder: "#26365f", text: "#e9edff", heading: "#ffffff", muted: "#9ca9cf", accent: "#61d9ff", link: "#7dd3fc", codeBackground: "#0a1020", codeText: "#e6f3ff", codeBorder: "#294b73", quoteBackground: "#111d36", quoteBorder: "#ff4fd8", tableHeader: "#172642", tableRow: "#111a2d", divider: "#2d4774", shadow: "rgba(2, 6, 23, 0.48)")
            case ("developer-slate", true), ("developer-spec", true), ("api-reference", true):
                return Self(bodyBackground: "#0b1117", contentBackground: "#111a22", contentBorder: "#2b414f", text: "#d8e6eb", heading: "#f4fbff", muted: "#8da5ad", accent: "#55e6bd", link: "#67e8f9", codeBackground: "#091017", codeText: "#d9f7ee", codeBorder: "#2e5c5b", quoteBackground: "#10241f", quoteBorder: "#55e6bd", tableHeader: "#19302e", tableRow: "#13211f", divider: "#315251", shadow: "rgba(0, 0, 0, 0.38)")
            case ("solarized", true), ("blueprint", true):
                return Self(bodyBackground: "#002b36", contentBackground: "#073642", contentBorder: "#1f5962", text: "#eee8d5", heading: "#fdf6e3", muted: "#93a1a1", accent: "#2aa198", link: "#268bd2", codeBackground: "#002b36", codeText: "#eee8d5", codeBorder: "#1f5962", quoteBackground: "#073642", quoteBorder: "#b58900", tableHeader: "#0b4652", tableRow: "#0a3e49", divider: "#28616a", shadow: "rgba(0, 20, 24, 0.36)")
            case ("terminal-notes", true):
                return Self(bodyBackground: "#020403", contentBackground: "#07100a", contentBorder: "#1c5b32", text: "#d8ffe4", heading: "#effff3", muted: "#78b88b", accent: "#39ff88", link: "#6ee7ff", codeBackground: "#010201", codeText: "#baffce", codeBorder: "#1f713d", quoteBackground: "#0b1c11", quoteBorder: "#39ff88", tableHeader: "#10351d", tableRow: "#0a2112", divider: "#257844", shadow: "rgba(0, 0, 0, 0.58)")
            case ("notebook", true):
                return Self(bodyBackground: "#17141e", contentBackground: "#211c2a", contentBorder: "#584770", text: "#f2ebff", heading: "#fff8e7", muted: "#b7a7ce", accent: "#f5c451", link: "#8bd5ff", codeBackground: "#181522", codeText: "#eee6ff", codeBorder: "#67527d", quoteBackground: "#2a2237", quoteBorder: "#ff8c69", tableHeader: "#382b49", tableRow: "#282038", divider: "#6b557f", shadow: "rgba(16, 8, 26, 0.44)")
            case ("article", true):
                return Self(bodyBackground: "#111418", contentBackground: "#1b2026", contentBorder: "#3f4b58", text: "#e9edf2", heading: "#fff8f0", muted: "#a6b0bb", accent: "#ff8a65", link: "#7dd3fc", codeBackground: "#12171c", codeText: "#f0f6fa", codeBorder: "#4c5966", quoteBackground: "#252029", quoteBorder: "#ff8a65", tableHeader: "#30313b", tableRow: "#232933", divider: "#536170", shadow: "rgba(0, 0, 0, 0.36)")
            case ("nordic-light", true):
                return Self(bodyBackground: "#0a141c", contentBackground: "#10222d", contentBorder: "#31566a", text: "#e6f6ff", heading: "#f3fbff", muted: "#91b4c5", accent: "#78d4e8", link: "#9cc8ff", codeBackground: "#0b1b25", codeText: "#dff5ff", codeBorder: "#3d6b7f", quoteBackground: "#14303a", quoteBorder: "#b5e48c", tableHeader: "#1b3b47", tableRow: "#142d38", divider: "#3b697b", shadow: "rgba(0, 12, 22, 0.42)")
            case ("electric-pop", true):
                return Self(bodyBackground: "#10051f", contentBackground: "#1a0a2e", contentBorder: "#56227d", text: "#f7edff", heading: "#ffffff", muted: "#c9a9df", accent: "#ff4fd8", link: "#71f6ff", codeBackground: "#120621", codeText: "#f4e7ff", codeBorder: "#7137a3", quoteBackground: "#26103d", quoteBorder: "#ffb347", tableHeader: "#321351", tableRow: "#211037", divider: "#6c2e92", shadow: "rgba(22, 3, 39, 0.52)")
            case ("aurora", true):
                return Self(bodyBackground: "#06151a", contentBackground: "#0b2428", contentBorder: "#1d5a5b", text: "#e8fff8", heading: "#f3fffc", muted: "#91c5bd", accent: "#62f6c7", link: "#70d7ff", codeBackground: "#071b20", codeText: "#d9fff2", codeBorder: "#28706d", quoteBackground: "#103335", quoteBorder: "#ff6b9e", tableHeader: "#164243", tableRow: "#102e32", divider: "#2b7771", shadow: "rgba(0, 20, 24, 0.44)")
            case ("citrus", true):
                return Self(bodyBackground: "#151008", contentBackground: "#241b0a", contentBorder: "#6c4e16", text: "#fff7df", heading: "#fffbea", muted: "#d5b978", accent: "#ffd166", link: "#5eead4", codeBackground: "#1b1408", codeText: "#fff1bd", codeBorder: "#84611b", quoteBackground: "#35200b", quoteBorder: "#ff6b35", tableHeader: "#4b2d0b", tableRow: "#2c1e0a", divider: "#8b651d", shadow: "rgba(30, 15, 0, 0.46)")
            case ("plasma", true):
                return Self(bodyBackground: "#180515", contentBackground: "#270a25", contentBorder: "#7e1f69", text: "#fff0fb", heading: "#ffffff", muted: "#d9a6ca", accent: "#ff4d9d", link: "#ffb86b", codeBackground: "#1d071b", codeText: "#ffe6f6", codeBorder: "#9b3283", quoteBackground: "#3a0c2f", quoteBorder: "#a78bfa", tableHeader: "#501244", tableRow: "#32102b", divider: "#8c2a78", shadow: "rgba(48, 3, 39, 0.52)")
            case ("deep-ocean", true):
                return Self(bodyBackground: "#03101f", contentBackground: "#071e35", contentBorder: "#155486", text: "#e6f7ff", heading: "#f5fcff", muted: "#8db6d2", accent: "#38bdf8", link: "#a5f3fc", codeBackground: "#04172a", codeText: "#dbf4ff", codeBorder: "#1f679a", quoteBackground: "#0a2c48", quoteBorder: "#fbbf24", tableHeader: "#0d3b5f", tableRow: "#092b47", divider: "#21628e", shadow: "rgba(0, 18, 38, 0.52)")
            case ("ember-glow", true):
                return Self(bodyBackground: "#1c0808", contentBackground: "#2a100d", contentBorder: "#78352a", text: "#fff1e8", heading: "#fffaf5", muted: "#d7a28f", accent: "#ff7043", link: "#ffb86b", codeBackground: "#200a09", codeText: "#ffe7d6", codeBorder: "#984534", quoteBackground: "#3b1712", quoteBorder: "#ffb347", tableHeader: "#4e1f16", tableRow: "#32130f", divider: "#914130", shadow: "rgba(38, 4, 0, 0.52)")
            case ("forest-canopy", true):
                return Self(bodyBackground: "#06150e", contentBackground: "#0c2417", contentBorder: "#23633b", text: "#e9fff0", heading: "#f4fff7", muted: "#8fc6a0", accent: "#7bed9f", link: "#67e8f9", codeBackground: "#071b10", codeText: "#ddffe7", codeBorder: "#2d7a48", quoteBackground: "#10351f", quoteBorder: "#bef264", tableHeader: "#16472a", tableRow: "#0f2e1d", divider: "#347c4b", shadow: "rgba(0, 25, 10, 0.48)")
            case ("ultraviolet", true):
                return Self(bodyBackground: "#0d0922", contentBackground: "#171039", contentBorder: "#4e3c96", text: "#f3efff", heading: "#ffffff", muted: "#b9a9e9", accent: "#a78bfa", link: "#67e8f9", codeBackground: "#100b2b", codeText: "#eee8ff", codeBorder: "#6550b5", quoteBackground: "#211650", quoteBorder: "#f472b6", tableHeader: "#2c2064", tableRow: "#1d1546", divider: "#5c49a1", shadow: "rgba(11, 3, 35, 0.56)")
            case ("cobalt", true):
                return Self(bodyBackground: "#050d20", contentBackground: "#0b1b3b", contentBorder: "#214c9a", text: "#e7efff", heading: "#f7faff", muted: "#91aee1", accent: "#60a5fa", link: "#93c5fd", codeBackground: "#07132e", codeText: "#e4eeff", codeBorder: "#2b61b5", quoteBackground: "#102653", quoteBorder: "#facc15", tableHeader: "#17346d", tableRow: "#102858", divider: "#3263ae", shadow: "rgba(0, 8, 30, 0.56)")
            case ("mint-paper", true):
                return Self(bodyBackground: "#061715", contentBackground: "#0d2522", contentBorder: "#26766a", text: "#e6fff8", heading: "#f2fffb", muted: "#8fc9bd", accent: "#34d399", link: "#93c5fd", codeBackground: "#081c19", codeText: "#dcfff4", codeBorder: "#318f7d", quoteBackground: "#123831", quoteBorder: "#fbbf24", tableHeader: "#185145", tableRow: "#10352e", divider: "#398b79", shadow: "rgba(0, 24, 18, 0.48)")
            case ("high-contrast", true):
                return Self(bodyBackground: "#000000", contentBackground: "#050505", contentBorder: "#ffffff", text: "#ffffff", heading: "#ffffff", muted: "#e6e6e6", accent: "#ffff00", link: "#00ffff", codeBackground: "#000000", codeText: "#ffffff", codeBorder: "#ffffff", quoteBackground: "#111111", quoteBorder: "#ffff00", tableHeader: "#202020", tableRow: "#101010", divider: "#ffffff", shadow: "transparent")
            case ("warm-sepia", true):
                return Self(bodyBackground: "#211710", contentBackground: "#2d2118", contentBorder: "#76543b", text: "#f9ead6", heading: "#fff4e5", muted: "#c9aa8b", accent: "#e7a45b", link: "#8fd3ff", codeBackground: "#241911", codeText: "#f9e1c2", codeBorder: "#805d42", quoteBackground: "#3a281b", quoteBorder: "#f0b35c", tableHeader: "#4a3020", tableRow: "#332319", divider: "#815d42", shadow: "rgba(18, 9, 3, 0.42)")
            case ("nordic-light", false), ("docs", false), ("minimal-reader", false):
                return Self(bodyBackground: "#eef3f7", contentBackground: "#ffffff", contentBorder: "#d5e0e8", text: "#263746", heading: "#172b3a", muted: "#637789", accent: "#0f766e", link: "#1769aa", codeBackground: "#edf3f5", codeText: "#24343d", codeBorder: "#c9d8de", quoteBackground: "#eef8f6", quoteBorder: "#0f766e", tableHeader: "#e4f0f1", tableRow: "#f6fafb", divider: "#c8d6dc", shadow: "rgba(30, 58, 73, 0.10)")
            case ("developer-slate", false):
                return Self(bodyBackground: "#edf1f5", contentBackground: "#fbfcfd", contentBorder: "#c8d2dc", text: "#273746", heading: "#172433", muted: "#647789", accent: "#475569", link: "#075985", codeBackground: "#e8eef3", codeText: "#263b4a", codeBorder: "#bccbd7", quoteBackground: "#e9f2f8", quoteBorder: "#2563a8", tableHeader: "#dce6ee", tableRow: "#f5f8fa", divider: "#b8c7d3", shadow: "rgba(30, 52, 70, 0.10)")
            case ("solarized", false):
                return Self(bodyBackground: "#fdf6e3", contentBackground: "#fffdf5", contentBorder: "#e5dcc2", text: "#586e75", heading: "#073642", muted: "#839496", accent: "#2aa198", link: "#268bd2", codeBackground: "#eee8d5", codeText: "#586e75", codeBorder: "#d8cfb5", quoteBackground: "#f3eedb", quoteBorder: "#b58900", tableHeader: "#e8e0c8", tableRow: "#faf6e8", divider: "#d6ccb0", shadow: "rgba(88, 110, 117, 0.12)")
            case ("terminal-notes", false):
                return Self(bodyBackground: "#f1f8f2", contentBackground: "#fbfffc", contentBorder: "#a9d2b3", text: "#16351f", heading: "#082611", muted: "#54745d", accent: "#15803d", link: "#0369a1", codeBackground: "#edf8ef", codeText: "#194c29", codeBorder: "#a8cdb0", quoteBackground: "#e7f5e9", quoteBorder: "#15803d", tableHeader: "#d5eed9", tableRow: "#f6fcf7", divider: "#9ac5a3", shadow: "rgba(22, 72, 34, 0.10)")
            case ("notebook", false):
                return Self(bodyBackground: "#f4efe2", contentBackground: "#fffdf5", contentBorder: "#d9c89d", text: "#35304b", heading: "#28233f", muted: "#786f89", accent: "#9b5de5", link: "#2563a8", codeBackground: "#f0e8d8", codeText: "#443657", codeBorder: "#d5c09b", quoteBackground: "#fff0df", quoteBorder: "#f77f00", tableHeader: "#eee0c2", tableRow: "#fffaf0", divider: "#d2bc8b", shadow: "rgba(89, 69, 35, 0.10)")
            case ("article", false):
                return Self(bodyBackground: "#f5f7fa", contentBackground: "#ffffff", contentBorder: "#d9e1e8", text: "#263746", heading: "#172b3a", muted: "#667889", accent: "#e45756", link: "#1769aa", codeBackground: "#f0f4f7", codeText: "#293b49", codeBorder: "#cbd8e1", quoteBackground: "#fff1ef", quoteBorder: "#e45756", tableHeader: "#e9eef3", tableRow: "#f8fafc", divider: "#cfdae3", shadow: "rgba(31, 51, 69, 0.09)")
            case ("electric-pop", false):
                return Self(bodyBackground: "#fff1fb", contentBackground: "#ffffff", contentBorder: "#f0b6df", text: "#35122f", heading: "#260d27", muted: "#87557c", accent: "#df168d", link: "#006f9f", codeBackground: "#fff0fa", codeText: "#4a1742", codeBorder: "#e7a5d3", quoteBackground: "#fff4df", quoteBorder: "#ed7b18", tableHeader: "#ffe1f3", tableRow: "#fff8fc", divider: "#e8afd5", shadow: "rgba(119, 24, 101, 0.12)")
            case ("aurora", false):
                return Self(bodyBackground: "#effff9", contentBackground: "#ffffff", contentBorder: "#b8e7d9", text: "#153b3a", heading: "#073c3c", muted: "#5b8580", accent: "#087f67", link: "#0876a8", codeBackground: "#edfff8", codeText: "#17433c", codeBorder: "#a6dccb", quoteBackground: "#fff1f6", quoteBorder: "#d92f6e", tableHeader: "#d9f7ec", tableRow: "#f5fffb", divider: "#abd9cb", shadow: "rgba(8, 87, 72, 0.11)")
            case ("citrus", false):
                return Self(bodyBackground: "#fff9e8", contentBackground: "#fffef8", contentBorder: "#f0d58a", text: "#49320d", heading: "#3a2507", muted: "#8e6f31", accent: "#d97706", link: "#0f766e", codeBackground: "#fff5d6", codeText: "#543500", codeBorder: "#e8c56c", quoteBackground: "#fff0df", quoteBorder: "#ea580c", tableHeader: "#ffe3a3", tableRow: "#fffaf0", divider: "#e8cb7e", shadow: "rgba(124, 79, 0, 0.12)")
            case ("plasma", false):
                return Self(bodyBackground: "#fff0f8", contentBackground: "#ffffff", contentBorder: "#f2afd2", text: "#421331", heading: "#2d0924", muted: "#925b7d", accent: "#d91578", link: "#b45309", codeBackground: "#ffedf7", codeText: "#4a1638", codeBorder: "#e6a1c7", quoteBackground: "#f3eeff", quoteBorder: "#7c3aed", tableHeader: "#ffd9ed", tableRow: "#fff7fb", divider: "#e6acd0", shadow: "rgba(125, 25, 91, 0.12)")
            case ("deep-ocean", false):
                return Self(bodyBackground: "#eef9ff", contentBackground: "#ffffff", contentBorder: "#acd5ed", text: "#12344a", heading: "#062b48", muted: "#5b7e93", accent: "#087ea4", link: "#075985", codeBackground: "#eaf7ff", codeText: "#123a52", codeBorder: "#a8cee4", quoteBackground: "#fff7df", quoteBorder: "#b7791f", tableHeader: "#d8f0fb", tableRow: "#f5fbff", divider: "#a8cee4", shadow: "rgba(8, 74, 112, 0.11)")
            case ("ember-glow", false):
                return Self(bodyBackground: "#fff3ed", contentBackground: "#fffdfb", contentBorder: "#efb7a4", text: "#472116", heading: "#35130c", muted: "#8e6254", accent: "#dc4b2f", link: "#b45309", codeBackground: "#fff0e9", codeText: "#542317", codeBorder: "#e2a08c", quoteBackground: "#fff1e8", quoteBorder: "#ea580c", tableHeader: "#ffe0d2", tableRow: "#fff8f4", divider: "#e0a18d", shadow: "rgba(130, 47, 22, 0.12)")
            case ("forest-canopy", false):
                return Self(bodyBackground: "#effaf2", contentBackground: "#fcfffd", contentBorder: "#add8b9", text: "#173b25", heading: "#0c2c18", muted: "#5e856a", accent: "#16803c", link: "#0369a1", codeBackground: "#edf9ef", codeText: "#1c4b2a", codeBorder: "#a5cdb0", quoteBackground: "#e3f7e8", quoteBorder: "#16a34a", tableHeader: "#d1efd8", tableRow: "#f5fcf6", divider: "#98c6a2", shadow: "rgba(22, 91, 42, 0.10)")
            case ("ultraviolet", false):
                return Self(bodyBackground: "#f5f0ff", contentBackground: "#ffffff", contentBorder: "#d3c4f4", text: "#30204f", heading: "#21113e", muted: "#75649a", accent: "#7c3aed", link: "#0369a1", codeBackground: "#f4efff", codeText: "#3b2860", codeBorder: "#c4b5e8", quoteBackground: "#fceff8", quoteBorder: "#db2777", tableHeader: "#e9ddff", tableRow: "#faf7ff", divider: "#c7b6e8", shadow: "rgba(80, 36, 150, 0.12)")
            case ("cobalt", false):
                return Self(bodyBackground: "#eef5ff", contentBackground: "#ffffff", contentBorder: "#b5cdf4", text: "#172f55", heading: "#0a2450", muted: "#5d78a2", accent: "#1d4ed8", link: "#075985", codeBackground: "#edf4ff", codeText: "#173562", codeBorder: "#a9c4ed", quoteBackground: "#fff9df", quoteBorder: "#d97706", tableHeader: "#d9e8ff", tableRow: "#f6f9ff", divider: "#a8c2e9", shadow: "rgba(21, 58, 130, 0.12)")
            case ("mint-paper", false):
                return Self(bodyBackground: "#edfff8", contentBackground: "#fbfffd", contentBorder: "#a9ddcc", text: "#153d35", heading: "#0b2d26", muted: "#5c897d", accent: "#059669", link: "#0369a1", codeBackground: "#e9fbf4", codeText: "#194d41", codeBorder: "#9fd4c2", quoteBackground: "#e0f8ee", quoteBorder: "#0f766e", tableHeader: "#ccefe1", tableRow: "#f4fcf8", divider: "#94c9b8", shadow: "rgba(9, 93, 72, 0.10)")
            case ("high-contrast", false):
                return Self(bodyBackground: "#ffffff", contentBackground: "#ffffff", contentBorder: "#000000", text: "#000000", heading: "#000000", muted: "#222222", accent: "#000000", link: "#0000ee", codeBackground: "#ffffff", codeText: "#000000", codeBorder: "#000000", quoteBackground: "#ffff00", quoteBorder: "#000000", tableHeader: "#e6e6e6", tableRow: "#ffffff", divider: "#000000", shadow: "transparent")
            case ("warm-sepia", false):
                return Self(bodyBackground: "#f3e6d2", contentBackground: "#fffaf0", contentBorder: "#d8b990", text: "#4b3625", heading: "#3b2415", muted: "#80664d", accent: "#a85d24", link: "#1d628c", codeBackground: "#f5e7d1", codeText: "#523a26", codeBorder: "#d5b486", quoteBackground: "#f8ecd9", quoteBorder: "#b7791f", tableHeader: "#eed8b8", tableRow: "#fff7e9", divider: "#d4b183", shadow: "rgba(92, 55, 22, 0.12)")
            case ("neon-editorial", false):
                return Self(bodyBackground: "#fff3fb", contentBackground: "#ffffff", contentBorder: "#efb9dc", text: "#32152f", heading: "#240d2b", muted: "#895b83", accent: "#c026d3", link: "#0369a1", codeBackground: "#fff0fa", codeText: "#421a3e", codeBorder: "#e6a5d1", quoteBackground: "#fff2f7", quoteBorder: "#f43f5e", tableHeader: "#ffe0f2", tableRow: "#fff8fc", divider: "#e5afd2", shadow: "rgba(112, 24, 95, 0.12)")
            default:
                if dark {
                    return Self(bodyBackground: "#111827", contentBackground: "#0f172a", contentBorder: "#293548", text: "#e5e7eb", heading: "#f8fafc", muted: "#9ca3af", accent: "#8b5cf6", link: "#93c5fd", codeBackground: "#0b1220", codeText: "#e5e7eb", codeBorder: "#334155", quoteBackground: "#111827", quoteBorder: "#8b5cf6", tableHeader: "#172033", tableRow: "#131c2b", divider: "#334155", shadow: "rgba(0, 0, 0, 0.32)")
                }
                return Self(bodyBackground: "#f7f9fb", contentBackground: "#ffffff", contentBorder: "#dfe6ed", text: "#263342", heading: "#142131", muted: "#667585", accent: "#2563eb", link: "#1d4ed8", codeBackground: "#f1f5f9", codeText: "#263342", codeBorder: "#d5dee8", quoteBackground: "#f3f7ff", quoteBorder: "#2563eb", tableHeader: "#e8eff8", tableRow: "#f8fafc", divider: "#d5dee8", shadow: "rgba(15, 23, 42, 0.08)")
            }
        }
    }

    struct MarkdownPreviewTheme: Equatable, Sendable {
        let palette: MarkdownPreviewSemanticPalette
        let bodyPadding: String
        let fontSize: String
        let lineHeight: String
        let contentMaxWidth: String
        let bodyFontFamily: String
        let contentRadius: String
        let blockSpacing: String
        let headingSpacing: String
        let tableCellPadding: String

        static func make(template: String, dark: Bool) -> Self {
            let palette = MarkdownPreviewSemanticPalette.make(template: template, dark: dark)
            switch template {
            case "neon-editorial", "magazine", "editorial-review":
                return Self(palette: palette, bodyPadding: "34px 52px", fontSize: "17px", lineHeight: "1.8", contentMaxWidth: "820px", bodyFontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif", contentRadius: "18px", blockSpacing: "1.1em", headingSpacing: "1.7em", tableCellPadding: "0.72em 0.9em")
            case "developer-slate", "developer-spec", "api-reference", "terminal-notes":
                return Self(palette: palette, bodyPadding: "22px 30px", fontSize: "15px", lineHeight: "1.65", contentMaxWidth: "980px", bodyFontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif", contentRadius: "10px", blockSpacing: "0.85em", headingSpacing: "1.35em", tableCellPadding: "0.58em 0.72em")
            case "nordic-light", "docs", "minimal-reader":
                return Self(palette: palette, bodyPadding: "28px 44px", fontSize: "16px", lineHeight: "1.75", contentMaxWidth: "880px", bodyFontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif", contentRadius: "14px", blockSpacing: "1em", headingSpacing: "1.55em", tableCellPadding: "0.68em 0.82em")
            case "solarized", "blueprint", "notebook":
                return Self(palette: palette, bodyPadding: "26px 38px", fontSize: "15px", lineHeight: "1.7", contentMaxWidth: "920px", bodyFontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif", contentRadius: "12px", blockSpacing: "0.95em", headingSpacing: "1.5em", tableCellPadding: "0.64em 0.82em")
            case "article", "academic-paper", "warm-sepia", "focus-writing":
                return Self(palette: palette, bodyPadding: "34px 48px", fontSize: "17px", lineHeight: "1.82", contentMaxWidth: "780px", bodyFontFamily: "Charter, \"Iowan Old Style\", \"Palatino Linotype\", serif", contentRadius: "12px", blockSpacing: "1.15em", headingSpacing: "1.85em", tableCellPadding: "0.72em 0.9em")
            case "electric-pop", "aurora", "citrus", "plasma", "deep-ocean", "ember-glow", "forest-canopy", "ultraviolet", "cobalt", "mint-paper":
                return Self(palette: palette, bodyPadding: "30px 42px", fontSize: "16px", lineHeight: "1.72", contentMaxWidth: "900px", bodyFontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif", contentRadius: "16px", blockSpacing: "1em", headingSpacing: "1.55em", tableCellPadding: "0.68em 0.86em")
            default:
                return Self(palette: palette, bodyPadding: "22px 30px", fontSize: "15px", lineHeight: "1.7", contentMaxWidth: "900px", bodyFontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif", contentRadius: "14px", blockSpacing: "1em", headingSpacing: "1.5em", tableCellPadding: "0.64em 0.82em")
            }
        }
    }

    static func markdownPreviewSemanticCSS(template: String, dark: Bool) -> String {
        let theme = MarkdownPreviewTheme.make(template: template, dark: dark)
        let palette = theme.palette
        let editorialCSS = ["neon-editorial", "article", "magazine", "academic-paper", "focus-writing", "editorial-review"].contains(template)
            ? ".content > p:first-of-type { font-size: 1.1em; letter-spacing: 0.005em; }"
            : ""
        let headingCSS: String
        switch template {
        case "developer-slate", "terminal-notes", "developer-spec", "api-reference":
            headingCSS = "h1, h2 { border-inline-start: 3px solid var(--md-accent-color); padding-inline-start: 0.7em; } h1::before, h2::before { display: none; } h1 { font-family: \"SF Mono\", Menlo, monospace; letter-spacing: 0.02em; } h2 { text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.96em; }"
        case "article", "academic-paper", "warm-sepia", "focus-writing":
            headingCSS = "h1, h2 { padding-inline-start: 0; } h1::before, h2::before { display: none; } h1 { border-bottom: 4px double var(--md-accent-color); text-align: center; letter-spacing: -0.03em; } h2 { border-bottom: 1px solid var(--md-accent-color); font-style: italic; }"
        case "high-contrast":
            headingCSS = "h1, h2 { padding-inline-start: 0.3em; border-inline-start: 0.38em solid var(--md-accent-color); border-bottom: 3px solid var(--md-accent-color); } h1::before, h2::before { display: none; } h1 { text-transform: uppercase; letter-spacing: 0.045em; }"
        case "solarized", "notebook", "blueprint":
            headingCSS = "h1, h2 { padding-inline-start: 0; border-bottom: 2px dashed var(--md-quote-border); } h1::before, h2::before { display: none; } h1 { font-family: Georgia, serif; } h2 { color: var(--md-accent-color); }"
        case "nordic-light", "docs", "minimal-reader":
            headingCSS = "h1, h2 { padding-inline-start: 0; border-bottom: 0; } h1::before, h2::before { display: none; } h1::after, h2::after { content: \"\"; display: block; width: 2.8em; height: 0.18em; margin-top: 0.35em; border-radius: 99px; background: var(--md-accent-color); }"
        case "electric-pop", "plasma":
            headingCSS = "h1, h2 { padding-inline-start: 0; border-bottom: 0; } h1::before, h2::before { display: none; } h1 { text-shadow: 0 0 20px color-mix(in srgb, var(--md-accent-color) 42%, transparent); } h1::after { content: \"\"; display: block; height: 0.16em; margin-top: 0.3em; background: linear-gradient(90deg, var(--md-accent-color), var(--md-link-color), transparent); border-radius: 99px; } h2 { border-inline-start: 0.22em solid var(--md-quote-border); padding-inline-start: 0.55em; }"
        case "aurora", "deep-ocean":
            headingCSS = "h1, h2 { padding-inline-start: 0; border-bottom: 0; } h1::before, h2::before { display: none; } h1 { border-bottom: 2px solid var(--md-accent-color); } h2 { border-bottom: 1px solid color-mix(in srgb, var(--md-link-color) 60%, transparent); } h1::after { content: \"\"; display: block; width: 4em; height: 0.22em; margin-top: 0.3em; background: linear-gradient(90deg, var(--md-accent-color), var(--md-link-color)); clip-path: polygon(0 0, 100% 0, 78% 100%, 0 100%); }"
        case "citrus":
            headingCSS = "h1, h2 { padding-inline-start: 0; border-bottom: 0; } h1::before, h2::before { display: none; } h1 { border-bottom: 3px solid var(--md-accent-color); } h2 { display: flex; align-items: baseline; gap: 0.45em; } h2::after { content: \"*\"; color: var(--md-quote-border); font-size: 0.7em; }"
        case "ember-glow":
            headingCSS = "h1, h2 { padding-inline-start: 0.7em; border-inline-start: 0.24em solid var(--md-accent-color); } h1::before, h2::before { display: none; } h1 { border-image: linear-gradient(var(--md-accent-color), var(--md-link-color)) 1; } h2 { border-inline-start-width: 0.14em; border-bottom: 1px solid color-mix(in srgb, var(--md-accent-color) 48%, transparent); }"
        case "forest-canopy":
            headingCSS = "h1, h2 { padding-inline-start: 0; border-bottom: 0; } h1::before, h2::before { display: none; } h1::after { content: \"\"; display: block; width: 3.2em; height: 0.18em; margin-top: 0.28em; background: repeating-linear-gradient(90deg, var(--md-accent-color) 0 0.55em, transparent 0.55em 0.82em); } h2 { border-bottom: 2px dotted var(--md-quote-border); }"
        case "ultraviolet":
            headingCSS = "h1, h2 { padding-inline-start: 0.5em; border-inline-start: 0.16em solid var(--md-accent-color); } h1::before, h2::before { display: none; } h1 { text-shadow: 0 0 16px color-mix(in srgb, var(--md-accent-color) 45%, transparent); } h2 { border-inline-start-color: var(--md-quote-border); font-style: italic; }"
        case "cobalt":
            headingCSS = "h1, h2 { padding-inline-start: 0; border-bottom: 0; } h1::before, h2::before { display: none; } h1 { border-top: 3px double var(--md-accent-color); padding-top: 0.3em; } h2 { border-bottom: 2px solid var(--md-link-color); }"
        case "mint-paper":
            headingCSS = "h1, h2 { padding-inline-start: 0.55em; border-inline-start: 0.18em solid var(--md-accent-color); } h1::before, h2::before { display: none; } h1 { border-bottom: 1px dashed var(--md-quote-border); } h2 { border-inline-start-style: dotted; color: var(--md-accent-color); }"
        default:
            headingCSS = ""
        }
        return """
        :root {
          --md-body-background: \(palette.bodyBackground);
          --md-content-background: \(palette.contentBackground);
          --md-content-border: 1px solid \(palette.contentBorder);
          --md-text-color: \(palette.text);
          --md-heading-color: \(palette.heading);
          --md-muted-color: \(palette.muted);
          --md-accent-color: \(palette.accent);
          --md-link-color: \(palette.link);
          --md-code-background: \(palette.codeBackground);
          --md-code-text: \(palette.codeText);
          --md-code-border: \(palette.codeBorder);
          --md-quote-background: \(palette.quoteBackground);
          --md-quote-border: \(palette.quoteBorder);
          --md-table-header-background: \(palette.tableHeader);
          --md-table-row-background: \(palette.tableRow);
          --md-hr-color: \(palette.divider);
          --md-shadow-color: \(palette.shadow);
          --md-body-padding: \(theme.bodyPadding);
          --md-font-size: \(theme.fontSize);
          --md-line-height: \(theme.lineHeight);
          --md-content-max-width: \(theme.contentMaxWidth);
          --md-body-font-family: \(theme.bodyFontFamily);
          --md-content-radius: \(theme.contentRadius);
          --md-block-spacing: \(theme.blockSpacing);
          --md-heading-spacing: \(theme.headingSpacing);
          --md-table-cell-padding: \(theme.tableCellPadding);
        }
        html, body { font-family: var(--md-body-font-family); font-size: var(--md-font-size); line-height: var(--md-line-height); }
        body { background: var(--md-body-background); color: var(--md-text-color); }
        .content { max-width: var(--md-content-max-width); padding: var(--md-body-padding); border-radius: var(--md-content-radius); background: var(--md-content-background); color: var(--md-text-color); }
        .content > p, .content > ul, .content > ol, .content > blockquote, .content > .table-scroll, .content > .code-block, .content > .markdown-image { margin-block: var(--md-block-spacing); }
        h1, h2, h3, h4, h5, h6 { color: var(--md-heading-color); }
        h1, h2 { position: relative; margin-top: var(--md-heading-spacing); padding-bottom: 0.35em; }
        a { color: var(--md-link-color); text-decoration-line: underline; text-decoration-thickness: 0.09em; text-decoration-color: color-mix(in srgb, var(--md-link-color) 72%, transparent); text-underline-offset: 0.18em; transition: color 160ms ease, text-decoration-color 160ms ease, text-underline-offset 160ms ease; }
        a:hover, a:focus-visible { color: var(--md-accent-color); text-decoration-color: var(--md-accent-color); text-underline-offset: 0.28em; }
        code:not(pre code) { display: inline-block; color: var(--md-code-text); background: color-mix(in srgb, var(--md-accent-color) 10%, var(--md-code-background)); border: 1px solid color-mix(in srgb, var(--md-accent-color) 34%, var(--md-code-border)); border-radius: 0.42em; padding: 0.08em 0.38em; font-size: 0.9em; box-shadow: 0 1px 0 color-mix(in srgb, var(--md-accent-color) 24%, transparent); }
        blockquote { position: relative; box-shadow: inset 4px 0 0 var(--md-quote-border); border-radius: 0 var(--md-content-radius) var(--md-content-radius) 0; background: var(--md-quote-background); }
        blockquote::before { content: "“"; position: absolute; inset-inline-end: 0.55em; inset-block-start: -0.16em; color: var(--md-quote-border); opacity: 0.5; font-size: 3em; line-height: 1; font-family: Georgia, serif; }
        blockquote cite, blockquote .quote-meta { display: block; margin-top: 0.7em; color: var(--md-muted-color); font-size: 0.82em; font-style: normal; letter-spacing: 0.025em; }
        .code-block { overflow: hidden; box-shadow: 0 12px 26px var(--md-shadow-color); border-color: var(--md-code-border); background: var(--md-code-background); }
        .code-block-toolbar { color: var(--md-accent-color); border-bottom: 1px solid color-mix(in srgb, var(--md-code-border) 82%, transparent); background: color-mix(in srgb, var(--md-accent-color) 10%, var(--md-code-background)); }
        .code-block-language-label { letter-spacing: 0.08em; text-transform: uppercase; font-size: 0.78em; }
        .code-block-copy { color: var(--md-accent-color); border-color: color-mix(in srgb, var(--md-accent-color) 48%, var(--md-code-border)); background: color-mix(in srgb, var(--md-accent-color) 10%, transparent); }
        .code-block pre, .code-block pre code { color: var(--md-code-text); }
        .table-scroll { border: 1px solid var(--md-content-border); border-radius: var(--md-content-radius); overflow: auto; background: var(--md-content-background); }
        table { border-collapse: separate; border-spacing: 0; }
        th, td { padding: var(--md-table-cell-padding); }
        th { position: sticky; top: 0; z-index: 1; color: var(--md-heading-color); background: var(--md-table-header-background); box-shadow: 0 1px 0 var(--md-accent-color); letter-spacing: 0.02em; }
        tbody tr:nth-child(even) { background: var(--md-table-row-background); }
        tbody tr:hover { background: color-mix(in srgb, var(--md-accent-color) 9%, var(--md-table-row-background)); }
        input[type="checkbox"] { accent-color: var(--md-accent-color); width: 1em; height: 1em; vertical-align: -0.12em; }
        .markdown-image { margin-inline: 0; padding: 0.65em; border: 1px solid var(--md-content-border); border-radius: var(--md-content-radius); background: color-mix(in srgb, var(--md-accent-color) 5%, var(--md-content-background)); box-shadow: 0 10px 24px var(--md-shadow-color); }
        .markdown-image img { display: block; width: 100%; border-radius: calc(var(--md-content-radius) * 0.72); }
        .markdown-image figcaption { margin-top: 0.62em; color: var(--md-muted-color); font-size: 0.82em; text-align: center; }
        .content > p:first-of-type { margin-top: var(--md-block-spacing); }
        \(editorialCSS)
        \(headingCSS)
        hr { border-color: var(--md-hr-color); }
        """
    }

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
        var textColor: String
        var mutedTextColor: String
        var linkColor: String
        var codeBackground: String
        let codeBorder: String
        let quoteBackground: String
        let quoteBorder: String
        var tableHeaderBackground: String
        var horizontalRuleColor: String
        var shadowColor: String
        let bodyFontFamily: String
        let syntaxKeywordColor: String
        let syntaxStringColor: String
        let syntaxCommentColor: String
        let syntaxKeyColor: String
        let syntaxNumberColor: String
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
        case "compact":
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
        case "notebook":
            basePadding = "34px 42px"
            fontSize = "16px"
            lineHeight = "1.78"
            maxWidth = "780px"
            bodyBackground = preferDarkMode ? "#171712" : "#f5f0df"
            contentBackground = preferDarkMode ? "#1d1d16" : "#fffdf3"
            contentBorder = preferDarkMode ? "1px solid #47452f" : "1px solid #ded3ad"
            textColor = preferDarkMode ? "#f5f1dc" : "#2d3227"
            mutedTextColor = preferDarkMode ? "#c7c1a7" : "#706c57"
            linkColor = preferDarkMode ? "#9fd3ff" : "#1769aa"
            codeBackground = preferDarkMode ? "#151710" : "#f4efd9"
            codeBorder = preferDarkMode ? "#4a4933" : "#d8cfae"
            quoteBackground = preferDarkMode ? "#202016" : "#faf3d9"
            quoteBorder = preferDarkMode ? "#f2b84b" : "#c9851d"
            tableHeaderBackground = preferDarkMode ? "#29291d" : "#f0e8c8"
            horizontalRuleColor = preferDarkMode ? "#4a4933" : "#d8cfae"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.28)" : "rgba(102, 86, 45, 0.08)"
            bodyFontFamily = "Charter, \"Iowan Old Style\", Georgia, serif"
        case "blueprint":
            basePadding = "26px 30px"
            fontSize = "14px"
            lineHeight = "1.62"
            maxWidth = "980px"
            bodyBackground = preferDarkMode ? "#071827" : "#e8f4fb"
            contentBackground = preferDarkMode ? "#0a2134" : "#f8fcff"
            contentBorder = preferDarkMode ? "1px solid #1d5270" : "1px solid #a8cddd"
            textColor = preferDarkMode ? "#d9f4ff" : "#0b3449"
            mutedTextColor = preferDarkMode ? "#8fc3d9" : "#52788a"
            linkColor = preferDarkMode ? "#67e8f9" : "#087ea4"
            codeBackground = preferDarkMode ? "#061522" : "#e5f4fb"
            codeBorder = preferDarkMode ? "#24617f" : "#9ac7db"
            quoteBackground = preferDarkMode ? "#0c2a3f" : "#eaf7fd"
            quoteBorder = preferDarkMode ? "#38bdf8" : "#0284c7"
            tableHeaderBackground = preferDarkMode ? "#10334a" : "#d7edf7"
            horizontalRuleColor = preferDarkMode ? "#24617f" : "#9ac7db"
            shadowColor = preferDarkMode ? "rgba(0, 0, 0, 0.34)" : "rgba(8, 126, 164, 0.08)"
            bodyFontFamily = "\"SF Mono\", Menlo, Monaco, monospace"
        case "high-contrast":
            basePadding = "28px 34px"
            fontSize = "16px"
            lineHeight = "1.72"
            maxWidth = "840px"
            bodyBackground = preferDarkMode ? "#000000" : "#ffffff"
            contentBackground = preferDarkMode ? "#000000" : "#ffffff"
            contentBorder = preferDarkMode ? "2px solid #ffffff" : "2px solid #000000"
            textColor = preferDarkMode ? "#ffffff" : "#000000"
            mutedTextColor = preferDarkMode ? "#e5e5e5" : "#262626"
            linkColor = preferDarkMode ? "#ffff00" : "#0037ff"
            codeBackground = preferDarkMode ? "#1a1a1a" : "#f0f0f0"
            codeBorder = preferDarkMode ? "#ffffff" : "#000000"
            quoteBackground = preferDarkMode ? "#141414" : "#f5f5f5"
            quoteBorder = preferDarkMode ? "#ffff00" : "#000000"
            tableHeaderBackground = preferDarkMode ? "#262626" : "#e5e5e5"
            horizontalRuleColor = preferDarkMode ? "#ffffff" : "#000000"
            shadowColor = "transparent"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif"
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
        case "dense-compact":
            basePadding = "10px 12px"
            fontSize = "12px"
            lineHeight = "1.42"
            maxWidth = "none"
            bodyBackground = preferDarkMode ? "#111827" : "#f5f7fa"
            contentBackground = preferDarkMode ? "#151d2b" : "#ffffff"
            contentBorder = preferDarkMode ? "1px solid #334155" : "1px solid #d8dee8"
            textColor = preferDarkMode ? "#e5e7eb" : "#172033"
            mutedTextColor = preferDarkMode ? "#a8b3c5" : "#607086"
            linkColor = preferDarkMode ? "#7dd3fc" : "#0369a1"
            codeBackground = preferDarkMode ? "#0b1220" : "#edf2f7"
            codeBorder = preferDarkMode ? "#334155" : "#cbd5e1"
            quoteBackground = preferDarkMode ? "#111827" : "#f7fafc"
            quoteBorder = preferDarkMode ? "#38bdf8" : "#0284c7"
            tableHeaderBackground = preferDarkMode ? "#1e293b" : "#eef2f7"
            horizontalRuleColor = preferDarkMode ? "#334155" : "#cbd5e1"
            shadowColor = "transparent"
            bodyFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
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
            case .template, .translucent, .neutral, .paper, .slate, .ink:
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
        case .paper:
            bodyBackground = "#eee9dd"
            contentBackground = "#fffdf7"
            contentBorder = "1px solid #ddd4c3"
            textColor = "#292722"
            mutedTextColor = "#746d60"
            codeBackground = "#f3ede1"
            tableHeaderBackground = "#f0e9dc"
            horizontalRuleColor = "#d6cbbb"
            shadowColor = "rgba(57, 48, 35, 0.10)"
        case .slate:
            bodyBackground = "#dfe3e8"
            contentBackground = "#f6f8fa"
            contentBorder = "1px solid #c6ced7"
            textColor = "#1c2630"
            mutedTextColor = "#5d6a76"
            codeBackground = "#e9edf1"
            tableHeaderBackground = "#e3e8ed"
            horizontalRuleColor = "#bcc6d0"
            shadowColor = "rgba(30, 41, 59, 0.10)"
        case .ink:
            bodyBackground = "#000000"
            contentBackground = "#0b0b0d"
            contentBorder = "1px solid #2a2a2e"
            textColor = "#f2f2f4"
            mutedTextColor = "#a3a3a9"
            linkColor = "#8ab4ff"
            codeBackground = "#17171a"
            tableHeaderBackground = "#1b1b1f"
            horizontalRuleColor = "#303036"
            shadowColor = "rgba(0, 0, 0, 0.42)"
        case .automatic:
            break
        }

        // Keep code tokens vivid and legible in both preview themes. These fixed
        // colors also keep exported previews visually consistent with the live preview.
        syntaxKeywordColor = "#ff4fd8"
        syntaxStringColor = "#14d990"
        syntaxCommentColor = "#8b95a7"
        syntaxKeyColor = "#7c5cff"
        syntaxNumberColor = "#ff9f1c"

        let templateAccentCSS: String
        switch template {
        case "article", "focus-writing":
            templateAccentCSS = """
            h1 { font-size: 2.25em; letter-spacing: -0.035em; border-bottom: 0; }
            h2 { margin-top: 1.7em; border-bottom: 0; }
            p:first-of-type { font-size: 1.08em; }
            """
        case "academic-paper":
            templateAccentCSS = """
            h1 { text-align: center; border-bottom: 0; font-size: 2em; }
            h2 { margin-top: 2em; font-size: 1.25em; letter-spacing: 0.035em; text-transform: uppercase; }
            blockquote { border-left-width: 1px; border-radius: 0; font-style: italic; }
            """
        case "magazine", "editorial-review":
            templateAccentCSS = """
            h1 { font-size: 2.5em; line-height: 1.05; border-bottom: 0; letter-spacing: -0.045em; }
            h2 { border-bottom: 0; font-size: 1em; letter-spacing: 0.1em; text-transform: uppercase; }
            p:first-of-type { font-size: 1.12em; }
            """
        case "presentation":
            templateAccentCSS = """
            h1 { font-size: 2.65em; border-bottom: 0; letter-spacing: -0.045em; }
            h2 { font-size: 1.6em; border-bottom: 0; margin-top: 1.55em; }
            li { margin: 0.5em 0; }
            blockquote { padding: 0.75em 1em; }
            """
        case "minimal-reader":
            templateAccentCSS = """
            .content { border-radius: 0; }
            h1, h2 { border-bottom: 0; font-weight: 600; }
            blockquote { background: transparent; border-radius: 0; }
            """
        case "terminal-notes", "developer-spec", "lab-notes":
            templateAccentCSS = """
            .content, blockquote, pre, .table-scroll { border-radius: 3px; }
            h1, h2 { font-family: \"SF Mono\", Menlo, Monaco, monospace; letter-spacing: 0.035em; text-transform: uppercase; }
            h1 { font-size: 1.55em; }
            h2 { font-size: 1.15em; }
            th { text-transform: uppercase; font-size: 0.88em; letter-spacing: 0.035em; }
            """
        case "api-reference":
            templateAccentCSS = """
            .content, blockquote, pre, .table-scroll { border-radius: 4px; }
            h1 { border-bottom-width: 2px; }
            h2 { font-size: 1.1em; letter-spacing: 0.07em; text-transform: uppercase; }
            th { font-family: \"SF Mono\", Menlo, Monaco, monospace; font-size: 0.84em; }
            """
        case "changelog":
            templateAccentCSS = """
            h1 { border-bottom-width: 2px; }
            h2 { padding: 0.42em 0.6em; border: 0; border-left: 4px solid var(--md-quote-border); background: var(--md-table-header-background); }
            ul { padding-left: 1.55em; }
            """
        case "dense-compact":
            templateAccentCSS = """
            .content { border-radius: 7px; }
            h1 { font-size: 1.45em; margin-top: 0.55em; }
            h2 { font-size: 1.2em; margin-top: 0.9em; }
            p, ul, ol, blockquote, pre { margin: 0.4em 0; }
            th, td { padding: 0.28em 0.38em; }
            """
        case "notebook":
            let paperLines = resolvedBackgroundStyle == .template
                ? "background-image: repeating-linear-gradient(to bottom, transparent 0, transparent 27px, color-mix(in srgb, var(--md-link-color) 13%, transparent) 28px); background-size: 100% 28px;"
                : ""
            templateAccentCSS = """
            .content { border-radius: 8px; \(paperLines) }
            h1 { border-bottom: 2px solid var(--md-quote-border); font-size: 2.2em; }
            h2 { border-bottom: 0; font-size: 1.25em; }
            blockquote { border-left-width: 5px; border-radius: 0; }
            """
        case "blueprint":
            let grid = resolvedBackgroundStyle == .template
                ? "background-image: linear-gradient(color-mix(in srgb, var(--md-link-color) 13%, transparent) 1px, transparent 1px), linear-gradient(90deg, color-mix(in srgb, var(--md-link-color) 13%, transparent) 1px, transparent 1px); background-size: 20px 20px;"
                : ""
            templateAccentCSS = """
            .content { border-radius: 0; \(grid) }
            h1, h2 { font-family: \"SF Mono\", Menlo, Monaco, monospace; border-bottom-style: dashed; }
            h1 { font-size: 1.7em; letter-spacing: 0.045em; text-transform: uppercase; }
            h2 { font-size: 1.15em; letter-spacing: 0.06em; text-transform: uppercase; }
            blockquote, pre, .table-scroll { border-radius: 0; }
            """
        case "high-contrast":
            templateAccentCSS = """
            .content, blockquote, pre, .table-scroll, code { border-radius: 0; }
            h1, h2 { border-bottom-color: currentColor; }
            a { border-bottom-width: 2px; font-weight: 700; text-decoration: underline; }
            th, td { border-bottom-color: currentColor; }
            """
        default:
            templateAccentCSS = ""
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
          --md-syntax-keyword: \(syntaxKeywordColor);
          --md-syntax-string: \(syntaxStringColor);
          --md-syntax-comment: \(syntaxCommentColor);
          --md-syntax-key: \(syntaxKeyColor);
          --md-syntax-number: \(syntaxNumberColor);
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
        p, ul, ol, blockquote, pre { margin: 0.65em 0; }
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
        .code-block {
          max-width: 100%;
          margin: 0.9em 0;
          overflow: hidden;
          border: 1px solid var(--md-code-border);
          border-radius: 9px;
          background: var(--md-code-background);
        }
        .code-block-toolbar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.65em;
          max-width: 100%;
          margin: 0;
          padding: 0.35em 0.6em;
          color: var(--md-muted-color);
          background: color-mix(in srgb, var(--md-content-background) 55%, var(--md-code-background));
          border-bottom: none;
          font-size: 0.76em;
          line-height: 1.2;
        }
        .code-block-language-label {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 650;
          letter-spacing: 0.02em;
          text-transform: uppercase;
        }
        .code-block-actions {
          display: inline-flex;
          align-items: center;
          gap: 0.45em;
          min-width: 0;
        }
        .code-block-language-control {
          display: inline-flex;
          align-items: center;
          gap: 0.25em;
          min-width: 0;
          white-space: nowrap;
        }
        .code-block-language-caption {
          position: absolute;
          width: 1px;
          height: 1px;
          padding: 0;
          margin: -1px;
          overflow: hidden;
          clip: rect(0, 0, 0, 0);
          white-space: nowrap;
          border: 0;
        }
        .code-block-language-picker {
          max-width: 10em;
          min-height: 1.75em;
          color: var(--md-text-color);
          background: transparent;
          border: 1px solid color-mix(in srgb, var(--md-muted-color) 40%, transparent);
          border-radius: 5px;
          font: inherit;
        }
        .code-block-copy {
          appearance: none;
          border: 1px solid color-mix(in srgb, var(--md-muted-color) 40%, transparent);
          border-radius: 5px;
          padding: 0.25em 0.55em;
          color: var(--md-muted-color);
          background: transparent;
          font: inherit;
          cursor: pointer;
        }
        .code-block-copy:hover,
        .code-block-copy:focus-visible,
        .code-block-language-picker:focus-visible {
          color: var(--md-link-color);
          border-color: var(--md-link-color);
          outline: none;
        }
        .code-block pre {
          margin-top: 0;
          border: 0;
          border-radius: 0;
        }
        .syntax-kw { color: \(syntaxKeywordColor); font-weight: 650; }
        .syntax-str { color: \(syntaxStringColor); }
        .syntax-comment { color: var(--md-syntax-comment); font-style: italic; }
        .syntax-key { color: \(syntaxKeyColor); font-weight: 600; }
        .syntax-num { color: \(syntaxNumberColor); }
        /* Keep exported token colors stable across light and dark preview themes. */
        .syntax-kw { color: var(--md-syntax-keyword); font-weight: 650; }
        .syntax-str { color: var(--md-syntax-string); }
        .syntax-key { color: var(--md-syntax-key); font-weight: 600; }
        .syntax-num { color: var(--md-syntax-number); }
        pre {
          max-width: 100%;
          overflow-x: auto;
          padding: 0.75em 0.9em;
          background: var(--md-code-background);
          line-height: 1.35;
          white-space: pre;
          overflow-wrap: normal;
          word-break: normal;
        }
        pre code {
          display: block;
          padding: 0;
          background: transparent;
          border-radius: 0;
          font-size: 0.88em;
          line-height: 1.35;
          white-space: pre;
          overflow-wrap: normal;
          word-break: normal;
        }
        @media print {
          .code-block-copy,
          .code-block-language-control { display: none; }
        }
        .table-scroll {
          display: block;
          max-width: 100%;
          overflow-x: auto;
          border: 1px solid color-mix(in srgb, currentColor 16%, transparent);
          border-radius: 8px;
          margin: 0.65em 0;
          -webkit-overflow-scrolling: touch;
        }
        table {
          width: max-content;
          min-width: 100%;
          border-collapse: collapse;
        }
        th, td {
          text-align: left;
          padding: 0.45em 0.55em;
          border-bottom: 1px solid color-mix(in srgb, currentColor 10%, transparent);
          vertical-align: top;
          overflow-wrap: break-word;
          word-break: normal;
        }
        th {
          background: var(--md-table-header-background);
          font-weight: 600;
          white-space: nowrap;
        }
        .mermaid-diagram {
          margin: 0.9em 0;
          padding: 0.75em;
          border-radius: 10px;
          border: 1px solid color-mix(in srgb, currentColor 14%, transparent);
          background: color-mix(in srgb, var(--md-code-background) 82%, transparent);
        }
        .mermaid-diagram-scroll {
          max-height: min(68vh, 760px);
          overflow: auto;
          overscroll-behavior: contain;
          -webkit-overflow-scrolling: touch;
        }
        .mermaid-svg {
          display: block;
          width: max(100%, 620px);
          max-width: none;
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
        \(templateAccentCSS)
        \(Self.markdownPreviewSemanticCSS(template: template, dark: preferDarkMode))
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
