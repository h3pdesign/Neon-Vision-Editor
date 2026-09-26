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
        var shortcuts: Set<EditorShortcutDescriptor> = []
        for action in EditorShortcutAction.allCases {
            let shortcut = action.defaultShortcut
            XCTAssertFalse(shortcut.key.isEmpty)
            XCTAssertTrue(shortcut.modifiers.contains(.command))
            XCTAssertTrue(shortcuts.insert(shortcut).inserted, "Duplicate default shortcut: \(action.title)")
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

    func testMobileEditorEditingShortcutsStayReserved() {
        let editingKeys = ["a", "c", "x", "v", "z", "b", "i", "k"]
        for key in editingKeys {
            let descriptor = EditorShortcutDescriptor(key: key, modifiers: [.command])
            XCTAssertTrue(
                ShortcutPreferences.reservedMobileCommandShortcuts.contains(descriptor),
                "Editor-owned Cmd+\(key.uppercased()) must not be assigned to an app action"
            )
        }
        XCTAssertTrue(ShortcutPreferences.reservedMobileCommandShortcuts.contains(
            .init(key: "z", modifiers: [.command, .shift])
        ))
    }

    func testKeyboardAccessoryActionsUseDefaultsAndIgnoreUnknownValues() {
        XCTAssertEqual(KeyboardAccessoryAction.configuredActions(rawValue: nil), KeyboardAccessoryAction.defaultActions)
        XCTAssertEqual(
            KeyboardAccessoryAction.configuredActions(rawValue: "find,unknown,save,find"),
            [.save, .find]
        )
    }
}
