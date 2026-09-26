import SwiftUI
#if canImport(UIKit)
import UIKit



// MARK: - Types

struct IPadKeyboardShortcutBridge: UIViewRepresentable {
    let onCloseTab: () -> Void
    let onNewTab: () -> Void
    let onOpenFile: () -> Void
    let onSave: () -> Void
    let onSaveAs: () -> Void
    let onToggleLineWrap: () -> Void
    let onLanguageSearch: () -> Void
    let onUndo: () -> Void
    let onFind: () -> Void
    let onFindInFiles: () -> Void
    let onGoToLine: () -> Void
    let onGoToSymbol: () -> Void
    let onQuickOpen: () -> Void
    let onToggleSidebar: () -> Void
    let onToggleProjectSidebar: () -> Void

    func makeUIView(context: Context) -> KeyboardCommandView {
        let view = KeyboardCommandView()
        view.onCloseTab = onCloseTab
        view.onNewTab = onNewTab
        view.onOpenFile = onOpenFile
        view.onSave = onSave
        view.onSaveAs = onSaveAs
        view.onToggleLineWrap = onToggleLineWrap
        view.onLanguageSearch = onLanguageSearch
        view.onUndo = onUndo
        view.onFind = onFind
        view.onFindInFiles = onFindInFiles
        view.onGoToLine = onGoToLine
        view.onGoToSymbol = onGoToSymbol
        view.onQuickOpen = onQuickOpen
        view.onToggleSidebar = onToggleSidebar
        view.onToggleProjectSidebar = onToggleProjectSidebar
        return view
    }

    func updateUIView(_ uiView: KeyboardCommandView, context: Context) {
        uiView.onNewTab = onNewTab
        uiView.onCloseTab = onCloseTab
        uiView.onOpenFile = onOpenFile
        uiView.onSave = onSave
        uiView.onSaveAs = onSaveAs
        uiView.onToggleLineWrap = onToggleLineWrap
        uiView.onLanguageSearch = onLanguageSearch
        uiView.onUndo = onUndo
        uiView.onFind = onFind
        uiView.onFindInFiles = onFindInFiles
        uiView.onGoToLine = onGoToLine
        uiView.onGoToSymbol = onGoToSymbol
        uiView.onQuickOpen = onQuickOpen
        uiView.onToggleSidebar = onToggleSidebar
        uiView.onToggleProjectSidebar = onToggleProjectSidebar
        uiView.refreshFirstResponderStatus()
    }
}

final class KeyboardCommandView: UIView {
    var onCloseTab: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onOpenFile: (() -> Void)?
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onToggleLineWrap: (() -> Void)?
    var onLanguageSearch: (() -> Void)?
    var onUndo: (() -> Void)?
    var onFind: (() -> Void)?
    var onFindInFiles: (() -> Void)?
    var onGoToLine: (() -> Void)?
    var onGoToSymbol: (() -> Void)?
    var onQuickOpen: (() -> Void)?
    var onToggleSidebar: (() -> Void)?
    var onToggleProjectSidebar: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        // The same hardware-keyboard command bridge is useful on iPhone with
        // an attached keyboard; keep it aligned with the iPadOS/iOS/visionOS help text.
        guard Self.supportsHardwareKeyboardCommands else { return [] }
        let undoCommand = UIKeyCommand(
            input: "z",
            modifierFlags: .command,
            action: #selector(undo)
        )
        undoCommand.discoverabilityTitle = "Undo"
        if #available(iOS 15.0, *) {
            undoCommand.wantsPriorityOverSystemBehavior = true
        }
        return Self.configuredAppCommands(action: #selector(handleConfiguredAppShortcut(_:))) + [undoCommand]
    }

    static func configuredAppCommands(action selector: Selector) -> [UIKeyCommand] {
        ShortcutPreferences.nonConflictingActions(
            EditorShortcutAction.allCases,
            reservedShortcuts: ShortcutPreferences.reservedMobileCommandShortcuts
        ).compactMap { action in
            let descriptor = ShortcutPreferences.shortcut(for: action)
            guard let input = uiKeyInput(from: descriptor.key) else { return nil }
            let command = UIKeyCommand(
                input: input,
                modifierFlags: uiKeyModifierFlags(from: descriptor.modifiers),
                action: selector
            )
            command.discoverabilityTitle = action.title
            return command
        }
    }

    static func configuredAction(for command: UIKeyCommand) -> EditorShortcutAction? {
        ShortcutPreferences.nonConflictingActions(
            EditorShortcutAction.allCases,
            reservedShortcuts: ShortcutPreferences.reservedMobileCommandShortcuts
        ).first { action in
            let descriptor = ShortcutPreferences.shortcut(for: action)
            return uiKeyInput(from: descriptor.key) == command.input &&
                uiKeyModifierFlags(from: descriptor.modifiers) == command.modifierFlags
        }
    }

    static var supportsHardwareKeyboardCommands: Bool {
#if os(visionOS)
        true
#else
        UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .phone
#endif
    }

    private static func uiKeyModifierFlags(from modifiers: EditorShortcutModifiers) -> UIKeyModifierFlags {
        var result: UIKeyModifierFlags = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.alternate) { result.insert(.alternate) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }

    private static func uiKeyInput(from key: String) -> String? {
        switch key {
        case "↑": return UIKeyCommand.inputUpArrow
        case "↓": return UIKeyCommand.inputDownArrow
        case "←": return UIKeyCommand.inputLeftArrow
        case "→": return UIKeyCommand.inputRightArrow
        default:
            guard key.count == 1 else { return nil }
            return key.lowercased()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshFirstResponderStatus()
    }

    func refreshFirstResponderStatus() {
        guard window != nil, Self.supportsHardwareKeyboardCommands else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            if let currentResponder = window.neonFirstResponder() {
                if currentResponder === self { return }
                if currentResponder is UITextView || currentResponder is UITextField {
                    return
                }
            }
            _ = self.becomeFirstResponder()
        }
    }

    @objc private func handleConfiguredAppShortcut(_ command: UIKeyCommand) {
        guard let action = Self.configuredAction(for: command) else { return }
        switch action {
        case .closeTab: onCloseTab?()
        case .newTab: onNewTab?()
        case .openFile: onOpenFile?()
        case .save: onSave?()
        case .saveAs: onSaveAs?()
        case .toggleLineWrap: onToggleLineWrap?()
        case .languageSearch: onLanguageSearch?()
        case .find: onFind?()
        case .findInFiles: onFindInFiles?()
        case .goToLine: onGoToLine?()
        case .goToSymbol: onGoToSymbol?()
        case .quickOpen: onQuickOpen?()
        case .toggleSidebar: onToggleSidebar?()
        case .toggleProjectSidebar: onToggleProjectSidebar?()
        }
    }
    @objc private func undo() { onUndo?() }
}

private extension UIView {
    func neonFirstResponder() -> UIResponder? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.neonFirstResponder() {
                return responder
            }
        }
        return nil
    }
}
#endif
