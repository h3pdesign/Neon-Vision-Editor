//
//  PreviewModel.swift
//  SyntaxQuicklook
//
//  Created by Hilthart Pedersen on 30.01.26.
//


// PreviewRootView.swift
// SwiftUI root view and theming for Quick Look preview

import SwiftUI
import UniformTypeIdentifiers

struct PreviewModel {
    let text: String
    let contentType: UTType
    var fileExtension: String = ""
    var isTruncated: Bool = false
}

struct EditorTheme {
    let identifier: String
    var background: Color
    var lineNumberBackground: Color
    var lineNumberForeground: Color
    var text: Color
    var keyword: Color
    var type: Color
    var string: Color
    var number: Color
    var comment: Color
    var punctuation: Color
    var accent: Color
    var font: Font
    var lineHeight: CGFloat

    static func neon(for colorScheme: ColorScheme) -> EditorTheme {
        if colorScheme == .dark {
            return EditorTheme(
                identifier: "dark",
                background: .clear,
                lineNumberBackground: Color.white.opacity(0.10),
                lineNumberForeground: Color.gray.opacity(0.7),
                text: .white.opacity(0.92),
                keyword: Color(red: 0.56, green: 0.77, blue: 1.0),
                type: Color(red: 0.72, green: 0.64, blue: 1.0),
                string: Color(red: 0.60, green: 1.0, blue: 0.74),
                number: Color(red: 1.0, green: 0.78, blue: 0.47),
                comment: Color.gray,
                punctuation: Color.white.opacity(0.8),
                accent: Color(red: 0.25, green: 0.85, blue: 0.90),
                font: .system(size: 10, design: .monospaced),
                lineHeight: 14
            )
        }

        return EditorTheme(
            identifier: "light",
            background: .clear,
            lineNumberBackground: Color.black.opacity(0.08),
            lineNumberForeground: Color(red: 0.34, green: 0.39, blue: 0.46),
            text: Color(red: 0.09, green: 0.11, blue: 0.15),
            keyword: Color(red: 0.48, green: 0.16, blue: 0.72),
            type: Color(red: 0.05, green: 0.36, blue: 0.72),
            string: Color(red: 0.05, green: 0.47, blue: 0.25),
            number: Color(red: 0.67, green: 0.34, blue: 0.04),
            comment: Color(red: 0.34, green: 0.39, blue: 0.46),
            punctuation: Color(red: 0.25, green: 0.29, blue: 0.36),
            accent: Color(red: 0.0, green: 0.42, blue: 0.84),
            font: .system(size: 10, design: .monospaced),
            lineHeight: 14
        )
    }
}

struct PreviewRootView: View {
    let model: PreviewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = EditorTheme.neon(for: colorScheme)
        Group {
            if isMarkdownDocument {
                MarkdownQuickLookView(model: model, theme: theme)
            } else {
                EditorView(
                    text: model.text,
                    contentType: model.contentType,
                    fileExtension: model.fileExtension,
                    theme: theme,
                    isTruncated: model.isTruncated
                )
            }
        }
        .background(theme.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isMarkdownDocument: Bool {
        let markdownType = UTType(importedAs: "net.daringfireball.markdown")
        return model.contentType.conforms(to: markdownType)
            || ["md", "markdown", "mdown", "mkdn"].contains(model.fileExtension.lowercased())
    }
}
