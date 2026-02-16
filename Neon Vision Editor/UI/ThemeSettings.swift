import SwiftUI

#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
#else
import UIKit
private typealias PlatformColor = UIColor
#endif

struct EditorTheme {
    let text: Color
    let background: Color
    let cursor: Color
    let selection: Color
    let syntax: SyntaxColors
}

private struct ThemePalette {
    let text: Color
    let background: Color
    let cursor: Color
    let selection: Color
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let type: Color
    let property: Color
    let builtin: Color
}

struct ThemePaletteColors {
    let text: Color
    let background: Color
    let cursor: Color
    let selection: Color
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let type: Color
    let property: Color
    let builtin: Color
}

private struct RGBColorComponents {
    let red: Double
    let green: Double
    let blue: Double
}

private func colorComponents(_ color: Color) -> RGBColorComponents? {
#if os(macOS)
    let platform = PlatformColor(color)
    guard let srgb = platform.usingColorSpace(.sRGB) else { return nil }
    return RGBColorComponents(
        red: Double(srgb.redComponent),
        green: Double(srgb.greenComponent),
        blue: Double(srgb.blueComponent)
    )
#else
    let platform = PlatformColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard platform.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
    return RGBColorComponents(red: Double(red), green: Double(green), blue: Double(blue))
#endif
}

private func relativeLuminance(_ components: RGBColorComponents) -> Double {
    (0.2126 * components.red) + (0.7152 * components.green) + (0.0722 * components.blue)
}

private func blend(_ source: Color, with target: Color, amount: Double) -> Color {
    guard let sourceComponents = colorComponents(source), let targetComponents = colorComponents(target) else {
        return source
    }
    let clamped = min(1.0, max(0.0, amount))
    return Color(
        red: sourceComponents.red + ((targetComponents.red - sourceComponents.red) * clamped),
        green: sourceComponents.green + ((targetComponents.green - sourceComponents.green) * clamped),
        blue: sourceComponents.blue + ((targetComponents.blue - sourceComponents.blue) * clamped)
    )
}

private func modeAdjustedEditorBackground(_ background: Color, colorScheme: ColorScheme) -> Color {
    guard let components = colorComponents(background) else { return background }
    let luminance = relativeLuminance(components)

    if colorScheme == .light {
        // Keep all themes readable in light/system-light by lifting dark palettes.
        if luminance >= 0.78 { return background }
        let targetLuminance = 0.96
        let normalized = (targetLuminance - luminance) / max(0.0001, 1.0 - luminance)
        let mixAmount = min(0.95, max(0.70, normalized))
        return blend(background, with: .white, amount: mixAmount)
    }

    // Keep all themes readable in dark/system-dark by lowering bright palettes.
    if luminance <= 0.28 { return background }
    let targetLuminance = 0.14
    let normalized = (luminance - targetLuminance) / max(0.0001, luminance)
    let mixAmount = min(0.90, max(0.55, normalized))
    return blend(background, with: .black, amount: mixAmount)
}

private func modeAdjustedSyntaxColor(
    _ color: Color,
    colorScheme: ColorScheme,
    darkenInLight amountLight: Double,
    brightenInDark amountDark: Double
) -> Color {
    if colorScheme == .light {
        return blend(color, with: .black, amount: amountLight)
    }
    return blend(color, with: .white, amount: amountDark)
}

///MARK: Syntax Adjustment Profiles

// Internal strategy for token color adjustment per theme family.
private enum SyntaxAdjustmentProfile {
    case standard
    case neonRaw
}

private func adjustedSyntaxColor(
    _ color: Color,
    colorScheme: ColorScheme,
    profile: SyntaxAdjustmentProfile,
    darkenInLight amountLight: Double,
    brightenInDark amountDark: Double
) -> Color {
    switch profile {
    case .standard:
        return modeAdjustedSyntaxColor(
            color,
            colorScheme: colorScheme,
            darkenInLight: amountLight,
            brightenInDark: amountDark
        )
    case .neonRaw:
        // Keep Neon Glow vivid in light mode and only apply a tiny dark-mode lift.
        if colorScheme == .light { return color }
        return blend(color, with: .white, amount: 0.03)
    }
}

///MARK: Theme Name Canonicalization

// Canonical theme names shown in settings and used for palette lookup.
let editorThemeNames: [String] = [
    "Neon Glow",
    "Neon Flow",
    "Dracula",
    "One Dark Pro",
    "Nord",
    "Tokyo Night",
    "Gruvbox",
    "Arc",
    "Dusk",
    "Aurora",
    "Horizon",
    "Midnight",
    "Mono",
    "Paper",
    "Solar",
    "Pulse",
    "Mocha",
    "Custom"
]

// Normalize persisted theme values so legacy/case variants still resolve correctly.
func canonicalThemeName(_ rawName: String) -> String {
    let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Neon Glow" }

    if let exact = editorThemeNames.first(where: { $0 == trimmed }) {
        return exact
    }

    if let caseInsensitive = editorThemeNames.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
        return caseInsensitive
    }

    return "Neon Glow"
}

private func paletteForThemeName(_ name: String, defaults: UserDefaults) -> ThemePalette {
    let canonicalName = canonicalThemeName(name)
    let palette: ThemePalette = {
        switch canonicalName {
        case "Neon Glow":
            return ThemePalette(
                text: Color(red: 0.00, green: 0.00, blue: 0.00),
                background: Color(red: 1.00, green: 1.00, blue: 1.00),
                cursor: Color(red: 0.30, green: 0.60, blue: 0.90),
                selection: Color(red: 0.18, green: 0.24, blue: 0.33),
                keyword: Color(red: 0.93, green: 0.00, blue: 0.88),
                string: Color(red: 0.00, green: 0.243137, blue: 1.00),
                number: Color(red: 1.00, green: 0.02, blue: 0.12),
                comment: Color(red: 0.38, green: 0.38, blue: 0.40),
                type: Color(red: 0.20, green: 0.82, blue: 0.41),
                property: Color(red: 0.86, green: 0.44, blue: 0.84),
                builtin: Color(red: 0.92, green: 0.47, blue: 0.53)
            )
        case "Neon Flow":
            return ThemePalette(
                text: Color(red: 0.00, green: 0.00, blue: 0.00),
                background: Color(red: 1.00, green: 1.00, blue: 1.00),
                cursor: Color(red: 0.29, green: 0.60, blue: 0.91),
                selection: Color(red: 0.95, green: 0.17, blue: 0.56),
                keyword: Color(red: 0.92, green: 0.05, blue: 0.91),
                string: Color(red: 0.09, green: 0.56, blue: 0.91),
                number: Color(red: 0.95, green: 0.17, blue: 0.56),
                comment: Color(red: 0.62, green: 0.62, blue: 0.62),
                type: Color(red: 0.08, green: 0.89, blue: 0.37),
                property: Color(red: 0.92, green: 0.05, blue: 0.91),
                builtin: Color(red: 0.96, green: 0.20, blue: 0.04)
            )
        case "Dracula":
            return ThemePalette(
                text: Color(red: 0.97, green: 0.97, blue: 0.95),
                background: Color(red: 0.16, green: 0.17, blue: 0.21),
                cursor: Color(red: 0.97, green: 0.97, blue: 0.95),
                selection: Color(red: 0.27, green: 0.28, blue: 0.35),
                keyword: Color(red: 1.00, green: 0.48, blue: 0.78),
                string: Color(red: 0.95, green: 0.98, blue: 0.55),
                number: Color(red: 0.74, green: 0.58, blue: 0.98),
                comment: Color(red: 0.38, green: 0.45, blue: 0.64),
                type: Color(red: 0.55, green: 0.91, blue: 0.99),
                property: Color(red: 0.31, green: 0.98, blue: 0.48),
                builtin: Color(red: 1.00, green: 0.72, blue: 0.42)
            )
        case "One Dark Pro":
            return ThemePalette(
                text: Color(red: 0.67, green: 0.70, blue: 0.75),
                background: Color(red: 0.16, green: 0.17, blue: 0.20),
                cursor: Color(red: 0.32, green: 0.55, blue: 1.00),
                selection: Color(red: 0.24, green: 0.27, blue: 0.32),
                keyword: Color(red: 0.78, green: 0.47, blue: 0.87),
                string: Color(red: 0.60, green: 0.76, blue: 0.47),
                number: Color(red: 0.82, green: 0.60, blue: 0.40),
                comment: Color(red: 0.36, green: 0.39, blue: 0.44),
                type: Color(red: 0.90, green: 0.75, blue: 0.48),
                property: Color(red: 0.38, green: 0.69, blue: 0.94),
                builtin: Color(red: 0.34, green: 0.71, blue: 0.76)
            )
        case "Nord":
            return ThemePalette(
                text: Color(red: 0.85, green: 0.87, blue: 0.91),
                background: Color(red: 0.18, green: 0.20, blue: 0.25),
                cursor: Color(red: 0.53, green: 0.75, blue: 0.82),
                selection: Color(red: 0.26, green: 0.30, blue: 0.37),
                keyword: Color(red: 0.51, green: 0.63, blue: 0.76),
                string: Color(red: 0.64, green: 0.75, blue: 0.55),
                number: Color(red: 0.71, green: 0.56, blue: 0.68),
                comment: Color(red: 0.38, green: 0.43, blue: 0.53),
                type: Color(red: 0.56, green: 0.74, blue: 0.73),
                property: Color(red: 0.82, green: 0.53, blue: 0.44),
                builtin: Color(red: 0.92, green: 0.80, blue: 0.55)
            )
        case "Tokyo Night":
            return ThemePalette(
                text: Color(red: 0.75, green: 0.79, blue: 0.96),
                background: Color(red: 0.10, green: 0.11, blue: 0.15),
                cursor: Color(red: 0.48, green: 0.64, blue: 0.97),
                selection: Color(red: 0.20, green: 0.28, blue: 0.49),
                keyword: Color(red: 0.73, green: 0.60, blue: 0.97),
                string: Color(red: 0.62, green: 0.81, blue: 0.42),
                number: Color(red: 1.00, green: 0.62, blue: 0.39),
                comment: Color(red: 0.34, green: 0.37, blue: 0.54),
                type: Color(red: 0.49, green: 0.81, blue: 1.00),
                property: Color(red: 0.16, green: 0.77, blue: 0.87),
                builtin: Color(red: 0.97, green: 0.46, blue: 0.56)
            )
        case "Gruvbox":
            return ThemePalette(
                text: Color(red: 0.92, green: 0.86, blue: 0.70),
                background: Color(red: 0.16, green: 0.16, blue: 0.16),
                cursor: Color(red: 0.98, green: 0.74, blue: 0.18),
                selection: Color(red: 0.31, green: 0.29, blue: 0.27),
                keyword: Color(red: 0.98, green: 0.29, blue: 0.20),
                string: Color(red: 0.72, green: 0.73, blue: 0.15),
                number: Color(red: 0.83, green: 0.53, blue: 0.61),
                comment: Color(red: 0.57, green: 0.51, blue: 0.46),
                type: Color(red: 0.56, green: 0.75, blue: 0.49),
                property: Color(red: 0.51, green: 0.65, blue: 0.60),
                builtin: Color(red: 1.00, green: 0.50, blue: 0.10)
            )
        case "Arc":
            return ThemePalette(
                text: Color(red: 0.95, green: 0.96, blue: 0.98),
                background: Color(red: 0.12, green: 0.13, blue: 0.16),
                cursor: Color(red: 0.35, green: 0.67, blue: 0.98),
                selection: Color(red: 0.22, green: 0.29, blue: 0.40),
                keyword: Color(red: 0.85, green: 0.48, blue: 1.0),
                string: Color(red: 0.45, green: 0.88, blue: 0.72),
                number: Color(red: 0.98, green: 0.75, blue: 0.37),
                comment: Color(red: 0.56, green: 0.60, blue: 0.70),
                type: Color(red: 0.44, green: 0.66, blue: 0.98),
                property: Color(red: 0.94, green: 0.61, blue: 0.32),
                builtin: Color(red: 0.99, green: 0.51, blue: 0.71)
            )
        case "Dusk":
            return ThemePalette(
                text: Color(red: 0.93, green: 0.92, blue: 0.95),
                background: Color(red: 0.14, green: 0.10, blue: 0.20),
                cursor: Color(red: 0.93, green: 0.54, blue: 0.94),
                selection: Color(red: 0.28, green: 0.22, blue: 0.39),
                keyword: Color(red: 0.98, green: 0.72, blue: 0.40),
                string: Color(red: 0.48, green: 0.89, blue: 0.67),
                number: Color(red: 0.98, green: 0.54, blue: 0.62),
                comment: Color(red: 0.62, green: 0.57, blue: 0.70),
                type: Color(red: 0.57, green: 0.75, blue: 1.0),
                property: Color(red: 0.88, green: 0.64, blue: 0.98),
                builtin: Color(red: 0.94, green: 0.44, blue: 0.76)
            )
        case "Aurora":
            return ThemePalette(
                text: Color(red: 0.92, green: 0.96, blue: 0.98),
                background: Color(red: 0.08, green: 0.12, blue: 0.14),
                cursor: Color(red: 0.35, green: 0.96, blue: 0.76),
                selection: Color(red: 0.18, green: 0.28, blue: 0.30),
                keyword: Color(red: 0.36, green: 0.92, blue: 0.98),
                string: Color(red: 0.44, green: 0.98, blue: 0.62),
                number: Color(red: 0.98, green: 0.76, blue: 0.38),
                comment: Color(red: 0.70, green: 0.86, blue: 0.92),
                type: Color(red: 0.52, green: 0.74, blue: 0.98),
                property: Color(red: 0.90, green: 0.60, blue: 0.98),
                builtin: Color(red: 0.98, green: 0.52, blue: 0.72)
            )
        case "Horizon":
            return ThemePalette(
                text: Color(red: 0.95, green: 0.94, blue: 0.92),
                background: Color(red: 0.14, green: 0.10, blue: 0.09),
                cursor: Color(red: 0.99, green: 0.62, blue: 0.36),
                selection: Color(red: 0.30, green: 0.20, blue: 0.18),
                keyword: Color(red: 0.99, green: 0.46, blue: 0.36),
                string: Color(red: 0.98, green: 0.78, blue: 0.36),
                number: Color(red: 0.98, green: 0.60, blue: 0.80),
                comment: Color(red: 0.86, green: 0.72, blue: 0.64),
                type: Color(red: 0.60, green: 0.78, blue: 0.98),
                property: Color(red: 0.96, green: 0.56, blue: 0.45),
                builtin: Color(red: 0.90, green: 0.72, blue: 0.36)
            )
        case "Midnight":
            return ThemePalette(
                text: Color(red: 0.90, green: 0.94, blue: 0.98),
                background: Color(red: 0.08, green: 0.10, blue: 0.16),
                cursor: Color(red: 0.25, green: 0.78, blue: 0.98),
                selection: Color(red: 0.16, green: 0.22, blue: 0.32),
                keyword: Color(red: 0.35, green: 0.86, blue: 0.96),
                string: Color(red: 0.48, green: 0.94, blue: 0.62),
                number: Color(red: 0.96, green: 0.77, blue: 0.31),
                comment: Color(red: 0.55, green: 0.63, blue: 0.74),
                type: Color(red: 0.40, green: 0.65, blue: 0.98),
                property: Color(red: 0.96, green: 0.56, blue: 0.45),
                builtin: Color(red: 0.86, green: 0.52, blue: 1.0)
            )
        case "Mono":
            return ThemePalette(
                text: Color(red: 0.88, green: 0.88, blue: 0.88),
                background: Color(red: 0.12, green: 0.12, blue: 0.12),
                cursor: Color.white,
                selection: Color(red: 0.26, green: 0.26, blue: 0.26),
                keyword: Color(red: 0.92, green: 0.92, blue: 0.92),
                string: Color(red: 0.80, green: 0.80, blue: 0.80),
                number: Color(red: 0.86, green: 0.86, blue: 0.86),
                comment: Color(red: 0.55, green: 0.55, blue: 0.55),
                type: Color(red: 0.90, green: 0.90, blue: 0.90),
                property: Color(red: 0.84, green: 0.84, blue: 0.84),
                builtin: Color(red: 0.78, green: 0.78, blue: 0.78)
            )
        case "Paper":
            return ThemePalette(
                text: Color(red: 0.12, green: 0.12, blue: 0.12),
                background: Color(red: 0.98, green: 0.97, blue: 0.94),
                cursor: Color(red: 0.16, green: 0.31, blue: 0.90),
                selection: Color(red: 0.86, green: 0.90, blue: 0.98),
                keyword: Color(red: 0.60, green: 0.18, blue: 0.82),
                string: Color(red: 0.12, green: 0.54, blue: 0.39),
                number: Color(red: 0.78, green: 0.37, blue: 0.09),
                comment: Color(red: 0.46, green: 0.46, blue: 0.46),
                type: Color(red: 0.12, green: 0.34, blue: 0.75),
                property: Color(red: 0.67, green: 0.27, blue: 0.52),
                builtin: Color(red: 0.74, green: 0.42, blue: 0.10)
            )
        case "Solar":
            return ThemePalette(
                text: Color(red: 0.98, green: 0.95, blue: 0.90),
                background: Color(red: 0.19, green: 0.12, blue: 0.08),
                cursor: Color(red: 0.99, green: 0.74, blue: 0.30),
                selection: Color(red: 0.33, green: 0.20, blue: 0.14),
                keyword: Color(red: 0.99, green: 0.64, blue: 0.24),
                string: Color(red: 0.98, green: 0.84, blue: 0.34),
                number: Color(red: 0.98, green: 0.52, blue: 0.74),
                comment: Color(red: 0.92, green: 0.80, blue: 0.66),
                type: Color(red: 0.52, green: 0.78, blue: 0.98),
                property: Color(red: 0.98, green: 0.58, blue: 0.38),
                builtin: Color(red: 0.94, green: 0.48, blue: 0.58)
            )
        case "Pulse":
            return ThemePalette(
                text: Color(red: 0.95, green: 0.96, blue: 0.98),
                background: Color(red: 0.10, green: 0.10, blue: 0.14),
                cursor: Color(red: 0.93, green: 0.45, blue: 0.57),
                selection: Color(red: 0.24, green: 0.18, blue: 0.28),
                keyword: Color(red: 0.98, green: 0.54, blue: 0.62),
                string: Color(red: 0.46, green: 0.92, blue: 0.83),
                number: Color(red: 0.96, green: 0.76, blue: 0.30),
                comment: Color(red: 0.62, green: 0.63, blue: 0.72),
                type: Color(red: 0.45, green: 0.72, blue: 0.98),
                property: Color(red: 0.96, green: 0.59, blue: 0.32),
                builtin: Color(red: 0.86, green: 0.52, blue: 1.0)
            )
        case "Mocha":
            return ThemePalette(
                text: Color(red: 0.95, green: 0.92, blue: 0.90),
                background: Color(red: 0.12, green: 0.09, blue: 0.08),
                cursor: Color(red: 0.82, green: 0.62, blue: 0.48),
                selection: Color(red: 0.22, green: 0.17, blue: 0.15),
                keyword: Color(red: 0.82, green: 0.60, blue: 0.98),
                string: Color(red: 0.84, green: 0.72, blue: 0.46),
                number: Color(red: 0.98, green: 0.70, blue: 0.46),
                comment: Color(red: 0.78, green: 0.70, blue: 0.66),
                type: Color(red: 0.52, green: 0.78, blue: 0.98),
                property: Color(red: 0.94, green: 0.56, blue: 0.32),
                builtin: Color(red: 0.90, green: 0.46, blue: 0.72)
            )
        case "Custom":
            let text = colorFromHex(defaults.string(forKey: "SettingsThemeTextColor") ?? "#EDEDED", fallback: .white)
            let background = colorFromHex(defaults.string(forKey: "SettingsThemeBackgroundColor") ?? "#0E1116", fallback: .black)
            let cursor = colorFromHex(defaults.string(forKey: "SettingsThemeCursorColor") ?? "#4EA4FF", fallback: .blue)
            let selection = colorFromHex(defaults.string(forKey: "SettingsThemeSelectionColor") ?? "#2A3340", fallback: .gray)
            let keyword = colorFromHex(defaults.string(forKey: "SettingsThemeKeywordColor") ?? "#F5D90A", fallback: .yellow)
            let string = colorFromHex(defaults.string(forKey: "SettingsThemeStringColor") ?? "#FF7AD9", fallback: .pink)
            let number = colorFromHex(defaults.string(forKey: "SettingsThemeNumberColor") ?? "#FFB86C", fallback: .orange)
            let comment = colorFromHex(defaults.string(forKey: "SettingsThemeCommentColor") ?? "#7F8C98", fallback: .gray)
            let type = colorFromHex(defaults.string(forKey: "SettingsThemeTypeColor") ?? "#32D269", fallback: .green)
            let builtin = colorFromHex(defaults.string(forKey: "SettingsThemeBuiltinColor") ?? "#EC7887", fallback: .red)
            return ThemePalette(
                text: text,
                background: background,
                cursor: cursor,
                selection: selection,
                keyword: keyword,
                string: string,
                number: number,
                comment: comment,
                type: type,
                property: string,
                builtin: builtin
            )
        default:
            return ThemePalette(
                text: Color(red: 0.93, green: 0.95, blue: 0.98),
                background: Color(red: 0.10, green: 0.11, blue: 0.14),
                cursor: Color(red: 0.31, green: 0.72, blue: 0.99),
                selection: Color(red: 0.22, green: 0.30, blue: 0.43),
                keyword: Color(red: 0.96, green: 0.84, blue: 0.23),
                string: Color(red: 0.98, green: 0.48, blue: 0.82),
                number: Color(red: 0.98, green: 0.72, blue: 0.33),
                comment: Color(red: 0.60, green: 0.66, blue: 0.74),
                type: Color(red: 0.41, green: 0.69, blue: 0.99),
                property: Color(red: 0.39, green: 0.90, blue: 0.72),
                builtin: Color(red: 0.94, green: 0.42, blue: 0.66)
            )
        }
    }()
    return palette
}

func themePaletteColors(for name: String, defaults: UserDefaults = .standard) -> ThemePaletteColors {
    let palette = paletteForThemeName(canonicalThemeName(name), defaults: defaults)
    return ThemePaletteColors(
        text: palette.text,
        background: palette.background,
        cursor: palette.cursor,
        selection: palette.selection,
        keyword: palette.keyword,
        string: palette.string,
        number: palette.number,
        comment: palette.comment,
        type: palette.type,
        property: palette.property,
        builtin: palette.builtin
    )
}

func currentEditorTheme(colorScheme: ColorScheme) -> EditorTheme {
    let defaults = UserDefaults.standard
    // Always respect the user's selected theme across iOS and macOS.
    let name = canonicalThemeName(defaults.string(forKey: "SettingsThemeName") ?? "Neon Glow")
    let palette = paletteForThemeName(name, defaults: defaults)
    // Keep base editor text legible and consistent across all themes.
    // Neon Glow gets a slightly brighter dark-mode text tone.
    let baseTextColor: Color = {
        if colorScheme == .light { return .black }
        if name == "Neon Glow" {
            return Color(red: 0.94, green: 0.94, blue: 0.94)
        }
        return Color(red: 0.90, green: 0.90, blue: 0.90)
    }()

    let profile: SyntaxAdjustmentProfile = (name == "Neon Glow") ? .neonRaw : .standard
    let keyword = adjustedSyntaxColor(
        palette.keyword,
        colorScheme: colorScheme,
        profile: profile,
        darkenInLight: 0.30,
        brightenInDark: 0.08
    )
    let string = adjustedSyntaxColor(
        palette.string,
        colorScheme: colorScheme,
        profile: profile,
        darkenInLight: 0.40,
        brightenInDark: 0.10
    )
    let number = adjustedSyntaxColor(
        palette.number,
        colorScheme: colorScheme,
        profile: profile,
        darkenInLight: 0.28,
        brightenInDark: 0.08
    )
    let comment = adjustedSyntaxColor(
        palette.comment,
        colorScheme: colorScheme,
        profile: profile,
        darkenInLight: 0.28,
        brightenInDark: 0.20
    )
    let type = adjustedSyntaxColor(
        palette.type,
        colorScheme: colorScheme,
        profile: profile,
        darkenInLight: 0.30,
        brightenInDark: 0.08
    )
    let property = adjustedSyntaxColor(
        palette.property,
        colorScheme: colorScheme,
        profile: profile,
        darkenInLight: 0.32,
        brightenInDark: 0.08
    )
    let builtin = adjustedSyntaxColor(
        palette.builtin,
        colorScheme: colorScheme,
        profile: profile,
        darkenInLight: 0.30,
        brightenInDark: 0.08
    )

    let syntax = SyntaxColors(
        keyword: keyword,
        string: string,
        number: number,
        comment: comment,
        attribute: property,
        variable: property,
        def: type,
        property: property,
        meta: builtin,
        tag: keyword,
        atom: builtin,
        builtin: builtin,
        type: type
    )

    return EditorTheme(
        text: baseTextColor,
        background: modeAdjustedEditorBackground(palette.background, colorScheme: colorScheme),
        cursor: palette.cursor,
        selection: palette.selection,
        syntax: syntax
    )
}

func colorFromHex(_ hex: String, fallback: Color) -> Color {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    guard cleaned.count == 6, let intVal = Int(cleaned, radix: 16) else { return fallback }
    let r = Double((intVal >> 16) & 0xFF) / 255.0
    let g = Double((intVal >> 8) & 0xFF) / 255.0
    let b = Double(intVal & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

func colorToHex(_ color: Color) -> String {
#if os(macOS)
    let platform = PlatformColor(color)
    guard let srgb = platform.usingColorSpace(.sRGB) else { return "#FFFFFF" }
    let r = Int(round(srgb.redComponent * 255))
    let g = Int(round(srgb.greenComponent * 255))
    let b = Int(round(srgb.blueComponent * 255))
#else
    let platform = PlatformColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    platform.getRed(&r, green: &g, blue: &b, alpha: &a)
    let rInt = Int(round(r * 255))
    let gInt = Int(round(g * 255))
    let bInt = Int(round(b * 255))
#endif
#if os(macOS)
    return String(format: "#%02X%02X%02X", r, g, b)
#else
    return String(format: "#%02X%02X%02X", rInt, gInt, bInt)
#endif
}
