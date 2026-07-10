import AppKit
import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
final class EditorActivityFocusTests: XCTestCase {
    func testRestoresFocusWhenWindowBecomesKeyAndWindowOwnsResponder() {
        XCTAssertTrue(
            AcceptingTextView.shouldRestoreEditorFocusAfterActivityChange(
                notificationName: NSWindow.didBecomeKeyNotification,
                notificationTargetsOwnWindow: true,
                windowIsKey: true,
                windowIsMain: true,
                isSelectable: true,
                focusOwner: .window
            )
        )
    }

    func testRestoresFocusWhenAppBecomesActiveAndEditorChromeOwnsResponder() {
        XCTAssertTrue(
            AcceptingTextView.shouldRestoreEditorFocusAfterActivityChange(
                notificationName: NSApplication.didBecomeActiveNotification,
                notificationTargetsOwnWindow: false,
                windowIsKey: false,
                windowIsMain: true,
                isSelectable: true,
                focusOwner: .editorChrome
            )
        )
    }

    func testDoesNotRestoreFocusWhenAnotherControlOwnsResponder() {
        XCTAssertFalse(
            AcceptingTextView.shouldRestoreEditorFocusAfterActivityChange(
                notificationName: NSWindow.didBecomeKeyNotification,
                notificationTargetsOwnWindow: true,
                windowIsKey: true,
                windowIsMain: true,
                isSelectable: true,
                focusOwner: .other
            )
        )
    }

    func testDoesNotRestoreFocusForResignNotifications() {
        XCTAssertFalse(
            AcceptingTextView.shouldRestoreEditorFocusAfterActivityChange(
                notificationName: NSWindow.didResignKeyNotification,
                notificationTargetsOwnWindow: true,
                windowIsKey: false,
                windowIsMain: false,
                isSelectable: true,
                focusOwner: .window
            )
        )
    }
}
#endif
