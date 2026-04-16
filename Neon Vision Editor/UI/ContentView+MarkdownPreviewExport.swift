import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension ContentView {
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
        switch markdownPreviewTemplateRaw {
        case "docs",
             "article",
             "compact",
             "github-docs",
             "academic-paper",
             "terminal-notes",
             "magazine",
             "minimal-reader",
             "presentation",
             "night-contrast",
             "warm-sepia",
             "dense-compact",
             "developer-spec":
            return markdownPreviewTemplateRaw
        default:
            return "default"
        }
    }

    var markdownPreviewBackgroundStyle: MarkdownPreviewBackgroundStyle {
        MarkdownPreviewBackgroundStyle(rawValue: markdownPreviewBackgroundStyleRaw) ?? .automatic
    }

    var markdownPreviewPreferDarkMode: Bool {
        if let forcedScheme = ReleaseRuntimePolicy.preferredColorScheme(for: appearance) {
            return forcedScheme == .dark
        }
        return colorScheme == .dark
    }

    @MainActor
    func exportMarkdownPreviewPDF() {
        Task { @MainActor in
            do {
                let exportSource = await markdownExportSourceText()
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

    var markdownPreviewRenderByteLimit: Int { 180_000 }
    var markdownPreviewFallbackCharacterLimit: Int { 120_000 }

    func markdownPreviewHTML(from markdownText: String, preferDarkMode: Bool) -> String {
        let bodyHTML = markdownPreviewBodyHTML(from: markdownText, useRenderLimits: true)
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(markdownPreviewCSS(
            template: markdownPreviewTemplate,
            preferDarkMode: preferDarkMode,
            backgroundStyle: markdownPreviewBackgroundStyle,
            translucentBackgroundEnabled: enableTranslucentWindow
        ))
        \(markdownPreviewRuntimePreviewScaleCSS())
        </style>
        </head>
        <body class="\(markdownPreviewTemplate)">
        <main class="content">
        \(bodyHTML)
        </main>
        </body>
        </html>
        """
    }

    func markdownPreviewRuntimePreviewScaleCSS() -> String {
        let previewLayoutCSS = """
        html, body {
          min-height: 100%;
        }
        body {
          background: var(--md-content-background);
        }
        .content {
          max-width: none !important;
          min-height: 100vh;
          margin: 0 !important;
          padding: clamp(14px, 2.2vw, 24px);
          background: transparent !important;
          border: none !important;
          border-radius: 0 !important;
          box-shadow: none !important;
          -webkit-backdrop-filter: none !important;
          backdrop-filter: none !important;
        }
        """
#if os(iOS)
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        return """
        \(previewLayoutCSS)
        html {
          -webkit-text-size-adjust: \(isPad ? "126%" : "108%");
        }
        body {
          font-size: \(isPad ? "1.08em" : "0.98em");
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
        let bodyHTML = markdownPreviewBodyHTML(from: markdownText, useRenderLimits: false)
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

    func markdownPreviewBodyHTML(from markdownText: String, useRenderLimits: Bool) -> String {
        let byteCount = markdownText.lengthOfBytes(using: .utf8)
        if useRenderLimits && byteCount > markdownPreviewRenderByteLimit {
            return largeMarkdownFallbackHTML(from: markdownText, byteCount: byteCount)
        }
        if !useRenderLimits && byteCount > markdownPreviewRenderByteLimit {
            return "<pre>\(escapedHTML(markdownText))</pre>"
        }
        return renderedMarkdownBodyHTML(from: markdownText) ?? "<pre>\(escapedHTML(markdownText))</pre>"
    }

    func largeMarkdownFallbackHTML(from markdownText: String, byteCount: Int) -> String {
        let previewText = String(markdownText.prefix(markdownPreviewFallbackCharacterLimit))
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

    func renderedMarkdownBodyHTML(from markdownText: String) -> String? {
        let html = simpleMarkdownToHTML(markdownText).trimmingCharacters(in: .whitespacesAndNewlines)
        return html.isEmpty ? nil : html
    }

    func simpleMarkdownToHTML(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [String] = []
        var paragraphLines: [String] = []
        var insideCodeFence = false
        var codeFenceLanguage: String?
        var insideUnorderedList = false
        var insideOrderedList = false
        var insideBlockquote = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = paragraphLines.map { inlineMarkdownToHTML($0) }.joined(separator: "<br/>")
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

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if insideCodeFence {
                    result.append("</code></pre>")
                    insideCodeFence = false
                    codeFenceLanguage = nil
                } else {
                    closeBlockquote()
                    closeParagraphAndInlineContainers()
                    insideCodeFence = true
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeFenceLanguage = lang.isEmpty ? nil : lang
                    if let codeFenceLanguage {
                        result.append("<pre><code class=\"language-\(escapedHTML(codeFenceLanguage))\">")
                    } else {
                        result.append("<pre><code>")
                    }
                }
                continue
            }

            if insideCodeFence {
                result.append("\(escapedHTML(rawLine))\n")
                continue
            }

            if trimmed.isEmpty {
                closeParagraphAndInlineContainers()
                closeBlockquote()
                continue
            }

            if let heading = markdownHeading(from: trimmed) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                result.append("<h\(heading.level)>\(inlineMarkdownToHTML(heading.text))</h\(heading.level)>")
                continue
            }

            if isMarkdownHorizontalRule(trimmed) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                result.append("<hr/>")
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
                result.append("<li>\(inlineMarkdownToHTML(unordered))</li>")
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
                result.append("<li>\(inlineMarkdownToHTML(ordered))</li>")
                continue
            }

            closeLists()
            paragraphLines.append(workingLine)
        }

        closeBlockquote()
        closeParagraphAndInlineContainers()
        if insideCodeFence {
            result.append("</code></pre>")
        }
        return result.joined(separator: "\n")
    }

    func markdownHeading(from line: String) -> (level: Int, text: String)? {
        let pattern = "^(#{1,6})\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let hashesRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (line[hashesRange].count, String(line[textRange]))
    }

    func isMarkdownHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact == "***" || compact == "---" || compact == "___"
    }

    func markdownUnorderedListItem(from line: String) -> String? {
        let pattern = "^[-*+]\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let textRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[textRange])
    }

    func markdownOrderedListItem(from line: String) -> String? {
        let pattern = "^\\d+[\\.)]\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let textRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[textRange])
    }

    func inlineMarkdownToHTML(_ text: String) -> String {
        var html = escapedHTML(text)
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
            return "<img src=\"\(parts[1])\" alt=\"\(parts[0])\"/>"
        }

        html = replacingRegex(in: html, pattern: "\\[([^\\]]+)\\]\\(([^\\)\\s]+)\\)") { match in
            let parts = captureGroups(in: match, pattern: "\\[([^\\]]+)\\]\\(([^\\)\\s]+)\\)")
            guard parts.count == 2 else { return match }
            return "<a href=\"\(parts[1])\">\(parts[0])</a>"
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

    func replacingRegex(in text: String, pattern: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
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

    func captureGroups(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern),
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

    func markdownPreviewCSS(
        template: String,
        preferDarkMode: Bool = false,
        backgroundStyle: MarkdownPreviewBackgroundStyle = .template,
        translucentBackgroundEnabled: Bool = false
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
          background: var(--md-body-background);
          color: var(--md-text-color);
          font-family: \(bodyFontFamily);
          font-size: \(fontSize);
          line-height: \(lineHeight);
        }
        .content {
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
        }
        h1 { font-size: 1.85em; border-bottom: 1px solid color-mix(in srgb, currentColor 18%, transparent); padding-bottom: 0.25em; }
        h2 { font-size: 1.45em; border-bottom: 1px solid color-mix(in srgb, currentColor 13%, transparent); padding-bottom: 0.2em; }
        h3 { font-size: 1.2em; }
        p, li, td, th { color: var(--md-text-color); }
        .preview-warning-meta, figcaption { color: var(--md-muted-color); }
        p, ul, ol, blockquote, table, pre { margin: 0.65em 0; }
        ul, ol { padding-left: 1.3em; }
        li { margin: 0.2em 0; }
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
        }
        pre {
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
        }
        th {
          background: var(--md-table-header-background);
          font-weight: 600;
        }
        a {
          color: var(--md-link-color);
          text-decoration: none;
          border-bottom: 1px solid color-mix(in srgb, var(--md-link-color) 45%, transparent);
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

    func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
