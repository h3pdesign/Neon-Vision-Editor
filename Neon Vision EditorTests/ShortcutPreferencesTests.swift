import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ShortcutPreferencesTests: XCTestCase {
    func testParseShortcutAcceptsCommonFormat() {
        let parsed = ShortcutPreferences.parseShortcut("cmd+shift+f")
        XCTAssertEqual(parsed?.key, "f")
        XCTAssertTrue(parsed?.modifiers.contains(.command) == true)
        XCTAssertTrue(parsed?.modifiers.contains(.shift) == true)
    }

    func testParseShortcutRequiresCommandModifier() {
        XCTAssertNil(ShortcutPreferences.parseShortcut("shift+f"))
        XCTAssertNil(ShortcutPreferences.parseShortcut("alt+p"))
    }

    func testParseShortcutNormalizesCaseAndWhitespace() {
        let parsed = ShortcutPreferences.parseShortcut(" Cmd + Alt + P ")
        XCTAssertEqual(parsed?.normalizedStorageValue, "cmd+alt+p")
    }

    func testDefaultShortcutExistsForEveryAction() {
        for action in EditorShortcutAction.allCases {
            let shortcut = action.defaultShortcut
            XCTAssertFalse(shortcut.key.isEmpty)
            XCTAssertTrue(shortcut.modifiers.contains(.command))
        }
    }

    func testNonConflictingActionsKeepsFirstActionForDuplicateShortcut() {
        let defaults = UserDefaults(suiteName: "ShortcutPreferencesTests")!
        defer { defaults.removePersistentDomain(forName: "ShortcutPreferencesTests") }
        defaults.set("cmd+f", forKey: ShortcutPreferences.storageKey(for: .find))
        defaults.set("cmd+f", forKey: ShortcutPreferences.storageKey(for: .findInFiles))

        XCTAssertEqual(
            ShortcutPreferences.nonConflictingActions(
                [.find, .findInFiles],
                defaults: defaults
            ),
            [.find]
        )
    }

    func testNonConflictingActionsExcludesReservedCommandMenuShortcut() {
        let defaults = UserDefaults(suiteName: "ShortcutPreferencesTests")!
        defer { defaults.removePersistentDomain(forName: "ShortcutPreferencesTests") }
        defaults.set("cmd+z", forKey: ShortcutPreferences.storageKey(for: .save))

        XCTAssertTrue(
            ShortcutPreferences.nonConflictingActions(
                [.save],
                reservedShortcuts: ShortcutPreferences.reservedMobileCommandShortcuts,
                defaults: defaults
            ).isEmpty
        )
    }
}
