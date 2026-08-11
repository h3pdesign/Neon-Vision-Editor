//
//  EditorView.swift
//  SyntaxQuicklook
//
//  Quick Look code preview backed by AppKit's text system.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    let text: String
    let contentType: UTType
    let fileExtension: String
    let fileName: String
    let theme: EditorTheme
    let isTruncated: Bool

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(
                fileName: fileName,
                fileExtension: fileExtension,
                isTruncated: isTruncated,
                theme: theme
            )

            CodePreviewView(
                text: text,
                contentType: contentType,
                fileExtension: fileExtension,
                theme: theme
            )
        }
        .background(theme.background)
    }
}

private struct PreviewHeader: View {
    let fileName: String
    let fileExtension: String
    let isTruncated: Bool
    let theme: EditorTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(theme.accent)

            Text(fileName.isEmpty ? "Text Preview" : fileName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            if !fileExtension.isEmpty {
                Text(fileExtension.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.lineNumberForeground)
            }

            Spacer(minLength: 8)

            if isTruncated {
                Label("Preview truncated", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.number)
                    .accessibilityLabel("Preview truncated because the file is large")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(theme.lineNumberBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.accent.opacity(0.25))
                .frame(height: 1)
        }
    }
}

private struct CodePreviewView: NSViewRepresentable {
    let text: String
    let contentType: UTType
    let fileExtension: String
    let theme: EditorTheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        // Quick Look should use the available preview width instead of forcing
        // a second scroll axis for long source lines.
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 8
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        scrollView.documentView = textView
        let ruler = LineNumberRulerView(scrollView: scrollView, textView: textView, theme: theme)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        apply(
            to: textView,
            in: scrollView,
            ruler: ruler,
            coordinator: context.coordinator
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let ruler = scrollView.verticalRulerView as? LineNumberRulerView else { return }
        ruler.theme = theme
        apply(to: textView, in: scrollView, ruler: ruler, coordinator: context.coordinator)
    }

    private func apply(
        to textView: NSTextView,
        in scrollView: NSScrollView,
        ruler: LineNumberRulerView,
        coordinator: Coordinator
    ) {
        let key = PreviewContentKey(text: text, extension: fileExtension, type: contentType.identifier)
        if coordinator.lastContentKey != key {
            textView.textStorage?.setAttributedString(
                makeAttributedString()
            )
            coordinator.lastContentKey = key
        }

        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            let viewportSize = scrollView.contentView.bounds.size
            let availableWidth = max(1, viewportSize.width)
            if abs(textView.frame.width - availableWidth) > 0.5 {
                textView.setFrameSize(NSSize(width: availableWidth, height: textView.frame.height))
            }
            let usedRect = layoutManager.usedRect(for: textContainer)
            let documentSize = NSSize(
                width: availableWidth,
                height: max(viewportSize.height, ceil(usedRect.maxY) + 16)
            )
            if textView.frame.size != documentSize {
                textView.setFrameSize(documentSize)
            }
        }

        textView.needsDisplay = true
        ruler.needsDisplay = true
    }

    private func makeAttributedString() -> NSAttributedString {
        let highlighter = SyntaxHighlighter()
        let tokens = highlighter.highlight(
            text,
            contentType: contentType,
            fileExtension: fileExtension
        )
        let result = NSMutableAttributedString(string: text)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        result.addAttributes([
            .font: font,
            .foregroundColor: NSColor(theme.text)
        ], range: NSRange(location: 0, length: result.length))

        for token in tokens {
            let nsRange = NSRange(token.range, in: text)
            let color: NSColor
            switch token.kind {
            case .keyword: color = NSColor(theme.keyword)
            case .type: color = NSColor(theme.type)
            case .string: color = NSColor(theme.string)
            case .number: color = NSColor(theme.number)
            case .comment: color = NSColor(theme.comment)
            case .punctuation: color = NSColor(theme.punctuation)
            case .plain: color = NSColor(theme.text)
            }
            result.addAttribute(.foregroundColor, value: color, range: nsRange)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = theme.lineHeight
        paragraph.maximumLineHeight = theme.lineHeight
        // Character wrapping guarantees that narrow Quick Look windows never
        // grow a horizontal scroll view for a single long source line.
        paragraph.lineBreakMode = .byCharWrapping
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    final class Coordinator {
        var lastContentKey: PreviewContentKey?
    }
}

private struct PreviewContentKey: Equatable {
    let text: String
    let `extension`: String
    let type: String
}

private final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var theme: EditorTheme

    init(scrollView: NSScrollView, textView: NSTextView, theme: EditorTheme) {
        self.textView = textView
        self.theme = theme
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 56
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSColor(theme.lineNumberBackground).setFill()
        rect.fill()

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let text = textView.string as NSString
        let baseLine = text.substring(to: min(visibleCharacterRange.location, text.length))
            .reduce(into: 1) { count, character in
                if character == "\n" { count += 1 }
            }

        var lineNumber = baseLine
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            let y = rect.minY + textView.textContainerInset.height - visibleRect.minY
            let label = "\(lineNumber)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(self.theme.lineNumberForeground)
            ]
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: self.ruleThickness - size.width - 8, y: y), withAttributes: attributes)
            lineNumber += 1
        }
    }
}
