import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - Settings Preference Schema

/// Preference keys shared by Settings, the editor shell, and native editor bridges.
/// Keep stored values stable; migrate every consumer before renaming a key.
enum SettingsPreferenceKey {
    static let editorFontName = "SettingsEditorFontName"
    static let useSystemFont = "SettingsUseSystemFont"
    static let editorFontSize = "SettingsEditorFontSize"
    static let lineHeight = "SettingsLineHeight"
    static let letterSpacing = "SettingsLetterSpacing"
    static let lineWrapEnabled = "SettingsLineWrapEnabled"
    static let showLineNumbers = "SettingsShowLineNumbers"
    static let showInvisibleCharacters = "SettingsShowInvisibleCharacters"
    static let indentStyle = "SettingsIndentStyle"
    static let indentWidth = "SettingsIndentWidth"
    static let autocorrectionEnabled = "SettingsAutocorrectionEnabled"
    static let autocapitalizationEnabled = "SettingsAutocapitalizationEnabled"
    static let spellCheckingEnabled = "SettingsSpellCheckingEnabled"
    static let writingAssistanceMode = "SettingsWritingAssistanceMode"
    static let themeName = "SettingsThemeName"
    static let themeHexOverrides = "SettingsThemeHexOverrides"
    static let savedCustomThemes = "SavedCustomThemesData"
    static let themeBoldKeywords = "SettingsThemeBoldKeywords"
    static let themeItalicComments = "SettingsThemeItalicComments"
    static let themeUnderlineLinks = "SettingsThemeUnderlineLinks"
    static let themeBoldMarkdownHeadings = "SettingsThemeBoldMarkdownHeadings"
}

enum EditorWritingAssistanceMode: String, CaseIterable, Identifiable {
    case automatic
    case custom

    var id: String { rawValue }
    var title: String { self == .automatic ? "Automatic" : "Custom" }
}

struct EditorWritingAssistanceProfile: Equatable {
    let autocorrection: Bool
    let autocapitalization: Bool
    let spellChecking: Bool

    static func resolved(language: String, defaults: UserDefaults = .standard) -> Self {
        let custom = Self(
            autocorrection: defaults.bool(forKey: SettingsPreferenceKey.autocorrectionEnabled),
            autocapitalization: defaults.bool(forKey: SettingsPreferenceKey.autocapitalizationEnabled),
            spellChecking: defaults.bool(forKey: SettingsPreferenceKey.spellCheckingEnabled)
        )
        guard defaults.string(forKey: SettingsPreferenceKey.writingAssistanceMode)
                != EditorWritingAssistanceMode.custom.rawValue else {
            return custom
        }

        let proseLanguages: Set<String> = [
            "plain text", "plaintext", "text", "markdown", "md", "rich text"
        ]
        let isProse = proseLanguages.contains(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        return Self(
            autocorrection: isProse,
            autocapitalization: isProse,
            spellChecking: isProse
        )
    }
}

// MARK: - Theme JSON Caches

// Settings redraw frequently while sliders and pickers change; cache decoded theme blobs by data signature.
enum SettingsThemeJSONCache {
    private struct State: Sendable {
        var customThemesSignature: Int = 0
        var customThemes: [String: [String: String]] = [:]
        var sortedCustomThemeNames: [String] = []
        var hexOverridesSignature: Int = 0
        var hexOverrides: [String: [String: String]] = [:]
    }

    nonisolated private static let state = NVELock(State())

    nonisolated static func customThemes(from data: Data) -> [String: [String: String]] {
        let signature = data.count ^ data.hashValue
        return state.withLock { state in
            if signature == state.customThemesSignature { return state.customThemes }
            let decoded = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
            state.customThemesSignature = signature
            state.customThemes = decoded
            state.sortedCustomThemeNames = decoded.keys.sorted()
            return decoded
        }
    }

    nonisolated static func customThemeNames(from data: Data) -> [String] {
        _ = customThemes(from: data)
        return state.withLock { $0.sortedCustomThemeNames }
    }

    nonisolated static func hexOverrides(from data: Data) -> [String: [String: String]] {
        let signature = data.count ^ data.hashValue
        return state.withLock { state in
            if signature == state.hexOverridesSignature { return state.hexOverrides }
            let decoded = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
            state.hexOverridesSignature = signature
            state.hexOverrides = decoded
            return decoded
        }
    }
}

// MARK: - Custom Theme Import and Export

struct EditorThemeArchive: Codable, Equatable {
    let version: Int
    let themes: [String: [String: String]]
}

enum EditorThemeArchiveError: LocalizedError {
    case invalidFile
    case unsupportedVersion
    case invalidTheme

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "The selected file is not a Neon Vision Editor theme archive."
        case .unsupportedVersion:
            return "This theme archive uses an unsupported format version."
        case .invalidTheme:
            return "The archive contains an invalid theme name or color value."
        }
    }
}

enum EditorThemeArchiveCodec {
    private static let maximumArchiveBytes = 1_000_000
    private static let maximumThemeCount = 100
    private static let allowedColorKeys: Set<String> = [
        "text", "background", "backgroundLight", "backgroundDark", "cursor", "selection",
        "keyword", "string", "number", "comment", "type", "builtin"
    ]

    static func encode(themes: [String: [String: String]]) throws -> Data {
        try JSONEncoder.prettyPrinted.encode(EditorThemeArchive(version: 1, themes: themes))
    }

    static func decode(_ data: Data, builtInThemeNames: Set<String>) throws -> [String: [String: String]] {
        guard !data.isEmpty, data.count <= maximumArchiveBytes,
              let archive = try? JSONDecoder().decode(EditorThemeArchive.self, from: data) else {
            throw EditorThemeArchiveError.invalidFile
        }
        guard archive.version == 1 else {
            throw EditorThemeArchiveError.unsupportedVersion
        }
        guard !archive.themes.isEmpty, archive.themes.count <= maximumThemeCount else {
            throw EditorThemeArchiveError.invalidTheme
        }

        for (name, colors) in archive.themes {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedName == name,
                  !trimmedName.isEmpty,
                  trimmedName.count <= 80,
                  !builtInThemeNames.contains(where: {
                      $0.caseInsensitiveCompare(trimmedName) == .orderedSame
                  }),
                  !colors.isEmpty else {
                throw EditorThemeArchiveError.invalidTheme
            }
            for (key, value) in colors {
                guard allowedColorKeys.contains(key), isHexColor(value) else {
                    throw EditorThemeArchiveError.invalidTheme
                }
            }
        }
        return archive.themes
    }

    private static func isHexColor(_ value: String) -> Bool {
        guard value.first == "#", value.count == 7 || value.count == 9 else { return false }
        return value.dropFirst().allSatisfy(\.isHexDigit)
    }
}

struct EditorThemeArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw EditorThemeArchiveError.invalidFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

// MARK: - Settings Layout

struct SettingsFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = flowRows(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = flowRows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func flowRows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var rows: [FlowRow] = []
        var current = FlowRow()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = FlowRow()
            }
            current.append(index: index, size: size, spacing: spacing)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }

    private struct FlowItem { let index: Int; let size: CGSize }
    private struct FlowRow {
        var items: [FlowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        mutating func append(index: Int, size: CGSize, spacing: CGFloat) {
            width += items.isEmpty ? size.width : spacing + size.width
            height = max(height, size.height)
            items.append(FlowItem(index: index, size: size))
        }
    }
}
