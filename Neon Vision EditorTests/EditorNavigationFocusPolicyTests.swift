import XCTest
@testable import Neon_Vision_Editor

final class EditorNavigationFocusPolicyTests: XCTestCase {
    func testExplicitNonFocusingNavigationKeepsEditorUnfocused() {
        XCTAssertFalse(
            EditorNavigationFocusPolicy.shouldFocusEditor(explicitValue: false)
        )
    }

    func testExistingNavigationCommandsFocusByDefault() {
        XCTAssertTrue(
            EditorNavigationFocusPolicy.shouldFocusEditor(explicitValue: nil)
        )
    }

    func testExplicitFocusingNavigationStillFocusesEditor() {
        XCTAssertTrue(
            EditorNavigationFocusPolicy.shouldFocusEditor(explicitValue: true)
        )
    }
}
