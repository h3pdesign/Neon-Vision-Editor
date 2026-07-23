import SwiftUI
import Foundation

// MARK: - Settings Preference Schema

/// Preference keys shared by Settings, the editor shell, and native editor bridges.
/// Keep stored values stable; migrate every consumer before renaming a key.
enum SettingsPreferenceKey {
    static let editorFontName = "SettingsEditorFontName"
    static let useSystemFont = "SettingsUseSystemFont"
    static let editorFontSize = "SettingsEditorFontSize"
    static let lineHeight = "SettingsLineHeight"
    static let lineWrapEnabled = "SettingsLineWrapEnabled"
    static let showLineNumbers = "SettingsShowLineNumbers"
    static let showInvisibleCharacters = "SettingsShowInvisibleCharacters"
    static let indentStyle = "SettingsIndentStyle"
    static let indentWidth = "SettingsIndentWidth"
    static let themeName = "SettingsThemeName"
    static let themeHexOverrides = "SettingsThemeHexOverrides"
    static let savedCustomThemes = "SavedCustomThemesData"
    static let themeBoldKeywords = "SettingsThemeBoldKeywords"
    static let themeItalicComments = "SettingsThemeItalicComments"
    static let themeUnderlineLinks = "SettingsThemeUnderlineLinks"
    static let themeBoldMarkdownHeadings = "SettingsThemeBoldMarkdownHeadings"
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
