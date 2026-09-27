#if os(iOS)
import Foundation
import SwiftUI
import UIKit

/// TextKit invalidates a whole paragraph after an edit. These display-only
/// paragraph separators bound that work without changing document offsets.
struct SegmentedLargeLineText {
    static let maximumParagraphUTF16 = 8_192
    static let separator = "\u{2029}"

    let display: String
    let separatorOffsets: [Int]

    init(source: String) {
        var display = String()
        display.reserveCapacity(source.utf16.count + source.utf16.count / Self.maximumParagraphUTF16)
        var offsets: [Int] = []
        var segmentStart = source.startIndex
        var segmentLength = 0
        var displayLength = 0
        for index in source.indices {
            let character = source[index]
            let length = character.utf16.count
            if segmentLength > 0 && segmentLength + length > Self.maximumParagraphUTF16 {
                let segment = source[segmentStart..<index]
                display.append(contentsOf: segment)
                displayLength += segment.utf16.count
                offsets.append(displayLength)
                display.append(contentsOf: Self.separator)
                displayLength += 1
                segmentStart = index
                segmentLength = 0
            }
            segmentLength = character == "\n" || character == "\r" || character == "\r\n" || character == "\u{2029}"
                ? 0 : segmentLength + length
        }
        display.append(contentsOf: source[segmentStart...])
        self.display = display
        self.separatorOffsets = offsets
    }

    static func sourceOffset(_ displayOffset: Int, separators: [Int]) -> Int {
        displayOffset - separators.partitioningIndex { $0 >= displayOffset }
    }

    static func displayOffset(_ sourceOffset: Int, separators: [Int]) -> Int {
        var lower = 0
        var upper = separators.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if separators[middle] - middle <= sourceOffset { lower = middle + 1 }
            else { upper = middle }
        }
        return sourceOffset + lower
    }
}

private extension Array where Element == Int {
    func partitioningIndex(_ predicate: (Int) -> Bool) -> Int {
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = (lower + upper) / 2
            if predicate(self[middle]) { upper = middle }
            else { lower = middle + 1 }
        }
        return lower
    }
}

final class SegmentedLargeLineInputView: EditorInputTextView {
    var copiedSource: ((NSRange) -> String)?
    var prepareInsertion: ((String, NSRange) -> String)?

    override func insertText(_ text: String) {
        super.insertText(prepareInsertion?(text, selectedRange) ?? text)
    }

    override func paste(_ sender: Any?) {
        if let value = UIPasteboard.general.string, !value.isEmpty {
            insertText(EditorTextSanitizer.sanitize(value))
        } else {
            super.paste(sender)
        }
    }

    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0, let copiedSource else {
            super.copy(sender)
            return
        }
        UIPasteboard.general.string = copiedSource(selectedRange)
    }

    override func cut(_ sender: Any?) {
        guard isEditable, selectedRange.length > 0 else { return }
        let selectedSource = copiedSource?(selectedRange)
        super.cut(sender)
        if let selectedSource { UIPasteboard.general.string = selectedSource }
    }
}

struct SegmentedLargeLineEditor: UIViewRepresentable {
    @Binding var text: String
    let documentID: UUID?
    let documentResourceID: String
    let storedCaretLocation: Int?
    let colorScheme: ColorScheme
    let formattingPreferences: EditorFormattingPreferences
    let ignoreBackgroundOverrides: Bool
    let fontSize: CGFloat
    let isReadOnly: Bool
    let showKeyboardAccessoryBar: Bool
    let softwareKeyboardVisible: Bool
    let onTextMutation: ((EditorTextMutation) -> Void)?
    let onShortcutAction: ((EditorShortcutAction) -> Void)?

    static let syntheticBreakKey = NSAttributedString.Key("NVESyntheticParagraphBreak")

    func makeUIView(context: Context) -> LineNumberedTextViewContainer {
        let view = SegmentedLargeLineInputView(usingTextLayoutManager: true)
        let container = LineNumberedTextViewContainer(textView: view)
        container.hideSyntheticLineGutter()
        view.delegate = context.coordinator
        view.onConfiguredAppShortcut = onShortcutAction
        view.isEditable = !isReadOnly
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceHorizontal = false
        view.showsHorizontalScrollIndicator = false
        view.accessibilityHint = NSLocalizedString(
            "Long lines wrap automatically to keep editing responsive.",
            comment: "Editor safety wrap accessibility hint"
        )
        let theme = currentEditorTheme(
            colorScheme: colorScheme,
            formatting: formattingPreferences,
            ignoreBackgroundOverrides: ignoreBackgroundOverrides
        )
        container.backgroundColor = UIColor(theme.background)
        view.backgroundColor = .clear
        view.textColor = UIColor(theme.text)
        view.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.textContainer.lineBreakMode = .byCharWrapping
        view.textContainer.widthTracksTextView = true
        view.setBracketAccessoryVisible(showKeyboardAccessoryBar)
        container.setSoftwareKeyboardVisible(softwareKeyboardVisible)
        context.coordinator.install(text, in: view, caret: storedCaretLocation)
        view.copiedSource = { [weak coordinator = context.coordinator] range in
            coordinator?.sourceText(in: range) ?? ""
        }
        view.prepareInsertion = { [weak coordinator = context.coordinator] value, range in
            coordinator?.prepareInsertion(value, replacing: range) ?? value
        }
        return container
    }

    func updateUIView(_ container: LineNumberedTextViewContainer, context: Context) {
        guard let view = container.textView as? SegmentedLargeLineInputView else { return }
        context.coordinator.parent = self
        view.onConfiguredAppShortcut = onShortcutAction
        view.isEditable = !isReadOnly
        view.setBracketAccessoryVisible(showKeyboardAccessoryBar)
        container.setSoftwareKeyboardVisible(softwareKeyboardVisible)
        if view.font?.pointSize != fontSize {
            view.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if context.coordinator.resourceID != documentResourceID || context.coordinator.source != text {
            context.coordinator.install(text, in: view, caret: storedCaretLocation)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SegmentedLargeLineEditor
        var resourceID = ""
        var source = ""
        private var display = ""
        private var separatorOffsets: [Int] = []
        private var isInstalling = false
        private var pendingChange: (range: NSRange, replacement: String)?
        private var pendingNewBreakOffsets: [Int] = []
        private var hasPreparedInsertion = false

        init(_ parent: SegmentedLargeLineEditor) { self.parent = parent }

        func install(_ source: String, in view: SegmentedLargeLineInputView, caret: Int?) {
            isInstalling = true
            defer { isInstalling = false }
            let segmented = SegmentedLargeLineText(source: source)
            self.source = source
            display = segmented.display
            separatorOffsets = segmented.separatorOffsets
            resourceID = parent.documentResourceID
            pendingChange = nil
            pendingNewBreakOffsets = []
            hasPreparedInsertion = false
            view.text = display
            markBreaks(segmented.separatorOffsets, in: view)
            view.accessibilityValue = source
            let safeCaret = min(max(0, caret ?? 0), (source as NSString).length)
            view.selectedRange = NSRange(
                location: SegmentedLargeLineText.displayOffset(safeCaret, separators: separatorOffsets),
                length: 0
            )
            view.rememberPreferredWrapLayout(
                shouldWrapText: true,
                containerWidth: max(1, view.bounds.width),
                lineBreakMode: .byCharWrapping
            )
            publishSelection(view)
        }

        private func markBreaks(_ offsets: [Int], in view: UITextView) {
            let storage = view.textStorage
            let contents = storage.string as NSString
            storage.beginEditing()
            for offset in offsets where offset < storage.length {
                guard contents.character(at: offset) == 0x2029 else { continue }
                storage.addAttribute(
                    SegmentedLargeLineEditor.syntheticBreakKey,
                    value: true,
                    range: NSRange(location: offset, length: 1)
                )
            }
            storage.endEditing()
        }

        func sourceText(in displayRange: NSRange) -> String {
            let start = SegmentedLargeLineText.sourceOffset(displayRange.location, separators: separatorOffsets)
            let end = SegmentedLargeLineText.sourceOffset(NSMaxRange(displayRange), separators: separatorOffsets)
            let safe = NSRange(location: max(0, start), length: max(0, end - start))
            guard NSMaxRange(safe) <= (source as NSString).length else { return "" }
            return (source as NSString).substring(with: safe)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard !isInstalling else { return false }
            if hasPreparedInsertion { return true }
            let rawStart = SegmentedLargeLineText.sourceOffset(range.location, separators: separatorOffsets)
            let rawEnd = SegmentedLargeLineText.sourceOffset(NSMaxRange(range), separators: separatorOffsets)
            guard rawStart >= 0, rawEnd <= (source as NSString).length else { return false }
            pendingChange = (NSRange(location: rawStart, length: rawEnd - rawStart), replacement)
            return true
        }

        func prepareInsertion(_ value: String, replacing displayRange: NSRange) -> String {
            guard !parent.isReadOnly,
                  value.utf16.count > SegmentedLargeLineText.maximumParagraphUTF16 else { return value }
            let segmented = SegmentedLargeLineText(source: value)
            let rawStart = SegmentedLargeLineText.sourceOffset(displayRange.location, separators: separatorOffsets)
            let rawEnd = SegmentedLargeLineText.sourceOffset(NSMaxRange(displayRange), separators: separatorOffsets)
            pendingChange = (NSRange(location: rawStart, length: rawEnd - rawStart), value)
            pendingNewBreakOffsets = segmented.separatorOffsets.map { displayRange.location + $0 }
            hasPreparedInsertion = true
            return segmented.display
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isInstalling else { return }
            let newDisplay = textView.text ?? ""
            if !pendingNewBreakOffsets.isEmpty {
                markBreaks(pendingNewBreakOffsets, in: textView)
            }
            let newBreaks = syntheticBreakOffsets(in: textView)
            let change = pendingChange ?? inferredChange(in: newDisplay, newBreaks: newBreaks)
            pendingChange = nil
            pendingNewBreakOffsets = []
            hasPreparedInsertion = false
            guard let change else { return }
            source = (source as NSString).replacingCharacters(in: change.range, with: change.replacement)
            display = newDisplay
            separatorOffsets = newBreaks
            textView.typingAttributes.removeValue(forKey: SegmentedLargeLineEditor.syntheticBreakKey)
            textView.accessibilityValue = source
            if let documentID = parent.documentID, let onTextMutation = parent.onTextMutation {
                onTextMutation(EditorTextMutation(documentID: documentID, range: change.range, replacement: change.replacement))
            } else {
                parent.text = source
            }
            publishSelection(textView)
        }

        private func inferredChange(
            in newDisplay: String,
            newBreaks: [Int]
        ) -> (range: NSRange, replacement: String)? {
            let old = display as NSString
            let new = newDisplay as NSString
            var prefix = 0
            while prefix < min(old.length, new.length),
                  old.character(at: prefix) == new.character(at: prefix) {
                prefix += 1
            }
            var suffix = 0
            while suffix < min(old.length - prefix, new.length - prefix),
                  old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) {
                suffix += 1
            }
            guard prefix < old.length || prefix < new.length else { return nil }
            let oldRange = NSRange(location: prefix, length: old.length - prefix - suffix)
            let newRange = NSRange(location: prefix, length: new.length - prefix - suffix)
            let replacement = NSMutableString(string: new.substring(with: newRange))
            for offset in newBreaks.reversed() where offset >= prefix && offset < NSMaxRange(newRange) {
                replacement.deleteCharacters(in: NSRange(location: offset - prefix, length: 1))
            }
            let rawStart = SegmentedLargeLineText.sourceOffset(prefix, separators: separatorOffsets)
            let rawEnd = SegmentedLargeLineText.sourceOffset(NSMaxRange(oldRange), separators: separatorOffsets)
            return (NSRange(location: rawStart, length: rawEnd - rawStart), replacement as String)
        }

        private func syntheticBreakOffsets(in textView: UITextView) -> [Int] {
            let storage = textView.textStorage
            let contents = storage.string as NSString
            var result: [Int] = []
            storage.enumerateAttribute(
                SegmentedLargeLineEditor.syntheticBreakKey,
                in: NSRange(location: 0, length: storage.length)
            ) { value, range, _ in
                guard value != nil else { return }
                for offset in range.location..<NSMaxRange(range) where contents.character(at: offset) == 0x2029 {
                    result.append(offset)
                }
            }
            return result
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isInstalling else { return }
            publishSelection(textView)
        }

        private func publishSelection(_ textView: UITextView) {
            let displaySelection = textView.selectedRange
            guard displaySelection.location != NSNotFound else { return }
            let rawStart = SegmentedLargeLineText.sourceOffset(displaySelection.location, separators: separatorOffsets)
            let rawEnd = SegmentedLargeLineText.sourceOffset(NSMaxRange(displaySelection), separators: separatorOffsets)
            var userInfo: [AnyHashable: Any] = ["line": 0, "column": rawStart, "location": rawStart]
            if let documentID = parent.documentID {
                userInfo[EditorCommandUserInfo.documentID] = documentID.uuidString
            }
            NotificationCenter.default.post(name: .caretPositionDidChange, object: nil, userInfo: userInfo)
            userInfo["range"] = NSValue(range: NSRange(location: rawStart, length: rawEnd - rawStart))
            NotificationCenter.default.post(
                name: .editorSelectionDidChange,
                object: sourceText(in: displaySelection),
                userInfo: userInfo
            )
        }
    }
}
#endif
