import SwiftUI
#if canImport(UIKit)
import UIKit



// MARK: - Types

struct IPadKeyboardShortcutBridge: UIViewRepresentable {
    let onCloseTab: () -> Void
    let onNewTab: () -> Void
    let onOpenFile: () -> Void
    let onSave: () -> Void
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
    var onFind: (() -> Void)?
    var onFindInFiles: (() -> Void)?
    var onGoToLine: (() -> Void)?
    var onGoToSymbol: (() -> Void)?
    var onQuickOpen: (() -> Void)?
    var onToggleSidebar: (() -> Void)?
    var onToggleProjectSidebar: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return [] }
        let mappings: [(EditorShortcutAction, Selector, String)] = [
            (.closeTab, #selector(closeTab), "Close Tab"),
            (.newTab, #selector(newTab), "New Tab"),
            (.openFile, #selector(openFile), "Open File"),
            (.save, #selector(saveFile), "Save"),
            (.find, #selector(handleFindCommand), "Find"),
            (.findInFiles, #selector(findInFiles), "Find in Files"),
            (.goToLine, #selector(goToLine), "Go to Line"),
            (.goToSymbol, #selector(goToSymbol), "Go to Symbol"),
            (.quickOpen, #selector(quickOpen), "Quick Open"),
            (.toggleSidebar, #selector(handleToggleSidebarCommand), "Toggle Sidebar"),
            (.toggleProjectSidebar, #selector(handleToggleProjectSidebarCommand), "Toggle Project Structure Sidebar")
        ]
        return mappings.compactMap { action, selector, title in
            let descriptor = ShortcutPreferences.shortcut(for: action)
            guard let input = uiKeyInput(from: descriptor.key) else { return nil }
            let command = UIKeyCommand(
                input: input,
                modifierFlags: uiKeyModifierFlags(from: descriptor.modifiers),
                action: selector
            )
            command.discoverabilityTitle = title
            return command
        }
    }

    private func uiKeyModifierFlags(from modifiers: EditorShortcutModifiers) -> UIKeyModifierFlags {
        var result: UIKeyModifierFlags = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.alternate) { result.insert(.alternate) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }

    private func uiKeyInput(from key: String) -> String? {
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
        guard window != nil, UIDevice.current.userInterfaceIdiom == .pad else { return }
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

    @objc private func newTab() { onNewTab?() }
    @objc private func closeTab() { onCloseTab?() }
    @objc private func openFile() { onOpenFile?() }
    @objc private func saveFile() { onSave?() }
    @objc private func handleFindCommand() { onFind?() }
    @objc private func findInFiles() { onFindInFiles?() }
    @objc private func goToLine() { onGoToLine?() }
    @objc private func goToSymbol() { onGoToSymbol?() }
    @objc private func quickOpen() { onQuickOpen?() }
    @objc private func handleToggleSidebarCommand() { onToggleSidebar?() }
    @objc private func handleToggleProjectSidebarCommand() { onToggleProjectSidebar?() }
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
