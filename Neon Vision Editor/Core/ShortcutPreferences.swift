import Foundation
#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Applies the user-configured shortcut to SwiftUI commands on every platform.
    func editorShortcut(_ action: EditorShortcutAction) -> some View {
        let descriptor = ShortcutPreferences.shortcut(for: action)
        return keyboardShortcut(descriptor.keyEquivalent, modifiers: descriptor.eventModifiers)
    }
}
#endif

enum EditorShortcutAction: String, CaseIterable, Identifiable {
    case closeTab
    case newTab
    case openFile
    case save
    case find
    case findInFiles
    case goToLine
    case goToSymbol
    case quickOpen
    case toggleSidebar
    case toggleProjectSidebar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closeTab: return "Close Tab"
        case .newTab: return "New Tab"
        case .openFile: return "Open File"
        case .save: return "Save"
        case .find: return "Find"
        case .findInFiles: return "Find in Files"
        case .goToLine: return "Go to Line"
        case .goToSymbol: return "Go to Symbol"
        case .quickOpen: return "Quick Open"
        case .toggleSidebar: return "Toggle Sidebar"
        case .toggleProjectSidebar: return "Toggle Project Sidebar"
        }
    }

    var defaultShortcut: EditorShortcutDescriptor {
        switch self {
        case .closeTab: return .init(key: "w", modifiers: [.command])
        case .newTab: return .init(key: "t", modifiers: [.command])
        case .openFile: return .init(key: "o", modifiers: [.command])
        case .save: return .init(key: "s", modifiers: [.command])
        case .find: return .init(key: "f", modifiers: [.command])
        case .findInFiles: return .init(key: "f", modifiers: [.command, .shift])
        case .goToLine: return .init(key: "l", modifiers: [.command])
        case .goToSymbol: return .init(key: "j", modifiers: [.command, .shift])
        case .quickOpen: return .init(key: "p", modifiers: [.command])
        case .toggleSidebar: return .init(key: "s", modifiers: [.command, .alternate])
        case .toggleProjectSidebar: return .init(key: "p", modifiers: [.command, .alternate])
        }
    }
}

enum KeyboardAccessoryAction: String, CaseIterable, Identifiable {
    case save
    case find
    case undo
    case redo

    static let storageKey = "SettingsKeyboardShortcutAccessoryActionsIOS"
    static let defaultActions: [KeyboardAccessoryAction] = [.save, .find, .undo, .redo]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .save: return "Save"
        case .find: return "Find"
        case .undo: return "Undo"
        case .redo: return "Redo"
        }
    }

    var symbolName: String {
        switch self {
        case .save: return "square.and.arrow.down"
        case .find: return "magnifyingglass"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        }
    }

    static func configuredActions(rawValue: String?) -> [KeyboardAccessoryAction] {
        let selected = Set((rawValue ?? defaultActions.map(\.rawValue).joined(separator: ","))
            .split(separator: ",")
            .compactMap { KeyboardAccessoryAction(rawValue: String($0)) })
        return allCases.filter(selected.contains)
    }

    static func storageValue(for actions: [KeyboardAccessoryAction]) -> String {
        allCases.filter(actions.contains).map(\.rawValue).joined(separator: ",")
    }
}

struct EditorShortcutModifiers: OptionSet, Hashable {
    let rawValue: Int
    static let command = EditorShortcutModifiers(rawValue: 1 << 0)
    static let shift = EditorShortcutModifiers(rawValue: 1 << 1)
    static let alternate = EditorShortcutModifiers(rawValue: 1 << 2)
    static let control = EditorShortcutModifiers(rawValue: 1 << 3)
}

struct EditorShortcutDescriptor: Equatable, Hashable {
    let key: String
    let modifiers: EditorShortcutModifiers

    var normalizedStorageValue: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.alternate) { parts.append("alt") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        parts.append(key.lowercased())
        return parts.joined(separator: "+")
    }
}

enum ShortcutPreferences {
    private static let keyPrefix = "SettingsShortcut."
    static let reservedMobileCommandShortcuts: Set<EditorShortcutDescriptor> = [
        .init(key: "z", modifiers: [.command]),
        .init(key: "z", modifiers: [.command, .shift]),
        .init(key: "o", modifiers: [.command, .shift]),
        .init(key: "g", modifiers: [.command]),
        .init(key: "?", modifiers: [.command]),
        .init(key: ",", modifiers: [.command])
    ]

    static func storageKey(for action: EditorShortcutAction) -> String {
        keyPrefix + action.rawValue
    }

    static func shortcut(for action: EditorShortcutAction, defaults: UserDefaults = .standard) -> EditorShortcutDescriptor {
        guard let raw = defaults.string(forKey: storageKey(for: action)),
              let parsed = parseShortcut(raw) else {
            return action.defaultShortcut
        }
        return parsed
    }

    static func rawShortcut(for action: EditorShortcutAction, defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: storageKey(for: action)),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        return action.defaultShortcut.normalizedStorageValue
    }

    static func setRawShortcut(_ raw: String, for action: EditorShortcutAction, defaults: UserDefaults = .standard) {
        defaults.set(raw, forKey: storageKey(for: action))
    }

    static func resetAllToDefaults(defaults: UserDefaults = .standard) {
        for action in EditorShortcutAction.allCases {
            defaults.set(action.defaultShortcut.normalizedStorageValue, forKey: storageKey(for: action))
        }
    }

    /// Preserves declaration order while ensuring UIKit receives at most one
    /// command for each key/modifier pair. Reserved commands are owned by the
    /// app's command menu rather than the editor shortcut bridge.
    static func nonConflictingActions(
        _ actions: [EditorShortcutAction],
        reservedShortcuts: Set<EditorShortcutDescriptor> = [],
        defaults: UserDefaults = .standard
    ) -> [EditorShortcutAction] {
        var registeredShortcuts = reservedShortcuts
        return actions.filter { action in
            registeredShortcuts.insert(shortcut(for: action, defaults: defaults)).inserted
        }
    }

    static func parseShortcut(_ rawValue: String) -> EditorShortcutDescriptor? {
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return nil }

        let tokens = normalized.split(separator: "+").map(String.init)
        guard !tokens.isEmpty else { return nil }

        var modifiers: EditorShortcutModifiers = []
        var keyToken: String?

        for token in tokens {
            switch token {
            case "cmd", "command", "⌘":
                modifiers.insert(.command)
            case "shift", "⇧":
                modifiers.insert(.shift)
            case "alt", "option", "⌥":
                modifiers.insert(.alternate)
            case "ctrl", "control", "^":
                modifiers.insert(.control)
            default:
                if keyToken == nil {
                    keyToken = token
                } else {
                    return nil
                }
            }
        }

        guard modifiers.contains(.command),
              let keyToken,
              let resolvedKey = normalizedKey(from: keyToken) else {
            return nil
        }

        return EditorShortcutDescriptor(key: resolvedKey, modifiers: modifiers)
    }

    private static func normalizedKey(from token: String) -> String? {
        if token.count == 1 {
            let scalar = token.unicodeScalars.first
            if let scalar, CharacterSet.alphanumerics.contains(scalar) {
                return String(token.lowercased())
            }
        }

        switch token {
        case "up", "uparrow": return UIKeyAlias.upArrow
        case "down", "downarrow": return UIKeyAlias.downArrow
        case "left", "leftarrow": return UIKeyAlias.leftArrow
        case "right", "rightarrow": return UIKeyAlias.rightArrow
        default:
            return nil
        }
    }
}

private enum UIKeyAlias {
    static let upArrow = "↑"
    static let downArrow = "↓"
    static let leftArrow = "←"
    static let rightArrow = "→"
}

#if canImport(SwiftUI)
extension EditorShortcutDescriptor {
    var keyEquivalent: KeyEquivalent {
        switch key {
        case UIKeyAlias.upArrow:
            return .upArrow
        case UIKeyAlias.downArrow:
            return .downArrow
        case UIKeyAlias.leftArrow:
            return .leftArrow
        case UIKeyAlias.rightArrow:
            return .rightArrow
        default:
            return KeyEquivalent(Character(key.lowercased()))
        }
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.alternate) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}
#endif
