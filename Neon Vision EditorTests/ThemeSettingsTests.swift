import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit
private typealias TestPlatformColor = NSColor
#else
import UIKit
private typealias TestPlatformColor = UIColor
#endif

private struct TestColorComponents: Hashable {
    let red: Int
    let green: Int
    let blue: Int
}

private func testColorComponents(_ color: Color) -> TestColorComponents? {
#if os(macOS)
    let platform = TestPlatformColor(color)
    guard let srgb = platform.usingColorSpace(.sRGB) else { return nil }
    return TestColorComponents(
        red: Int(round(srgb.redComponent * 100)),
        green: Int(round(srgb.greenComponent * 100)),
        blue: Int(round(srgb.blueComponent * 100))
    )
#else
    let platform = TestPlatformColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard platform.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
    return TestColorComponents(
        red: Int(round(red * 100)),
        green: Int(round(green * 100)),
        blue: Int(round(blue * 100))
    )
#endif
}

private func testRelativeLuminance(_ color: Color) -> Double {
    guard let components = testColorComponents(color) else { return 0 }
    return (0.2126 * Double(components.red) / 100.0)
        + (0.7152 * Double(components.green) / 100.0)
        + (0.0722 * Double(components.blue) / 100.0)
}

@MainActor
final class ThemeSettingsTests: XCTestCase {
    func testAmoledThemeUsesDeepBlackAndVibrantSyntaxColors() {
        XCTAssertEqual(canonicalThemeName("amoled neon"), "AMOLED Neon")
        XCTAssertTrue(editorThemeNames.contains("AMOLED Neon"))

        let palette = themePaletteColors(for: "AMOLED Neon")
        let background = testColorComponents(palette.background)
        let string = testColorComponents(palette.string)
        let keyword = testColorComponents(palette.keyword)

        XCTAssertEqual(background, TestColorComponents(red: 0, green: 0, blue: 0))
        XCTAssertGreaterThanOrEqual(string?.green ?? 0, 100)
        XCTAssertLessThanOrEqual(string?.red ?? 100, 1)
        XCTAssertGreaterThanOrEqual(keyword?.red ?? 0, 100)
        XCTAssertGreaterThanOrEqual(keyword?.blue ?? 0, 85)
    }

    func testNeonGlowBuiltinUsesYellowByAppearance() {
        let previousTheme = UserDefaults.standard.string(forKey: "SettingsThemeName")
        let previousOverrides = UserDefaults.standard.data(forKey: "SettingsThemeHexOverrides")
        let previousOverridesVersion = UserDefaults.standard.string(forKey: "SettingsThemeOverridesVersion")
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: "SettingsThemeName")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeName")
            }
            if let previousOverrides {
                UserDefaults.standard.set(previousOverrides, forKey: "SettingsThemeHexOverrides")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeHexOverrides")
            }
            if let previousOverridesVersion {
                UserDefaults.standard.set(previousOverridesVersion, forKey: "SettingsThemeOverridesVersion")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeOverridesVersion")
            }
        }

        UserDefaults.standard.set("v2", forKey: "SettingsThemeOverridesVersion")
        UserDefaults.standard.removeObject(forKey: "SettingsThemeHexOverrides")
        UserDefaults.standard.set("Neon Glow", forKey: "SettingsThemeName")

        let darkBuiltin = currentEditorTheme(colorScheme: .dark).syntax.builtin
        let lightBuiltin = currentEditorTheme(colorScheme: .light).syntax.builtin
        let darkComponents = testColorComponents(darkBuiltin)
        let lightComponents = testColorComponents(lightBuiltin)

        XCTAssertGreaterThanOrEqual(darkComponents?.red ?? 0, 98)
        XCTAssertGreaterThanOrEqual(darkComponents?.green ?? 0, 86)
        XCTAssertLessThanOrEqual(darkComponents?.blue ?? 100, 15)
        XCTAssertGreaterThanOrEqual(lightComponents?.red ?? 0, 75)
        XCTAssertGreaterThanOrEqual(lightComponents?.green ?? 0, 65)
        XCTAssertLessThanOrEqual(lightComponents?.blue ?? 100, 10)
        XCTAssertGreaterThan(testRelativeLuminance(darkBuiltin), testRelativeLuminance(lightBuiltin))
    }

    func testNeonFlowUsesDistinctVibrantPaletteFromNeonGlow() {
        let glow = themePaletteColors(for: "Neon Glow")
        let flow = themePaletteColors(for: "Neon Flow")

        XCTAssertNotEqual(testColorComponents(flow.keyword), testColorComponents(glow.keyword))
        XCTAssertNotEqual(testColorComponents(flow.string), testColorComponents(glow.string))
        XCTAssertNotEqual(testColorComponents(flow.number), testColorComponents(glow.number))
        XCTAssertNotEqual(testColorComponents(flow.builtin), testColorComponents(glow.builtin))

        let keyword = testColorComponents(flow.keyword)
        let string = testColorComponents(flow.string)
        let number = testColorComponents(flow.number)
        let property = testColorComponents(flow.property)

        XCTAssertGreaterThanOrEqual(keyword?.green ?? 0, 70)
        XCTAssertGreaterThanOrEqual(keyword?.blue ?? 0, 80)
        XCTAssertGreaterThanOrEqual(string?.blue ?? 0, 95)
        XCTAssertGreaterThanOrEqual(number?.red ?? 0, 95)
        XCTAssertGreaterThanOrEqual(property?.blue ?? 0, 95)
    }

    func testLaserwaveStringColorRemainsReadableInLightMode() {
        let previousTheme = UserDefaults.standard.string(forKey: "SettingsThemeName")
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: "SettingsThemeName")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeName")
            }
        }

        UserDefaults.standard.set("Laserwave", forKey: "SettingsThemeName")
        let theme = currentEditorTheme(colorScheme: .light)

        XCTAssertLessThan(
            testRelativeLuminance(theme.syntax.string),
            0.55,
            "Laserwave strings should darken enough to remain readable on light editor backgrounds."
        )
    }

    func testDefaultThemesFollowSystemLightAndDarkContrast() {
        let previousTheme = UserDefaults.standard.string(forKey: "SettingsThemeName")
        let previousOverrides = UserDefaults.standard.data(forKey: "SettingsThemeHexOverrides")
        let previousOverridesVersion = UserDefaults.standard.string(forKey: "SettingsThemeOverridesVersion")
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: "SettingsThemeName")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeName")
            }
            if let previousOverrides {
                UserDefaults.standard.set(previousOverrides, forKey: "SettingsThemeHexOverrides")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeHexOverrides")
            }
            if let previousOverridesVersion {
                UserDefaults.standard.set(previousOverridesVersion, forKey: "SettingsThemeOverridesVersion")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeOverridesVersion")
            }
        }

        UserDefaults.standard.set("v2", forKey: "SettingsThemeOverridesVersion")
        UserDefaults.standard.removeObject(forKey: "SettingsThemeHexOverrides")

        for themeName in editorThemeNames {
            UserDefaults.standard.set(themeName, forKey: "SettingsThemeName")

            let lightTheme = currentEditorTheme(colorScheme: .light)
            XCTAssertGreaterThanOrEqual(testRelativeLuminance(lightTheme.background), 0.72, "\(themeName) should use a light default background in light mode.")
            XCTAssertLessThanOrEqual(testRelativeLuminance(lightTheme.text), 0.35, "\(themeName) should use dark default text in light mode.")

            let darkTheme = currentEditorTheme(colorScheme: .dark)
            XCTAssertLessThanOrEqual(testRelativeLuminance(darkTheme.background), 0.34, "\(themeName) should use a dark default background in dark mode.")
            XCTAssertGreaterThanOrEqual(testRelativeLuminance(darkTheme.text), 0.68, "\(themeName) should use light default text in dark mode.")
        }
    }

    func testTextOverrideDoesNotCreateDarkLightModeBackground() throws {
        let previousTheme = UserDefaults.standard.string(forKey: "SettingsThemeName")
        let previousOverrides = UserDefaults.standard.data(forKey: "SettingsThemeHexOverrides")
        let previousOverridesVersion = UserDefaults.standard.string(forKey: "SettingsThemeOverridesVersion")
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: "SettingsThemeName")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeName")
            }
            if let previousOverrides {
                UserDefaults.standard.set(previousOverrides, forKey: "SettingsThemeHexOverrides")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeHexOverrides")
            }
            if let previousOverridesVersion {
                UserDefaults.standard.set(previousOverridesVersion, forKey: "SettingsThemeOverridesVersion")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeOverridesVersion")
            }
        }

        UserDefaults.standard.set("v2", forKey: "SettingsThemeOverridesVersion")
        UserDefaults.standard.set("Laserwave", forKey: "SettingsThemeName")
        let overrides = ["Laserwave": ["text": "#FF0000"]]
        UserDefaults.standard.set(try JSONEncoder().encode(overrides), forKey: "SettingsThemeHexOverrides")

        let theme = currentEditorTheme(colorScheme: .light)

        XCTAssertGreaterThanOrEqual(
            testRelativeLuminance(theme.background),
            0.72,
            "Changing only text color must not turn the light-mode background into a dark explicit override."
        )
    }

    func testAccidentalDefaultTextOverridesFollowAppearanceContrast() throws {
        let previousTheme = UserDefaults.standard.string(forKey: "SettingsThemeName")
        let previousOverrides = UserDefaults.standard.data(forKey: "SettingsThemeHexOverrides")
        let previousOverridesVersion = UserDefaults.standard.string(forKey: "SettingsThemeOverridesVersion")
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: "SettingsThemeName")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeName")
            }
            if let previousOverrides {
                UserDefaults.standard.set(previousOverrides, forKey: "SettingsThemeHexOverrides")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeHexOverrides")
            }
            if let previousOverridesVersion {
                UserDefaults.standard.set(previousOverridesVersion, forKey: "SettingsThemeOverridesVersion")
            } else {
                UserDefaults.standard.removeObject(forKey: "SettingsThemeOverridesVersion")
            }
        }

        UserDefaults.standard.set("v2", forKey: "SettingsThemeOverridesVersion")

        UserDefaults.standard.set("Neon Glow", forKey: "SettingsThemeName")
        UserDefaults.standard.set(try JSONEncoder().encode(["Neon Glow": ["text": "#F0F0F0"]]), forKey: "SettingsThemeHexOverrides")
        XCTAssertLessThanOrEqual(
            testRelativeLuminance(currentEditorTheme(colorScheme: .light).text),
            0.35,
            "Legacy raw default text overrides must not force white text in light mode."
        )

        UserDefaults.standard.set("Neon Flow", forKey: "SettingsThemeName")
        UserDefaults.standard.set(try JSONEncoder().encode(["Neon Flow": ["text": "#000000"]]), forKey: "SettingsThemeHexOverrides")
        XCTAssertGreaterThanOrEqual(
            testRelativeLuminance(currentEditorTheme(colorScheme: .dark).text),
            0.68,
            "Legacy raw default text overrides must not force dark text in dark mode."
        )
    }

    func testNeonStringPalettesAreDistinctAcrossNearbyThemes() {
        let themeNames = [
            "Laserwave",
            "Plasma Storm",
            "Ultraviolet Flux",
            "Midnight",
            "Pulse",
            "AMOLED Neon"
        ]
        let stringColors = themeNames.compactMap { testColorComponents(themePaletteColors(for: $0).string) }

        XCTAssertEqual(stringColors.count, themeNames.count)
        XCTAssertEqual(
            Set(stringColors).count,
            themeNames.count,
            "Nearby neon themes should not collapse onto the same string token color."
        )
    }
}
