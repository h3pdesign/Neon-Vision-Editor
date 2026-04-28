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
