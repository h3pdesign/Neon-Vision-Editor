import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
private typealias SnapshotPreviewImage = NSImage
#else
import UIKit
private typealias PlatformColor = UIColor
private typealias SnapshotPreviewImage = UIImage
#endif

// MARK: - Snapshot Models

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

enum CodeSnapshotTheme: String, CaseIterable, Identifiable, Hashable {
    case midnight
    case nord
    case solarized
    case paper
    case rose
    case dracula
    case tokyoNight
    case monokai
    case githubDark
    case xcodeLight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .nord: return "Nord"
        case .solarized: return "Solarized"
        case .paper: return "Paper"
        case .rose: return "Rose"
        case .dracula: return "Dracula"
        case .tokyoNight: return "Tokyo Night"
        case .monokai: return "Monokai"
        case .githubDark: return "GitHub Dark"
        case .xcodeLight: return "Xcode Light"
        }
    }

    var appearance: CodeSnapshotAppearance {
        switch self {
        case .paper, .xcodeLight: return .light
        default: return .dark
        }
    }

    var surface: Color {
        switch self {
        case .midnight: return Color(red: 0.055, green: 0.065, blue: 0.105)
        case .nord: return Color(red: 0.118, green: 0.145, blue: 0.192)
        case .solarized: return Color(red: 0.000, green: 0.169, blue: 0.212)
        case .paper: return Color(red: 0.975, green: 0.965, blue: 0.925)
        case .rose: return Color(red: 0.105, green: 0.070, blue: 0.105)
        case .dracula: return Color(red: 0.157, green: 0.165, blue: 0.212)
        case .tokyoNight: return Color(red: 0.102, green: 0.110, blue: 0.176)
        case .monokai: return Color(red: 0.153, green: 0.157, blue: 0.133)
        case .githubDark: return Color(red: 0.051, green: 0.067, blue: 0.090)
        case .xcodeLight: return Color(red: 0.969, green: 0.969, blue: 0.980)
        }
    }

    var text: Color {
        appearance == .light ? Color(red: 0.16, green: 0.17, blue: 0.20) : Color.white.opacity(0.92)
    }

    var accent: Color {
        switch self {
        case .midnight: return Color(red: 0.31, green: 0.72, blue: 1.00)
        case .nord: return Color(red: 0.53, green: 0.75, blue: 0.82)
        case .solarized: return Color(red: 0.71, green: 0.54, blue: 0.00)
        case .paper: return Color(red: 0.10, green: 0.36, blue: 0.78)
        case .rose: return Color(red: 1.00, green: 0.48, blue: 0.66)
        case .dracula: return Color(red: 0.74, green: 0.58, blue: 0.98)
        case .tokyoNight: return Color(red: 0.48, green: 0.67, blue: 1.00)
        case .monokai: return Color(red: 0.65, green: 0.89, blue: 0.18)
        case .githubDark: return Color(red: 0.35, green: 0.65, blue: 0.98)
        case .xcodeLight: return Color(red: 0.00, green: 0.48, blue: 1.00)
        }
    }

    var syntaxColors: SyntaxColors {
        let keyword: Color
        let string: Color
        let number: Color
        let comment: Color
        let type: Color
        switch self {
        case .midnight:
            (keyword, string, number, comment, type) = (.pink, .mint, .orange, .gray, .cyan)
        case .nord:
            (keyword, string, number, comment, type) = (Color(red: 0.71, green: 0.56, blue: 0.68), Color(red: 0.64, green: 0.75, blue: 0.55), Color(red: 0.82, green: 0.53, blue: 0.44), Color(red: 0.38, green: 0.45, blue: 0.55), Color(red: 0.53, green: 0.75, blue: 0.82))
        case .solarized:
            (keyword, string, number, comment, type) = (Color(red: 0.83, green: 0.21, blue: 0.51), Color(red: 0.52, green: 0.60, blue: 0.00), Color(red: 0.80, green: 0.29, blue: 0.09), Color(red: 0.35, green: 0.43, blue: 0.46), Color(red: 0.15, green: 0.55, blue: 0.82))
        case .paper:
            (keyword, string, number, comment, type) = (Color(red: 0.55, green: 0.12, blue: 0.38), Color(red: 0.10, green: 0.46, blue: 0.24), Color(red: 0.78, green: 0.30, blue: 0.08), Color(red: 0.46, green: 0.47, blue: 0.49), Color(red: 0.10, green: 0.36, blue: 0.78))
        case .rose:
            (keyword, string, number, comment, type) = (Color(red: 1.00, green: 0.45, blue: 0.70), Color(red: 0.55, green: 0.91, blue: 0.72), Color(red: 1.00, green: 0.72, blue: 0.39), Color(red: 0.57, green: 0.48, blue: 0.58), Color(red: 0.73, green: 0.63, blue: 1.00))
        case .dracula:
            (keyword, string, number, comment, type) = (Color(red: 1.00, green: 0.47, blue: 0.78), Color(red: 0.95, green: 0.98, blue: 0.55), Color(red: 0.74, green: 0.58, blue: 0.98), Color(red: 0.38, green: 0.45, blue: 0.64), Color(red: 0.55, green: 0.91, blue: 0.99))
        case .tokyoNight:
            (keyword, string, number, comment, type) = (Color(red: 0.73, green: 0.48, blue: 1.00), Color(red: 0.62, green: 0.82, blue: 0.42), Color(red: 1.00, green: 0.62, blue: 0.38), Color(red: 0.34, green: 0.39, blue: 0.58), Color(red: 0.49, green: 0.76, blue: 1.00))
        case .monokai:
            (keyword, string, number, comment, type) = (Color(red: 0.98, green: 0.15, blue: 0.45), Color(red: 0.90, green: 0.86, blue: 0.45), Color(red: 0.68, green: 0.51, blue: 1.00), Color(red: 0.46, green: 0.44, blue: 0.38), Color(red: 0.40, green: 0.85, blue: 0.94))
        case .githubDark:
            (keyword, string, number, comment, type) = (Color(red: 1.00, green: 0.48, blue: 0.56), Color(red: 0.65, green: 0.80, blue: 0.96), Color(red: 0.47, green: 0.65, blue: 1.00), Color(red: 0.55, green: 0.60, blue: 0.66), Color(red: 1.00, green: 0.65, blue: 0.40))
        case .xcodeLight:
            (keyword, string, number, comment, type) = (Color(red: 0.62, green: 0.00, blue: 0.65), Color(red: 0.77, green: 0.10, blue: 0.09), Color(red: 0.11, green: 0.00, blue: 0.81), Color(red: 0.25, green: 0.50, blue: 0.25), Color(red: 0.15, green: 0.35, blue: 0.55))
        }
        return SyntaxColors(
            keyword: keyword,
            string: string,
            number: number,
            comment: comment,
            attribute: type,
            variable: text,
            def: accent,
            property: type,
            meta: keyword,
            tag: keyword,
            atom: number,
            builtin: accent,
            type: type
        )
    }
}

enum CodeSnapshotBackgroundPreset: String, CaseIterable, Identifiable, Hashable {
    case aurora
    case sunrise
    case ocean
    case graphite
    case transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .sunrise: return "Sunrise"
        case .ocean: return "Ocean"
        case .graphite: return "Graphite"
        case .transparent: return "Transparent"
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
        case .graphite:
            return LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.10), Color(red: 0.20, green: 0.22, blue: 0.27)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .transparent:
            return LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
        }
    }
}

enum CodeSnapshotFrameStyle: String, CaseIterable, Identifiable, Hashable {
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

enum CodeSnapshotSizePreset: String, CaseIterable, Identifiable, Hashable {
    case fit
    case square
    case classic
    case widescreen
    case portrait
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: return "Fit Content"
        case .square: return "1:1 Square"
        case .classic: return "4:3 Classic"
        case .widescreen: return "16:9 Wide"
        case .portrait: return "9:16 Story"
        case .custom: return "Custom"
        }
    }
}

struct CodeSnapshotStyle: Equatable, Hashable {
    var theme: CodeSnapshotTheme = .midnight
    var backgroundPreset: CodeSnapshotBackgroundPreset = .sunrise
    var frameStyle: CodeSnapshotFrameStyle = .macWindow
    var sizePreset: CodeSnapshotSizePreset = .fit
    var showLineNumbers: Bool = true
    var lineWrap: Bool = true
    var showTrafficLights: Bool = true
    var showTitle: Bool = true
    var fontSize: CGFloat = 15
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 28
    var customCardWidth: CGFloat = 1200
    var customCardHeight: CGFloat = 900

    static let defaultInitialStyle = CodeSnapshotStyle()
}

enum CodeSnapshotSizing {
    static func dimensions(payload: CodeSnapshotPayload, style: CodeSnapshotStyle) -> CGSize {
        switch style.sizePreset {
        case .square:
            return CGSize(width: 1200, height: 1200)
        case .classic:
            return CGSize(width: 1200, height: 900)
        case .widescreen:
            return CGSize(width: 1600, height: 900)
        case .portrait:
            return CGSize(width: 1080, height: 1920)
        case .custom:
            return CGSize(
                width: min(max(480, style.customCardWidth), 2400),
                height: min(max(360, style.customCardHeight), 3200)
            )
        case .fit:
            let lines = payload.text.components(separatedBy: "\n")
            let longestLine = lines.map(\.count).max() ?? 0
            let lineNumberWidth: CGFloat = style.showLineNumbers ? 64 : 0
            let characterWidth = max(6, style.fontSize * 0.60)
            let width = min(max(720, CGFloat(longestLine) * characterWidth + lineNumberWidth + (style.padding * 2) + 150), 1800)
            let headerHeight: CGFloat = style.frameStyle == .macWindow ? 54 : 0
            let lineHeight = max(18, style.fontSize * 1.55)
            let wrapWidth = max(1, Int((width - lineNumberWidth - (style.padding * 2) - 150) / characterWidth))
            let renderedLineCount = style.lineWrap
                ? lines.reduce(0) { $0 + max(1, ($1.count + wrapWidth - 1) / wrapWidth) }
                : lines.count
            let height = min(max(420, CGFloat(max(1, renderedLineCount)) * lineHeight + headerHeight + (style.padding * 2) + 112), 3200)
            return CGSize(width: width.rounded(.up), height: height.rounded(.up))
        }
    }
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

// MARK: - Snapshot Rendering

private enum CodeSnapshotRenderer {
    static func attributedLines(
        text: String,
        language: String,
        theme: CodeSnapshotTheme
    ) -> [AttributedString] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: platformColor(theme.text),
                .font: snapshotFont()
            ]
        )

        let patterns = getSyntaxPatterns(for: language, colors: theme.syntaxColors, profile: .full)
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
        let dimensions = CodeSnapshotSizing.dimensions(payload: payload, style: style)
        let card = CodeSnapshotCardView(
            payload: payload,
            style: style,
            cardWidth: dimensions.width,
            cardHeight: dimensions.height
        )
        .frame(width: dimensions.width, height: dimensions.height)
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

// MARK: - Snapshot Preview Card

private struct CodeSnapshotCardView: View {
    let payload: CodeSnapshotPayload
    let style: CodeSnapshotStyle
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    private let outerCanvasInset: CGFloat = 56

    private var lines: [AttributedString] {
        CodeSnapshotRenderer.attributedLines(
            text: payload.text,
            language: payload.language,
            theme: style.theme
        )
    }

    private var surfaceBackground: Color {
        style.theme.surface
    }

    private var surfaceBorder: Color {
        style.theme.appearance == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private var bodyTextColor: Color {
        style.theme.text
    }

    private var longestLineLength: Int {
        payload.text
            .components(separatedBy: "\n")
            .map(\.count)
            .max() ?? 0
    }

    private var codeFontSize: CGFloat {
        let maxLineLength = max(1, longestLineLength)
        let lineCount = max(1, lines.count)
        let lineNumberWidth: CGFloat = style.showLineNumbers ? 48 : 0
        let availableCodeWidth = max(220, cardWidth - (outerCanvasInset * 2) - (style.padding * 2) - lineNumberWidth)
        let headerHeight: CGFloat = style.frameStyle == .macWindow ? 54 : 0
        let availableCodeHeight = max(180, cardHeight - (outerCanvasInset * 2) - (style.padding * 2) - headerHeight)
        let estimatedCharacterWidth = style.fontSize * 0.60
        let widthScale = availableCodeWidth / (CGFloat(maxLineLength) * estimatedCharacterWidth)
        let heightScale = availableCodeHeight / (CGFloat(lineCount) * style.fontSize * 1.55)
        let fitted = style.fontSize * min(1, widthScale, heightScale)
        return max(8, min(style.fontSize, fitted))
    }

    @ViewBuilder
    var body: some View {
        let card = ZStack {
            style.backgroundPreset.gradient
            VStack(alignment: .leading, spacing: 0) {
                if style.frameStyle == .macWindow {
                    HStack(spacing: 8) {
                        if style.showTrafficLights {
                            Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.33)).frame(width: 12, height: 12)
                            Circle().fill(Color(red: 1.00, green: 0.76, blue: 0.20)).frame(width: 12, height: 12)
                            Circle().fill(Color(red: 0.18, green: 0.80, blue: 0.44)).frame(width: 12, height: 12)
                        }
                        Spacer()
                        if style.showTitle {
                            Text(payload.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(bodyTextColor.opacity(0.74))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(surfaceBackground.opacity(style.theme.appearance == .dark ? 0.96 : 0.94))
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
                                .font(.system(size: codeFontSize, weight: .regular, design: .monospaced))
                                .lineLimit(style.lineWrap ? nil : 1)
                                .minimumScaleFactor(0.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(style.padding)
                .background(surfaceBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .stroke(surfaceBorder, lineWidth: 1)
            )
            .shadow(color: style.frameStyle == .glow ? Color.white.opacity(0.24) : Color.black.opacity(0.18), radius: style.frameStyle == .glow ? 26 : 16, y: 10)
            .padding(outerCanvasInset)
        }
        card
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
    }
}

// MARK: - Snapshot Composer UI

struct CodeSnapshotComposerView: View {
    let payload: CodeSnapshotPayload

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("EnableTranslucentWindow") private var translucentWindow = true
#else
    @AppStorage("EnableTranslucentWindow") private var translucentWindow = false
#endif
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw = "balanced"
#endif
    @State private var style: CodeSnapshotStyle
    @State private var sourceText: String
    @State private var renderedPNGData: Data?
    @State private var renderedPreviewImage: SnapshotPreviewImage?
    @State private var shareURL: URL?
    @State private var showExporter = false
    @State private var didCopySnapshot = false
#if !os(macOS)
    @State private var showsMobilePreview = true
#endif

    private var surfaceBackground: Color {
        currentEditorTheme(colorScheme: colorScheme).background
    }

    private var usesTranslucentSurface: Bool {
        translucentWindow && !reduceTransparency
    }

    private var composerSurfaceStyle: AnyShapeStyle {
#if os(macOS)
        guard usesTranslucentSurface else { return AnyShapeStyle(surfaceBackground) }
        switch macTranslucencyModeRaw {
        case "subtle":
            return AnyShapeStyle(.thickMaterial.opacity(0.92))
        case "vibrant":
            return AnyShapeStyle(.regularMaterial.opacity(0.84))
        default:
            return AnyShapeStyle(.thickMaterial.opacity(0.88))
        }
#else
        return usesTranslucentSurface
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(surfaceBackground)
#endif
    }

    private var settingsSurfaceStyle: AnyShapeStyle {
        usesTranslucentSurface
            ? AnyShapeStyle(.regularMaterial)
            : AnyShapeStyle(surfaceBackground.opacity(0.96))
    }

    init(payload: CodeSnapshotPayload) {
        self.payload = payload
        _style = State(initialValue: CodeSnapshotStyle.defaultInitialStyle)
        _sourceText = State(initialValue: payload.text)
    }

    var body: some View {
        Group {
#if os(macOS)
            macSnapshotStudio
#else
            touchSnapshotStudio
#endif
        }
        .background(composerSurfaceStyle)
        .presentationBackground(composerSurfaceStyle)
#if os(macOS)
        .modifier(MacToolbarVisibilityModifier())
        .frame(minWidth: 1080, minHeight: 720)
#else
        .toolbarBackground(composerSurfaceStyle, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .presentationDetents(usesCompactScrollingLayout ? [.large] : [.fraction(0.96), .large])
        .presentationDragIndicator(.visible)
#endif
        .task(id: renderKey) {
            await refreshRenderedSnapshot()
        }
        .fileExporter(
            isPresented: $showExporter,
            document: PNGSnapshotDocument(data: renderedPNGData ?? Data()),
            contentType: .png,
            defaultFilename: snapshotPNGFileName
        ) { _ in }
    }

    private struct RenderKey: Hashable {
        let style: CodeSnapshotStyle
        let text: String
    }

    private var renderKey: RenderKey {
        RenderKey(style: style, text: sourceText)
    }

    private var renderPayload: CodeSnapshotPayload {
        CodeSnapshotPayload(title: payload.title, language: payload.language, text: sourceText)
    }

#if os(macOS)
    private var macSnapshotStudio: some View {
        HSplitView {
            snapshotInspector
                .frame(minWidth: 276, idealWidth: 300, maxWidth: 324)
            VStack(spacing: 0) {
                studioToolbar
                Divider().overlay(Color.primary.opacity(0.08))
                previewWorkspace
                Divider().overlay(Color.primary.opacity(0.08))
                sourceEditor
                    .frame(minHeight: 150, idealHeight: 190, maxHeight: 260)
            }
            .background(surfaceBackground)
        }
        .background(surfaceBackground)
    }

    private var snapshotInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                inspectorSection("Theme") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(CodeSnapshotTheme.allCases) { theme in
                            Button {
                                style.theme = theme
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(LinearGradient(colors: [theme.surface, theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(height: 42)
                                        .overlay {
                                            if style.theme == theme {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(Color.accentColor, lineWidth: 2)
                                            }
                                        }
                                    Text(theme.title)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(style.theme == theme ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                inspectorSection("Background") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(CodeSnapshotBackgroundPreset.allCases) { preset in
                            Button {
                                style.backgroundPreset = preset
                            } label: {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(preset.gradient)
                                    .frame(height: 34)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(style.backgroundPreset == preset ? Color.accentColor : Color.white.opacity(0.12), lineWidth: style.backgroundPreset == preset ? 2 : 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(preset.title)
                        }
                    }
                }

                inspectorSection("Typography") {
                    inspectorSlider("Font Size", value: $style.fontSize, range: 11...24, step: 1, unit: "pt")
                    inspectorToggle("Line Numbers", isOn: $style.showLineNumbers)
                }

                inspectorSection("Window") {
                    inspectorPicker("Frame", selection: $style.frameStyle, values: CodeSnapshotFrameStyle.allCases)
                    inspectorToggle("Traffic Lights", isOn: $style.showTrafficLights)
                        .disabled(style.frameStyle != .macWindow)
                    inspectorToggle("Title", isOn: $style.showTitle)
                        .disabled(style.frameStyle != .macWindow)
                    inspectorSlider("Corners", value: $style.cornerRadius, range: 6...30, step: 1, unit: "pt")
                    inspectorSlider("Padding", value: $style.padding, range: 16...56, step: 1, unit: "pt")
                }

                inspectorSection("Canvas") {
                    inspectorPicker("Size", selection: $style.sizePreset, values: CodeSnapshotSizePreset.allCases)
                    if style.sizePreset == .custom {
                        inspectorSlider("Width", value: $style.customCardWidth, range: 480...2400, step: 20, unit: "px")
                        inspectorSlider("Height", value: $style.customCardHeight, range: 360...3200, step: 20, unit: "px")
                    }
                }
            }
            .padding(16)
        }
        .background(surfaceBackground)
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12, weight: .medium))
    }

    private func inspectorSlider(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        unit: String
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
    }

    private func inspectorPicker<Value: Hashable & Identifiable>(
        _ title: String,
        selection: Binding<Value>,
        values: [Value]
    ) -> some View where Value.ID == String {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values) { value in
                    Text(snapshotPickerTitle(value)).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 132)
        }
    }

    private func snapshotPickerTitle<Value>(_ value: Value) -> String {
        if let value = value as? CodeSnapshotFrameStyle { return value.title }
        if let value = value as? CodeSnapshotSizePreset { return value.title }
        return String(describing: value)
    }

    private var studioToolbar: some View {
        HStack(spacing: 10) {
            Text("Code Snapshot")
                .font(.headline.weight(.semibold))
            Text(dimensionLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if let shareURL {
                ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Share Snapshot")
            }
            Button(action: copySnapshotToClipboard) {
                Label(didCopySnapshot ? "Copied" : "Copy", systemImage: didCopySnapshot ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .tint(style.theme.accent)
            .disabled(renderedPNGData == nil)
            Button("Save") { showExporter = true }
                .buttonStyle(.bordered)
                .disabled(renderedPNGData == nil)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(surfaceBackground)
    }

    private var previewWorkspace: some View {
        ZStack {
            surfaceBackground
            fittedSnapshotPreview
                .padding(34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SOURCE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(payload.language.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color.primary.opacity(0.04))
            TextEditor(text: $sourceText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(surfaceBackground)
        }
    }
#endif

#if !os(macOS)
    private var touchSnapshotStudio: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    snapshotControls(useCompactLayout: true)
                    if showsMobilePreview {
                        mobileSnapshotPreview
                    }
                    snapshotActionBar(compact: true)
                }
                .padding(16)
            }
            .navigationTitle("Code Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsMobilePreview.toggle()
                        }
                    } label: {
                        Label(showsMobilePreview ? "Hide Preview" : "Preview", systemImage: showsMobilePreview ? "eye.slash" : "eye")
                    }
                }
            }
        }
    }

    private var mobileSnapshotPreview: some View {
        fittedSnapshotPreview
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(surfaceBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
            .animation(.easeInOut(duration: 0.2), value: previewAspectRatio)
    }
#endif

    private var usesCompactScrollingLayout: Bool {
#if os(iOS)
        return horizontalSizeClass == .compact
#else
        return false
#endif
    }

    @ViewBuilder
    private func snapshotControls(useCompactLayout: Bool) -> some View {
        if useCompactLayout {
            compactIPadSnapshotControls
        } else {
            standardSnapshotControls
        }
    }

    @ViewBuilder
    private var fittedSnapshotPreview: some View {
        Group {
#if os(macOS)
            if let renderedPreviewImage {
                Image(nsImage: renderedPreviewImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityLabel("Snapshot preview")
            } else {
                ProgressView("Preparing Snapshot Preview")
            }
#else
            if let renderedPreviewImage {
                Image(uiImage: renderedPreviewImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityLabel("Snapshot preview")
            } else {
                ProgressView("Preparing Snapshot Preview")
            }
#endif
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, 12)
    }

    private var compactIPadSnapshotControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Snapshot style", systemImage: "slider.horizontal.3")
                .font(.headline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                    compactSnapshotMenu("Theme") {
                        Picker("Theme", selection: $style.theme) {
                            ForEach(CodeSnapshotTheme.allCases) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                    }
                    compactSnapshotMenu("Background") {
                        Picker("Background", selection: $style.backgroundPreset) {
                            ForEach(CodeSnapshotBackgroundPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                    }
                    compactSnapshotMenu("Frame") {
                        Picker("Frame", selection: $style.frameStyle) {
                            ForEach(CodeSnapshotFrameStyle.allCases) { frame in
                                Text(frame.title).tag(frame)
                            }
                        }
                    }
                    compactSnapshotMenu("Size") {
                        Picker("Size", selection: $style.sizePreset) {
                            ForEach(CodeSnapshotSizePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                    }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                Toggle("Line Numbers", isOn: $style.showLineNumbers)
                Toggle("Line Wrap", isOn: $style.lineWrap)
                Toggle("Traffic Lights", isOn: $style.showTrafficLights)
                    .disabled(style.frameStyle != .macWindow)
                Toggle("Title", isOn: $style.showTitle)
                    .disabled(style.frameStyle != .macWindow)
            }
            .font(.subheadline.weight(.medium))

            compactSnapshotSlider("Font Size", value: $style.fontSize, range: 10...24, step: 1, unit: "pt")
            compactSnapshotSlider("Corners", value: $style.cornerRadius, range: 0...32, step: 1, unit: "pt")
            compactSnapshotSlider("Padding", value: $style.padding, range: 16...56, step: 1, unit: "pt")

            if style.sizePreset == .custom {
                compactSnapshotSlider("Width", value: $style.customCardWidth, range: 480...2400, step: 20, unit: "px")
                compactSnapshotSlider("Height", value: $style.customCardHeight, range: 360...3200, step: 20, unit: "px")
            }
        }
        .padding(14)
        .background(settingsSurfaceStyle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
    }

    private var standardSnapshotControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Snapshot style", systemImage: "slider.horizontal.3")
                    .font(.headline.weight(.semibold))
                Text("Choose how the exported image is presented.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 10) {
                snapshotMenuRow("Theme") {
                    Picker("Theme", selection: $style.theme) {
                        ForEach(CodeSnapshotTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                }

                snapshotMenuRow("Background") {
                    Picker("Background", selection: $style.backgroundPreset) {
                        ForEach(CodeSnapshotBackgroundPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                }

                snapshotMenuRow("Frame") {
                    Picker("Frame", selection: $style.frameStyle) {
                        ForEach(CodeSnapshotFrameStyle.allCases) { frame in
                            Text(frame.title).tag(frame)
                        }
                    }
                }

                snapshotMenuRow("Size") {
                    Picker("Size", selection: $style.sizePreset) {
                        ForEach(CodeSnapshotSizePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                }

                snapshotToggleRow("Line Numbers", isOn: $style.showLineNumbers)
            }

            Divider()

            VStack(spacing: 10) {
                snapshotSliderRow("Padding", value: $style.padding, range: 16...56, step: 1, unit: "pt")

                if style.sizePreset == .custom {
                    snapshotSliderRow("Width", value: $style.customCardWidth, range: 200...2200, step: 20, unit: "px")
                    snapshotSliderRow("Height", value: $style.customCardHeight, range: 560...1800, step: 20, unit: "px")
                }
            }
        }
        .padding(20)
        .background(settingsSurfaceStyle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
    }

    // MARK: - Snapshot Control Rows and Actions

    @ViewBuilder
    private func compactSnapshotMenu<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .neonSettingsDropdown(maxWidth: nil)
                .accessibilityLabel(title)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func compactSnapshotSlider(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func snapshotMenuRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)

            content()
                .neonSettingsDropdown(maxWidth: nil)
                .accessibilityLabel(title)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func snapshotToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)

            Toggle(title, isOn: isOn)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func snapshotSliderRow(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        unit: String
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
            Text("\(Int(value.wrappedValue)) \(unit)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var outputDimensions: CGSize {
        CodeSnapshotSizing.dimensions(payload: renderPayload, style: style)
    }

    private var previewAspectRatio: CGFloat {
        max(0.25, min(4, outputDimensions.width / max(1, outputDimensions.height)))
    }

    private var dimensionLabel: String {
        "\(Int(outputDimensions.width)) x \(Int(outputDimensions.height)) px"
    }

    @ViewBuilder
    private func snapshotActionBar(compact: Bool) -> some View {
        let copyButton = Button(action: copySnapshotToClipboard) {
            Label(
                didCopySnapshot ? "Copied to Clipboard" : "Copy Snapshot",
                systemImage: didCopySnapshot ? "checkmark.circle.fill" : "doc.on.doc.fill"
            )
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [style.theme.accent, Color(red: 0.00, green: 0.64, blue: 0.72)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: style.theme.accent.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(renderedPNGData == nil)
        .accessibilityHint("Copies the rendered PNG image to the clipboard")

        let secondaryActions = HStack(spacing: 10) {
            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            Button {
                showExporter = true
            } label: {
                Label("Save PNG", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(renderedPNGData == nil)
        }

        if compact {
            VStack(spacing: 10) {
                copyButton
                secondaryActions
            }
        } else {
            HStack(spacing: 12) {
                copyButton
                secondaryActions
            }
        }
    }

    private func copySnapshotToClipboard() {
        guard let renderedPNGData else { return }
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(renderedPNGData, forType: .png)
#else
        guard let image = UIImage(data: renderedPNGData) else { return }
        UIPasteboard.general.image = image
#endif
        didCopySnapshot = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            didCopySnapshot = false
        }
    }

    @MainActor
    private func refreshRenderedSnapshot() async {
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let data = CodeSnapshotRenderer.pngData(payload: renderPayload, style: style)
        renderedPNGData = data
#if os(macOS)
        renderedPreviewImage = data.flatMap(NSImage.init(data:))
#else
        renderedPreviewImage = data.flatMap(UIImage.init(data:))
#endif
        guard let data else {
            shareURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(snapshotPNGFileName)
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

    private var snapshotPNGFileName: String {
        "\(sanitizedFileName).png"
    }
}
