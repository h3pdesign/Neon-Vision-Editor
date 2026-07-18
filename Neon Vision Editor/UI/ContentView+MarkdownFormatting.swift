import SwiftUI
import Foundation

enum MarkdownFormattingAction: CaseIterable, Identifiable {
    case bold, italic, link, quote, inlineCode, codeBlock
    case heading, heading1, heading2, heading3, heading4, heading5
    case bulletList, numberedList, checklist, divider, image, table

    var id: Self { self }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .link: "Link"
        case .quote: "Quote"
        case .inlineCode: "Inline Code"
        case .codeBlock: "Code Block"
        case .heading: "Heading"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .heading4: "Heading 4"
        case .heading5: "Heading 5"
        case .bulletList: "Bullet List"
        case .numberedList: "Numbered List"
        case .checklist: "Checklist"
        case .divider: "Divider"
        case .image: "Image"
        case .table: "Table"
        }
    }

    var icon: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .link: "link"
        case .quote: "text.quote"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "chevron.left.forwardslash.chevron.right"
        case .heading, .heading1, .heading2, .heading3, .heading4, .heading5: "textformat.size"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .checklist: "checklist"
        case .divider: "minus"
        case .image: "photo"
        case .table: "tablecells"
        }
    }

    var shortcut: String? {
        switch self {
        case .bold: "Cmd-B"
        case .italic: "Cmd-I"
        case .link: "Cmd-K"
        default: nil
        }
    }

    init?(commandIdentifier: String) {
        switch commandIdentifier {
        case "bold": self = .bold
        case "italic": self = .italic
        case "link": self = .link
        default: return nil
        }
    }
}

extension ContentView {
    var shouldShowMarkdownFormattingControls: Bool {
        currentLanguage == "markdown"
            && viewModel.selectedTab?.isReadOnlyPreview != true
            && !brainDumpLayoutEnabled
            && viewModel.selectedTab?.isLoadingContent != true
    }

#if os(iOS) || os(visionOS)
    var shouldEmbedMarkdownFormattingInMobileStatusRow: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && shouldPinFloatingStatusToTop
            && shouldShowMarkdownFormattingControls
    }

    var iPhoneMarkdownFormattingStatusControl: some View {
        Menu {
            markdownFormattingMenuItems(primaryOnly: false)
        } label: {
            Image(systemName: "textformat")
                .frame(width: 34, height: 32)
        }
        .foregroundStyle(iOSToolbarForegroundColor)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .accessibilityLabel("Markdown Formatting")
    }
#endif

    var shouldOverlayMarkdownFormattingControls: Bool {
#if os(iOS) || os(visionOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return useIOSUnifiedTopHost
                && shouldShowMarkdownFormattingControls
                && !shouldEmbedMarkdownFormattingInMobileStatusRow
        }
        return shouldShowMarkdownFormattingControls
#else
        shouldShowMarkdownFormattingControls
#endif
    }

    @ViewBuilder
    var markdownFormattingControlBar: some View {
#if os(iOS) || os(visionOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            if !shouldEmbedMarkdownFormattingInMobileStatusRow {
                HStack {
                    iPhoneMarkdownFormattingStatusControl
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        } else {
            markdownFormattingToolbar
        }
#else
        markdownFormattingToolbar
#endif
    }

    @ViewBuilder
    private var markdownFormattingToolbar: some View {
        if markdownFormattingToolbarCollapsed {
            HStack {
                Menu {
                    markdownFormattingMenuItems(primaryOnly: false)
                } label: {
                    Image(systemName: "textformat")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Markdown Formatting")

                Button {
                    markdownFormattingToolbarCollapsed = false
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand Markdown Formatting Toolbar")
            }
            .padding(4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        } else {
            markdownFormattingCapsule
        }
    }

    private var markdownFormattingCapsule: some View {
        HStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    markdownFormattingButton(.bold)
                    markdownFormattingButton(.italic)
                    markdownFormattingButton(.link)
                    Divider().frame(height: 18)
                    markdownFormattingButton(.quote)
                    markdownFormattingButton(.inlineCode)
                    markdownFormattingButton(.codeBlock)
                    Divider().frame(height: 18)
                    markdownHeadingMenu
                    markdownFormattingButton(.bulletList)
                    markdownFormattingButton(.numberedList)
                    markdownFormattingButton(.checklist)
                    Divider().frame(height: 18)
                    markdownFormattingButton(.divider)
                    markdownFormattingButton(.image)
                    markdownFormattingButton(.table)
                    Divider().frame(height: 18)
                    Button {
                        markdownFormattingToolbarCollapsed = true
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 24, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Collapse Markdown Formatting Toolbar")
                }
                .padding(4)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func markdownFormattingMenuItems(primaryOnly: Bool) -> some View {
        if !primaryOnly {
            markdownFormattingMenuButton(.bold)
            markdownFormattingMenuButton(.italic)
            markdownFormattingMenuButton(.link)
            Divider()
            markdownFormattingMenuButton(.quote)
            markdownFormattingMenuButton(.inlineCode)
            markdownFormattingMenuButton(.codeBlock)
            Divider()
        } else {
            markdownFormattingMenuButton(.codeBlock)
            Divider()
        }
        markdownHeadingMenuItems
        markdownFormattingMenuButton(.bulletList)
        markdownFormattingMenuButton(.numberedList)
        markdownFormattingMenuButton(.checklist)
        Divider()
        markdownFormattingMenuButton(.divider)
        markdownFormattingMenuButton(.image)
        markdownFormattingMenuButton(.table)
    }

    private var markdownHeadingMenu: some View {
        Menu {
            markdownHeadingMenuItems
        } label: {
            Image(systemName: "textformat.size")
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel("Markdown Heading Level")
    }

    @ViewBuilder
    private var markdownHeadingMenuItems: some View {
        markdownFormattingMenuButton(.heading1)
        markdownFormattingMenuButton(.heading2)
        markdownFormattingMenuButton(.heading3)
        markdownFormattingMenuButton(.heading4)
        markdownFormattingMenuButton(.heading5)
    }

    private func markdownFormattingButton(_ action: MarkdownFormattingAction) -> some View {
        Button {
            applyMarkdownFormatting(action)
        } label: {
            Image(systemName: action.icon)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(markdownFormattingActionIsActive(action) ? Color.accentColor : Color.primary)
        .background(
            Circle().fill(markdownFormattingActionIsActive(action) ? Color.accentColor.opacity(0.16) : .clear)
        )
        .accessibilityLabel(action.title)
    }

    private func markdownFormattingMenuButton(_ action: MarkdownFormattingAction) -> some View {
        Button {
            applyMarkdownFormatting(action)
        } label: {
            if let shortcut = action.shortcut {
                Label("\(action.title) (\(shortcut))", systemImage: action.icon)
            } else {
                Label(action.title, systemImage: action.icon)
            }
        }
    }

    private func markdownFormattingActionIsActive(_ action: MarkdownFormattingAction) -> Bool {
        let text = currentContent as NSString
        let location = min(max(0, lastCaretLocation), text.length)
        let before = text.substring(with: NSRange(location: max(0, location - 4), length: min(4, location)))
        let after = text.substring(with: NSRange(location: location, length: min(4, text.length - location)))
        switch action {
        case .bold: return before.hasSuffix("**") && after.hasPrefix("**")
        case .italic: return before.hasSuffix("*") && after.hasPrefix("*")
        case .inlineCode: return before.hasSuffix("`") && after.hasPrefix("`")
        case .quote:
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            return text.substring(with: lineRange).trimmingCharacters(in: .whitespaces).hasPrefix(">")
        case .heading1, .heading2, .heading3, .heading4, .heading5:
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let line = text.substring(with: lineRange).trimmingCharacters(in: .whitespaces)
            let level: Int
            switch action {
            case .heading1: level = 1
            case .heading2: level = 2
            case .heading3: level = 3
            case .heading4: level = 4
            case .heading5: level = 5
            default: level = 2
            }
            return line.hasPrefix(String(repeating: "#", count: level) + " ")
        case .codeBlock:
            return before.hasSuffix("```") || after.hasPrefix("```")
        default: return false
        }
    }

    func applyMarkdownFormatting(_ action: MarkdownFormattingAction) {
#if os(macOS)
        guard let textView = activeEditorTextView() else { return }
        applyMarkdownFormatting(action, text: textView.string, selection: textView.selectedRange()) { replacement in
            guard let storage = textView.textStorage,
                  NSMaxRange(replacement.range) <= storage.length else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: replacement.range, with: replacement.text)
            storage.endEditing()
            textView.setSelectedRange(Self.clampedSelection(replacement.selection, textLength: storage.length))
            textView.didChangeText()
            finalizeMarkdownFormattingMutation(textView.string)
            textView.window?.makeFirstResponder(textView)
        }
#elseif canImport(UIKit)
        guard let textView = activeEditorInputTextView() else { return }
        applyMarkdownFormatting(action, text: textView.text ?? "", selection: textView.selectedRange) { replacement in
            guard NSMaxRange(replacement.range) <= textView.textStorage.length else { return }
            textView.textStorage.replaceCharacters(in: replacement.range, with: replacement.text)
            textView.selectedRange = Self.clampedSelection(replacement.selection, textLength: textView.textStorage.length)
            textView.delegate?.textViewDidChange?(textView)
            finalizeMarkdownFormattingMutation(textView.text ?? "")
            textView.becomeFirstResponder()
        }
#endif
    }

    private func finalizeMarkdownFormattingMutation(_ text: String) {
        // Direct text-storage edits bypass SwiftUI's normal binding update. Keep the document
        // classified as Markdown and force the editor bridge to restore syntax attributes.
        currentContentBinding.wrappedValue = text
        currentLanguageBinding.wrappedValue = "markdown"
        scheduleHighlightRefresh(delay: 0)
    }

    private static func clampedSelection(_ selection: NSRange, textLength: Int) -> NSRange {
        let location = min(max(0, selection.location), textLength)
        let length = min(max(0, selection.length), textLength - location)
        return NSRange(location: location, length: length)
    }

    private func applyMarkdownFormatting(
        _ action: MarkdownFormattingAction,
        text: String,
        selection: NSRange,
        apply: ((range: NSRange, text: String, selection: NSRange)) -> Void
    ) {
        let source = text as NSString
        let location = min(max(0, selection.location), source.length)
        let length = min(max(0, selection.length), source.length - location)
        let range = NSRange(location: location, length: length)
        let selected = source.substring(with: range)

        func replace(_ replacement: String, caretOffset: Int, selectedLength: Int = 0) {
            apply((range, replacement, NSRange(location: location + caretOffset, length: selectedLength)))
        }

        switch action {
        case .bold: wrap(selected, prefix: "**", suffix: "**", replace: replace)
        case .italic: wrap(selected, prefix: "*", suffix: "*", replace: replace)
        case .inlineCode: wrap(selected, prefix: "`", suffix: "`", replace: replace)
        case .link: wrap(selected, prefix: "[", suffix: "](url)", replace: replace)
        case .quote:
            if selected.isEmpty { replace("> ", caretOffset: 2) }
            else { replace(selected.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n"), caretOffset: 0, selectedLength: selected.utf16.count + 2) }
        case .codeBlock: wrap(selected, prefix: "```\n", suffix: "\n```", replace: replace)
        case .heading, .heading1, .heading2, .heading3, .heading4, .heading5:
            let level: Int
            switch action {
            case .heading1: level = 1
            case .heading2, .heading: level = 2
            case .heading3: level = 3
            case .heading4: level = 4
            case .heading5: level = 5
            default: level = 2
            }
            guard let replacement = Self.headingReplacement(
                in: source,
                selection: range,
                level: level
            ) else { return }
            apply(replacement)
        case .bulletList: replace("- \(selected)", caretOffset: selected.isEmpty ? 2 : 0, selectedLength: selected.isEmpty ? 0 : selected.utf16.count)
        case .numberedList: replace("1. \(selected)", caretOffset: selected.isEmpty ? 3 : 0, selectedLength: selected.isEmpty ? 0 : selected.utf16.count)
        case .checklist: replace("- [ ] \(selected)", caretOffset: selected.isEmpty ? 6 : 0, selectedLength: selected.isEmpty ? 0 : selected.utf16.count)
        case .divider: replace("---\n", caretOffset: 4)
        case .image: replace("![alt text](url)", caretOffset: 2)
        case .table: replace("| Column | Column |\n| --- | --- |\n| Value | Value |", caretOffset: 2)
        }
    }

    private func wrap(
        _ selected: String,
        prefix: String,
        suffix: String,
        replace: (String, Int, Int) -> Void
    ) {
        let replacement = prefix + selected + suffix
        if selected.isEmpty {
            replace(replacement, prefix.utf16.count, 0)
        } else {
            replace(replacement, prefix.utf16.count, selected.utf16.count)
        }
    }

    private static func headingReplacement(
        in source: NSString,
        selection: NSRange,
        level: Int
    ) -> (range: NSRange, text: String, selection: NSRange)? {
        guard source.length > 0 else {
            let prefix = String(repeating: "#", count: level) + " "
            return (NSRange(location: 0, length: 0), prefix, NSRange(location: prefix.utf16.count, length: 0))
        }

        let safeSelection = clampedSelection(selection, textLength: source.length)
        let firstLineRange = source.lineRange(for: NSRange(location: safeSelection.location, length: 0))
        let affectedRange: NSRange
        if safeSelection.length == 0 {
            affectedRange = firstLineRange
        } else {
            let endLocation = safeSelection.location + safeSelection.length - 1
            affectedRange = NSUnionRange(firstLineRange, source.lineRange(for: NSRange(location: endLocation, length: 0)))
        }

        let prefix = String(repeating: "#", count: level) + " "
        let affectedText = source.substring(with: affectedRange)
        let lines = affectedText.split(separator: "\n", omittingEmptySubsequences: false)
        let replacement = lines.map { line -> String in
            guard !line.isEmpty else { return "" }
            let rawLine = String(line)
            let indentationLength = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
            let indentation = String(rawLine.prefix(indentationLength))
            let remainder = String(rawLine.dropFirst(indentationLength))
            let markerCount = remainder.prefix(while: { $0 == "#" }).count
            let content: String
            if (1...6).contains(markerCount),
               remainder.dropFirst(markerCount).first?.isWhitespace == true {
                content = remainder.dropFirst(markerCount).trimmingCharacters(in: .whitespaces)
            } else {
                content = remainder
            }
            return indentation + prefix + content
        }.joined(separator: "\n")

        let replacementLength = (replacement as NSString).length
        let replacementSelection: NSRange
        if safeSelection.length == 0 {
            let indentationLength = (source.substring(with: firstLineRange)
                .prefix(while: { $0 == " " || $0 == "\t" }) as NSString).length
            replacementSelection = NSRange(
                location: affectedRange.location + indentationLength + prefix.utf16.count,
                length: 0
            )
        } else {
            replacementSelection = NSRange(location: affectedRange.location, length: replacementLength)
        }
        return (affectedRange, replacement, replacementSelection)
    }
}
