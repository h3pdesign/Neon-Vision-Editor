import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class EditorSettingsDefaultsTests: XCTestCase {
    func testCodeTemplateCatalogProvidesUsefulDefaultsForEverySupportedLanguage() throws {
        XCTAssertEqual(Set(CodeTemplateCatalog.supportedLanguages).count, CodeTemplateCatalog.supportedLanguages.count)

        for language in CodeTemplateCatalog.supportedLanguages {
            let template = try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: language), language)
            XCTAssertFalse(template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, language)
            XCTAssertTrue(template.hasSuffix("\n"), language)
            XCTAssertNotEqual(template, "TODO\n", language)
        }
    }

    func testCodeTemplateCatalogUsesPracticalLanguageSpecificStarters() throws {
        XCTAssertTrue(try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: "swift")).contains("CommandLine.arguments"))
        XCTAssertTrue(try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: "python")).contains("if __name__ == \"__main__\""))
        XCTAssertTrue(try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: "html")).contains("name=\"viewport\""))
        XCTAssertTrue(try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: "bash")).contains("set -euo pipefail"))
        XCTAssertNil(CodeTemplateCatalog.defaultTemplate(for: "unknown"))
    }

    func testStructuredCodeTemplatesAreValidJSON() throws {
        for language in ["json", "ipynb"] {
            let template = try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: language))
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(template.utf8)), language)
        }
    }

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

    func testEditorFontSizeSetterClampsPinchUpdatesToSupportedRange() {
        let defaults = UserDefaults.standard
        let key = "SettingsEditorFontSize"
        let previousValue = defaults.object(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        let contentView = ContentView()

        contentView.setEditorFontSize(18)
        XCTAssertEqual(contentView.editorFontSize, 18)

        contentView.setEditorFontSize(40)
        XCTAssertEqual(contentView.editorFontSize, 28)

        contentView.setEditorFontSize(4)
        XCTAssertEqual(contentView.editorFontSize, 10)
    }

    func testAutomaticWritingAssistanceFollowsDocumentLanguage() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.set(EditorWritingAssistanceMode.automatic.rawValue, forKey: SettingsPreferenceKey.writingAssistanceMode)

        XCTAssertEqual(
            EditorWritingAssistanceProfile.resolved(language: "markdown", defaults: defaults),
            EditorWritingAssistanceProfile(autocorrection: true, autocapitalization: true, spellChecking: true)
        )
        XCTAssertEqual(
            EditorWritingAssistanceProfile.resolved(language: "swift", defaults: defaults),
            EditorWritingAssistanceProfile(autocorrection: false, autocapitalization: false, spellChecking: false)
        )
    }

    func testCustomWritingAssistanceOverridesLanguageDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.set(EditorWritingAssistanceMode.custom.rawValue, forKey: SettingsPreferenceKey.writingAssistanceMode)
        defaults.set(true, forKey: SettingsPreferenceKey.spellCheckingEnabled)

        XCTAssertEqual(
            EditorWritingAssistanceProfile.resolved(language: "swift", defaults: defaults),
            EditorWritingAssistanceProfile(autocorrection: false, autocapitalization: false, spellChecking: true)
        )
    }
}
