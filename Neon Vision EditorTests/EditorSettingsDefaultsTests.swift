import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class EditorSettingsDefaultsTests: XCTestCase {
    func testFreshEditorSettingsDefaultsStayReviewSafe() {
        let defaults = UserDefaults.standard
        let keys = [
            "SettingsLineWrapEnabled",
            "SettingsEditorFontSize",
            "SettingsLineHeight"
        ]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let previousValue = previousValues[key] ?? nil {
                    defaults.set(previousValue, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        keys.forEach(defaults.removeObject)

        let contentView = ContentView()
        XCTAssertTrue(contentView.settingsLineWrapEnabled)
        XCTAssertEqual(contentView.editorFontSize, 14)
        XCTAssertEqual(contentView.editorLineHeight, 1.0)
    }
}
