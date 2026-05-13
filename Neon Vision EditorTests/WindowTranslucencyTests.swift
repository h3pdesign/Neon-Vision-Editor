import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit

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
}
#endif
