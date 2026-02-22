import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit

@MainActor
final class WindowTranslucencyTests: XCTestCase {
    // Verifies that the translucency toggle updates AppKit window flags used by the toolbar/titlebar.
    func testApplyWindowTranslucencyUpdatesMacWindowFlags() {
        let testWindow = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        testWindow.isReleasedWhenClosed = false
        testWindow.orderFront(nil)

        defer {
            testWindow.orderOut(nil)
            testWindow.close()
        }

        let sut = ContentView()

        sut.applyWindowTranslucency(true)
        XCTAssertFalse(testWindow.isOpaque)
        XCTAssertTrue(testWindow.titlebarAppearsTransparent)
        XCTAssertEqual(testWindow.backgroundColor, .clear)

        sut.applyWindowTranslucency(false)
        XCTAssertTrue(testWindow.isOpaque)
        XCTAssertFalse(testWindow.titlebarAppearsTransparent)
        XCTAssertEqual(testWindow.backgroundColor, NSColor.windowBackgroundColor)
    }
}
#endif
