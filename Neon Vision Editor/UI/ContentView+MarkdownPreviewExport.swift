import Foundation
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

extension ContentView {
    enum MarkdownPDFExportMode: String {
        case paginatedFit = "paginated-fit"
        case onePageFit = "one-page-fit"
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
#else
                markdownPDFExportDocument = PDFExportDocument(data: pdfData)
                markdownPDFExportFilename = filename
                showMarkdownPDFExporter = true
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
        \(markdownPreviewCSS(template: markdownPreviewTemplate, preferDarkMode: preferDarkMode))
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
        \(markdownPreviewCSS(template: markdownPreviewTemplate))
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

    func markdownPreviewCSS(template: String, preferDarkMode: Bool = false) -> String {
        let basePadding: String
        let fontSize: String
        let lineHeight: String
        let maxWidth: String
        switch template {
        case "docs":
            basePadding = "22px 30px"
            fontSize = "15px"
            lineHeight = "1.7"
            maxWidth = "900px"
        case "article":
            basePadding = "32px 48px"
            fontSize = "17px"
            lineHeight = "1.8"
            maxWidth = "760px"
        case "compact", "dense-compact":
            basePadding = "14px 16px"
            fontSize = "13px"
            lineHeight = "1.5"
            maxWidth = "none"
        default:
            basePadding = "18px 22px"
            fontSize = "14px"
            lineHeight = "1.6"
            maxWidth = "860px"
        }

        let textColor = preferDarkMode ? "#E5E7EB" : "#111827"
        let linkColor = preferDarkMode ? "#7FB0FF" : "#2F7CF6"
        let previewBackground = preferDarkMode && template == "night-contrast"
            ? "linear-gradient(180deg, #020617 0%, #050816 100%)"
            : "transparent"

        return """
        :root {
          color-scheme: light dark;
          --md-text-color: \(textColor);
          --md-link-color: \(linkColor);
        }
        html, body {
          margin: 0;
          padding: 0;
          background: \(previewBackground);
          color: var(--md-text-color);
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          font-size: \(fontSize);
          line-height: \(lineHeight);
        }
        .content {
          max-width: \(maxWidth);
          padding: \(basePadding);
          margin: 0 auto;
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
        p, ul, ol, blockquote, table, pre { margin: 0.65em 0; }
        ul, ol { padding-left: 1.3em; }
        li { margin: 0.2em 0; }
        blockquote {
          margin-left: 0;
          padding: 0.45em 0.9em;
          border-left: 3px solid color-mix(in srgb, currentColor 30%, transparent);
          background: color-mix(in srgb, currentColor 6%, transparent);
          border-radius: 6px;
        }
        code {
          font-family: "SF Mono", "Menlo", "Monaco", monospace;
          font-size: 0.9em;
          padding: 0.12em 0.35em;
          border-radius: 5px;
          background: color-mix(in srgb, currentColor 10%, transparent);
        }
        pre {
          overflow-x: auto;
          padding: 0.8em 0.95em;
          border-radius: 9px;
          background: color-mix(in srgb, currentColor 8%, transparent);
          border: 1px solid color-mix(in srgb, currentColor 14%, transparent);
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
          background: color-mix(in srgb, currentColor 7%, transparent);
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
          border-top: 1px solid color-mix(in srgb, currentColor 15%, transparent);
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
