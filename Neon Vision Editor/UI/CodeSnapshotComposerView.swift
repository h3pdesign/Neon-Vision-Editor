import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
#else
import UIKit
private typealias PlatformColor = UIColor
#endif

struct CodeSnapshotPayload: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let language: String
    let text: String
}

enum CodeSnapshotAppearance: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum CodeSnapshotBackgroundPreset: String, CaseIterable, Identifiable {
    case aurora
    case sunrise
    case ocean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .sunrise: return "Sunrise"
        case .ocean: return "Ocean"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .aurora:
            return LinearGradient(
                colors: [Color(red: 0.12, green: 0.20, blue: 0.52), Color(red: 0.00, green: 0.67, blue: 0.73), Color(red: 0.62, green: 0.20, blue: 0.87)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sunrise:
            return LinearGradient(
                colors: [Color(red: 0.98, green: 0.38, blue: 0.33), Color(red: 1.00, green: 0.64, blue: 0.28), Color(red: 0.96, green: 0.20, blue: 0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ocean:
            return LinearGradient(
                colors: [Color(red: 0.04, green: 0.22, blue: 0.42), Color(red: 0.06, green: 0.52, blue: 0.76), Color(red: 0.16, green: 0.78, blue: 0.80)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

enum CodeSnapshotFrameStyle: String, CaseIterable, Identifiable {
    case macWindow
    case clean
    case glow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macWindow: return "Window"
        case .clean: return "Clean"
        case .glow: return "Glow"
        }
    }
}

struct CodeSnapshotStyle: Equatable {
    var appearance: CodeSnapshotAppearance = .dark
    var backgroundPreset: CodeSnapshotBackgroundPreset = .sunrise
    var frameStyle: CodeSnapshotFrameStyle = .macWindow
    var showLineNumbers: Bool = true
    var padding: CGFloat = 26
}

struct PNGSnapshotDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum CodeSnapshotRenderer {
    static func attributedLines(
        text: String,
        language: String,
        appearance: CodeSnapshotAppearance
    ) -> [AttributedString] {
        let theme = currentEditorTheme(colorScheme: appearance.colorScheme)
        let colors = SyntaxColors(
            keyword: theme.syntax.keyword,
            string: theme.syntax.string,
            number: theme.syntax.number,
            comment: theme.syntax.comment,
            attribute: theme.syntax.attribute,
            variable: theme.syntax.variable,
            def: theme.syntax.def,
            property: theme.syntax.property,
            meta: theme.syntax.meta,
            tag: theme.syntax.tag,
            atom: theme.syntax.atom,
            builtin: theme.syntax.builtin,
            type: theme.syntax.type
        )
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: platformColor(theme.text),
                .font: snapshotFont()
            ]
        )

        let patterns = getSyntaxPatterns(for: language, colors: colors, profile: .full)
        for (pattern, color) in patterns {
            guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: platformColor(color)]
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }
                attributed.addAttributes(attributes, range: match.range)
            }
        }

        let nsAttributed = attributed
        let lines = nsText.components(separatedBy: "\n")
        var cursor = 0
        var output: [AttributedString] = []
        for (index, line) in lines.enumerated() {
            let lineLength = (line as NSString).length
            let range = NSRange(location: min(cursor, nsAttributed.length), length: min(lineLength, max(0, nsAttributed.length - cursor)))
            let attributedLine = range.length > 0
                ? nsAttributed.attributedSubstring(from: range)
                : NSAttributedString(string: "")
            output.append(AttributedString(attributedLine))
            cursor += lineLength
            if index < lines.count - 1 {
                cursor += 1
            }
        }

        return output
    }

    @MainActor
    static func pngData(
        payload: CodeSnapshotPayload,
        style: CodeSnapshotStyle
    ) -> Data? {
        let card = CodeSnapshotCardView(payload: payload, style: style)
            .frame(width: 940)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
#if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
#else
        return renderer.uiImage?.pngData()
#endif
    }

    private static func snapshotFont() -> PlatformFont {
#if os(macOS)
        return .monospacedSystemFont(ofSize: 15, weight: .regular)
#else
        return .monospacedSystemFont(ofSize: 15, weight: .regular)
#endif
    }

    private static func platformColor(_ color: Color) -> PlatformColor {
#if os(macOS)
        return PlatformColor(color)
#else
        return PlatformColor(color)
#endif
    }
}

#if os(macOS)
private typealias PlatformFont = NSFont
#else
private typealias PlatformFont = UIFont
#endif

private struct CodeSnapshotCardView: View {
    let payload: CodeSnapshotPayload
    let style: CodeSnapshotStyle

    private var lines: [AttributedString] {
        CodeSnapshotRenderer.attributedLines(
            text: payload.text,
            language: payload.language,
            appearance: style.appearance
        )
    }

    private var surfaceBackground: Color {
        switch style.appearance {
        case .dark:
            return Color(red: 0.09, green: 0.10, blue: 0.14)
        case .light:
            return Color.white.opacity(0.97)
        }
    }

    private var surfaceBorder: Color {
        switch style.appearance {
        case .dark:
            return Color.white.opacity(0.08)
        case .light:
            return Color.black.opacity(0.08)
        }
    }

    private var bodyTextColor: Color {
        switch style.appearance {
        case .dark:
            return Color.white.opacity(0.92)
        case .light:
            return Color.black.opacity(0.78)
        }
    }

    var body: some View {
        ZStack {
            style.backgroundPreset.gradient
            VStack(alignment: .leading, spacing: 0) {
                if style.frameStyle == .macWindow {
                    HStack(spacing: 8) {
                        Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.33)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 1.00, green: 0.76, blue: 0.20)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 0.18, green: 0.80, blue: 0.44)).frame(width: 12, height: 12)
                        Spacer()
                        Text(payload.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(bodyTextColor.opacity(0.74))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(surfaceBackground.opacity(style.appearance == .dark ? 0.96 : 0.92))
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 14) {
                            if style.showLineNumbers {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(bodyTextColor.opacity(0.42))
                                    .frame(width: 34, alignment: .trailing)
                                    .accessibilityHidden(true)
                            }
                            Text(line)
                                .font(.system(size: 15, weight: .regular, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(style.padding)
                .background(surfaceBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(surfaceBorder, lineWidth: 1)
            )
            .shadow(color: style.frameStyle == .glow ? Color.white.opacity(0.24) : Color.black.opacity(0.18), radius: style.frameStyle == .glow ? 26 : 16, y: 10)
            .padding(42)
        }
        .aspectRatio(1.25, contentMode: .fit)
    }
}

struct CodeSnapshotComposerView: View {
    let payload: CodeSnapshotPayload

    @Environment(\.dismiss) private var dismiss
    @State private var style = CodeSnapshotStyle()
    @State private var renderedPNGData: Data?
    @State private var shareURL: URL?
    @State private var showExporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                snapshotControls
                ScrollView([.vertical, .horizontal]) {
                    CodeSnapshotCardView(payload: payload, style: style)
                        .frame(maxWidth: 980)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 20)
                }
            }
            .padding(20)
            .navigationTitle("Code Snapshot")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        showExporter = true
                    } label: {
                        Label("Export PNG", systemImage: "photo")
                    }
                    .disabled(renderedPNGData == nil)
                }
            }
        }
        .task(id: style) {
            await refreshRenderedSnapshot()
        }
        .fileExporter(
            isPresented: $showExporter,
            document: PNGSnapshotDocument(data: renderedPNGData ?? Data()),
            contentType: .png,
            defaultFilename: sanitizedFileName
        ) { _ in }
    }

    private var snapshotControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Picker("Appearance", selection: $style.appearance) {
                    ForEach(CodeSnapshotAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                Picker("Background", selection: $style.backgroundPreset) {
                    ForEach(CodeSnapshotBackgroundPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Picker("Frame", selection: $style.frameStyle) {
                    ForEach(CodeSnapshotFrameStyle.allCases) { frame in
                        Text(frame.title).tag(frame)
                    }
                }
                Toggle("Line Numbers", isOn: $style.showLineNumbers)
            }

            HStack(spacing: 12) {
                Text("Padding")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Slider(value: $style.padding, in: 18...40, step: 2)
                Text("\(Int(style.padding))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @MainActor
    private func refreshRenderedSnapshot() async {
        let data = CodeSnapshotRenderer.pngData(payload: payload, style: style)
        renderedPNGData = data
        guard let data else {
            shareURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedFileName).png")
        do {
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            shareURL = nil
        }
    }

    private var sanitizedFileName: String {
        let base = payload.title.replacingOccurrences(of: " ", with: "-")
        return base.isEmpty ? "code-snapshot" : base
    }
}
