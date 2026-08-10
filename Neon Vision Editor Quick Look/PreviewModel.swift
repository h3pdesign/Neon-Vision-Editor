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
    var fileName: String = ""
    var isTruncated: Bool = false
}

struct EditorTheme {
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

    static var neonDark: EditorTheme {
        EditorTheme(
            background: Color(red: 0.06, green: 0.07, blue: 0.10),
            lineNumberBackground: Color(red: 0.08, green: 0.09, blue: 0.12),
            lineNumberForeground: Color.gray.opacity(0.7),
            text: .white.opacity(0.92),
            keyword: Color(red: 0.56, green: 0.77, blue: 1.0),
            type: Color(red: 0.72, green: 0.64, blue: 1.0),
            string: Color(red: 0.60, green: 1.0, blue: 0.74),
            number: Color(red: 1.0, green: 0.78, blue: 0.47),
            comment: Color.gray,
            punctuation: Color.white.opacity(0.8),
            accent: Color(red: 0.25, green: 0.85, blue: 0.90),
            font: .system(.body, design: .monospaced),
            lineHeight: 20
        )
    }
}

struct PreviewRootView: View {
    let model: PreviewModel

    var body: some View {
        EditorView(
            text: model.text,
            contentType: model.contentType,
            fileExtension: model.fileExtension,
            fileName: model.fileName,
            theme: .neonDark,
            isTruncated: model.isTruncated
        )
        .background(EditorTheme.neonDark.background)
    }
}
