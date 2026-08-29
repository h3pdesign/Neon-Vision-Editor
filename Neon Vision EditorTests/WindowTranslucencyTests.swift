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

    func testVirtualEditorCoreTextDrawingOwnsCoordinateState() {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.translateBy(x: 0, y: 4)
        context.scaleBy(x: 1, y: -1)
        let inheritedPosition = CGPoint(x: 1, y: 1)
        context.textMatrix = CGAffineTransform(scaleX: -1, y: 1)
        context.textPosition = inheritedPosition
        let inheritedMatrix = context.textMatrix
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "A"))

        VirtualEditorCoreTextDrawing.draw(
            line,
            in: context,
            at: CGPoint(x: 2, y: 3),
            flippedCoordinates: true
        )

        XCTAssertEqual(context.textMatrix, inheritedMatrix)
        XCTAssertEqual(context.textPosition, inheritedPosition)

        let flippedMatrix = VirtualEditorCoreTextDrawing.textMatrix(forFlippedCoordinates: true)
        XCTAssertEqual(flippedMatrix.a, 1, accuracy: 0.001)
        XCTAssertEqual(flippedMatrix.d, -1, accuracy: 0.001)
        XCTAssertGreaterThan(context.ctm.d * flippedMatrix.d, 0)

        let unflippedMatrix = VirtualEditorCoreTextDrawing.textMatrix(forFlippedCoordinates: false)
        XCTAssertEqual(unflippedMatrix, .identity)
    }

    func testVirtualEditorCanvasUsesEditorThemeWhenTranslucencyIsDisabled() {
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
        let expected = try! XCTUnwrap(NSColor(currentEditorTheme(colorScheme: .light).background).usingColorSpace(.deviceRGB))
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

    func testInterPaneBackgroundFollowsTranslucencyAndOpaqueEditorCanvas() {
        let translucent = ContentView.MacEditorSurfacePolicy.interPaneBackground(
            translucent: true,
            opaqueEditorCanvas: true,
            editor: .red,
            solid: .blue
        )
        let opaqueEditor = ContentView.MacEditorSurfacePolicy.interPaneBackground(
            translucent: false,
            opaqueEditorCanvas: true,
            editor: .red,
            solid: .blue
        )
        let opaqueWindow = ContentView.MacEditorSurfacePolicy.interPaneBackground(
            translucent: false,
            opaqueEditorCanvas: false,
            editor: .red,
            solid: .blue
        )

        XCTAssertEqual(NSColor(translucent).alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(NSColor(opaqueEditor), NSColor(.red))
        XCTAssertEqual(NSColor(opaqueWindow), NSColor(.blue))
    }

    func testEditorSurfaceVisualMatrixMatchesAppearanceAndOpacityModes() throws {
        let lightWindow = ContentView.MacEditorSurfacePolicy.windowBackground(
            translucent: false,
            modeRaw: "balanced",
            isDarkMode: false
        )
        let darkWindow = ContentView.MacEditorSurfacePolicy.windowBackground(
            translucent: false,
            modeRaw: "balanced",
            isDarkMode: true
        )
        let lightEditor = NSColor(currentEditorTheme(colorScheme: .light).background)
        let darkEditor = NSColor(currentEditorTheme(colorScheme: .dark).background)

        let cases: [(String, Color, NSColor)] = [
            (
                "light opaque window",
                ContentView.MacEditorSurfacePolicy.interPaneBackground(
                    translucent: false,
                    opaqueEditorCanvas: false,
                    editor: Color(lightEditor),
                    solid: Color(lightWindow)
                ),
                lightWindow
            ),
            (
                "dark opaque window",
                ContentView.MacEditorSurfacePolicy.interPaneBackground(
                    translucent: false,
                    opaqueEditorCanvas: false,
                    editor: Color(darkEditor),
                    solid: Color(darkWindow)
                ),
                darkWindow
            ),
            (
                "light opaque editor",
                ContentView.MacEditorSurfacePolicy.interPaneBackground(
                    translucent: false,
                    opaqueEditorCanvas: true,
                    editor: Color(lightEditor),
                    solid: Color(lightWindow)
                ),
                lightEditor
            ),
            (
                "dark opaque editor",
                ContentView.MacEditorSurfacePolicy.interPaneBackground(
                    translucent: false,
                    opaqueEditorCanvas: true,
                    editor: Color(darkEditor),
                    solid: Color(darkWindow)
                ),
                darkEditor
            )
        ]

        for (name, color, expected) in cases {
            let actual = try XCTUnwrap(renderedPixel(color: NSColor(color)))
            assertColor(actual, matches: expected, message: name)
        }

        for isDarkMode in [false, true] {
            let translucent = ContentView.MacEditorSurfacePolicy.interPaneBackground(
                translucent: true,
                opaqueEditorCanvas: true,
                editor: isDarkMode ? Color(darkEditor) : Color(lightEditor),
                solid: Color(
                    ContentView.MacEditorSurfacePolicy.windowBackground(
                        translucent: false,
                        modeRaw: "balanced",
                        isDarkMode: isDarkMode
                    )
                )
            )
            let actual = try XCTUnwrap(renderedPixel(color: NSColor(translucent)))
            XCTAssertEqual(actual.alphaComponent, 0, accuracy: 1.0 / 255.0)
        }
    }

    private func renderedPixel(color: NSColor) -> NSColor? {
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
        color.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
    }

    private func assertColor(_ actual: NSColor, matches expected: NSColor, message: String) {
        let expectedRGB = expected.usingColorSpace(.deviceRGB) ?? expected
        let tolerance = 1.0 / 255.0
        XCTAssertEqual(actual.redComponent, expectedRGB.redComponent, accuracy: tolerance, message)
        XCTAssertEqual(actual.greenComponent, expectedRGB.greenComponent, accuracy: tolerance, message)
        XCTAssertEqual(actual.blueComponent, expectedRGB.blueComponent, accuracy: tolerance, message)
        XCTAssertEqual(actual.alphaComponent, expectedRGB.alphaComponent, accuracy: tolerance, message)
    }
}
#endif
