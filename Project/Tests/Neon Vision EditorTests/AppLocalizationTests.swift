import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class AppLocalizationTests: XCTestCase {
    func testEveryWebsiteLanguageIsBundledWithTranslatedEditorUI() throws {
        for code in ["de", "da", "fr", "es", "ja", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj"), code)
            let bundle = try XCTUnwrap(Bundle(path: path), code)
            for key in ["Settings", "Save", "Close Tab", "Editor Essentials"] {
                let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
                XCTAssertNotEqual(value, key, "Missing \(key) translation for \(code)")
            }
            let countFormat = bundle.localizedString(forKey: "%d lines", value: nil, table: "Localizable")
            XCTAssertFalse(String(format: countFormat, 42).contains("%d"), "Broken count format for \(code)")
        }
    }
}
