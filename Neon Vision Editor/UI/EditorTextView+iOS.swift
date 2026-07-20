#if os(iOS) || os(visionOS)
import Dispatch
import SwiftUI
import Foundation
import OSLog
import UIKit

// MARK: - iOS Editor Text View

final class EditorInputTextView: UITextView {
    private let vimModeDefaultsKey = "EditorVimModeEnabled"
    private let vimInterceptionDefaultsKey = "EditorVimInterceptionEnabled"
    private let bracketTokens: [String] = ["(", ")", "{", "}", "[", "]", "<", ">", "'", "\"", "`", "()", "{}", "[]", "\"\"", "''"]
    private var isVimInsertMode: Bool = true
    private var pendingDeleteCurrentLineCommand = false
    private var preferredShouldWrapText: Bool = true
    private var preferredTextContainerWidth: CGFloat = 0
    var markdownFormattingEnabled: Bool = false
    var rendersInvisibleCharacters: Bool = false {
        didSet {
            if oldValue != rendersInvisibleCharacters {
                invisibleCharactersOverlayView?.rendersInvisibleCharacters = rendersInvisibleCharacters
            }
        }
    }
    var rendersIndentationGuides: Bool = false {
        didSet {
            if oldValue != rendersIndentationGuides {
                invisibleCharactersOverlayView?.rendersIndentationGuides = rendersIndentationGuides
            }
        }
    }
    var indentationGuideWidth: Int = 4 {
        didSet {
            if oldValue != indentationGuideWidth {
                invisibleCharactersOverlayView?.indentationWidth = indentationGuideWidth
            }
        }
    }
    weak var invisibleCharactersOverlayView: InvisibleCharacterOverlayView?
    weak var currentLineHighlightOverlayView: CurrentLineHighlightOverlayView?
    var highlightsCurrentLine: Bool = false {
        didSet {
            if oldValue != highlightsCurrentLine {
                currentLineHighlightOverlayView?.isCurrentLineHighlightEnabled = highlightsCurrentLine
                setNeedsDisplay()
            }
        }
    }
    var currentLineHighlightColor: UIColor = UIColor.systemBlue.withAlphaComponent(0.22) {
        didSet {
            if oldValue != currentLineHighlightColor {
                currentLineHighlightOverlayView?.currentLineHighlightColor = currentLineHighlightColor
                setNeedsDisplay()
            }
        }
    }
    var matchingBracketHighlightRanges: [NSRange] = [] {
        didSet {
            if oldValue != matchingBracketHighlightRanges {
                setNeedsDisplay()
            }
        }
    }

    private lazy var bracketAccessoryView: UIView = {
        let host = UIView()
        host.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        host.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        for token in bracketTokens {
            let button = UIButton(type: .system)
            button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
            button.accessibilityIdentifier = token
            if #available(iOS 15.0, *) {
                var config = UIButton.Configuration.plain()
                config.title = token
                config.baseForegroundColor = .label
                config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                config.background.cornerRadius = 8
                config.background.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
                button.configuration = config
            } else {
                button.setTitle(token, for: .normal)
                button.setTitleColor(.label, for: .normal)
                button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            }
            button.tintColor = .label
            button.layer.cornerRadius = 8
            button.layer.masksToBounds = true
            button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
            button.addTarget(self, action: #selector(insertBracketToken(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        host.addSubview(scroll)
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            host.heightAnchor.constraint(equalToConstant: 46),

            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: host.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -6),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        return host
    }()
    private var isBracketAccessoryVisible: Bool = true

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        #if !os(visionOS)
        inputAccessoryView = bracketAccessoryView
        #endif
        syncVimModeFromDefaults()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVimModeStateDidChange(_:)),
            name: .vimModeStateDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        #if !os(visionOS)
        inputAccessoryView = bracketAccessoryView
        #endif
        syncVimModeFromDefaults()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVimModeStateDidChange(_:)),
            name: .vimModeStateDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setBracketAccessoryVisible(_ visible: Bool) {
        guard isBracketAccessoryVisible != visible else { return }
        isBracketAccessoryVisible = visible
        #if !os(visionOS)
        inputAccessoryView = visible ? bracketAccessoryView : nil
        #endif
        if isFirstResponder {
            reloadInputViews()
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return isEditable && (UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs)
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override var keyCommands: [UIKeyCommand]? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return super.keyCommands }
        let baseCommands = hardwareKeyboardEditingCommands(merging: super.keyCommands)
        guard UserDefaults.standard.bool(forKey: vimInterceptionDefaultsKey),
              UserDefaults.standard.bool(forKey: vimModeDefaultsKey) else {
            return baseCommands
        }

        var commands = baseCommands
        if isVimInsertMode {
            commands.append(vimCommand(input: UIKeyCommand.inputEscape, action: #selector(vimEscapeToNormalMode), title: "Vim: Normal Mode"))
            return commands
        }

        commands.append(vimCommand(input: "h", action: #selector(vimMoveLeft), title: "Vim: Move Left"))
        commands.append(vimCommand(input: UIKeyCommand.inputLeftArrow, action: #selector(vimMoveLeft), title: "Vim: Move Left"))
        commands.append(vimCommand(input: "j", action: #selector(vimMoveDown), title: "Vim: Move Down"))
        commands.append(vimCommand(input: UIKeyCommand.inputDownArrow, action: #selector(vimMoveDown), title: "Vim: Move Down"))
        commands.append(vimCommand(input: "k", action: #selector(vimMoveUp), title: "Vim: Move Up"))
        commands.append(vimCommand(input: UIKeyCommand.inputUpArrow, action: #selector(vimMoveUp), title: "Vim: Move Up"))
        commands.append(vimCommand(input: "l", action: #selector(vimMoveRight), title: "Vim: Move Right"))
        commands.append(vimCommand(input: UIKeyCommand.inputRightArrow, action: #selector(vimMoveRight), title: "Vim: Move Right"))
        commands.append(vimCommand(input: "w", action: #selector(vimMoveWordForward), title: "Vim: Next Word"))
        commands.append(vimCommand(input: "b", action: #selector(vimMoveWordBackward), title: "Vim: Previous Word"))
        commands.append(vimCommand(input: "0", action: #selector(vimMoveToLineStart), title: "Vim: Line Start"))
        commands.append(vimCommand(input: UIKeyCommand.inputEscape, action: #selector(vimEscapeToNormalMode), title: "Vim: Stay in Normal Mode"))
        commands.append(vimCommand(input: "x", action: #selector(vimDeleteForward), title: "Vim: Delete Character"))
        commands.append(vimCommand(input: "i", action: #selector(vimEnterInsertMode), title: "Vim: Insert Mode"))
        commands.append(vimCommand(input: "a", action: #selector(vimAppendInsertMode), title: "Vim: Append Mode"))
        commands.append(vimCommand(input: "d", action: #selector(vimDeleteLineStep), title: "Vim: Delete Line"))
        commands.append(vimCommand(input: "$", modifiers: [.shift], action: #selector(vimMoveToLineEnd), title: "Vim: Line End"))
        return commands
    }

    private func hardwareKeyboardEditingCommands(merging existing: [UIKeyCommand]?) -> [UIKeyCommand] {
        var commands = (existing ?? []).filter { command in
            guard command.modifierFlags.contains(.command), let input = command.input?.lowercased() else {
                return true
            }
            if command.modifierFlags.contains(.shift) {
                return input != "z"
            }
            return !["a", "c", "x", "v", "z"].contains(input)
        }
        let selectAllCommand = UIKeyCommand(
            input: "a",
            modifierFlags: .command,
            action: #selector(selectAllFromHardwareKeyboard)
        )
        selectAllCommand.discoverabilityTitle = "Select All"
        let copyCommand = UIKeyCommand(
            input: "c",
            modifierFlags: .command,
            action: #selector(copy(_:))
        )
        copyCommand.discoverabilityTitle = "Copy"
        let cutCommand = UIKeyCommand(
            input: "x",
            modifierFlags: .command,
            action: #selector(cut(_:))
        )
        cutCommand.discoverabilityTitle = "Cut"
        let pasteCommand = UIKeyCommand(
            input: "v",
            modifierFlags: .command,
            action: #selector(paste(_:))
        )
        pasteCommand.discoverabilityTitle = "Paste"
        let undoCommand = UIKeyCommand(
            input: "z",
            modifierFlags: .command,
            action: #selector(undoFromHardwareKeyboard)
        )
        undoCommand.discoverabilityTitle = "Undo"
        let redoCommand = UIKeyCommand(
            input: "z",
            modifierFlags: [.command, .shift],
            action: #selector(redoFromHardwareKeyboard)
        )
        redoCommand.discoverabilityTitle = "Redo"
        let markdownCommands = markdownFormattingEnabled ? [
            markdownFormattingCommand(input: "b", action: #selector(requestMarkdownBold), title: "Bold"),
            markdownFormattingCommand(input: "i", action: #selector(requestMarkdownItalic), title: "Italic"),
            markdownFormattingCommand(input: "k", action: #selector(requestMarkdownLink), title: "Link")
        ] : []
        commands.insert(contentsOf: [selectAllCommand, copyCommand, cutCommand, pasteCommand, undoCommand, redoCommand] + markdownCommands, at: 0)
        return commands
    }

    private func markdownFormattingCommand(input: String, action: Selector, title: String) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: .command, action: action)
        command.discoverabilityTitle = title
        return command
    }

    @objc private func requestMarkdownBold() { NotificationCenter.default.post(name: .markdownFormattingRequested, object: "bold") }
    @objc private func requestMarkdownItalic() { NotificationCenter.default.post(name: .markdownFormattingRequested, object: "italic") }
    @objc private func requestMarkdownLink() { NotificationCenter.default.post(name: .markdownFormattingRequested, object: "link") }

    @objc private func selectAllFromHardwareKeyboard() {
        selectAll(nil)
    }

    @objc private func undoFromHardwareKeyboard() {
        undoManager?.undo()
    }

    @objc private func redoFromHardwareKeyboard() {
        undoManager?.redo()
    }

    override func paste(_ sender: Any?) {
        // Force plain-text fallback so simulator/device paste remains reliable
        // even when the pasteboard advertises rich content first.
        if let raw = UIPasteboard.general.string, !raw.isEmpty {
            let sanitized = EditorTextSanitizer.sanitize(raw)
            if let selection = selectedTextRange {
                replace(selection, withText: sanitized)
            } else {
                insertText(sanitized)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.selectedRange = NSRange(location: 0, length: 0)
                self.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
            return
        }
        super.paste(sender)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.selectedRange = NSRange(location: 0, length: 0)
            self.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        enforcePreferredWrapLayout()
        if rendersInvisibleCharacters || rendersIndentationGuides {
            invisibleCharactersOverlayView?.requestRedraw()
        }
    }

    func rememberPreferredWrapLayout(shouldWrapText: Bool, containerWidth: CGFloat) {
        preferredShouldWrapText = shouldWrapText
        preferredTextContainerWidth = containerWidth
        enforcePreferredWrapLayout()
    }

    private func enforcePreferredWrapLayout() {
        let desiredLineBreakMode: NSLineBreakMode = preferredShouldWrapText ? .byWordWrapping : .byClipping
        let visibleWidth = max(1, bounds.width - textContainerInset.left - textContainerInset.right)
        let targetWidth = preferredShouldWrapText ? visibleWidth : max(preferredTextContainerWidth, visibleWidth)
        if textContainer.lineBreakMode != desiredLineBreakMode {
            textContainer.lineBreakMode = desiredLineBreakMode
        }
        if textContainer.widthTracksTextView != preferredShouldWrapText {
            textContainer.widthTracksTextView = preferredShouldWrapText
        }
        if abs(textContainer.size.width - targetWidth) > 1 {
            textContainer.size = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
        }
        guard !preferredShouldWrapText else { return }
        let horizontalInsets = textContainerInset.left + textContainerInset.right
        let requiredWidth = max(bounds.width, targetWidth + horizontalInsets)
        if requiredWidth.isFinite, requiredWidth > contentSize.width + 1 {
            contentSize = CGSize(width: requiredWidth, height: contentSize.height)
        }
    }
}

// MARK: - Invisible Character Overlay

final class InvisibleCharacterOverlayView: UIView {
    private enum RenderLimits {
        static let verticalPadding: CGFloat = 80
        static let maxIndentationLineFragments = 260
    }

    weak var textView: UITextView?
    private var pendingRedraw: DispatchWorkItem?
    private var lastRedrawUptime: TimeInterval = 0
    var rendersInvisibleCharacters: Bool = false {
        didSet {
            isHidden = !rendersInvisibleCharacters && !rendersIndentationGuides
            requestRedraw(immediate: true)
        }
    }
    var rendersIndentationGuides: Bool = false {
        didSet {
            isHidden = !rendersInvisibleCharacters && !rendersIndentationGuides
            requestRedraw(immediate: true)
        }
    }
    var indentationWidth: Int = 4 {
        didSet { requestRedraw(immediate: true) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
        isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
        isHidden = true
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        drawIndentationGuides()
        drawInvisibleCharacterMarkers()
    }

    func requestRedraw(immediate: Bool = false) {
        guard !isHidden else { return }
        pendingRedraw?.cancel()
        pendingRedraw = nil

        let now = ProcessInfo.processInfo.systemUptime
        let interval = redrawInterval
        if immediate || now - lastRedrawUptime >= interval {
            lastRedrawUptime = now
            setNeedsDisplay()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRedraw = nil
            self.lastRedrawUptime = ProcessInfo.processInfo.systemUptime
            self.setNeedsDisplay()
        }
        pendingRedraw = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (interval - (now - lastRedrawUptime)), execute: work)
    }

    private var redrawInterval: TimeInterval {
        guard isPhoneLayout,
              let textView,
              textView.isDragging || textView.isDecelerating || textView.isTracking else {
            return 1.0 / 30.0
        }
        return 1.0 / 18.0
    }

    private var maxInvisibleMarkerUTF16Length: Int {
        isPhoneLayout ? 4_000 : 8_000
    }

    private var maxInvisibleMarkersPerDraw: Int {
        isPhoneLayout ? 1_600 : 3_200
    }

    private var isPhoneLayout: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }

    private func drawIndentationGuides() {
        guard rendersIndentationGuides, let textView else { return }
        guard textView.textStorage.length > 0 else { return }

        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
            .insetBy(dx: 0, dy: -RenderLimits.verticalPadding)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else { return }

        let text = textView.textStorage.string as NSString
        let textLength = text.length
        let guideWidth = max(1, indentationWidth)
        let font = textView.font ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let columnWidth = NSString(string: " ").size(withAttributes: [.font: font]).width
        let color = (textView.textColor ?? UIColor.label).withAlphaComponent(0.14)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1 / max(1, textView.traitCollection.displayScale))

        var renderedFragments = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, stop in
            guard renderedFragments < RenderLimits.maxIndentationLineFragments else {
                stop.pointee = true
                return
            }
            renderedFragments += 1
            let charIndex = layoutManager.characterIndexForGlyph(at: lineGlyphRange.location)
            guard charIndex < textLength else { return }
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineEnd = min(textLength, lineRange.location + lineRange.length)
            var column = 0
            var index = lineRange.location
            while index < lineEnd {
                let unit = text.character(at: index)
                if unit == 32 {
                    column += 1
                } else if unit == 9 {
                    column += guideWidth
                } else {
                    break
                }
                index += 1
            }
            guard column >= guideWidth else { return }
            for guideColumn in stride(from: guideWidth, through: column, by: guideWidth) {
                let x = textView.textContainerInset.left + (CGFloat(guideColumn) * columnWidth) - textView.contentOffset.x
                let y1 = textView.textContainerInset.top + usedRect.minY - textView.contentOffset.y
                let y2 = textView.textContainerInset.top + usedRect.maxY - textView.contentOffset.y
                context.move(to: CGPoint(x: x, y: y1))
                context.addLine(to: CGPoint(x: x, y: y2))
            }
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawInvisibleCharacterMarkers() {
        guard rendersInvisibleCharacters, let textView else { return }
        guard textView.textStorage.length > 0 else { return }

        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
            .insetBy(dx: 0, dy: -RenderLimits.verticalPadding)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else { return }

        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let text = textView.textStorage.string as NSString
        let end = min(text.length, NSMaxRange(characterRange))
        guard characterRange.location < end else { return }
        guard end - characterRange.location <= maxInvisibleMarkerUTF16Length else { return }

        let markerFont = UIFont.monospacedSystemFont(ofSize: max(9, (textView.font?.pointSize ?? 14) * 0.78), weight: .regular)
        let markerColor = (textView.textColor ?? UIColor.label).withAlphaComponent(0.38)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: markerFont,
            .foregroundColor: markerColor
        ]
        let spaceMarker = NSString(string: "·")
        let tabMarker = NSString(string: "→")
        let newlineMarker = NSString(string: "¶")
        let spaceMarkerSize = spaceMarker.size(withAttributes: attributes)
        let tabMarkerSize = tabMarker.size(withAttributes: attributes)
        let newlineMarkerSize = newlineMarker.size(withAttributes: attributes)

        var renderedMarkers = 0
        for index in characterRange.location..<end {
            guard renderedMarkers < maxInvisibleMarkersPerDraw else { break }
            switch text.character(at: index) {
            case 32:
                drawInlineInvisibleMarker(spaceMarker, atCharacterIndex: index, size: spaceMarkerSize, attributes: attributes)
                renderedMarkers += 1
            case 9:
                drawInlineInvisibleMarker(tabMarker, atCharacterIndex: index, size: tabMarkerSize, attributes: attributes)
                renderedMarkers += 1
            case 10:
                drawLineEndInvisibleMarker(newlineMarker, nearCharacterIndex: index, size: newlineMarkerSize, attributes: attributes)
                renderedMarkers += 1
            default:
                continue
            }
        }
    }

    private func drawInlineInvisibleMarker(
        _ marker: NSString,
        atCharacterIndex index: Int,
        size markerSize: CGSize,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let textView else { return }
        let layoutManager = textView.layoutManager
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1),
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return }

        let glyphIndex = glyphRange.location
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
        let drawPoint = CGPoint(
            x: textView.textContainerInset.left + glyphLocation.x - textView.contentOffset.x,
            y: textView.textContainerInset.top + lineRect.minY + ((lineRect.height - markerSize.height) / 2) - textView.contentOffset.y
        )
        marker.draw(at: drawPoint, withAttributes: attributes)
    }

    private func drawLineEndInvisibleMarker(
        _ marker: NSString,
        nearCharacterIndex index: Int,
        size markerSize: CGSize,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let textView else { return }
        let layoutManager = textView.layoutManager
        let textLength = textView.textStorage.length
        let anchorIndex = max(0, min(index == 0 ? 0 : index - 1, max(0, textLength - 1)))
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: anchorIndex, length: min(1, textLength - anchorIndex)),
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return }

        let glyphIndex = glyphRange.location
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let drawPoint = CGPoint(
            x: textView.textContainerInset.left + lineRect.maxX + 2 - textView.contentOffset.x,
            y: textView.textContainerInset.top + lineRect.minY + ((lineRect.height - markerSize.height) / 2) - textView.contentOffset.y
        )
        marker.draw(at: drawPoint, withAttributes: attributes)
    }
}

// MARK: - Editing Commands and Vim Helpers

extension EditorInputTextView {
    @objc private func insertBracketToken(_ sender: UIButton) {
        guard isEditable, let token = sender.accessibilityIdentifier else { return }
        becomeFirstResponder()

        let selection = selectedRange
        if let pair = pairForToken(token) {
            textStorage.replaceCharacters(in: selection, with: pair.open + pair.close)
            selectedRange = NSRange(location: selection.location + pair.open.count, length: 0)
            delegate?.textViewDidChange?(self)
            return
        }

        textStorage.replaceCharacters(in: selection, with: token)
        selectedRange = NSRange(location: selection.location + token.count, length: 0)
        delegate?.textViewDidChange?(self)
    }

    private func pairForToken(_ token: String) -> (open: String, close: String)? {
        switch token {
        case "()": return ("(", ")")
        case "{}": return ("{", "}")
        case "[]": return ("[", "]")
        case "\"\"": return ("\"", "\"")
        case "''": return ("'", "'")
        default: return nil
        }
    }

    private func vimCommand(
        input: String,
        modifiers: UIKeyModifierFlags = [],
        action: Selector,
        title: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
        command.discoverabilityTitle = title
        if #available(iOS 15.0, *) {
            command.wantsPriorityOverSystemBehavior = true
        }
        return command
    }

    private func syncVimModeFromDefaults() {
        let enabled = UserDefaults.standard.bool(forKey: vimModeDefaultsKey)
        let interceptionEnabled = UserDefaults.standard.bool(forKey: vimInterceptionDefaultsKey)
        if !enabled || !interceptionEnabled {
            pendingDeleteCurrentLineCommand = false
            if !isVimInsertMode {
                setVimInsertMode(true)
            }
        }
    }

    private func setVimInsertMode(_ isInsertMode: Bool) {
        isVimInsertMode = isInsertMode
        pendingDeleteCurrentLineCommand = false
        NotificationCenter.default.post(
            name: .vimModeStateDidChange,
            object: nil,
            userInfo: ["insertMode": isInsertMode]
        )
    }

    @objc private func handleVimModeStateDidChange(_ notification: Notification) {
        if let insertMode = notification.userInfo?["insertMode"] as? Bool {
            isVimInsertMode = insertMode
            pendingDeleteCurrentLineCommand = false
        } else {
            syncVimModeFromDefaults()
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        drawMatchingBracketHighlights()
    }

    private func drawMatchingBracketHighlights() {
        guard !matchingBracketHighlightRanges.isEmpty, textStorage.length <= 250_000 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let textLength = textStorage.length
        let fillColor = UIColor.systemOrange.withAlphaComponent(0.24)
        let strokeColor = UIColor.systemOrange.withAlphaComponent(0.78)
        for range in matchingBracketHighlightRanges where range.location != NSNotFound && NSMaxRange(range) <= textLength {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textContainerInset.left - contentOffset.x - 1
            rect.origin.y += textContainerInset.top - contentOffset.y - 1
            rect.size.width += 2
            rect.size.height += 2
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 3)
            fillColor.setFill()
            path.fill()
            strokeColor.setStroke()
            path.lineWidth = 1 / max(1, traitCollection.displayScale)
            path.stroke()
        }
    }

    private func vimText() -> NSString {
        (text ?? "") as NSString
    }

    private func collapseSelection() -> NSRange {
        let current = selectedRange
        if current.length == 0 {
            return current
        }
        let collapsed = NSRange(location: current.location, length: 0)
        selectedRange = collapsed
        delegate?.textViewDidChangeSelection?(self)
        return collapsed
    }

    private func moveCaret(to location: Int) {
        let length = vimText().length
        selectedRange = NSRange(location: max(0, min(location, length)), length: 0)
        scrollRangeToVisible(selectedRange)
        delegate?.textViewDidChangeSelection?(self)
    }

    private func currentLineRange(for range: NSRange? = nil) -> NSRange {
        let target = range ?? collapseSelection()
        return vimText().lineRange(for: NSRange(location: target.location, length: 0))
    }

    private func currentColumn(in lineRange: NSRange, location: Int) -> Int {
        max(0, location - lineRange.location)
    }

    private func lineStartLocations() -> [Int] {
        let nsText = vimText()
        var starts: [Int] = [0]
        var location = 0
        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let nextLocation = NSMaxRange(lineRange)
            if nextLocation >= nsText.length {
                break
            }
            starts.append(nextLocation)
            location = nextLocation
        }
        return starts
    }

    private func wordCharacterSetContains(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }

    private func moveWordForwardLocation(from location: Int) -> Int {
        let nsText = vimText()
        let length = nsText.length
        var index = min(max(0, location), length)
        while index < length {
            let codeUnit = nsText.character(at: index)
            guard let scalar = UnicodeScalar(codeUnit) else {
                index += 1
                continue
            }
            if wordCharacterSetContains(scalar) {
                break
            }
            index += 1
        }
        while index < length {
            let codeUnit = nsText.character(at: index)
            guard let scalar = UnicodeScalar(codeUnit) else {
                index += 1
                continue
            }
            if !wordCharacterSetContains(scalar) {
                break
            }
            index += 1
        }
        while index < length {
            let codeUnit = nsText.character(at: index)
            guard let scalar = UnicodeScalar(codeUnit) else {
                index += 1
                continue
            }
            if wordCharacterSetContains(scalar) {
                break
            }
            index += 1
        }
        return min(index, length)
    }

    private func moveWordBackwardLocation(from location: Int) -> Int {
        let nsText = vimText()
        var index = max(0, min(location, nsText.length))
        if index > 0 {
            index -= 1
        }
        while index > 0 {
            let codeUnit = nsText.character(at: index)
            guard let scalar = UnicodeScalar(codeUnit) else {
                index -= 1
                continue
            }
            if wordCharacterSetContains(scalar) {
                break
            }
            index -= 1
        }
        while index > 0 {
            let previous = nsText.character(at: index - 1)
            guard let scalar = UnicodeScalar(previous) else {
                index -= 1
                continue
            }
            if !wordCharacterSetContains(scalar) {
                break
            }
            index -= 1
        }
        return index
    }

    private func deleteText(in range: NSRange) {
        guard range.length > 0 else { return }
        textStorage.replaceCharacters(in: range, with: "")
        selectedRange = NSRange(location: min(range.location, vimText().length), length: 0)
        delegate?.textViewDidChange?(self)
        delegate?.textViewDidChangeSelection?(self)
    }

    @objc private func vimEscapeToNormalMode() {
        if isVimInsertMode {
            setVimInsertMode(false)
        }
    }

    @objc private func vimEnterInsertMode() {
        setVimInsertMode(true)
    }

    @objc private func vimAppendInsertMode() {
        let current = collapseSelection()
        if current.location < vimText().length {
            moveCaret(to: current.location + 1)
        }
        setVimInsertMode(true)
    }

    @objc private func vimMoveLeft() {
        let current = collapseSelection()
        moveCaret(to: current.location - 1)
    }

    @objc private func vimMoveRight() {
        let current = collapseSelection()
        moveCaret(to: current.location + 1)
    }

    @objc private func vimMoveUp() {
        let current = collapseSelection()
        let starts = lineStartLocations()
        guard let lineIndex = starts.lastIndex(where: { $0 <= current.location }), lineIndex > 0 else { return }
        let currentLine = currentLineRange(for: current)
        let column = currentColumn(in: currentLine, location: current.location)
        let previousStart = starts[lineIndex - 1]
        let previousLine = vimText().lineRange(for: NSRange(location: previousStart, length: 0))
        let previousLineEnd = max(previousLine.location, previousLine.location + max(0, previousLine.length - 1))
        moveCaret(to: min(previousStart + column, previousLineEnd))
    }

    @objc private func vimMoveDown() {
        let current = collapseSelection()
        let starts = lineStartLocations()
        guard let lineIndex = starts.lastIndex(where: { $0 <= current.location }), lineIndex + 1 < starts.count else { return }
        let currentLine = currentLineRange(for: current)
        let column = currentColumn(in: currentLine, location: current.location)
        let nextStart = starts[lineIndex + 1]
        let nextLine = vimText().lineRange(for: NSRange(location: nextStart, length: 0))
        let nextLineEnd = max(nextLine.location, nextLine.location + max(0, nextLine.length - 1))
        moveCaret(to: min(nextStart + column, nextLineEnd))
    }

    @objc private func vimMoveWordForward() {
        moveCaret(to: moveWordForwardLocation(from: collapseSelection().location))
    }

    @objc private func vimMoveWordBackward() {
        moveCaret(to: moveWordBackwardLocation(from: collapseSelection().location))
    }

    @objc private func vimMoveToLineStart() {
        let lineRange = currentLineRange()
        moveCaret(to: lineRange.location)
    }

    @objc private func vimMoveToLineEnd() {
        let lineRange = currentLineRange()
        let lineEnd = max(lineRange.location, lineRange.location + max(0, lineRange.length - 1))
        moveCaret(to: lineEnd)
    }

    @objc private func vimDeleteForward() {
        let current = collapseSelection()
        guard current.location < vimText().length else { return }
        deleteText(in: NSRange(location: current.location, length: 1))
    }

    @objc private func vimDeleteLineStep() {
        if pendingDeleteCurrentLineCommand {
            pendingDeleteCurrentLineCommand = false
            let lineRange = currentLineRange()
            deleteText(in: lineRange)
            return
        }
        pendingDeleteCurrentLineCommand = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.pendingDeleteCurrentLineCommand = false
        }
    }
}

final class CurrentLineHighlightOverlayView: UIView {
    weak var textView: EditorInputTextView?
    var isCurrentLineHighlightEnabled: Bool = false {
        didSet {
            if oldValue != isCurrentLineHighlightEnabled {
                setNeedsDisplay()
            }
        }
    }
    var currentLineHighlightColor: UIColor = UIColor.systemBlue.withAlphaComponent(0.22) {
        didSet {
            if oldValue != currentLineHighlightColor {
                setNeedsDisplay()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        drawCurrentLineHighlight()
    }

    private func drawCurrentLineHighlight() {
        guard isCurrentLineHighlightEnabled,
              let textView,
              textView.isFirstResponder,
              textView.textStorage.length <= 250_000 else { return }

        let inset = textView.textContainerInset
        let visibleWidth = max(0, bounds.width - inset.left - inset.right)
        let highlightX = inset.left - textView.contentOffset.x
        let textLength = textView.textStorage.length

        if textLength == 0 {
            let height = textView.font?.lineHeight ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular).lineHeight
            currentLineHighlightColor.setFill()
            UIRectFill(CGRect(x: highlightX, y: inset.top - textView.contentOffset.y, width: visibleWidth, height: height))
            return
        }

        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let clampedLocation = min(max(0, textView.selectedRange.location), textLength)
        let nsText = textView.textStorage.string as NSString
        if clampedLocation == textLength && nsText.length > 0 && nsText.character(at: nsText.length - 1) == 10 {
            let extraLineRect = textView.layoutManager.extraLineFragmentRect
            if !extraLineRect.isEmpty {
                currentLineHighlightColor.setFill()
                UIRectFill(CGRect(
                    x: highlightX,
                    y: extraLineRect.minY + inset.top - textView.contentOffset.y,
                    width: visibleWidth,
                    height: max(extraLineRect.height, textView.font?.lineHeight ?? 0)
                ))
                return
            }
        }

        let characterLocation = min(clampedLocation, textLength - 1)
        let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: characterLocation)
        guard glyphIndex < textView.layoutManager.numberOfGlyphs else { return }
        let lineRect = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        currentLineHighlightColor.setFill()
        UIRectFill(CGRect(
            x: highlightX,
            y: lineRect.minY + inset.top - textView.contentOffset.y,
            width: visibleWidth,
            height: lineRect.height
        ))
    }
}

// MARK: - Line Number Views

final class LineNumberGutterView: UIView {
    weak var textView: UITextView?
    var lineStarts: [Int] = [0]
    var font: UIFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    var textColor: UIColor = .secondaryLabel

    override func draw(_ rect: CGRect) {
        guard let textView else { return }
        let layoutManager = textView.layoutManager
        guard !lineStarts.isEmpty else { return }

        let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size).insetBy(dx: 0, dy: -80)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textView.textContainer)
        if glyphRange.length == 0 { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let rightPadding: CGFloat = 6
        let textContainerTop = textView.textContainerInset.top
        let contentOffsetY = textView.contentOffset.y
        let stickyTopY = textContainerTop + 1
        let visibleStartChar = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        let stickyLineIndex = lineNumberForCharacterIndex(visibleStartChar)
        let stickyLineStart = lineStarts[stickyLineIndex]
        let shouldShowStickyLineNumber = stickyLineStart < visibleStartChar
        var drawnLineIndices = Set<Int>()

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, glyphRange, _ in
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            let lineIndex = self.lineNumberForCharacterIndex(charIndex)
            if shouldShowStickyLineNumber && lineIndex == stickyLineIndex {
                return
            }
            if drawnLineIndices.contains(lineIndex) {
                return
            }
            drawnLineIndices.insert(lineIndex)

            let lineNumber = lineIndex + 1
            let drawY = usedRect.minY + textContainerTop - contentOffsetY
            let drawRect = CGRect(x: 0, y: drawY, width: self.bounds.width - rightPadding, height: usedRect.height)
            NSString(string: String(lineNumber)).draw(in: drawRect, withAttributes: attrs)
        }

        if shouldShowStickyLineNumber {
            let lineNumber = stickyLineIndex + 1
            let drawRect = CGRect(x: 0, y: stickyTopY, width: bounds.width - rightPadding, height: font.lineHeight)
            NSString(string: String(lineNumber)).draw(in: drawRect, withAttributes: attrs)
        }
    }

    private func lineNumberForCharacterIndex(_ index: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= index {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return max(0, min(high, lineStarts.count - 1))
    }
}

// MARK: - iOS Editor Container

final class LineNumberedTextViewContainer: UIView {
    let lineNumberView = LineNumberGutterView()
    let textView = EditorInputTextView()
    let currentLineHighlightOverlayView = CurrentLineHighlightOverlayView()
    let invisibleCharactersOverlayView = InvisibleCharacterOverlayView()
    private let divider = UIView()
    private var lineNumberWidthConstraint: NSLayoutConstraint?
    private var cachedLineStarts: [Int] = [0]
    private var cachedFontPointSize: CGFloat = 0
    private var cachedLineNumberWidth: CGFloat = 46
    private var cachedTextLength: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    private func configureViews() {
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        currentLineHighlightOverlayView.translatesAutoresizingMaskIntoConstraints = false
        invisibleCharactersOverlayView.translatesAutoresizingMaskIntoConstraints = false
        lineNumberView.textView = textView
        currentLineHighlightOverlayView.textView = textView
        textView.currentLineHighlightOverlayView = currentLineHighlightOverlayView
        invisibleCharactersOverlayView.textView = textView
        textView.invisibleCharactersOverlayView = invisibleCharactersOverlayView

        lineNumberView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.65)
        lineNumberView.textColor = UIColor.label.withAlphaComponent(0.70)
        lineNumberView.isUserInteractionEnabled = false

        textView.contentInsetAdjustmentBehavior = .never
        syncEditorInsets()

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.6)

        addSubview(lineNumberView)
        addSubview(divider)
        addSubview(currentLineHighlightOverlayView)
        addSubview(textView)
        addSubview(invisibleCharactersOverlayView)

        let dividerWidthConstraint = divider.widthAnchor.constraint(equalToConstant: 1)
        dividerWidthConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberView.topAnchor.constraint(equalTo: topAnchor),
            lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerWidthConstraint,

            currentLineHighlightOverlayView.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            currentLineHighlightOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            currentLineHighlightOverlayView.topAnchor.constraint(equalTo: topAnchor),
            currentLineHighlightOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            invisibleCharactersOverlayView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            invisibleCharactersOverlayView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            invisibleCharactersOverlayView.topAnchor.constraint(equalTo: textView.topAnchor),
            invisibleCharactersOverlayView.bottomAnchor.constraint(equalTo: textView.bottomAnchor)
        ])

        let widthConstraint = lineNumberView.widthAnchor.constraint(equalToConstant: 46)
        widthConstraint.isActive = true
        lineNumberWidthConstraint = widthConstraint
    }

    func applyLineNumberColors(editorBackground: UIColor, textColor: UIColor, translucentBackgroundEnabled: Bool) {
        backgroundColor = translucentBackgroundEnabled ? .clear : editorBackground
        #if os(visionOS)
        lineNumberView.backgroundColor = translucentBackgroundEnabled ? .clear : editorBackground
        divider.backgroundColor = textColor.withAlphaComponent(0.16)
        #else
        lineNumberView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.65)
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.6)
        #endif
        lineNumberView.textColor = textColor.withAlphaComponent(0.70)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncEditorInsets()
        currentLineHighlightOverlayView.setNeedsDisplay()
    }

    private func syncEditorInsets() {
        let desiredTextInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        if textView.textContainerInset != desiredTextInsets {
            textView.textContainerInset = desiredTextInsets
        }
        if textView.contentInset != .zero {
            textView.contentInset = .zero
        }
        if textView.verticalScrollIndicatorInsets != .zero {
            textView.verticalScrollIndicatorInsets = .zero
        }
        if textView.horizontalScrollIndicatorInsets != .zero {
            textView.horizontalScrollIndicatorInsets = .zero
        }
    }

    func updateLineNumbers(for text: String, fontSize: CGFloat) {
        var needsDisplayRefresh = false
        let numberFont = UIFont.monospacedDigitSystemFont(ofSize: max(11, fontSize - 1), weight: .regular)
        if abs(cachedFontPointSize - numberFont.pointSize) > 0.01 {
            lineNumberView.font = numberFont
            cachedFontPointSize = numberFont.pointSize
            needsDisplayRefresh = true
        }
        let lineStarts = lineStartOffsets(for: text)
        if lineStarts != cachedLineStarts {
            cachedLineStarts = lineStarts
            lineNumberView.lineStarts = lineStarts
            cachedTextLength = text.utf16.count
            needsDisplayRefresh = true
        }
        let lineCount = max(1, lineStarts.count)
        let digits = max(2, String(lineCount).count)
        let glyphWidth = NSString(string: "8").size(withAttributes: [.font: numberFont]).width
        let targetWidth = ceil((glyphWidth * CGFloat(digits)) + 14)
        if abs(cachedLineNumberWidth - targetWidth) > 0.5 {
            cachedLineNumberWidth = targetWidth
            lineNumberWidthConstraint?.constant = targetWidth
            setNeedsLayout()
            layoutIfNeeded()
            needsDisplayRefresh = true
        }
        if needsDisplayRefresh {
            lineNumberView.setNeedsDisplay()
        }
    }

    func updateLineNumbersAfterInteractiveEdit(for text: String, fontSize: CGFloat) {
        let textLength = text.utf16.count
        guard textLength <= 250_000 || abs(textLength - cachedTextLength) > 2_000 else {
            lineNumberView.setNeedsDisplay()
            return
        }
        updateLineNumbers(for: text, fontSize: fontSize)
    }

    private func lineStartOffsets(for text: String) -> [Int] {
        var starts: [Int] = [0]
        let utf16 = text.utf16
        starts.reserveCapacity(max(32, utf16.count / 24))
        var idx = 0
        for codeUnit in utf16 {
            idx += 1
            if codeUnit == 10 { // '\n'
                starts.append(idx)
            }
        }
        return starts
    }
}

// MARK: - iOS SwiftUI Bridge

struct CustomTextEditor: UIViewRepresentable {
    @Binding var text: String
    let documentID: UUID?
    let documentResourceID: String
    let storedCaretLocation: Int?
    let externalEditRevision: Int
    let language: String
    let colorScheme: ColorScheme
    let fontSize: CGFloat
    @Binding var isLineWrapEnabled: Bool
    let isLargeFileMode: Bool
    let showsCodeMinimap: Bool
    let translucentBackgroundEnabled: Bool
    let showKeyboardAccessoryBar: Bool
    let showLineNumbers: Bool
    let showInvisibleCharacters: Bool
    let highlightCurrentLine: Bool
    let highlightMatchingBrackets: Bool
    let showIndentationGuides: Bool
    let showScopeGuides: Bool
    let highlightScopeBackground: Bool
    let indentStyle: String
    let indentWidth: Int
    let autoIndentEnabled: Bool
    let autoCloseBracketsEnabled: Bool
    let highlightRefreshToken: Int
    let isTabLoadingContent: Bool
    let isReadOnly: Bool
    let onFontSizeChange: ((CGFloat) -> Void)?
    let onTextMutation: ((EditorTextMutation) -> Void)?

    private var fontName: String {
        UserDefaults.standard.string(forKey: "SettingsEditorFontName") ?? ""
    }

    private var useSystemFont: Bool {
        UserDefaults.standard.bool(forKey: "SettingsUseSystemFont")
    }

    private var lineHeightMultiple: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "SettingsLineHeight")
        return CGFloat(stored > 0 ? stored : 1.0)
    }

    private func resolvedUIFont(size: CGFloat? = nil) -> UIFont {
        let targetSize = size ?? fontSize
        if useSystemFont {
            return UIFont.systemFont(ofSize: targetSize)
        }
        if let named = UIFont(name: fontName, size: targetSize) {
            return named
        }
        return UIFont.monospacedSystemFont(ofSize: targetSize, weight: .regular)
    }

    private func currentLineHighlightColor(for colorScheme: ColorScheme) -> UIColor {
        UIColor.systemBlue.withAlphaComponent(colorScheme == .dark ? 0.30 : 0.22)
    }

    private func applyInvisibleCharacterPreference(_ textView: UITextView) {
        let shouldShow = showInvisibleCharacters
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "SettingsShowInvisibleCharacters") != shouldShow {
            defaults.set(shouldShow, forKey: "SettingsShowInvisibleCharacters")
        }
        if defaults.bool(forKey: "NSShowAllInvisibles") != shouldShow {
            defaults.set(shouldShow, forKey: "NSShowAllInvisibles")
        }
        if defaults.bool(forKey: "NSShowControlCharacters") != shouldShow {
            defaults.set(shouldShow, forKey: "NSShowControlCharacters")
        }
        if let editorTextView = textView as? EditorInputTextView {
            if editorTextView.rendersInvisibleCharacters != shouldShow {
                editorTextView.rendersInvisibleCharacters = shouldShow
            }
            if editorTextView.rendersIndentationGuides != showIndentationGuides {
                editorTextView.rendersIndentationGuides = showIndentationGuides
            }
            let guideWidth = max(1, indentWidth)
            if editorTextView.indentationGuideWidth != guideWidth {
                editorTextView.indentationGuideWidth = guideWidth
            }
        }
    }

    private func configurePointerSelectionBehavior(_ textView: UITextView) {
        #if os(visionOS)
        textView.textDragInteraction?.isEnabled = true
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            textView.keyboardDismissMode = .none
            textView.textDragInteraction?.isEnabled = true
        } else {
            textView.keyboardDismissMode = .interactive
        }
        #endif
    }

    private func applyWrapMode(_ shouldWrapText: Bool, textView: UITextView, preserveOffset: Bool = true) {
        let desiredLineBreakMode: NSLineBreakMode = shouldWrapText ? .byWordWrapping : .byClipping
        let visibleWidth = max(1, textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right)
        let targetContainerWidth: CGFloat
        if shouldWrapText {
            targetContainerWidth = visibleWidth
        } else {
            targetContainerWidth = noWrapContainerWidth(for: textView, visibleWidth: visibleWidth)
        }
        let targetContainerSize = CGSize(width: targetContainerWidth, height: .greatestFiniteMagnitude)
        let needsUpdate =
            textView.textContainer.lineBreakMode != desiredLineBreakMode ||
            textView.textContainer.widthTracksTextView != shouldWrapText ||
            abs(textView.textContainer.size.width - targetContainerSize.width) > 1
        textView.isScrollEnabled = true
        textView.alwaysBounceHorizontal = !shouldWrapText
        textView.showsHorizontalScrollIndicator = !shouldWrapText
        if !shouldWrapText {
            enforceNoWrapContentWidth(textView, containerWidth: targetContainerWidth)
        }
        guard needsUpdate else {
            (textView as? EditorInputTextView)?.rememberPreferredWrapLayout(
                shouldWrapText: shouldWrapText,
                containerWidth: targetContainerWidth
            )
            return
        }

        let priorOffset = textView.contentOffset
        textView.textContainer.lineBreakMode = desiredLineBreakMode
        textView.textContainer.widthTracksTextView = shouldWrapText
        textView.textContainer.size = targetContainerSize
        (textView as? EditorInputTextView)?.rememberPreferredWrapLayout(
            shouldWrapText: shouldWrapText,
            containerWidth: targetContainerWidth
        )
        if (textView.text as NSString?)?.length ?? 0 <= 300_000 {
            textView.layoutManager.ensureLayout(for: textView.textContainer)
        }
        if !shouldWrapText {
            enforceNoWrapContentWidth(textView, containerWidth: targetContainerWidth)
        }
        guard preserveOffset else { return }
        let inset = textView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)
        let clampedY = min(max(priorOffset.y, minY), maxY)
        let maxX = max(0, textView.contentSize.width - textView.bounds.width + inset.right)
        let clampedX = shouldWrapText ? 0 : min(max(priorOffset.x, 0), maxX)
        textView.setContentOffset(CGPoint(x: clampedX, y: clampedY), animated: false)
    }

    private func enforceNoWrapContentWidth(_ textView: UITextView, containerWidth: CGFloat) {
        let horizontalInsets = textView.textContainerInset.left + textView.textContainerInset.right
        let requiredWidth = max(textView.bounds.width, containerWidth + horizontalInsets)
        guard requiredWidth.isFinite, requiredWidth > textView.contentSize.width + 1 else { return }
        textView.contentSize = CGSize(width: requiredWidth, height: textView.contentSize.height)
    }

    private func noWrapContainerWidth(for textView: UITextView, visibleWidth: CGFloat) -> CGFloat {
        let text = textView.text ?? ""
        let minimumScrollableWidth = noWrapMinimumScrollableWidth(visibleWidth: visibleWidth)
        guard !text.isEmpty else { return minimumScrollableWidth }
        let nsText = text as NSString
        let sampleLimit = min(nsText.length, 120_000)
        var maxColumns = 0
        var currentColumns = 0
        let tabWidth = max(1, indentWidth)
        for index in 0..<sampleLimit {
            let unit = nsText.character(at: index)
            if unit == 10 || unit == 13 {
                maxColumns = max(maxColumns, currentColumns)
                currentColumns = 0
            } else if unit == 9 {
                currentColumns += tabWidth
            } else {
                currentColumns += 1
            }
        }
        maxColumns = max(maxColumns, currentColumns)
        let font = textView.font ?? resolvedUIFont()
        let columnWidth = NSString(string: "W").size(withAttributes: [.font: font]).width
        let measuredWidth = ceil(CGFloat(maxColumns) * max(1, columnWidth)) + textView.textContainerInset.left + textView.textContainerInset.right + 32
        return max(minimumScrollableWidth, min(measuredWidth, 20_000))
    }

    private func noWrapMinimumScrollableWidth(visibleWidth: CGFloat) -> CGFloat {
#if os(visionOS)
        return max(visibleWidth, 6_000)
#else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return max(visibleWidth, 8_000)
        }
        return max(visibleWidth, 4_000)
#endif
    }

    func makeUIView(context: Context) -> LineNumberedTextViewContainer {
        let container = LineNumberedTextViewContainer()
        let textView = container.textView
        let theme = currentEditorTheme(colorScheme: colorScheme)

        textView.delegate = context.coordinator
        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        textView.markdownFormattingEnabled = language.lowercased() == "markdown"
        let initialFont = resolvedUIFont()
        textView.font = initialFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = max(0.9, lineHeightMultiple)
        let baseColor = UIColor(theme.text)
        var typing = textView.typingAttributes
        typing[.paragraphStyle] = paragraphStyle
        typing[.foregroundColor] = baseColor
        typing[.font] = textView.font ?? initialFont
        textView.typingAttributes = typing
        let initialLength = (text as NSString).length
        if shouldUseChunkedLargeFileInstall(isLargeFileMode: isLargeFileMode, textLength: initialLength) {
            textView.text = ""
        } else {
            textView.text = text
        }
        if text.count <= 200_000 {
            textView.textStorage.beginEditing()
            textView.textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: textView.textStorage.length))
            textView.textStorage.endEditing()
        }
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.allowsEditingTextAttributes = false
        if #available(iOS 18.0, *) {
            textView.writingToolsBehavior = .none
        }
        applyInvisibleCharacterPreference(textView)
        textView.isOpaque = false
        textView.backgroundColor = .clear
        textView.highlightsCurrentLine = highlightCurrentLine && !isLargeFileMode
        textView.currentLineHighlightColor = currentLineHighlightColor(for: colorScheme)
        container.applyLineNumberColors(
            editorBackground: UIColor(theme.background),
            textColor: UIColor(theme.text),
            translucentBackgroundEnabled: translucentBackgroundEnabled
        )
        textView.setBracketAccessoryVisible(showKeyboardAccessoryBar)
        configurePointerSelectionBehavior(textView)
        context.coordinator.installFontSizePinchRecognizer(on: textView)
        let shouldWrapText = isLineWrapEnabled && !isLargeFileMode
        applyWrapMode(shouldWrapText, textView: textView, preserveOffset: false)

        if !showLineNumbers {
            container.lineNumberView.isHidden = true
        } else {
            container.lineNumberView.isHidden = false
            container.updateLineNumbers(for: text, fontSize: fontSize)
        }
        context.coordinator.container = container
        context.coordinator.textView = textView
        if shouldUseChunkedLargeFileInstall(isLargeFileMode: isLargeFileMode, textLength: initialLength) {
            DispatchQueue.main.async {
                _ = context.coordinator.installLargeTextIfNeeded(on: textView, target: text)
            }
        } else {
            context.coordinator.scheduleHighlightIfNeeded(currentText: text, immediate: true)
        }
        return container
    }

    func updateUIView(_ uiView: LineNumberedTextViewContainer, context: Context) {
        let textView = uiView.textView
        context.coordinator.parent = self
        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        let didSwitchDocumentResource = context.coordinator.lastDocumentResourceID != documentResourceID
        let didChangeStoredCaretLocation = context.coordinator.lastStoredCaretLocation != storedCaretLocation
        let didFinishTabLoad = (context.coordinator.lastTabLoadingContent == true) && !isTabLoadingContent
        let didReceiveExternalEdit = context.coordinator.lastExternalEditRevision != externalEditRevision
        let didTransitionDocumentState = didSwitchDocumentResource || didFinishTabLoad || didReceiveExternalEdit
        let shouldPublishMinimapViewport = didTransitionDocumentState ||
            (showsCodeMinimap && context.coordinator.lastShowsCodeMinimap != true)
        let isInteractivePhoneEditing =
            UIDevice.current.userInterfaceIdiom == .phone &&
            textView.isFirstResponder &&
            !didTransitionDocumentState &&
            !isTabLoadingContent
        if didSwitchDocumentResource {
            context.coordinator.cancelPendingBindingSync()
            context.coordinator.clearPendingTextMutation()
            context.coordinator.invalidateHighlightCache()
        }
        context.coordinator.lastDocumentResourceID = documentResourceID
        context.coordinator.lastTabLoadingContent = isTabLoadingContent
        context.coordinator.lastExternalEditRevision = externalEditRevision
        context.coordinator.lastShowsCodeMinimap = showsCodeMinimap
        context.coordinator.lastStoredCaretLocation = storedCaretLocation
        let targetLength = (text as NSString).length
        let shouldSkipLargeFileResync =
            isLargeFileMode &&
            targetLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length &&
            !didSwitchDocumentResource &&
            !didFinishTabLoad &&
            !didReceiveExternalEdit &&
            !context.coordinator.hasPendingBindingSync
        if textView.text != text {
            if !shouldSkipLargeFileResync {
                let shouldPreferEditorBuffer =
                    textView.isFirstResponder &&
                    !isTabLoadingContent &&
                    !didSwitchDocumentResource &&
                    !didFinishTabLoad &&
                    !didReceiveExternalEdit
                if shouldPreferEditorBuffer {
                    context.coordinator.syncBindingTextImmediately(textView.text)
                } else {
                    context.coordinator.cancelPendingBindingSync()
                    let priorSelection = textView.selectedRange
                    let priorOffset = textView.contentOffset
                    let didInstallLargeText = context.coordinator.installLargeTextIfNeeded(
                        on: textView,
                        target: text,
                        preserveSelection: !didSwitchDocumentResource,
                        preserveViewport: !didTransitionDocumentState,
                        restoredCaretLocation: didSwitchDocumentResource ? storedCaretLocation : nil
                    )
                    if !didInstallLargeText {
                        textView.text = text
                        let length = (textView.text as NSString).length
                        if didSwitchDocumentResource {
                            textView.selectedRange = NSRange(location: 0, length: 0)
                            textView.setContentOffset(.zero, animated: false)
                        } else {
                            let clampedLocation = min(priorSelection.location, length)
                            let clampedLength = min(priorSelection.length, max(0, length - clampedLocation))
                            textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
                            textView.setContentOffset(priorOffset, animated: false)
                        }
                    }
                }
            }
        }
        let targetFont = resolvedUIFont()
        if textView.font?.fontName != targetFont.fontName || textView.font?.pointSize != targetFont.pointSize {
            textView.font = targetFont
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = max(0.9, lineHeightMultiple)
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        if !isInteractivePhoneEditing, context.coordinator.lastLineHeight != lineHeightMultiple {
            let len = textView.textStorage.length
            if len > 0 && len <= 200_000 {
                let undoWasEnabled = textView.undoManager?.isUndoRegistrationEnabled ?? false
                if undoWasEnabled {
                    textView.undoManager?.disableUndoRegistration()
                }
                textView.textStorage.beginEditing()
                textView.textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: len))
                textView.textStorage.endEditing()
                if undoWasEnabled {
                    textView.undoManager?.enableUndoRegistration()
                }
            }
            context.coordinator.lastLineHeight = lineHeightMultiple
        }
        let theme = currentEditorTheme(colorScheme: colorScheme)
        let baseColor = UIColor(theme.text)
        textView.tintColor = UIColor(theme.cursor)
        textView.markdownFormattingEnabled = language.lowercased() == "markdown"
        textView.isOpaque = false
        textView.backgroundColor = .clear
        textView.highlightsCurrentLine = highlightCurrentLine && !isLargeFileMode
        textView.currentLineHighlightColor = currentLineHighlightColor(for: colorScheme)
        uiView.applyLineNumberColors(
            editorBackground: UIColor(theme.background),
            textColor: UIColor(theme.text),
            translucentBackgroundEnabled: translucentBackgroundEnabled
        )
        textView.setBracketAccessoryVisible(showKeyboardAccessoryBar)
        let shouldWrapText = isLineWrapEnabled && !isLargeFileMode
        if !isInteractivePhoneEditing {
            applyWrapMode(shouldWrapText, textView: textView)
        }
        textView.layoutManager.allowsNonContiguousLayout = true
        configurePointerSelectionBehavior(textView)
        if #available(iOS 18.0, *) {
            if textView.writingToolsBehavior != .none {
                textView.writingToolsBehavior = .none
            }
        }
        applyInvisibleCharacterPreference(textView)
        textView.typingAttributes[.foregroundColor] = baseColor
        if !showLineNumbers {
            uiView.lineNumberView.isHidden = true
        } else {
            uiView.lineNumberView.isHidden = false
            if isInteractivePhoneEditing {
                uiView.lineNumberView.setNeedsDisplay()
            } else if didTransitionDocumentState {
                uiView.updateLineNumbers(for: text, fontSize: fontSize)
            } else {
                uiView.updateLineNumbersAfterInteractiveEdit(for: text, fontSize: fontSize)
            }
        }
        context.coordinator.syncLineNumberScroll()
        if (didSwitchDocumentResource || didChangeStoredCaretLocation), let storedCaretLocation {
            context.coordinator.restoreCaret(storedCaretLocation, in: textView)
        }
        if didTransitionDocumentState {
            context.coordinator.scheduleHighlightIfNeeded(currentText: textView.text ?? text, immediate: true)
        } else if !isInteractivePhoneEditing {
            context.coordinator.scheduleHighlightIfNeeded(currentText: text)
        }
        if shouldPublishMinimapViewport {
            textView.layoutIfNeeded()
            context.coordinator.postMinimapViewportIfNeeded(textView: textView, scrollView: textView, force: true)
            context.coordinator.scheduleDeferredMinimapViewportPost(for: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: CustomTextEditor
        weak var container: LineNumberedTextViewContainer?
        weak var textView: EditorInputTextView?
        private let highlightQueue = DispatchQueue(label: "NeonVision.iOS.SyntaxHighlight", qos: .userInitiated)
        private var pendingHighlight: DispatchWorkItem?
        private var pendingBindingSync: DispatchWorkItem?
        private var pendingTextMutation: (range: NSRange, replacement: String)?
        private var pendingEditedRange: NSRange?
        private var isInstallingLargeText = false
        private var largeTextInstallGeneration: Int = 0
        private var lastHighlightedText: String = ""
        private var lastLanguage: String?
        private var lastColorScheme: ColorScheme?
        var lastLineHeight: CGFloat?
        private var lastHighlightToken: Int = 0
        private var lastSelectionLocation: Int = -1
        private var lastHighlightViewportAnchor: Int = -1
        private var lastTranslucencyEnabled: Bool?
        private var lastLineNumberContentOffsetY: CGFloat = .greatestFiniteMagnitude
        private var lastMinimapViewportTop: Double = -1
        private var lastMinimapViewportHeight: Double = -1
        private var pendingDeferredMinimapViewportPost = false
        private var isApplyingHighlight = false
        private var highlightGeneration: Int = 0
        private var lastCaretStatusLocation: Int = -1
        private var lastCaretStatusLine: Int = Int.min
        private var lastCaretStatusColumn: Int = Int.min
        private var fontSizePinchRecognizer: UIPinchGestureRecognizer?
        private var pinchStartFontSize: CGFloat?
        private var lastPinchFontSize: CGFloat?
        var lastDocumentResourceID: String?
        var lastStoredCaretLocation: Int?
        var lastTabLoadingContent: Bool?
        var lastExternalEditRevision: Int?
        var lastShowsCodeMinimap: Bool?
        var hasPendingBindingSync: Bool { pendingBindingSync != nil }

        private var isPhoneActivelyEditing: Bool {
            UIDevice.current.userInterfaceIdiom == .phone && (textView?.isFirstResponder ?? false)
        }

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(moveToLine(_:)), name: .moveCursorToLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(moveToRange(_:)), name: .moveCursorToRange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(scrollViewportToFraction(_:)), name: .scrollEditorViewportToFraction, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(updateKeyboardAccessoryVisibility(_:)), name: .keyboardAccessoryBarVisibilityChanged, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func installFontSizePinchRecognizer(on textView: UITextView) {
            guard fontSizePinchRecognizer == nil else { return }
            let recognizer = UIPinchGestureRecognizer(
                target: self,
                action: #selector(handleFontSizePinch(_:))
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            textView.addGestureRecognizer(recognizer)
            fontSizePinchRecognizer = recognizer
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === fontSizePinchRecognizer || otherGestureRecognizer === fontSizePinchRecognizer
        }

        @objc func handleFontSizePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                let startingFontSize = parent.fontSize
                pinchStartFontSize = startingFontSize
                lastPinchFontSize = startingFontSize

            case .changed:
                guard let pinchStartFontSize else { return }
                let requestedFontSize = pinchStartFontSize + ((gesture.scale - 1) * 10).rounded()
                let clampedFontSize = min(28, max(10, requestedFontSize))
                guard clampedFontSize != lastPinchFontSize else { return }
                lastPinchFontSize = clampedFontSize
                parent.onFontSizeChange?(clampedFontSize)

            case .ended, .cancelled, .failed:
                pinchStartFontSize = nil
                lastPinchFontSize = nil

            default:
                break
            }
        }

        private func shouldRenderLineNumbers() -> Bool {
            guard let lineView = container?.lineNumberView else { return false }
            return parent.showLineNumbers && !lineView.isHidden && !isInstallingLargeText
        }

        func invalidateHighlightCache() {
            lastHighlightedText = ""
            lastLanguage = nil
            lastColorScheme = nil
            lastLineHeight = nil
            lastHighlightToken = 0
            lastSelectionLocation = -1
            lastHighlightViewportAnchor = -1
            lastTranslucencyEnabled = nil
            lastLineNumberContentOffsetY = .greatestFiniteMagnitude
            lastCaretStatusLocation = -1
            lastCaretStatusLine = Int.min
            lastCaretStatusColumn = Int.min
            largeTextInstallGeneration &+= 1
            isInstallingLargeText = false
        }

        private func currentViewportAnchor(textLength: Int, language: String) -> Int {
            guard let textView,
                  supportsResponsiveLargeFileHighlight(language: language, textLength: textLength),
                  textLength >= 100_000 else { return -1 }
            let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size).insetBy(dx: 0, dy: -80)
            let glyphRange = textView.layoutManager.glyphRange(forBoundingRect: visibleRect, in: textView.textContainer)
            let charRange = textView.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.length > 0 else { return -1 }
            return charRange.location
        }

        private func syncBindingText(_ text: String, immediate: Bool = false) {
            if parent.isTabLoadingContent || isInstallingLargeText {
                return
            }
            pendingBindingSync?.cancel()
            pendingBindingSync = nil
            if immediate || (text as NSString).length < EditorRuntimeLimits.bindingDebounceUTF16Length {
                parent.text = text
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingBindingSync = nil
                if self.textView?.text == text {
                    self.parent.text = text
                }
            }
            pendingBindingSync = work
            DispatchQueue.main.asyncAfter(deadline: .now() + EditorRuntimeLimits.bindingDebounceDelay, execute: work)
        }

        func cancelPendingBindingSync() {
            pendingBindingSync?.cancel()
            pendingBindingSync = nil
        }

        func clearPendingTextMutation() {
            pendingTextMutation = nil
            pendingEditedRange = nil
        }

        func syncBindingTextImmediately(_ text: String) {
            guard !isInstallingLargeText else { return }
            syncBindingText(text, immediate: true)
        }

        fileprivate func installLargeTextIfNeeded(
            on textView: EditorInputTextView,
            target: String,
            preserveSelection: Bool = true,
            preserveViewport: Bool = true,
            restoredCaretLocation: Int? = nil
        ) -> Bool {
            guard parent.isLargeFileMode else { return false }
            let openMode = currentLargeFileOpenMode()
            guard openMode != .standard else { return false }
            let targetLength = (target as NSString).length
            guard targetLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length else { return false }

            largeTextInstallGeneration &+= 1
            let generation = largeTextInstallGeneration
            isInstallingLargeText = true
            pendingHighlight?.cancel()
            pendingHighlight = nil

            let previousSelection = textView.selectedRange
            let priorOffset = textView.contentOffset
            let wasFirstResponder = textView.isFirstResponder
            let installDocumentID = parent.documentID
            let installDocumentResourceID = parent.documentResourceID
            textView.isEditable = false
            textView.text = ""

            let nsTarget = target as NSString

            func applyChunk(from location: Int) {
                guard generation == self.largeTextInstallGeneration,
                      self.textView === textView,
                      self.parent.documentID == installDocumentID,
                      self.parent.documentResourceID == installDocumentResourceID else {
                    if generation == self.largeTextInstallGeneration {
                        self.isInstallingLargeText = false
                    }
                    return
                }
                let remaining = targetLength - location
                guard remaining > 0 else {
                    self.isInstallingLargeText = false
                    textView.isEditable = !parent.isReadOnly
                    if let restoredCaretLocation {
                        let range = NSRange(
                            location: min(max(0, restoredCaretLocation), targetLength),
                            length: 0
                        )
                        textView.selectedRange = range
                        textView.scrollRangeToVisible(range)
                    } else if preserveSelection {
                        let safeLocation = min(max(0, previousSelection.location), targetLength)
                        let safeLength = min(max(0, previousSelection.length), max(0, targetLength - safeLocation))
                        textView.selectedRange = NSRange(location: safeLocation, length: safeLength)
                    } else {
                        textView.selectedRange = NSRange(location: 0, length: 0)
                    }
                    if preserveViewport {
                        textView.setContentOffset(priorOffset, animated: false)
                    }
                    if wasFirstResponder && preserveSelection {
                        textView.becomeFirstResponder()
                    }
                    self.updateCaretStatus()
                    self.scheduleHighlightIfNeeded(currentText: target, immediate: true)
                    return
                }

                let chunkLength = min(LargeFileInstallRuntime.chunkUTF16, remaining)
                let chunk = nsTarget.substring(with: NSRange(location: location, length: chunkLength))
                let storage = textView.textStorage
                storage.beginEditing()
                storage.append(NSAttributedString(string: chunk))
                storage.endEditing()
                DispatchQueue.main.async {
                    applyChunk(from: location + chunkLength)
                }
            }

            applyChunk(from: 0)
            return true
        }

        func restoreCaret(_ location: Int, in textView: UITextView) {
            let length = ((textView.text ?? "") as NSString).length
            let range = NSRange(location: min(max(0, location), length), length: 0)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
            updateCaretStatus()
        }

        private func setPendingTextMutation(range: NSRange, replacement: String) {
            guard !parent.isTabLoadingContent, parent.documentID != nil else {
                pendingTextMutation = nil
                return
            }
            pendingTextMutation = (range: range, replacement: replacement)
        }

        private func applyPendingTextMutationIfPossible() -> Bool {
            defer { pendingTextMutation = nil }
            guard !parent.isTabLoadingContent,
                  let pendingTextMutation,
                  let documentID = parent.documentID,
                  let onTextMutation = parent.onTextMutation else {
                return false
            }
            onTextMutation(
                EditorTextMutation(
                    documentID: documentID,
                    range: pendingTextMutation.range,
                    replacement: pendingTextMutation.replacement
                )
            )
            return true
        }

        @objc private func updateKeyboardAccessoryVisibility(_ notification: Notification) {
            guard let textView else { return }
            let isVisible: Bool
            if let explicit = notification.object as? Bool {
                isVisible = explicit
            } else {
                isVisible = UserDefaults.standard.object(forKey: "SettingsShowKeyboardAccessoryBarIOS") as? Bool ?? false
            }
            textView.setBracketAccessoryVisible(isVisible)
            if isVisible && !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            textView.reloadInputViews()
        }

        @objc private func moveToRange(_ notification: Notification) {
            guard let textView else { return }
            guard let location = notification.userInfo?[EditorCommandUserInfo.rangeLocation] as? Int,
                  let length = notification.userInfo?[EditorCommandUserInfo.rangeLength] as? Int else { return }
            let textLength = (textView.text as NSString?)?.length ?? 0
            guard location >= 0, length >= 0, location + length <= textLength else { return }
            let range = NSRange(location: location, length: length)
            let shouldFocusEditor = notification.userInfo?[EditorCommandUserInfo.focusEditor] as? Bool ?? true
            DispatchQueue.main.async {
                if shouldFocusEditor {
                    textView.becomeFirstResponder()
                }
                textView.selectedRange = range
                textView.scrollRangeToVisible(range)
                self.updateCaretStatus()
            }
        }

        @objc private func moveToLine(_ notification: Notification) {
            if let targetDocumentID = notification.userInfo?[EditorCommandUserInfo.documentID] as? String,
               parent.documentID?.uuidString != targetDocumentID {
                return
            }
            guard let lineOneBased = notification.object as? Int, lineOneBased > 0 else { return }
            guard let textView else { return }
            let nsText = (textView.text ?? "") as NSString
            guard nsText.length > 0 else { return }

            let targetLine = max(1, lineOneBased)
            var currentLine = 1
            var location = 0
            while location < nsText.length, currentLine < targetLine {
                let codeUnit = nsText.character(at: location)
                location += 1
                if codeUnit == 10 {
                    currentLine += 1
                }
            }
            location = max(0, min(location, nsText.length))
            let target = NSRange(location: location, length: 0)
            textView.becomeFirstResponder()
            textView.selectedRange = target
            textView.scrollRangeToVisible(target)
            updateCaretStatus()
            scheduleHighlightIfNeeded(currentText: textView.text ?? "", immediate: true)
        }

        @objc private func scrollViewportToFraction(_ notification: Notification) {
            if let targetDocumentID = notification.userInfo?[EditorCommandUserInfo.documentID] as? String,
               parent.documentID?.uuidString != targetDocumentID {
                return
            }
            guard let textView,
                  let topFraction = notification.userInfo?[EditorCommandUserInfo.viewportTopFraction] as? Double else { return }

            textView.layoutIfNeeded()
            let visibleHeight = max(1, textView.bounds.height)
            let contentHeight = max(textView.contentSize.height, visibleHeight)
            let targetY = CGFloat(min(max(0, topFraction), 1)) * max(0, contentHeight - visibleHeight)
            let minOffsetY = -textView.adjustedContentInset.top
            let maxOffsetY = max(minOffsetY, textView.contentSize.height - visibleHeight + textView.adjustedContentInset.bottom)
            let clampedY = min(max(targetY, minOffsetY), maxOffsetY)
            textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: clampedY), animated: false)
            postMinimapViewportIfNeeded(textView: textView, scrollView: textView, force: true)
        }

        func scheduleHighlightIfNeeded(currentText: String? = nil, immediate: Bool = false) {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.scheduleHighlightIfNeeded(currentText: currentText, immediate: immediate)
                }
                return
            }
            guard let textView else { return }
            let text = currentText ?? textView.text ?? ""
            let lang = parent.language
            let scheme = parent.colorScheme
            let lineHeight = parent.lineHeightMultiple
            let token = parent.highlightRefreshToken
            let translucencyEnabled = parent.translucentBackgroundEnabled
            let useSystemFont = parent.useSystemFont
            let fontName = parent.fontName
            let fontSize = parent.fontSize
            let selectionLocation = textView.selectedRange.location
            let textLength = (text as NSString).length
            let nsText = text as NSString
            if textLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length &&
                !supportsResponsiveLargeFileHighlight(language: lang, textLength: textLength) {
                updateMatchingBracketOverlay(textView: textView, text: nsText, selectionLocation: selectionLocation)
                lastHighlightedText = ""
                lastLanguage = lang
                lastColorScheme = scheme
                lastLineHeight = lineHeight
                lastHighlightToken = token
                lastSelectionLocation = selectionLocation
                lastHighlightViewportAnchor = -1
                lastTranslucencyEnabled = translucencyEnabled
                return
            }
            let theme = currentEditorTheme(colorScheme: scheme)
            let syntaxProfile = syntaxProfile(for: lang, text: nsText)
            let colors = SyntaxColors(
                keyword: theme.syntax.keyword,
                string: theme.syntax.string,
                number: theme.syntax.number,
                comment: theme.syntax.comment,
                attribute: theme.syntax.attribute,
                variable: theme.syntax.variable,
                def: theme.syntax.def,
                property: theme.syntax.property,
                meta: theme.syntax.meta,
                tag: theme.syntax.tag,
                atom: theme.syntax.atom,
                builtin: theme.syntax.builtin,
                type: theme.syntax.type
            )
            let patterns = getSyntaxPatterns(for: lang, colors: colors, profile: syntaxProfile)
            let emphasisPatterns = syntaxEmphasisPatterns(for: lang, profile: syntaxProfile)
            let viewportAnchor = currentViewportAnchor(
                textLength: textLength,
                language: lang
            )

            if text == lastHighlightedText &&
                lang == lastLanguage &&
                scheme == lastColorScheme &&
                lineHeight == lastLineHeight &&
                lastHighlightToken == token &&
                lastSelectionLocation == selectionLocation &&
                lastHighlightViewportAnchor == viewportAnchor &&
                lastTranslucencyEnabled == translucencyEnabled {
                return
            }

            let styleStateUnchanged = lang == lastLanguage &&
                scheme == lastColorScheme &&
                lineHeight == lastLineHeight &&
                lastHighlightToken == token &&
                lastTranslucencyEnabled == translucencyEnabled
            let selectionOnlyChange = text == lastHighlightedText &&
                styleStateUnchanged &&
                lastSelectionLocation != selectionLocation
            if selectionOnlyChange && parent.isLineWrapEnabled {
                pendingHighlight?.cancel()
                pendingHighlight = nil
                updateMatchingBracketOverlay(textView: textView, text: nsText, selectionLocation: selectionLocation)
                lastSelectionLocation = selectionLocation
                return
            }
            if selectionOnlyChange && textLength >= EditorRuntimeLimits.cursorRehighlightMaxUTF16Length {
                updateMatchingBracketOverlay(textView: textView, text: nsText, selectionLocation: selectionLocation)
                lastSelectionLocation = selectionLocation
                return
            }

            let incrementalRange: NSRange? = {
                guard token == lastHighlightToken,
                      lang == lastLanguage,
                      scheme == lastColorScheme,
                      !immediate,
                      let edit = pendingEditedRange else { return nil }
                let supportsLargeFileJSON = parent.isLargeFileMode && supportsResponsiveLargeFileHighlight(language: lang, textLength: textLength)
                if !supportsLargeFileJSON && text.utf16.count >= 120_000 {
                    return nil
                }
                let padding = supportsLargeFileJSON
                    ? EditorRuntimeLimits.largeFileJSONIncrementalPaddingUTF16
                    : 6_000
                return expandedRange(around: edit, in: text as NSString, maxUTF16Padding: padding)
            }()
            pendingEditedRange = nil
            pendingHighlight?.cancel()
            highlightGeneration &+= 1
            let generation = highlightGeneration
            let applyRange = incrementalRange ?? preferredHighlightRange(textView: textView, text: text as NSString, immediate: immediate)
            let work = DispatchWorkItem { @Sendable [weak self] in
                Self.computeHighlightAndApply(
                    coordinator: self,
                    text: text,
                    language: lang,
                    colorScheme: scheme,
                    useSystemFont: useSystemFont,
                    fontName: fontName,
                    fontSize: fontSize,
                    theme: theme,
                    syntaxProfile: syntaxProfile,
                    colors: colors,
                    patterns: patterns,
                    emphasisPatterns: emphasisPatterns,
                    token: token,
                    generation: generation,
                    applyRange: applyRange
                )
            }
            pendingHighlight = work
            let allowImmediate = textLength < EditorRuntimeLimits.nonImmediateHighlightMaxUTF16Length
            if (immediate || lastHighlightedText.isEmpty || lastHighlightToken != token) && allowImmediate {
                highlightQueue.async(execute: work)
            } else {
                let delay: TimeInterval
                if text.utf16.count >= 120_000 {
                    delay = 0.24
                } else if text.utf16.count >= 80_000 {
                    delay = 0.18
                } else {
                    delay = 0.1
                }
                highlightQueue.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }

        private func expandedRange(around range: NSRange, in text: NSString, maxUTF16Padding: Int = 8000) -> NSRange {
            let start = max(0, range.location - maxUTF16Padding)
            let end = min(text.length, NSMaxRange(range) + maxUTF16Padding)
            let startLine = text.lineRange(for: NSRange(location: start, length: 0)).location
            let endAnchor = max(startLine, min(text.length - 1, max(0, end - 1)))
            let endLine = NSMaxRange(text.lineRange(for: NSRange(location: endAnchor, length: 0)))
            return NSRange(location: startLine, length: max(0, endLine - startLine))
        }

        private func preferredHighlightRange(
            textView: UITextView,
            text: NSString,
            immediate: Bool
        ) -> NSRange {
            let fullRange = NSRange(location: 0, length: text.length)
            // Restrict to visible range only for responsive large-file profiles.
            let supportsResponsiveRange =
                parent.isLargeFileMode &&
                supportsResponsiveLargeFileHighlight(language: parent.language, textLength: text.length)
            guard supportsResponsiveRange, text.length >= 100_000 else { return fullRange }
            let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size).insetBy(dx: 0, dy: -80)
            let glyphRange = textView.layoutManager.glyphRange(forBoundingRect: visibleRect, in: textView.textContainer)
            let charRange = textView.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.length > 0 else { return fullRange }
            let padding = EditorRuntimeLimits.largeFileJSONVisiblePaddingUTF16
            return expandedRange(around: charRange, in: text, maxUTF16Padding: padding)
        }

        private nonisolated static func computeHighlightAndApply(
            coordinator: Coordinator?,
            text: String,
            language: String,
            colorScheme: ColorScheme,
            useSystemFont: Bool,
            fontName: String,
            fontSize: CGFloat,
            theme: EditorTheme,
            syntaxProfile: SyntaxPatternProfile,
            colors: SyntaxColors,
            patterns: [String: Color],
            emphasisPatterns: SyntaxEmphasisPatterns,
            token: Int,
            generation: Int,
            applyRange: NSRange
        ) {
            let interval = syntaxHighlightSignposter.beginInterval("rehighlight_ios")
            defer { syntaxHighlightSignposter.endInterval("rehighlight_ios", interval) }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let baseColor = UIColor(theme.text)
            let baseFont: UIFont
            if useSystemFont {
                baseFont = UIFont.systemFont(ofSize: fontSize)
            } else if let named = UIFont(name: fontName, size: fontSize) {
                baseFont = named
            } else {
                baseFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }

            var coloredRanges: [(NSRange, UIColor)] = []
            var emphasizedRanges: [(NSRange, SyntaxFontEmphasis)] = []

            if let fastRanges = fastSyntaxColorRanges(
                language: language,
                profile: syntaxProfile,
                text: nsText,
                in: applyRange,
                colors: colors
            ) {
                for (range, color) in fastRanges {
                    guard isValidHighlightRange(range, utf16Length: fullRange.length) else { continue }
                    coloredRanges.append((range, UIColor(color)))
                }
                } else {
                    for (pattern, color) in patterns {
                    guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                    let matches = regex.matches(in: text, range: applyRange)
                    let uiColor = UIColor(color)
                    for match in matches {
                        guard isValidHighlightRange(match.range, utf16Length: fullRange.length) else { continue }
                        coloredRanges.append((match.range, uiColor))
                        }
                    }
                }
                // Apply broad tokens first so attributes and quoted values remain distinct.
                coloredRanges.sort { lhs, rhs in
                    lhs.0.length == rhs.0.length ? lhs.0.location < rhs.0.location : lhs.0.length > rhs.0.length
                }

                if theme.boldKeywords {
                for pattern in emphasisPatterns.keyword {
                    guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                    let matches = regex.matches(in: text, range: applyRange)
                    for match in matches {
                        guard isValidHighlightRange(match.range, utf16Length: fullRange.length) else { continue }
                        emphasizedRanges.append((match.range, .keyword))
                    }
                }
            }

            if theme.italicComments {
                for pattern in emphasisPatterns.comment {
                    guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                    let matches = regex.matches(in: text, range: applyRange)
                    for match in matches {
                        guard isValidHighlightRange(match.range, utf16Length: fullRange.length) else { continue }
                        emphasizedRanges.append((match.range, .comment))
                    }
                }
            }

            DispatchQueue.main.async { [weak coordinator] in
                guard let self = coordinator, let textView = self.textView else { return }
                guard generation == self.highlightGeneration else { return }
                guard textView.text == text else { return }
                guard !self.isPhoneActivelyEditing else { return }
                let selectedRange = textView.selectedRange
                let viewportAnchor = self.currentViewportAnchor(
                    textLength: (text as NSString).length,
                    language: language
                )
                let priorOffset = textView.contentOffset
                let wasFirstResponder = textView.isFirstResponder
                self.isApplyingHighlight = true
                let undoWasEnabled = textView.undoManager?.isUndoRegistrationEnabled ?? false
                if undoWasEnabled {
                    textView.undoManager?.disableUndoRegistration()
                }
                defer {
                    if undoWasEnabled {
                        textView.undoManager?.enableUndoRegistration()
                    }
                }
                textView.textStorage.beginEditing()
                textView.textStorage.removeAttribute(.foregroundColor, range: applyRange)
                textView.textStorage.removeAttribute(.backgroundColor, range: applyRange)
                textView.textStorage.removeAttribute(.underlineStyle, range: applyRange)
                textView.textStorage.addAttribute(.foregroundColor, value: baseColor, range: applyRange)
                textView.textStorage.addAttribute(.font, value: baseFont, range: applyRange)
                let boldKeywordFont = fontWithSymbolicTrait(baseFont, trait: .traitBold)
                let italicCommentFont = fontWithSymbolicTrait(baseFont, trait: .traitItalic)
                for (range, color) in coloredRanges {
                    textView.textStorage.addAttribute(.foregroundColor, value: color, range: range)
                }
                for (range, emphasis) in emphasizedRanges {
                    let font: UIFont
                    switch emphasis {
                    case .keyword:
                        font = boldKeywordFont
                    case .comment:
                        font = italicCommentFont
                    }
                    textView.textStorage.addAttribute(.font, value: font, range: range)
                }
                let suppressLargeFileExtras = self.parent.isLargeFileMode
                let scopeGuideVisualsSupported = supportsScopeGuideVisuals(language: self.parent.language)
                let wantsBracketTokens = self.parent.highlightMatchingBrackets && !suppressLargeFileExtras
                let wantsScopeBackground = self.parent.highlightScopeBackground && !suppressLargeFileExtras && !self.parent.isLineWrapEnabled && scopeGuideVisualsSupported
                let wantsScopeGuides = self.parent.showScopeGuides && !suppressLargeFileExtras && !self.parent.isLineWrapEnabled && scopeGuideVisualsSupported
                let needsScopeComputation = (wantsBracketTokens || wantsScopeBackground || wantsScopeGuides)
                    && fullRange.length < EditorRuntimeLimits.scopeComputationMaxUTF16Length
                let bracketMatch = needsScopeComputation ? computeBracketScopeMatch(text: text, caretLocation: selectedRange.location) : nil
                let indentationMatch: IndentationScopeMatch? = {
                    guard needsScopeComputation, supportsIndentationScopes(language: self.parent.language) else { return nil }
                    return computeIndentationScopeMatch(text: text, caretLocation: selectedRange.location)
                }()

                if wantsBracketTokens, let match = bracketMatch {
                    let textLength = fullRange.length
                    if isValidRange(match.openRange, utf16Length: textLength) {
                        textView.textStorage.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: match.openRange)
                        textView.textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.openRange)
                        textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemOrange.withAlphaComponent(0.22), range: match.openRange)
                    }
                    if isValidRange(match.closeRange, utf16Length: textLength) {
                        textView.textStorage.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: match.closeRange)
                        textView.textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.closeRange)
                        textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemOrange.withAlphaComponent(0.22), range: match.closeRange)
                    }
                }
                if wantsBracketTokens, let match = bracketMatch {
                    textView.matchingBracketHighlightRanges = [match.openRange, match.closeRange].filter {
                        Self.isValidHighlightRange($0, utf16Length: fullRange.length)
                    }
                } else {
                    textView.matchingBracketHighlightRanges = []
                }

                if wantsScopeBackground || wantsScopeGuides {
                    let textLength = fullRange.length
                    let scopeRange = bracketMatch?.scopeRange ?? indentationMatch?.scopeRange
                    let guideRanges = bracketMatch?.guideMarkerRanges ?? indentationMatch?.guideMarkerRanges ?? []

                    if wantsScopeBackground, let scope = scopeRange, isValidRange(scope, utf16Length: textLength) {
                        textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemOrange.withAlphaComponent(0.18), range: scope)
                    }
                    if wantsScopeGuides {
                        for marker in guideRanges {
                            if isValidRange(marker, utf16Length: textLength) {
                                textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemBlue.withAlphaComponent(0.36), range: marker)
                            }
                        }
                    }
                }
                textView.textStorage.endEditing()
                textView.selectedRange = selectedRange
                if wasFirstResponder {
                    textView.setContentOffset(priorOffset, animated: false)
                }
                textView.typingAttributes = [
                    .foregroundColor: baseColor,
                    .font: baseFont
                ]
                self.isApplyingHighlight = false
                self.lastHighlightedText = text
                self.lastLanguage = language
                self.lastColorScheme = colorScheme
                self.lastLineHeight = self.parent.lineHeightMultiple
                self.lastHighlightToken = token
                self.lastSelectionLocation = selectedRange.location
                self.lastHighlightViewportAnchor = viewportAnchor
                self.lastTranslucencyEnabled = self.parent.translucentBackgroundEnabled
                self.syncLineNumberScroll()
                textView.setNeedsDisplay()
            }
        }

        private nonisolated static func isValidHighlightRange(_ range: NSRange, utf16Length: Int) -> Bool {
            guard range.location != NSNotFound, range.length >= 0, range.location >= 0 else { return false }
            return NSMaxRange(range) <= utf16Length
        }

        private func updateMatchingBracketOverlay(textView: UITextView, text: NSString, selectionLocation: Int) {
            guard let editorTextView = textView as? EditorInputTextView else { return }
            guard parent.highlightMatchingBrackets,
                  !parent.isLargeFileMode,
                  text.length < EditorRuntimeLimits.scopeComputationMaxUTF16Length,
                  let match = computeBracketScopeMatch(text: text as String, caretLocation: selectionLocation) else {
                editorTextView.matchingBracketHighlightRanges = []
                return
            }
            editorTextView.matchingBracketHighlightRanges = [match.openRange, match.closeRange].filter {
                Self.isValidHighlightRange($0, utf16Length: text.length)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            let didApplyIncrementalMutation = applyPendingTextMutationIfPossible()
            if !didApplyIncrementalMutation {
                syncBindingText(textView.text)
            }
            if let editorTextView = textView as? EditorInputTextView,
               editorTextView.rendersInvisibleCharacters || editorTextView.rendersIndentationGuides {
                editorTextView.invisibleCharactersOverlayView?.requestRedraw(immediate: !isPhoneActivelyEditing)
            }
            if shouldRenderLineNumbers() {
                if UIDevice.current.userInterfaceIdiom == .phone, textView.isFirstResponder {
                    container?.lineNumberView.setNeedsDisplay()
                } else {
                    container?.updateLineNumbersAfterInteractiveEdit(for: textView.text, fontSize: parent.fontSize)
                }
            }
            let nsText = (textView.text ?? "") as NSString
            let caretLocation = min(nsText.length, textView.selectedRange.location)
            pendingEditedRange = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))
            updateCaretStatus()
            guard !isPhoneActivelyEditing else {
                pendingHighlight?.cancel()
                pendingHighlight = nil
                highlightGeneration &+= 1
                return
            }
            scheduleHighlightIfNeeded(currentText: textView.text)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            textView.setNeedsDisplay()
            let editorTextView = textView as? EditorInputTextView
            editorTextView?.currentLineHighlightOverlayView?.setNeedsDisplay()
            let nsText = (textView.text ?? "") as NSString
            publishSelectionSnapshot(from: nsText, selectedRange: textView.selectedRange)
            updateCaretStatus()
            if !(UIDevice.current.userInterfaceIdiom == .phone && textView.isFirstResponder) {
                let nsLength = (textView.text as NSString?)?.length ?? 0
                let immediateHighlight = nsLength < 200_000
                scheduleHighlightIfNeeded(currentText: textView.text, immediate: immediateHighlight)
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                pendingHighlight?.cancel()
                pendingHighlight = nil
                highlightGeneration &+= 1
            }
            NotificationCenter.default.post(name: .editorFocusDidChange, object: true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            NotificationCenter.default.post(name: .editorFocusDidChange, object: false)
            let textLength = (textView.text as NSString?)?.length ?? 0
            scheduleHighlightIfNeeded(
                currentText: textView.text,
                immediate: textLength < EditorRuntimeLimits.cursorRehighlightMaxUTF16Length
            )
        }

        @available(iOS 16.0, *)
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }
            let snapshotAction = UIAction(
                title: "Create Code Snapshot",
                image: UIImage(systemName: "camera.viewfinder")
            ) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                let nsText = (textView.text ?? "") as NSString
                self.publishSelectionSnapshot(from: nsText, selectedRange: textView.selectedRange)
                NotificationCenter.default.post(name: .editorRequestCodeSnapshotFromSelection, object: nil)
            }
            return UIMenu(children: suggestedActions + [snapshotAction])
        }

        private func publishSelectionSnapshot(from text: NSString, selectedRange: NSRange) {
            guard selectedRange.location != NSNotFound,
                  selectedRange.length > 0,
                  NSMaxRange(selectedRange) <= text.length else {
                NotificationCenter.default.post(name: .editorSelectionDidChange, object: "")
                return
            }
            let cappedLength = min(selectedRange.length, 20_000)
            let snippet = text.substring(with: NSRange(location: selectedRange.location, length: cappedLength))
            NotificationCenter.default.post(name: .editorSelectionDidChange, object: snippet)
        }

        private func updateCaretStatus() {
            guard let textView else { return }
            let nsText = (textView.text ?? "") as NSString
            let location = min(max(0, textView.selectedRange.location), nsText.length)
            let useOffsetOnlyStatus =
                parent.isLargeFileMode ||
                nsText.length > 300_000 ||
                (UIDevice.current.userInterfaceIdiom == .phone && nsText.length > 80_000) ||
                (isPhoneActivelyEditing && nsText.length > 20_000)
            if useOffsetOnlyStatus {
                postCaretStatusIfChanged(line: 0, column: location, location: location)
                return
            }

            let caret = editorCaretLineColumn(in: nsText, location: location)
            postCaretStatusIfChanged(line: caret.line, column: caret.column, location: location)
        }

        private func postCaretStatusIfChanged(line: Int, column: Int, location: Int) {
            guard line != lastCaretStatusLine ||
                    column != lastCaretStatusColumn ||
                    location != lastCaretStatusLocation else { return }
            lastCaretStatusLine = line
            lastCaretStatusColumn = column
            lastCaretStatusLocation = location
            var userInfo: [AnyHashable: Any] = ["line": line, "column": column, "location": location]
            if let documentID = parent.documentID {
                userInfo[EditorCommandUserInfo.documentID] = documentID.uuidString
            }
            NotificationCenter.default.post(
                name: .caretPositionDidChange,
                object: nil,
                userInfo: userInfo
            )
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            EditorPerformanceMonitor.shared.markFirstKeystroke()
            if text == "\t" {
                if let expansion = EmmetExpander.expansionIfPossible(
                    in: textView.text ?? "",
                    cursorUTF16Location: range.location,
                    language: parent.language
                ) {
                    setPendingTextMutation(range: expansion.range, replacement: expansion.expansion)
                    performProgrammaticReplacement(
                        in: textView,
                        range: expansion.range,
                        replacement: expansion.expansion,
                        selectedRange: NSRange(location: expansion.range.location + expansion.caretOffset, length: 0)
                    )
                    return false
                }
                let insertion: String
                if parent.indentStyle == "tabs" {
                    insertion = "\t"
                } else {
                    insertion = String(repeating: " ", count: max(1, parent.indentWidth))
                }
                setPendingTextMutation(range: range, replacement: insertion)
                performProgrammaticReplacement(
                    in: textView,
                    range: range,
                    replacement: insertion,
                    selectedRange: NSRange(location: range.location + insertion.count, length: 0)
                )
                return false
            }

            if text == "\n", parent.autoIndentEnabled {
                let ns = textView.text as NSString
                guard let returnContext = autoIndentReturnContext(
                    in: ns,
                    proposedRange: range,
                    selectedRange: textView.selectedRange
                ) else {
                    return true
                }
                let currentLine = returnContext.linePrefix
                let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
                let normalized = normalizedIndentation(String(indent))
                let listPrefix = continuedMarkdownListPrefix(for: currentLine, normalizedIndent: normalized)
                let replacement = "\n" + (listPrefix ?? normalized)
                setPendingTextMutation(range: returnContext.replacementRange, replacement: replacement)
                performProgrammaticReplacement(
                    in: textView,
                    range: returnContext.replacementRange,
                    replacement: replacement,
                    selectedRange: NSRange(location: returnContext.replacementRange.location + replacement.count, length: 0),
                    shouldPreserveViewport: false
                )
                return false
            }

            if parent.autoCloseBracketsEnabled, text.count == 1 {
                let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"]
                if let closing = pairs[text] {
                    let insertion = text + closing
                    setPendingTextMutation(range: range, replacement: insertion)
                    performProgrammaticReplacement(
                        in: textView,
                        range: range,
                        replacement: insertion,
                        selectedRange: NSRange(location: range.location + 1, length: 0)
                    )
                    return false
                }
            }

            setPendingTextMutation(range: range, replacement: text)
            return true
        }

        private func performProgrammaticReplacement(
            in textView: UITextView,
            range: NSRange,
            replacement: String,
            selectedRange: NSRange,
            shouldPreserveViewport: Bool = true
        ) {
            let priorOffset = textView.contentOffset
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            textView.selectedRange = selectedRange
            if shouldPreserveViewport,
               UIDevice.current.userInterfaceIdiom == .phone,
               textView.isFirstResponder,
               !textView.isTracking,
               !textView.isDragging,
               !textView.isDecelerating {
                let inset = textView.adjustedContentInset
                let minY = -inset.top
                let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)
                let clampedY = min(max(priorOffset.y, minY), maxY)
                textView.setContentOffset(CGPoint(x: priorOffset.x, y: clampedY), animated: false)
            }
            textViewDidChange(textView)
        }

        private func normalizedIndentation(_ indent: String) -> String {
            let width = max(1, parent.indentWidth)
            switch parent.indentStyle {
            case "tabs":
                let spacesCount = indent.filter { $0 == " " }.count
                let tabsCount = indent.filter { $0 == "\t" }.count
                let totalSpaces = spacesCount + (tabsCount * width)
                let tabs = String(repeating: "\t", count: totalSpaces / width)
                let leftover = String(repeating: " ", count: totalSpaces % width)
                return tabs + leftover
            default:
                let tabsCount = indent.filter { $0 == "\t" }.count
                let spacesCount = indent.filter { $0 == " " }.count
                let totalSpaces = spacesCount + (tabsCount * width)
                return String(repeating: " ", count: totalSpaces)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncLineNumberScroll()
            guard let textView else { return }
            postMinimapViewportIfNeeded(textView: textView, scrollView: scrollView)
            if textView.rendersInvisibleCharacters || textView.rendersIndentationGuides {
                textView.invisibleCharactersOverlayView?.requestRedraw()
            }
            if textView.highlightsCurrentLine {
                textView.currentLineHighlightOverlayView?.setNeedsDisplay()
            }
            if !textView.matchingBracketHighlightRanges.isEmpty {
                textView.setNeedsDisplay()
            }
            let textLength = (textView.text as NSString?)?.length ?? 0
            if textLength >= 100_000 && supportsResponsiveLargeFileHighlight(language: parent.language, textLength: textLength) {
                guard !isPhoneActivelyEditing else { return }
                scheduleHighlightIfNeeded(currentText: textView.text)
            }
        }

        func syncLineNumberScroll() {
            guard shouldRenderLineNumbers(), let textView else { return }
            let offsetY = textView.contentOffset.y
            if abs(lastLineNumberContentOffsetY - offsetY) <= 0.5 {
                return
            }
            lastLineNumberContentOffsetY = offsetY
            container?.lineNumberView.setNeedsDisplay()
        }

        func postMinimapViewportIfNeeded(
            textView: UITextView,
            scrollView: UIScrollView,
            force: Bool = false
        ) {
            guard let documentID = parent.documentID else { return }
            let contentHeight = max(scrollView.contentSize.height, textView.bounds.height)
            let visibleHeight = max(1, scrollView.bounds.height)
            guard contentHeight > visibleHeight else {
                if force || lastMinimapViewportTop != 0 || lastMinimapViewportHeight != 1 {
                    lastMinimapViewportTop = 0
                    lastMinimapViewportHeight = 1
                    NotificationCenter.default.post(
                        name: .editorViewportDidChange,
                        object: nil,
                        userInfo: [
                            EditorCommandUserInfo.documentID: documentID.uuidString,
                            EditorCommandUserInfo.viewportTopFraction: 0.0,
                            EditorCommandUserInfo.viewportHeightFraction: 1.0
                        ]
                    )
                }
                return
            }
            let viewport = codeMinimapViewport(
                visibleY: Double(max(0, scrollView.contentOffset.y)),
                visibleHeight: Double(visibleHeight),
                contentHeight: Double(contentHeight)
            )
            guard force ||
                    abs(viewport.topFraction - lastMinimapViewportTop) > 0.003 ||
                    abs(viewport.heightFraction - lastMinimapViewportHeight) > 0.003 else { return }
            lastMinimapViewportTop = viewport.topFraction
            lastMinimapViewportHeight = viewport.heightFraction
            NotificationCenter.default.post(
                name: .editorViewportDidChange,
                object: nil,
                userInfo: [
                    EditorCommandUserInfo.documentID: documentID.uuidString,
                    EditorCommandUserInfo.viewportTopFraction: viewport.topFraction,
                    EditorCommandUserInfo.viewportHeightFraction: viewport.heightFraction
                ]
            )
        }

        func scheduleDeferredMinimapViewportPost(for textView: UITextView) {
            guard !pendingDeferredMinimapViewportPost else { return }
            let expectedDocumentID = parent.documentID
            pendingDeferredMinimapViewportPost = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.pendingDeferredMinimapViewportPost = false
                guard self.parent.documentID == expectedDocumentID,
                      let textView else { return }
                textView.layoutIfNeeded()
                self.postMinimapViewportIfNeeded(textView: textView, scrollView: textView, force: true)
            }
        }
    }
}

#endif
