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
        let defaults = UserDefaults.standard
        let originalMode = defaults.object(forKey: "SettingsMacTranslucencyMode")
        defaults.set("balanced", forKey: "SettingsMacTranslucencyMode")
        defer {
            if let originalMode {
                defaults.set(originalMode, forKey: "SettingsMacTranslucencyMode")
            } else {
                defaults.removeObject(forKey: "SettingsMacTranslucencyMode")
            }
        }

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
        XCTAssertEqual(
            testWindow.backgroundColor,
            ContentView.MacEditorSurfacePolicy.windowBackground(
                translucent: false,
                modeRaw: "balanced",
                isDarkMode: false
            )
        )
    }

    func testMacSettingsWindowPolicyRemainsResizableAndScrollableAtMinimumSize() {
        let sizePolicy = NeonSettingsView.macSettingsWindowSizePolicy()

        XCTAssertGreaterThanOrEqual(sizePolicy.min.width, 600)
        XCTAssertLessThanOrEqual(sizePolicy.min.height, 360)
        XCTAssertEqual(sizePolicy.ideal.width, 900)
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

        XCTAssertEqual(subtle.alphaComponent, 0.92, accuracy: 0.001)
        XCTAssertEqual(balanced.alphaComponent, 0.88, accuracy: 0.001)
        XCTAssertEqual(vibrant.alphaComponent, 0.84, accuracy: 0.001)
        XCTAssertGreaterThan(subtle.alphaComponent, balanced.alphaComponent)
        XCTAssertLessThan(vibrant.alphaComponent, balanced.alphaComponent)
        XCTAssertEqual(disabled, NSColor.windowBackgroundColor)
    }

    func testVirtualEditorScrollSurfaceDoesNotPaintOpaqueDefaultBackground() {
        let scrollView = VirtualEditorScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertEqual(scrollView.backgroundColor, .clear)
        XCTAssertFalse(scrollView.contentView.drawsBackground)
    }

    func testVirtualEditorCanvasUsesWindowBackgroundWhenTranslucencyIsDisabled() {
        let defaults = UserDefaults.standard
        let originalMode = defaults.object(forKey: "SettingsMacTranslucencyMode")
        defaults.set("balanced", forKey: "SettingsMacTranslucencyMode")
        defer {
            if let originalMode {
                defaults.set(originalMode, forKey: "SettingsMacTranslucencyMode")
            } else {
                defaults.removeObject(forKey: "SettingsMacTranslucencyMode")
            }
        }

        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()

        let actual = try! XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let expected = try! XCTUnwrap(
            ContentView.MacEditorSurfacePolicy.windowBackground(
                translucent: false,
                modeRaw: "balanced",
                isDarkMode: false
            ).usingColorSpace(.deviceRGB)
        )
        let bitmapComponentTolerance = 1.0 / 255.0
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: bitmapComponentTolerance)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: bitmapComponentTolerance)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: bitmapComponentTolerance)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: bitmapComponentTolerance)
    }

    func testTranslucentEditorPanesLeaveTheWindowSurfaceUncovered() {
        let translucent = ContentView.MacEditorSurfacePolicy.paneBackground(translucent: true, solid: .red)
        let opaque = ContentView.MacEditorSurfacePolicy.paneBackground(translucent: false, solid: .red)

        XCTAssertEqual(NSColor(translucent).alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(NSColor(opaque), NSColor(.red))
    }
}
#endif
