import SwiftUI
import Foundation

// MARK: - Web Preview UI

extension ContentView {
    @ViewBuilder
    var webPreviewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            webPreviewHeader
            MarkdownPreviewWebView(html: webPreviewHTML(from: currentContent))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("\(webPreviewTitle) Content")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(editorSurfaceBackgroundStyle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(webPreviewTitle)
    }

    private var webPreviewHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: webPreviewIconName)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(webPreviewTitle)
                .font(.headline)
            Spacer(minLength: 0)
            Text(webPreviewStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            Rectangle()
                .fill(webPreviewHeaderBackgroundColor)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(webPreviewTitle)
        .accessibilityValue(webPreviewStatusText)
    }

    private var webPreviewTitle: String {
        isSVGDocument ? "SVG Preview" : "HTML Preview"
    }

    private var webPreviewIconName: String {
        isSVGDocument ? "photo" : "safari"
    }

    private var webPreviewStatusText: String {
        let byteCount = currentContent.utf8.count
        if byteCount >= 1_000_000 {
            return String(format: "%.1f MB", Double(byteCount) / 1_000_000.0)
        }
        if byteCount >= 1_000 {
            return "\(byteCount / 1_000) KB"
        }
        return "\(byteCount) bytes"
    }

    private var webPreviewHeaderBackgroundColor: Color {
#if os(macOS)
        currentEditorTheme(colorScheme: colorScheme).background
#else
        Color(.systemBackground)
#endif
    }

    private func webPreviewHTML(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSVGDocument {
            guard trimmed.localizedCaseInsensitiveContains("<svg") else {
                return webPreviewMessageHTML("No SVG root element found.")
            }
            return svgPreviewHTML(from: trimmed)
        }
        guard !trimmed.isEmpty else {
            return webPreviewMessageHTML("No HTML content found.")
        }
        return htmlPreviewHTML(from: trimmed)
    }

    private func svgPreviewHTML(from source: String) -> String {
        return """
        <!doctype html>
        <html class="svg-preview">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(webPreviewCSPMeta)
        <style>
        html, body {
          margin: 0;
          width: 100%;
          height: 100%;
          background: transparent;
          color: CanvasText;
        }
        body {
          min-width: 0;
          min-height: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          box-sizing: border-box;
          padding: 16px;
          overflow: auto;
        }
        .svg-stage {
          width: 100%;
          height: 100%;
          min-width: 0;
          min-height: 0;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .svg-stage > svg {
          display: block;
          flex: 0 1 auto;
          width: 100% !important;
          height: 100% !important;
          max-width: 100%;
          max-height: 100%;
        }
        </style>
        </head>
        <body>
        <div class="svg-stage">
        \(source)
        </div>
        </body>
        </html>
        """
    }

    private func htmlPreviewHTML(from source: String) -> String {
        webPreviewSourceWithCSP(source)
    }

    private var webPreviewCSPMeta: String {
        """
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; font-src data:; media-src data: blob:;">
        """
    }

    private func webPreviewSourceWithCSP(_ source: String) -> String {
        if let headRange = source.range(of: "<head", options: [.caseInsensitive]),
           let headEnd = source[headRange.lowerBound...].firstIndex(of: ">") {
            var output = source
            output.insert(contentsOf: "\n\(webPreviewBaseStyle)\n\(webPreviewCSPMeta)", at: source.index(after: headEnd))
            return output
        }
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        \(webPreviewCSPMeta)
        \(webPreviewBaseStyle)
        </head>
        <body>
        \(source)
        </body>
        </html>
        """
    }

    private var webPreviewBaseStyle: String {
        """
        <style>
        html, body {
          margin: 0;
          width: 100%;
          min-height: 100vh;
          background: \(webPreviewCanvasBackgroundCSS);
          color: CanvasText;
        }
        body {
          box-sizing: border-box;
          overflow-wrap: anywhere;
        }
        </style>
        """
    }

    private var webPreviewCanvasBackgroundCSS: String {
        colorScheme == .dark
        ? "linear-gradient(45deg, #25272b 25%, transparent 25%), linear-gradient(-45deg, #25272b 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #25272b 75%), linear-gradient(-45deg, transparent 75%, #25272b 75%), #1b1d21"
        : "linear-gradient(45deg, #e8eaed 25%, transparent 25%), linear-gradient(-45deg, #e8eaed 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #e8eaed 75%), linear-gradient(-45deg, transparent 75%, #e8eaed 75%), #f8f9fb"
    }

    private func webPreviewMessageHTML(_ message: String) -> String {
        let escapedMessage = Self.webPreviewEscapedHTML(message)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline';">
        <style>
        html, body {
          margin: 0;
          width: 100%;
          height: 100%;
          display: grid;
          place-items: center;
          font: 13px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          color: #6b7280;
          background: transparent;
        }
        </style>
        </head>
        <body>\(escapedMessage)</body>
        </html>
        """
    }

    private static func webPreviewEscapedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

}
