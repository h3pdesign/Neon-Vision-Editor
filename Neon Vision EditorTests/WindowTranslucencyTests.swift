import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit
import SwiftUI

@MainActor


/// MARK: - Tests

final class WindowTranslucencyTests: XCTestCase {
    // Verifies that the translucency toggle updates registered editor windows without touching unrelated panels.
    func testApplyWindowTranslucencyUpdatesMacWindowFlags() {
        let testWindow = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        testWindow.isReleasedWhenClosed = false
        testWindow.orderFront(nil)
        let viewModel = EditorViewModel()
        WindowViewModelRegistry.shared.register(viewModel, for: testWindow.windowNumber)

        defer {
            WindowViewModelRegistry.shared.unregister(windowNumber: testWindow.windowNumber)
            testWindow.orderOut(nil)
            testWindow.close()
        }

        let sut = ContentView()

        sut.applyWindowTranslucency(true)
        XCTAssertFalse(testWindow.isOpaque)
        XCTAssertTrue(testWindow.titlebarAppearsTransparent)
        XCTAssertTrue((testWindow.backgroundColor?.alphaComponent ?? 1) < 1)

        sut.applyWindowTranslucency(false)
        XCTAssertTrue(testWindow.isOpaque)
        XCTAssertTrue(testWindow.titlebarAppearsTransparent)
        XCTAssertEqual(testWindow.backgroundColor, NSColor.windowBackgroundColor)
    }

    func testMacSettingsWindowPolicyRemainsResizableAndScrollableAtMinimumSize() {
        let sizePolicy = NeonSettingsView.macSettingsWindowSizePolicy()

        XCTAssertGreaterThanOrEqual(sizePolicy.min.width, 600)
        XCTAssertLessThanOrEqual(sizePolicy.min.height, 360)
        XCTAssertGreaterThanOrEqual(sizePolicy.ideal.width, 900)
        XCTAssertGreaterThanOrEqual(sizePolicy.ideal.height, 900)
        XCTAssertGreaterThan(sizePolicy.ideal.width, sizePolicy.min.width)
        XCTAssertGreaterThan(sizePolicy.ideal.height, sizePolicy.min.height)
    }

    func testMacSettingsWindowTranslucencyUsesVisibleAlpha() {
        let subtle = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: true,
            translucencyModeRaw: "subtle",
            appearanceRaw: "dark",
            effectiveColorScheme: .dark
        )
        let balanced = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: true,
            translucencyModeRaw: "balanced",
            appearanceRaw: "dark",
            effectiveColorScheme: .dark
        )
        let vibrant = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: true,
            translucencyModeRaw: "vibrant",
            appearanceRaw: "dark",
            effectiveColorScheme: .dark
        )
        let disabled = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: false,
            translucencyModeRaw: "vibrant",
            appearanceRaw: "dark",
            effectiveColorScheme: .dark
        )

        XCTAssertEqual(subtle.alphaComponent, 0.82, accuracy: 0.001)
        XCTAssertEqual(balanced.alphaComponent, 0.72, accuracy: 0.001)
        XCTAssertEqual(vibrant.alphaComponent, 0.62, accuracy: 0.001)
        XCTAssertGreaterThan(subtle.alphaComponent, balanced.alphaComponent)
        XCTAssertLessThan(vibrant.alphaComponent, balanced.alphaComponent)
        XCTAssertEqual(disabled, NSColor.windowBackgroundColor)
    }
}
#endif
