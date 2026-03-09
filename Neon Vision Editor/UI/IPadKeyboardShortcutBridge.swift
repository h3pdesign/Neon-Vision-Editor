import SwiftUI
#if canImport(UIKit)
import UIKit



/// MARK: - Types

struct IPadKeyboardShortcutBridge: UIViewRepresentable {
    let onNewTab: () -> Void
    let onOpenFile: () -> Void
    let onSave: () -> Void
    let onFind: () -> Void
    let onFindInFiles: () -> Void
    let onQuickOpen: () -> Void

    func makeUIView(context: Context) -> KeyboardCommandView {
        let view = KeyboardCommandView()
        view.onNewTab = onNewTab
        view.onOpenFile = onOpenFile
        view.onSave = onSave
        view.onFind = onFind
        view.onFindInFiles = onFindInFiles
        view.onQuickOpen = onQuickOpen
        return view
    }

    func updateUIView(_ uiView: KeyboardCommandView, context: Context) {
        uiView.onNewTab = onNewTab
        uiView.onOpenFile = onOpenFile
        uiView.onSave = onSave
        uiView.onFind = onFind
        uiView.onFindInFiles = onFindInFiles
        uiView.onQuickOpen = onQuickOpen
        uiView.refreshFirstResponderStatus()
    }
}

final class KeyboardCommandView: UIView {
    var onNewTab: (() -> Void)?
    var onOpenFile: (() -> Void)?
    var onSave: (() -> Void)?
    var onFind: (() -> Void)?
    var onFindInFiles: (() -> Void)?
    var onQuickOpen: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return [] }
        let newTabCommand = UIKeyCommand(input: "t", modifierFlags: .command, action: #selector(newTab))
        newTabCommand.discoverabilityTitle = "New Tab"
        let openFileCommand = UIKeyCommand(input: "o", modifierFlags: .command, action: #selector(openFile))
        openFileCommand.discoverabilityTitle = "Open File"
        let saveCommand = UIKeyCommand(input: "s", modifierFlags: .command, action: #selector(saveFile))
        saveCommand.discoverabilityTitle = "Save"
        let findCommand = UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(handleFindCommand))
        findCommand.discoverabilityTitle = "Find"
        let findInFilesCommand = UIKeyCommand(input: "f", modifierFlags: [.command, .shift], action: #selector(findInFiles))
        findInFilesCommand.discoverabilityTitle = "Find in Files"
        let quickOpenCommand = UIKeyCommand(input: "p", modifierFlags: .command, action: #selector(quickOpen))
        quickOpenCommand.discoverabilityTitle = "Quick Open"

        return [
            newTabCommand,
            openFileCommand,
            saveCommand,
            findCommand,
            findInFilesCommand,
            quickOpenCommand
        ]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshFirstResponderStatus()
    }

    func refreshFirstResponderStatus() {
        guard window != nil, UIDevice.current.userInterfaceIdiom == .pad else { return }
        DispatchQueue.main.async { [weak self] in
            _ = self?.becomeFirstResponder()
        }
    }

    @objc private func newTab() { onNewTab?() }
    @objc private func openFile() { onOpenFile?() }
    @objc private func saveFile() { onSave?() }
    @objc private func handleFindCommand() { onFind?() }
    @objc private func findInFiles() { onFindInFiles?() }
    @objc private func quickOpen() { onQuickOpen?() }
}
#endif
