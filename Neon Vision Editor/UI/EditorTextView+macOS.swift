#if os(macOS)
import Dispatch
import SwiftUI
import Foundation
import OSLog
import AppKit

// MARK: - macOS SwiftUI Bridge

// NSViewRepresentable wrapper around NSTextView to integrate with SwiftUI.
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    let documentID: UUID?
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

    // MARK: - Text View Configuration

    // Toggle soft-wrapping by adjusting text container sizing and scroller visibility.
    private func applyWrapMode(isWrapped: Bool, textView: NSTextView, scrollView: NSScrollView, preserveOffset: Bool = true) {
        let priorOrigin = scrollView.contentView.bounds.origin
        if isWrapped {
            // Wrap: track the text view width, no horizontal scrolling
            textView.isHorizontallyResizable = false
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.heightTracksTextView = false
            scrollView.hasHorizontalScroller = false
            // Ensure the container width matches the visible content width right now
            let contentWidth = scrollView.contentSize.width
            let width = contentWidth > 0 ? contentWidth : scrollView.frame.size.width
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            // No wrap: allow horizontal expansion and horizontal scrolling
            textView.isHorizontallyResizable = true
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.heightTracksTextView = false
            scrollView.hasHorizontalScroller = true
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        // Keep wrap-mode flips lightweight; avoid forcing a full invalidation pass.
        let textLength = (textView.string as NSString).length
        if textLength <= 300_000, let container = textView.textContainer, let lm = textView.layoutManager {
            lm.ensureLayout(for: container)
        }
        guard preserveOffset else { return }
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - scrollView.contentSize.width)
        let maxY = max(0, documentSize.height - scrollView.contentSize.height)
        let restored = NSPoint(
            x: isWrapped ? 0 : min(max(0, priorOrigin.x), maxX),
            y: min(max(0, priorOrigin.y), maxY)
        )
        scrollView.contentView.scroll(to: restored)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func resolvedFont() -> NSFont {
        if useSystemFont {
            return NSFont.systemFont(ofSize: fontSize)
        }
        if let named = NSFont(name: fontName, size: fontSize) {
            return named
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private func currentLineHighlightColor(for colorScheme: ColorScheme) -> NSColor {
        NSColor.systemBlue.withAlphaComponent(colorScheme == .dark ? 0.30 : 0.22)
    }

    nonisolated static func shouldAllowNonContiguousLayout(
        wrapMode: Bool,
        boldKeywords: Bool,
        highlightCurrentLine: Bool,
        highlightMatchingBrackets: Bool,
        isLargeFileMode: Bool
    ) -> Bool {
        let usesSelectionOverlay = highlightCurrentLine || (highlightMatchingBrackets && !isLargeFileMode)
        return isLargeFileMode && !wrapMode && !(boldKeywords && usesSelectionOverlay)
    }

    private func shouldAllowNonContiguousLayout(wrapMode: Bool) -> Bool {
        let theme = currentEditorTheme(colorScheme: colorScheme)
        return Self.shouldAllowNonContiguousLayout(
            wrapMode: wrapMode,
            boldKeywords: theme.boldKeywords,
            highlightCurrentLine: highlightCurrentLine,
            highlightMatchingBrackets: highlightMatchingBrackets,
            isLargeFileMode: isLargeFileMode
        )
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = max(0.9, lineHeightMultiple)
        return style
    }

    private func effectiveBaseTextColor() -> NSColor {
        let theme = currentEditorTheme(colorScheme: colorScheme)
        return NSColor(theme.text)
    }

    private func applyInvisibleCharacterPreference(_ textView: NSTextView) {
        // Keep layout manager and defaults in sync with the user-facing setting.
        let shouldShow = showInvisibleCharacters
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "NSShowAllInvisibles") != shouldShow {
            defaults.set(shouldShow, forKey: "NSShowAllInvisibles")
        }
        if defaults.bool(forKey: "NSShowControlCharacters") != shouldShow {
            defaults.set(shouldShow, forKey: "NSShowControlCharacters")
        }
        if defaults.bool(forKey: "SettingsShowInvisibleCharacters") != shouldShow {
            defaults.set(shouldShow, forKey: "SettingsShowInvisibleCharacters")
        }
        let layoutChanged =
            textView.layoutManager?.showsInvisibleCharacters != shouldShow ||
            textView.layoutManager?.showsControlCharacters != shouldShow
        guard layoutChanged else { return }

        textView.layoutManager?.showsInvisibleCharacters = shouldShow
        textView.layoutManager?.showsControlCharacters = shouldShow
        let visibleRange = textView.visibleCharacterRangeForDisplayInvalidation()
        textView.layoutManager?.invalidateDisplay(forCharacterRange: visibleRange)
        textView.needsDisplay = true
    }

    private func sanitizedForExternalSet(_ input: String) -> String {
        let nsLength = (input as NSString).length
        if nsLength > 300_000 {
            if !input.contains("\0") && !input.contains("\r") {
                return input
            }
            return input
                .replacingOccurrences(of: "\0", with: "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }
        return AcceptingTextView.sanitizePlainText(input)
    }

    // MARK: - AppKit View Lifecycle

    func makeNSView(context: Context) -> NSScrollView {
        // Build scroll view and text view
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = !showsCodeMinimap
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = AcceptingTextView(frame: .zero)
        textView.identifier = NSUserInterfaceItemIdentifier("NeonEditorTextView")
        // Configure editing behavior and visuals
        textView.isEditable = !isReadOnly
        textView.isRichText = false
        textView.usesFindBar = !isLargeFileMode
        textView.usesInspectorBar = false
        textView.usesFontPanel = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = resolvedFont()

        // Apply visibility preference from Settings (off by default).
        applyInvisibleCharacterPreference(textView)
        textView.textStorage?.beginEditing()
        if let storage = textView.textStorage {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.removeAttribute(.underlineStyle, range: fullRange)
            storage.removeAttribute(.strikethroughStyle, range: fullRange)
        }
        textView.textStorage?.endEditing()

        let theme = currentEditorTheme(colorScheme: colorScheme)
        if translucentBackgroundEnabled {
            textView.backgroundColor = .clear
            textView.drawsBackground = false
        } else {
            textView.backgroundColor = NSColor(theme.background)
            textView.drawsBackground = true
        }

        // Use NSRulerView line numbering (v0.4.4-beta behavior).
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isSelectable = true
        textView.allowsUndo = !isLargeFileMode
        let baseTextColor = effectiveBaseTextColor()
        textView.textColor = baseTextColor
        textView.insertionPointColor = NSColor(theme.cursor)
        textView.selectedTextAttributes = [
            .backgroundColor: resolvedSelectionColor(for: theme)
        ]
        textView.usesInspectorBar = false
        textView.usesFontPanel = false
        let initialWrapMode = isLineWrapEnabled && !isLargeFileMode
        textView.layoutManager?.allowsNonContiguousLayout = shouldAllowNonContiguousLayout(wrapMode: initialWrapMode)
        // Keep a fixed left gutter gap so content never visually collides with line numbers.
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.lineFragmentPadding = 4

        // Keep horizontal rulers disabled; vertical ruler is dedicated to line numbers.
        let shouldShowInitialLineNumbers = showLineNumbers
        textView.usesRuler = shouldShowInitialLineNumbers
        textView.isRulerVisible = shouldShowInitialLineNumbers
        scrollView.hasHorizontalRuler = false
        scrollView.horizontalRulerView = nil
        scrollView.hasVerticalRuler = shouldShowInitialLineNumbers
        scrollView.rulersVisible = shouldShowInitialLineNumbers
        scrollView.verticalRulerView = shouldShowInitialLineNumbers ? LineNumberRulerView(textView: textView) : nil

        applyInvisibleCharacterPreference(textView)
        textView.autoIndentEnabled = autoIndentEnabled
        textView.autoCloseBracketsEnabled = autoCloseBracketsEnabled
        textView.emmetLanguage = language
        textView.indentStyle = indentStyle
        textView.indentWidth = indentWidth
        textView.highlightCurrentLine = highlightCurrentLine
        textView.currentLineHighlightColor = currentLineHighlightColor(for: colorScheme)
        textView.highlightMatchingBrackets = highlightMatchingBrackets
        textView.showIndentationGuides = showIndentationGuides && !initialWrapMode

        // Disable smart substitutions/detections that can interfere with selection when recoloring
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .none
        }

        textView.registerForDraggedTypes([.fileURL, .URL])

        // Embed the text view in the scroll view
        scrollView.documentView = textView

        // Configure the text view delegate
        textView.delegate = context.coordinator

        // Apply wrapping and seed initial content
        applyWrapMode(isWrapped: initialWrapMode, textView: textView, scrollView: scrollView, preserveOffset: false)
        context.coordinator.lastAppliedWrapMode = initialWrapMode

        // Seed initial text (strip control pictures when invisibles are hidden)
        let seeded = sanitizedForExternalSet(text)
        let seededLength = (seeded as NSString).length
        if shouldUseChunkedLargeFileInstall(isLargeFileMode: isLargeFileMode, textLength: seededLength) {
            textView.string = ""
            DispatchQueue.main.async {
                _ = context.coordinator.installLargeTextIfNeeded(
                    on: textView,
                    target: seeded,
                    preserveViewport: false
                )
            }
        } else {
            textView.string = seeded
            textView.undoManager?.removeAllActions()
            if seeded != text {
                // Keep binding clean of control-picture glyphs.
                DispatchQueue.main.async {
                    if self.text != seeded {
                        self.text = seeded
                    }
                }
            }
            context.coordinator.scheduleHighlightIfNeeded(currentText: text, immediate: true)
        }

        // Keep container width in sync when the scroll view resizes (coalesced and guarded in coordinator).
        context.coordinator.installWrapResizeObserver(for: textView, scrollView: scrollView)

        context.coordinator.textView = textView
        return scrollView
    }

    // Keep NSTextView in sync with SwiftUI state and schedule highlighting when needed.
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            context.coordinator.parent = self
            var needsLayoutRefresh = false
            var didChangeRulerConfiguration = false
            nsView.autohidesScrollers = true
            nsView.scrollerStyle = .overlay
            nsView.hasVerticalScroller = !showsCodeMinimap
            textView.isEditable = !isReadOnly
            textView.isSelectable = true
            let acceptingView = textView as? AcceptingTextView
            let isDropApplyInFlight = acceptingView?.isApplyingDroppedContent ?? false
            if let acceptingView {
                context.coordinator.installContentLayoutRefreshHandler(on: acceptingView, scrollView: nsView)
            }
            context.coordinator.installWrapResizeObserver(for: textView, scrollView: nsView)
            let didSwitchDocument = context.coordinator.lastDocumentID != documentID
            let didFinishTabLoad = (context.coordinator.lastTabLoadingContent == true) && !isTabLoadingContent
            let didReceiveExternalEdit = context.coordinator.lastExternalEditRevision != externalEditRevision
            let didTransitionDocumentState = didSwitchDocument || didFinishTabLoad || didReceiveExternalEdit
            let shouldPublishMinimapViewport = didTransitionDocumentState ||
                (showsCodeMinimap && context.coordinator.lastShowsCodeMinimap != true)
            let isInteractionSuppressed = context.coordinator.isInInteractionSuppressionWindow()
            if didSwitchDocument {
                context.coordinator.lastDocumentID = documentID
                context.coordinator.cancelPendingBindingSync()
                context.coordinator.clearPendingTextMutation()
                context.coordinator.invalidateHighlightCache()
            }
            context.coordinator.lastTabLoadingContent = isTabLoadingContent
            context.coordinator.lastExternalEditRevision = externalEditRevision
            context.coordinator.lastShowsCodeMinimap = showsCodeMinimap

            // Sanitize and avoid publishing binding during update
            let target = sanitizedForExternalSet(text)
            let targetLength = (target as NSString).length
            let shouldSkipLargeFileResync =
                isLargeFileMode &&
                targetLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length &&
                !didSwitchDocument &&
                !didFinishTabLoad &&
                !didReceiveExternalEdit &&
                !context.coordinator.hasPendingBindingSync
            if textView.string != target {
                if !shouldSkipLargeFileResync {
                    let hasFocus = (textView.window?.firstResponder as? NSTextView) === textView
                    let shouldPreferEditorBuffer =
                        hasFocus &&
                        !isTabLoadingContent &&
                        !didSwitchDocument &&
                        !didFinishTabLoad &&
                        !didReceiveExternalEdit
                    let shouldDeferToEditorBuffer =
                        shouldPreferEditorBuffer ||
                        (!didTransitionDocumentState && isInteractionSuppressed)
                    if shouldDeferToEditorBuffer {
                        context.coordinator.syncBindingTextImmediately(textView.string)
                    } else {
                        context.coordinator.cancelPendingBindingSync()
                        let didInstallLargeText = context.coordinator.installLargeTextIfNeeded(
                            on: textView,
                            target: target,
                            preserveViewport: !didTransitionDocumentState,
                            preserveHorizontalOffset: !didTransitionDocumentState
                        )
                        if !didInstallLargeText {
                            replaceTextPreservingSelectionAndFocus(
                                textView,
                                with: target,
                                preserveViewport: !didTransitionDocumentState,
                                preserveHorizontalOffset: !didTransitionDocumentState
                            )
                            needsLayoutRefresh = true
                        }
                        if didTransitionDocumentState {
                            textView.undoManager?.removeAllActions()
                        }
                        context.coordinator.invalidateHighlightCache()
                        DispatchQueue.main.async {
                            if self.text != target {
                                self.text = target
                            }
                        }
                    }
                }
            }

            let targetFont = resolvedFont()
            let currentFont = textView.font
            let fontChanged = currentFont?.fontName != targetFont.fontName ||
                abs((currentFont?.pointSize ?? -1) - targetFont.pointSize) > 0.001
            if fontChanged {
                textView.font = targetFont
                needsLayoutRefresh = true
                context.coordinator.invalidateHighlightCache()
            }
            if textView.textContainerInset.width != 6 || textView.textContainerInset.height != 8 {
                textView.textContainerInset = NSSize(width: 6, height: 8)
                needsLayoutRefresh = true
            }
            if textView.textContainer?.lineFragmentPadding != 4 {
                textView.textContainer?.lineFragmentPadding = 4
                needsLayoutRefresh = true
            }
            let style = paragraphStyle()
            let currentLineHeight = textView.defaultParagraphStyle?.lineHeightMultiple ?? 1.0
            if abs(currentLineHeight - style.lineHeightMultiple) > 0.0001 {
                textView.defaultParagraphStyle = style
                textView.typingAttributes[.paragraphStyle] = style
                needsLayoutRefresh = true
                let nsLen = (textView.string as NSString).length
                if nsLen <= 200_000, let storage = textView.textStorage {
                    let undoWasEnabled = textView.undoManager?.isUndoRegistrationEnabled ?? false
                    if undoWasEnabled {
                        textView.undoManager?.disableUndoRegistration()
                    }
                    storage.beginEditing()
                    storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: nsLen))
                    storage.endEditing()
                    restoreUndoRegistrationIfNeeded(textView.undoManager, wasEnabled: undoWasEnabled)
                }
            }

            // Defensive sanitize pass only for smaller documents to avoid heavy full-buffer scans.
            let currentLength = (textView.string as NSString).length
            if currentLength <= 300_000 {
                let sanitized = AcceptingTextView.sanitizePlainText(textView.string)
                if sanitized != textView.string, !isInteractionSuppressed {
                    replaceTextPreservingSelectionAndFocus(
                        textView,
                        with: sanitized,
                        preserveViewport: !didTransitionDocumentState,
                        preserveHorizontalOffset: !didTransitionDocumentState
                    )
                    needsLayoutRefresh = true
                    context.coordinator.invalidateHighlightCache()
                    DispatchQueue.main.async {
                        if self.text != sanitized {
                            self.text = sanitized
                        }
                    }
                }
            }

            let theme = currentEditorTheme(colorScheme: colorScheme)

            let effectiveHighlightCurrentLine = highlightCurrentLine
            let effectiveWrap = (isLineWrapEnabled && !isLargeFileMode)
            let allowsNonContiguousLayout = shouldAllowNonContiguousLayout(wrapMode: effectiveWrap)
            if textView.layoutManager?.allowsNonContiguousLayout != allowsNonContiguousLayout {
                textView.layoutManager?.allowsNonContiguousLayout = allowsNonContiguousLayout
                needsLayoutRefresh = true
            }
            if #available(macOS 15.0, *) {
                if textView.writingToolsBehavior != .none {
                    textView.writingToolsBehavior = .none
                }
            }

            // Background color adjustments for translucency
            if translucentBackgroundEnabled {
                nsView.drawsBackground = false
                textView.backgroundColor = .clear
                textView.drawsBackground = false
            } else {
                nsView.drawsBackground = false
                textView.backgroundColor = NSColor(theme.background)
                textView.drawsBackground = true
            }
            let baseTextColor = effectiveBaseTextColor()
            let caretColor = NSColor(theme.cursor)
            if textView.insertionPointColor != caretColor {
                textView.insertionPointColor = caretColor
            }
            textView.typingAttributes[.foregroundColor] = baseTextColor
            textView.selectedTextAttributes = [
                .backgroundColor: resolvedSelectionColor(for: theme)
            ]
            let showLineNumbersByDefault = showLineNumbers
            if textView.usesRuler != showLineNumbersByDefault {
                textView.usesRuler = showLineNumbersByDefault
                didChangeRulerConfiguration = true
            }
            if textView.isRulerVisible != showLineNumbersByDefault {
                textView.isRulerVisible = showLineNumbersByDefault
                didChangeRulerConfiguration = true
            }
            if nsView.hasHorizontalRuler {
                nsView.hasHorizontalRuler = false
                didChangeRulerConfiguration = true
            }
            if nsView.horizontalRulerView != nil {
                nsView.horizontalRulerView = nil
                didChangeRulerConfiguration = true
            }
            if nsView.hasVerticalRuler != showLineNumbersByDefault {
                nsView.hasVerticalRuler = showLineNumbersByDefault
                didChangeRulerConfiguration = true
            }
            if nsView.rulersVisible != showLineNumbersByDefault {
                nsView.rulersVisible = showLineNumbersByDefault
                didChangeRulerConfiguration = true
            }
            if showLineNumbersByDefault {
                if !(nsView.verticalRulerView is LineNumberRulerView) {
                    nsView.verticalRulerView = LineNumberRulerView(textView: textView)
                    didChangeRulerConfiguration = true
                }
            } else {
                if nsView.verticalRulerView != nil {
                    nsView.verticalRulerView = nil
                    didChangeRulerConfiguration = true
                }
            }

            // Re-apply invisible-character visibility preference after style updates.
            applyInvisibleCharacterPreference(textView)

            // Keep the text container width in sync & relayout
            acceptingView?.autoIndentEnabled = autoIndentEnabled
            acceptingView?.autoCloseBracketsEnabled = autoCloseBracketsEnabled
            acceptingView?.emmetLanguage = language
            acceptingView?.indentStyle = indentStyle
            acceptingView?.indentWidth = indentWidth
            acceptingView?.highlightCurrentLine = effectiveHighlightCurrentLine
            acceptingView?.currentLineHighlightColor = currentLineHighlightColor(for: colorScheme)
            acceptingView?.highlightMatchingBrackets = highlightMatchingBrackets && !isLargeFileMode
            acceptingView?.showIndentationGuides = showIndentationGuides && !effectiveWrap
            if context.coordinator.lastAppliedWrapMode != effectiveWrap {
                applyWrapMode(isWrapped: effectiveWrap, textView: textView, scrollView: nsView)
                context.coordinator.lastAppliedWrapMode = effectiveWrap
                needsLayoutRefresh = true
            }

            if showLineNumbersByDefault && didTransitionDocumentState {
                if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
                    ruler.forceRulerLayoutRefresh()
                } else {
                    context.coordinator.scheduleDeferredRulerTile(for: nsView)
                }
            } else if didChangeRulerConfiguration {
                context.coordinator.scheduleDeferredRulerTile(for: nsView)
            }
            if needsLayoutRefresh, let container = textView.textContainer {
                context.coordinator.scheduleDeferredEnsureLayout(for: textView, container: container)
            }
            if shouldPublishMinimapViewport {
                if let documentID {
                    EditorPerformanceMonitor.shared.beginMinimapViewportUpdate(tabID: documentID)
                }
                context.coordinator.scheduleDeferredMinimapViewportPost(for: textView, scrollView: nsView)
            }
            if didTransitionDocumentState {
                context.coordinator.normalizeHorizontalScrollOffset(for: nsView)
                acceptingView?.refreshDisplayAfterContentInstall()
            }

            if !isDropApplyInFlight {
                if didTransitionDocumentState {
                    context.coordinator.scheduleHighlightIfNeeded(currentText: textView.string, immediate: true)
                } else {
                    let shouldSchedule = context.coordinator.shouldScheduleHighlightFromUpdate(
                        currentText: textView.string,
                        language: language,
                        colorScheme: colorScheme,
                        lineHeightValue: lineHeightMultiple,
                        token: highlightRefreshToken,
                        translucencyEnabled: translucentBackgroundEnabled
                    )
                    if shouldSchedule {
                        context.coordinator.scheduleHighlightIfNeeded()
                    }
                }
            }
        }
    }

    private func resolvedSelectionColor(for theme: EditorTheme) -> NSColor {
        let base = NSColor(theme.selection)
        return base.blended(withFraction: colorScheme == .dark ? 0.18 : 0.12, of: .white) ?? base
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }


    // Coordinator: NSTextViewDelegate that bridges NSText changes to SwiftUI and manages highlighting.
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        weak var textView: NSTextView?

        // Background queue + debouncer for regex-based highlighting
        private let highlightQueue = DispatchQueue(label: "NeonVision.SyntaxHighlight", qos: .userInitiated)
        // Snapshots of last highlighted state to avoid redundant work
        private var pendingHighlight: DispatchWorkItem?
        private var lastHighlightedText: String = ""
        private var lastLanguage: String?
        private var lastColorScheme: ColorScheme?
        var lastLineHeight: CGFloat?
        private var lastHighlightToken: Int = 0
        private var lastSelectionLocation: Int = -1
        private var lastHighlightViewportAnchor: Int = -1
        private var lastTranslucencyEnabled: Bool?
        private var isApplyingHighlight = false
        private var highlightGeneration: Int = 0
        private var pendingEditedRange: NSRange?
        private var pendingBindingSync: DispatchWorkItem?
        private var pendingTextMutation: (range: NSRange, replacement: String)?
        private var pendingDeferredRulerTile = false
        private var pendingDeferredLayoutEnsure = false
        private var pendingDeferredMinimapViewportPost = false
        private var wrapResizeObserver: TextViewObserverToken?
        private weak var observedWrapContentView: NSClipView?
        private var lastObservedWrapContentWidth: CGFloat = -1
        private var lastMinimapViewportTop: Double = -1
        private var lastMinimapViewportHeight: Double = -1
        private var isInstallingLargeText = false
        private var largeTextInstallGeneration: Int = 0
        private var interactionSuppressionDeadline: TimeInterval = 0
        var lastAppliedWrapMode: Bool?
        var lastDocumentID: UUID?
        var lastTabLoadingContent: Bool?
        var lastExternalEditRevision: Int?
        var lastShowsCodeMinimap: Bool?
        var hasPendingBindingSync: Bool { pendingBindingSync != nil }

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(moveToLine(_:)), name: .moveCursorToLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(moveToRange(_:)), name: .moveCursorToRange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(scrollViewportToFraction(_:)), name: .scrollEditorViewportToFraction, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handlePointerInteraction(_:)), name: .editorPointerInteraction, object: nil)
        }

        deinit {
            if let wrapResizeObserver {
                NotificationCenter.default.removeObserver(wrapResizeObserver.raw)
            }
            NotificationCenter.default.removeObserver(self)
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
            largeTextInstallGeneration &+= 1
            isInstallingLargeText = false
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
                if self.textView?.string == text {
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

        fileprivate func installLargeTextIfNeeded(
            on textView: NSTextView,
            target: String,
            preserveViewport: Bool,
            preserveHorizontalOffset: Bool = true
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

            let previousSelection = textView.selectedRange()
            let hadFocus = (textView.window?.firstResponder as? NSTextView) === textView
            let priorOrigin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
            let installDocumentID = parent.documentID
            let undoWasEnabled = textView.undoManager?.isUndoRegistrationEnabled ?? false
            if undoWasEnabled {
                textView.undoManager?.disableUndoRegistration()
            }
            func finishUndoSuppression() {
                restoreUndoRegistrationIfNeeded(textView.undoManager, wasEnabled: undoWasEnabled)
                textView.undoManager?.removeAllActions()
            }
            textView.isEditable = false
            textView.string = ""

            func applyChunk(from location: Int) {
                guard generation == self.largeTextInstallGeneration,
                      self.textView === textView,
                      self.parent.documentID == installDocumentID else {
                    if generation == self.largeTextInstallGeneration {
                        self.isInstallingLargeText = false
                    }
                    finishUndoSuppression()
                    return
                }
                let remaining = targetLength - location
                guard remaining > 0 else {
                    self.isInstallingLargeText = false
                    textView.isEditable = !parent.isReadOnly
                    let safeLocation = min(max(0, previousSelection.location), targetLength)
                    let safeLength = min(max(0, previousSelection.length), max(0, targetLength - safeLocation))
                    textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
                    if let clipView = textView.enclosingScrollView?.contentView {
                        let targetOrigin: CGPoint
                        if preserveViewport {
                            targetOrigin = CGPoint(
                                x: preserveHorizontalOffset ? priorOrigin.x : 0,
                                y: priorOrigin.y
                            )
                        } else {
                            targetOrigin = .zero
                        }
                        clipView.scroll(to: targetOrigin)
                        textView.enclosingScrollView?.reflectScrolledClipView(clipView)
                    }
                    if hadFocus {
                        textView.window?.makeFirstResponder(textView)
                    }
                    finishUndoSuppression()
                    self.scheduleHighlightIfNeeded(currentText: target, immediate: true)
                    return
                }

                let chunkLength = min(LargeFileInstallRuntime.chunkUTF16, remaining)
                let chunk = (target as NSString).substring(with: NSRange(location: location, length: chunkLength))
                let storage = textView.textStorage
                storage?.beginEditing()
                storage?.append(NSAttributedString(string: chunk))
                storage?.endEditing()
                DispatchQueue.main.async {
                    applyChunk(from: location + chunkLength)
                }
            }

            applyChunk(from: 0)
            return true
        }

        func normalizeHorizontalScrollOffset(for scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            let origin = clipView.bounds.origin
            guard abs(origin.x) > 0.5 else { return }
            clipView.scroll(to: CGPoint(x: 0, y: origin.y))
            scrollView.reflectScrolledClipView(clipView)
        }

        private func debugViewportTrace(_ source: String, textView: NSTextView? = nil) {
#if DEBUG
            let tv = textView ?? self.textView
            let sel = tv?.selectedRange().location ?? -1
            let origin = tv?.enclosingScrollView?.contentView.bounds.origin ?? .zero
            print("[ViewportTrace] \(source) wrap=\(parent.isLineWrapEnabled) sel=\(sel) origin=(\(Int(origin.x)),\(Int(origin.y)))")
#endif
        }

        private func noteRecentInteraction(source: String, duration: TimeInterval = 0.24) {
            let now = ProcessInfo.processInfo.systemUptime
            interactionSuppressionDeadline = max(interactionSuppressionDeadline, now + duration)
            pendingHighlight?.cancel()
            pendingHighlight = nil
            highlightGeneration &+= 1
            debugViewportTrace("interaction:\(source)")
        }

        func isInInteractionSuppressionWindow() -> Bool {
            ProcessInfo.processInfo.systemUptime < interactionSuppressionDeadline
        }

        func shouldScheduleHighlightFromUpdate(
            currentText: String,
            language: String,
            colorScheme: ColorScheme,
            lineHeightValue: CGFloat,
            token: Int,
            translucencyEnabled: Bool
        ) -> Bool {
            let textLength = (currentText as NSString).length
            let viewportAnchor = currentViewportAnchor(
                textLength: textLength,
                language: language
            )
            if isInInteractionSuppressionWindow() {
                return false
            }
            if parent.isLargeFileMode && !supportsResponsiveLargeFileHighlight(language: language, textLength: textLength) {
                return false
            }
            return !(currentText == lastHighlightedText &&
                     language == lastLanguage &&
                     colorScheme == lastColorScheme &&
                     abs((lastLineHeight ?? lineHeightValue) - lineHeightValue) <= 0.0001 &&
                     token == lastHighlightToken &&
                     viewportAnchor == lastHighlightViewportAnchor &&
                     translucencyEnabled == lastTranslucencyEnabled)
        }

        private func currentViewportAnchor(textLength: Int, language: String) -> Int {
            guard usesResponsiveViewportHighlighting(textLength: textLength, language: language),
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return -1 }
            let glyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.length > 0 else { return -1 }
            return charRange.location
        }

        private func usesResponsiveViewportHighlighting(textLength: Int, language: String) -> Bool {
            parent.isLargeFileMode &&
                textLength >= 100_000 &&
                supportsResponsiveLargeFileHighlight(language: language, textLength: textLength)
        }

        func installWrapResizeObserver(for textView: NSTextView, scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            guard observedWrapContentView !== scrollView.contentView else { return }
            if let wrapResizeObserver {
                NotificationCenter.default.removeObserver(wrapResizeObserver.raw)
            }
            observedWrapContentView = scrollView.contentView
            lastObservedWrapContentWidth = -1
            postMinimapViewportIfNeeded(textView: textView, scrollView: scrollView, force: true)
            let tokenRaw = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak textView, weak scrollView] _ in
                Task { @MainActor [weak self, weak textView, weak scrollView] in
                    guard let self, let tv = textView, let sv = scrollView else { return }
                    if tv.textContainer?.widthTracksTextView == true {
                        let targetWidth = sv.contentSize.width
                        if targetWidth > 0, abs(self.lastObservedWrapContentWidth - targetWidth) > 0.5 {
                            self.lastObservedWrapContentWidth = targetWidth
                            let currentWidth = tv.textContainer?.containerSize.width ?? 0
                            if abs(currentWidth - targetWidth) > 0.5 {
                                tv.textContainer?.containerSize.width = targetWidth
                                self.debugViewportTrace("wrapWidthChanged", textView: tv)
                            }
                        }
                    }
                    self.postMinimapViewportIfNeeded(textView: tv, scrollView: sv)
                    let textLength = (tv.string as NSString).length
                    if self.usesResponsiveViewportHighlighting(textLength: textLength, language: self.parent.language) {
                        self.scheduleHighlightIfNeeded(currentText: tv.string)
                    }
                }
            }
            wrapResizeObserver = TextViewObserverToken(raw: tokenRaw)
        }

        func postMinimapViewportIfNeeded(
            textView: NSTextView,
            scrollView: NSScrollView,
            force: Bool = false
        ) {
            guard let documentID = parent.documentID else { return }
            // The clip view owns the actual scroll viewport. NSTextView.visibleRect can
            // still describe the full document while TextKit finishes its first layout.
            let visibleRect = scrollView.contentView.bounds
            let laidOutTextHeight: CGFloat = {
                guard let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else {
                    return 0
                }
                let usedRect = layoutManager.usedRect(for: textContainer)
                return ceil(usedRect.maxY + textView.textContainerInset.height)
            }()
            let visibleHeight = max(1, visibleRect.height)
            let estimatedTextHeight: CGFloat = {
                // Do not block a tab switch on full TextKit layout. Until it has caught
                // up, line count gives the marker a real, draggable viewport estimate.
                guard laidOutTextHeight <= visibleHeight else { return 0 }
                let lineCount = textView.string.utf8.reduce(1) { $0 + ($1 == 10 ? 1 : 0) }
                let lineHeight = max(1, (textView.font?.pointSize ?? 13) * 1.35)
                return CGFloat(lineCount) * lineHeight + textView.textContainerInset.height
            }()
            let contentHeight = max(
                laidOutTextHeight,
                estimatedTextHeight,
                visibleHeight
            )
            let viewport = codeMinimapViewport(
                visibleY: Double(max(0, visibleRect.minY)),
                visibleHeight: Double(visibleHeight),
                contentHeight: Double(contentHeight)
            )
            guard viewport.heightFraction < 1 else {
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

        @objc private func handlePointerInteraction(_ notification: Notification) {
            guard let interactedTextView = notification.object as? NSTextView else { return }
            guard let activeTextView = textView, interactedTextView === activeTextView else { return }
            noteRecentInteraction(source: "mouseDown")
        }

        func scheduleDeferredRulerTile(for scrollView: NSScrollView) {
            guard !pendingDeferredRulerTile else { return }
            pendingDeferredRulerTile = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self else { return }
                self.pendingDeferredRulerTile = false
                scrollView?.tile()
            }
        }

        func scheduleDeferredEnsureLayout(for textView: NSTextView, container _: NSTextContainer) {
            guard !pendingDeferredLayoutEnsure else { return }
            pendingDeferredLayoutEnsure = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.pendingDeferredLayoutEnsure = false
                guard let textView else { return }
                if let container = textView.textContainer {
                    textView.layoutManager?.ensureLayout(for: container)
                }
            }
        }

        func scheduleDeferredMinimapViewportPost(for textView: NSTextView, scrollView: NSScrollView) {
            guard !pendingDeferredMinimapViewportPost else { return }
            let expectedDocumentID = parent.documentID
            pendingDeferredMinimapViewportPost = true
            DispatchQueue.main.async { [weak self, weak textView, weak scrollView] in
                guard let self else { return }
                self.pendingDeferredMinimapViewportPost = false
                guard self.parent.documentID == expectedDocumentID,
                      let textView,
                      let scrollView else { return }
                scrollView.layoutSubtreeIfNeeded()
                textView.layoutSubtreeIfNeeded()
                self.postMinimapViewportIfNeeded(textView: textView, scrollView: scrollView, force: true)
            }
        }

        func installContentLayoutRefreshHandler(on textView: AcceptingTextView, scrollView: NSScrollView) {
            let expectedDocumentID = parent.documentID
            textView.onContentLayoutRefresh = { [weak self, weak textView, weak scrollView] in
                guard let self,
                      self.parent.documentID == expectedDocumentID,
                      let textView,
                      let scrollView else { return }
                self.postMinimapViewportIfNeeded(textView: textView, scrollView: scrollView, force: true)
            }
        }

        func syncBindingTextImmediately(_ text: String) {
            syncBindingText(text, immediate: true)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            EditorPerformanceMonitor.shared.markFirstKeystroke()
            guard !parent.isTabLoadingContent,
                  parent.documentID != nil,
                  let replacementString else {
                pendingTextMutation = nil
                return true
            }
            pendingTextMutation = (
                range: affectedCharRange,
                replacement: AcceptingTextView.sanitizePlainText(replacementString)
            )
            return true
        }

        func scheduleHighlightIfNeeded(currentText: String? = nil, immediate: Bool = false) {
            guard textView != nil else { return }
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.scheduleHighlightIfNeeded(currentText: currentText, immediate: immediate)
                }
                return
            }

            let isModalPresented = NSApp.modalWindow != nil

            if isModalPresented {
                pendingHighlight?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.scheduleHighlightIfNeeded(currentText: currentText)
                }
                pendingHighlight = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                return
            }

            let lang = parent.language
            let scheme = parent.colorScheme
            let lineHeightValue: CGFloat = parent.lineHeightMultiple
            let token = parent.highlightRefreshToken
            let translucencyEnabled = parent.translucentBackgroundEnabled
            let selectionLocation = textView?.selectedRange().location ?? 0
            let text: String = {
                if let currentText = currentText {
                    return currentText
                }

                return textView?.string ?? ""
            }()
            let textLength = (text as NSString).length
            let viewportAnchor = currentViewportAnchor(
                textLength: textLength,
                language: lang
            )

            if !immediate && isInInteractionSuppressionWindow() {
                lastSelectionLocation = selectionLocation
                debugViewportTrace("highlightSuppressedInteraction")
                return
            }

            if parent.isLargeFileMode && !supportsResponsiveLargeFileHighlight(language: lang, textLength: textLength) {
                self.lastHighlightedText = text
                self.lastLanguage = lang
                self.lastColorScheme = scheme
                self.lastLineHeight = lineHeightValue
                self.lastHighlightToken = token
                self.lastSelectionLocation = selectionLocation
                self.lastHighlightViewportAnchor = viewportAnchor
                self.lastTranslucencyEnabled = self.parent.translucentBackgroundEnabled
                return
            }
            if textLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length &&
                !supportsResponsiveLargeFileHighlight(language: lang, textLength: textLength) {
                self.lastHighlightedText = text
                self.lastLanguage = lang
                self.lastColorScheme = scheme
                self.lastLineHeight = lineHeightValue
                self.lastHighlightToken = token
                self.lastSelectionLocation = selectionLocation
                self.lastHighlightViewportAnchor = viewportAnchor
                self.lastTranslucencyEnabled = self.parent.translucentBackgroundEnabled
                return
            }

            if text == lastHighlightedText &&
                lastLanguage == lang &&
                lastColorScheme == scheme &&
                lastLineHeight == lineHeightValue &&
                lastHighlightToken == token &&
                lastSelectionLocation == selectionLocation &&
                lastHighlightViewportAnchor == viewportAnchor &&
                lastTranslucencyEnabled == translucencyEnabled {
                return
            }
            let styleStateUnchanged = lang == lastLanguage &&
                scheme == lastColorScheme &&
                lastLineHeight == lineHeightValue &&
                lastHighlightToken == token &&
                lastTranslucencyEnabled == translucencyEnabled
            let selectionOnlyChange = text == lastHighlightedText &&
                styleStateUnchanged &&
                lastSelectionLocation != selectionLocation
            if selectionOnlyChange && (parent.isLineWrapEnabled || textLength >= EditorRuntimeLimits.cursorRehighlightMaxUTF16Length) {
                // Avoid running stale highlight work that can re-apply an outdated viewport in wrapped mode.
                pendingHighlight?.cancel()
                pendingHighlight = nil
                highlightGeneration &+= 1
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
                return expandedHighlightRange(around: edit, in: text as NSString, maxUTF16Padding: padding)
            }()
            pendingEditedRange = nil
            let shouldRunImmediate = immediate || lastHighlightedText.isEmpty || lastHighlightToken != token
            highlightGeneration &+= 1
            let generation = highlightGeneration
            rehighlight(token: token, generation: generation, immediate: shouldRunImmediate, targetRange: incrementalRange)
        }

        private func expandedHighlightRange(around range: NSRange, in text: NSString, maxUTF16Padding: Int = 6000) -> NSRange {
            let start = max(0, range.location - maxUTF16Padding)
            let end = min(text.length, NSMaxRange(range) + maxUTF16Padding)
            let startLine = text.lineRange(for: NSRange(location: start, length: 0)).location
            let endAnchor = max(startLine, min(text.length - 1, max(0, end - 1)))
            let endLine = NSMaxRange(text.lineRange(for: NSRange(location: endAnchor, length: 0)))
            return NSRange(location: startLine, length: max(0, endLine - startLine))
        }

        private func preferredHighlightRange(
            in textView: NSTextView,
            text: NSString,
            explicitRange: NSRange?,
            immediate: Bool
        ) -> NSRange {
            let fullRange = NSRange(location: 0, length: text.length)
            if let explicitRange {
                return explicitRange
            }
            // Restrict to visible range only for responsive large-file profiles.
            guard usesResponsiveViewportHighlighting(textLength: text.length, language: parent.language) else { return fullRange }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return fullRange }
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
            let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
            guard visibleCharacterRange.length > 0 else { return fullRange }
            let padding = EditorRuntimeLimits.largeFileJSONVisiblePaddingUTF16
            return expandedHighlightRange(around: visibleCharacterRange, in: text, maxUTF16Padding: padding)
        }

        func rehighlight(token: Int, generation: Int, immediate: Bool = false, targetRange: NSRange? = nil) {
            if !Thread.isMainThread {
                DispatchQueue.main.async { [weak self] in
                    self?.rehighlight(token: token, generation: generation, immediate: immediate, targetRange: targetRange)
                }
                return
            }
            guard let textView = textView else { return }
            // Snapshot current state
            let textSnapshot = textView.string
            let language = parent.language
            let scheme = parent.colorScheme
            let lineHeightValue: CGFloat = parent.lineHeightMultiple
            let selected = textView.selectedRange()
            let theme = currentEditorTheme(colorScheme: scheme)
            let nsText = textSnapshot as NSString
            let syntaxProfile = syntaxProfile(for: language, text: nsText)
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
            let patterns = getSyntaxPatterns(for: language, colors: colors, profile: syntaxProfile)
            let fullRange = NSRange(location: 0, length: nsText.length)
            let applyRange = preferredHighlightRange(
                in: textView,
                text: nsText,
                explicitRange: targetRange,
                immediate: immediate
            )
            let emphasisPatterns = syntaxEmphasisPatterns(for: language, profile: syntaxProfile)

            // Cancel any in-flight work
            pendingHighlight?.cancel()

            let work = DispatchWorkItem { @Sendable [weak self] in
                let interval = syntaxHighlightSignposter.beginInterval("rehighlight_macos")
                let backgroundText = textSnapshot as NSString
                // Compute matches off the main thread
                var coloredRanges: [(NSRange, Color)] = []
                var emphasizedRanges: [(NSRange, SyntaxFontEmphasis)] = []
                if let fastRanges = fastSyntaxColorRanges(
                    language: language,
                    profile: syntaxProfile,
                    text: backgroundText,
                    in: applyRange,
                    colors: colors
                ) {
                    coloredRanges = fastRanges
                } else {
                    for (pattern, color) in patterns {
                        guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                        let matches = regex.matches(in: textSnapshot, range: applyRange)
                        for match in matches {
                            coloredRanges.append((match.range, color))
                        }
                    }
                }

                if theme.boldKeywords {
                    for pattern in emphasisPatterns.keyword {
                        guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                        let matches = regex.matches(in: textSnapshot, range: applyRange)
                        for match in matches {
                            emphasizedRanges.append((match.range, .keyword))
                        }
                    }
                }
                if theme.italicComments {
                    for pattern in emphasisPatterns.comment {
                        guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                        let matches = regex.matches(in: textSnapshot, range: applyRange)
                        for match in matches {
                            emphasizedRanges.append((match.range, .comment))
                        }
                    }
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let tv = self.textView else {
                        syntaxHighlightSignposter.endInterval("rehighlight_macos", interval)
                        return
                    }
                    defer { syntaxHighlightSignposter.endInterval("rehighlight_macos", interval) }
                    guard generation == self.highlightGeneration else { return }
                    // Discard if text changed since we started
                    guard tv.string == textSnapshot else { return }
                    let viewportAnchor = self.currentViewportAnchor(
                        textLength: (textSnapshot as NSString).length,
                        language: language
                    )
                    let baseColor = self.parent.effectiveBaseTextColor()
                    let priorSelectedRange = tv.selectedRange()
                    let selectionBeforeApply = priorSelectedRange
                    self.isApplyingHighlight = true
                    defer { self.isApplyingHighlight = false }
                    let undoWasEnabled = tv.undoManager?.isUndoRegistrationEnabled ?? false
                    if undoWasEnabled {
                        tv.undoManager?.disableUndoRegistration()
                    }
                    defer {
                        restoreUndoRegistrationIfNeeded(tv.undoManager, wasEnabled: undoWasEnabled)
                    }

                    tv.textStorage?.beginEditing()
                    tv.textStorage?.removeAttribute(.foregroundColor, range: applyRange)
                    tv.textStorage?.removeAttribute(.backgroundColor, range: applyRange)
                    tv.textStorage?.removeAttribute(.underlineStyle, range: applyRange)
                    tv.textStorage?.removeAttribute(.font, range: applyRange)
                    tv.textStorage?.addAttribute(.foregroundColor, value: baseColor, range: applyRange)
                    let baseFont = self.parent.resolvedFont()
                    tv.textStorage?.addAttribute(.font, value: baseFont, range: applyRange)
                    let boldKeywordFont = fontWithSymbolicTrait(baseFont, trait: .bold)
                    let italicCommentFont = fontWithSymbolicTrait(baseFont, trait: .italic)
                    // Apply colored ranges
                    for (range, color) in coloredRanges {
                        tv.textStorage?.addAttribute(.foregroundColor, value: NSColor(color), range: range)
                    }
                    for (range, emphasis) in emphasizedRanges {
                        let font: NSFont
                        switch emphasis {
                        case .keyword:
                            font = boldKeywordFont
                        case .comment:
                            font = italicCommentFont
                        }
                        tv.textStorage?.addAttribute(.font, value: font, range: range)
                    }

                    let selectedLocation = min(max(0, selected.location), max(0, fullRange.length))
                    let suppressLargeFileExtras = self.parent.isLargeFileMode
                    let scopeGuideVisualsSupported = supportsScopeGuideVisuals(language: self.parent.language)
                    let wantsScopeBackground = self.parent.highlightScopeBackground && !suppressLargeFileExtras && !self.parent.isLineWrapEnabled && scopeGuideVisualsSupported
                    let wantsScopeGuides = self.parent.showScopeGuides && !suppressLargeFileExtras && !self.parent.isLineWrapEnabled && scopeGuideVisualsSupported
                    let needsScopeComputation = (wantsScopeBackground || wantsScopeGuides)
                        && fullRange.length < EditorRuntimeLimits.scopeComputationMaxUTF16Length
                    let bracketMatch = needsScopeComputation ? computeBracketScopeMatch(text: textSnapshot, caretLocation: selectedLocation) : nil
                    let indentationMatch: IndentationScopeMatch? = {
                        guard needsScopeComputation, supportsIndentationScopes(language: self.parent.language) else { return nil }
                        return computeIndentationScopeMatch(text: textSnapshot, caretLocation: selectedLocation)
                    }()

                    if wantsScopeBackground || wantsScopeGuides {
                        let textLength = fullRange.length
                        let scopeRange = bracketMatch?.scopeRange ?? indentationMatch?.scopeRange
                        let guideRanges = bracketMatch?.guideMarkerRanges ?? indentationMatch?.guideMarkerRanges ?? []

                        if wantsScopeBackground, let scope = scopeRange, isValidRange(scope, utf16Length: textLength) {
                            tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.18), range: scope)
                        }

                        if wantsScopeGuides {
                            for marker in guideRanges {
                                if isValidRange(marker, utf16Length: textLength) {
                                    tv.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.36), range: marker)
                                }
                            }
                        }
                    }

                    tv.textStorage?.endEditing()
                    let textLength = (tv.string as NSString).length
                    let safeLocation = min(max(0, priorSelectedRange.location), textLength)
                    let safeLength = min(max(0, priorSelectedRange.length), max(0, textLength - safeLocation))
                    let safeRange = NSRange(location: safeLocation, length: safeLength)
                    let currentRange = tv.selectedRange()
                    let selectionUnchangedDuringApply =
                        currentRange.location == selectionBeforeApply.location &&
                        currentRange.length == selectionBeforeApply.length
                    if selectionUnchangedDuringApply &&
                        (currentRange.location != safeRange.location || currentRange.length != safeRange.length) {
                        tv.setSelectedRange(safeRange)
                    }
                    tv.typingAttributes[.foregroundColor] = baseColor

                    self.parent.applyInvisibleCharacterPreference(tv)

                    // Update last highlighted state
                    self.lastHighlightedText = textSnapshot
                    self.lastLanguage = language
                    self.lastColorScheme = scheme
                    self.lastLineHeight = lineHeightValue
                    self.lastHighlightToken = token
                    self.lastSelectionLocation = selectedLocation
                    self.lastHighlightViewportAnchor = viewportAnchor
                    self.lastTranslucencyEnabled = self.parent.translucentBackgroundEnabled
                }
            }

            pendingHighlight = work
            // Run immediately on first paint/explicit refresh, debounce while typing.
            if immediate {
                highlightQueue.async(execute: work)
            } else {
                let delay: TimeInterval
                if targetRange != nil {
                    delay = 0.08
                } else if textSnapshot.utf16.count >= 120_000 {
                    delay = 0.22
                } else {
                    delay = 0.12
                }
                highlightQueue.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if let accepting = textView as? AcceptingTextView, accepting.isApplyingDroppedContent {
                // Drop-import chunking mutates storage many times; defer expensive binding/highlight work
                // until the final didChangeText emitted after import completion.
                return
            }
            let currentText = textView.string
            let currentLength = (currentText as NSString).length
            let sanitized: String
            if currentLength > 300_000 {
                // Fast path while editing very large files.
                if currentText.contains("\0") || currentText.contains("\r") {
                    sanitized = currentText
                        .replacingOccurrences(of: "\0", with: "")
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                } else {
                    sanitized = currentText
                }
            } else {
                sanitized = AcceptingTextView.sanitizePlainText(currentText)
            }
            if sanitized != currentText {
                pendingTextMutation = nil
                replaceTextPreservingSelectionAndFocus(textView, with: sanitized)
            }
            let normalizedStyle = NSMutableParagraphStyle()
            normalizedStyle.lineHeightMultiple = max(0.9, parent.lineHeightMultiple)
            textView.defaultParagraphStyle = normalizedStyle
            textView.typingAttributes[.paragraphStyle] = normalizedStyle
            if let storage = textView.textStorage {
                let len = storage.length
                if len <= 200_000 {
                    let undoWasEnabled = textView.undoManager?.isUndoRegistrationEnabled ?? false
                    if undoWasEnabled {
                        textView.undoManager?.disableUndoRegistration()
                    }
                    storage.beginEditing()
                    storage.addAttribute(.paragraphStyle, value: normalizedStyle, range: NSRange(location: 0, length: len))
                    storage.endEditing()
                    restoreUndoRegistrationIfNeeded(textView.undoManager, wasEnabled: undoWasEnabled)
                }
            }
            let didApplyIncrementalMutation = applyPendingTextMutationIfPossible()
            if !didApplyIncrementalMutation {
                syncBindingText(sanitized)
            }
            parent.applyInvisibleCharacterPreference(textView)
            if let accepting = textView as? AcceptingTextView, accepting.isApplyingPaste {
                parent.applyInvisibleCharacterPreference(textView)
                let snapshot = textView.string
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.syncBindingText(snapshot, immediate: true)
                    self?.scheduleHighlightIfNeeded(currentText: snapshot)
                }
                return
            }
            parent.applyInvisibleCharacterPreference(textView)
            // Update SwiftUI binding, caret status, and rehighlight.
            let nsText = textView.string as NSString
            let caretLocation = min(nsText.length, textView.selectedRange().location)
            pendingEditedRange = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))
            updateCaretStatusAndHighlight(triggerHighlight: false)
            scheduleHighlightIfNeeded(currentText: sanitized)
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

        func textViewDidChangeSelection(_ notification: Notification) {
            if isApplyingHighlight { return }
            if let tv = notification.object as? AcceptingTextView {
                tv.clearInlineSuggestion()
                if let eventType = tv.window?.currentEvent?.type,
                   eventType == .leftMouseDown || eventType == .leftMouseDragged || eventType == .leftMouseUp {
                    noteRecentInteraction(source: "selection")
                }
                tv.invalidateBracketHighlightCache()
                tv.needsDisplay = true
                publishSelectionSnapshot(from: tv.string as NSString, selectedRange: tv.selectedRange())
            }
            updateCaretStatusAndHighlight(triggerHighlight: !parent.isLineWrapEnabled)
        }

        func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let selectedRange = textView.selectedRange()
            guard selectedRange.location != NSNotFound,
                  selectedRange.length > 0 else {
                return menu
            }
            let snapshotItem = NSMenuItem(
                title: "Create Code Snapshot",
                action: #selector(createCodeSnapshotFromContextMenu(_:)),
                keyEquivalent: ""
            )
            snapshotItem.target = self
            snapshotItem.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Create Code Snapshot")
            menu.addItem(.separator())
            menu.addItem(snapshotItem)
            return menu
        }

        @objc private func createCodeSnapshotFromContextMenu(_ sender: Any?) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let selectedRange = tv.selectedRange()
            guard selectedRange.location != NSNotFound,
                  selectedRange.length > 0,
                  NSMaxRange(selectedRange) <= ns.length else { return }
            publishSelectionSnapshot(from: ns, selectedRange: selectedRange)
            NotificationCenter.default.post(name: .editorRequestCodeSnapshotFromSelection, object: nil)
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

        // Compute (line, column), broadcast, and highlight the current line.
        private func updateCaretStatusAndHighlight(triggerHighlight: Bool = true) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let location = sel.location
            if parent.isLargeFileMode || ns.length > 300_000 {
                NotificationCenter.default.post(
                    name: .caretPositionDidChange,
                    object: nil,
                    userInfo: ["line": 0, "column": location, "location": location]
                )
                return
            }
            let caret = editorCaretLineColumn(in: ns, location: location)
            NotificationCenter.default.post(
                name: .caretPositionDidChange,
                object: nil,
                userInfo: ["line": caret.line, "column": caret.column, "location": location]
            )
            if triggerHighlight {
                // For very large files, avoid immediate full caret-triggered passes to keep UI responsive.
                let immediateHighlight = ns.length < 200_000
                scheduleHighlightIfNeeded(currentText: tv.string, immediate: immediateHighlight)
            }
        }

        @objc func moveToLine(_ notification: Notification) {
            if let targetWindow = notification.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
               let ownWindow = textView?.window?.windowNumber,
               targetWindow != ownWindow {
                return
            }
            if let targetDocumentID = notification.userInfo?[EditorCommandUserInfo.documentID] as? String,
               parent.documentID?.uuidString != targetDocumentID {
                return
            }
            guard let lineOneBased = notification.object as? Int,
                  let textView = textView else { return }

            // If there's no text, nothing to do
            let currentText = textView.string
            guard !currentText.isEmpty else { return }

            // Cancel any in-flight highlight to prevent it from restoring an old selection
            pendingHighlight?.cancel()

            // Work with NSString/UTF-16 indices to match NSTextView expectations
            let ns = currentText as NSString
            let totalLength = ns.length

            // Clamp target line to available line count (1-based input)
            let linesArray = currentText.components(separatedBy: .newlines)
            let clampedLineIndex = max(1, min(lineOneBased, linesArray.count)) - 1 // 0-based index

            // Compute the UTF-16 location by summing UTF-16 lengths of preceding lines + newline characters
            var location = 0
            if clampedLineIndex > 0 {
                for i in 0..<(clampedLineIndex) {
                    let lineNSString = linesArray[i] as NSString
                    location += lineNSString.length
                    // Add one for the newline that separates lines, as components(separatedBy:) drops separators
                    location += 1
                }
            }
            // Safety clamp
            location = max(0, min(location, totalLength))

            // Move caret and scroll into view on the main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tv = self.textView else { return }
                tv.window?.makeFirstResponder(tv)
                // Ensure layout is up-to-date before scrolling
                if let textContainer = tv.textContainer {
                    tv.layoutManager?.ensureLayout(for: textContainer)
                }
                tv.setSelectedRange(NSRange(location: location, length: 0))
                tv.scrollRangeToVisible(NSRange(location: location, length: 0))

                self.updateCaretStatusAndHighlight(triggerHighlight: false)
                self.scheduleHighlightIfNeeded(currentText: tv.string, immediate: true)
            }
        }

        @objc private func scrollViewportToFraction(_ notification: Notification) {
            if let targetWindow = notification.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
               let ownWindow = textView?.window?.windowNumber,
               targetWindow != ownWindow {
                return
            }
            if let targetDocumentID = notification.userInfo?[EditorCommandUserInfo.documentID] as? String,
               parent.documentID?.uuidString != targetDocumentID {
                return
            }
            guard let textView,
                  let scrollView = textView.enclosingScrollView,
                  let topFraction = notification.userInfo?[EditorCommandUserInfo.viewportTopFraction] as? Double else { return }

            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            let usedHeight: CGFloat = {
                guard let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else {
                    return 0
                }
                return ceil(layoutManager.usedRect(for: textContainer).maxY + textView.textContainerInset.height)
            }()
            let visibleHeight = max(1, scrollView.contentView.bounds.height)
            let contentHeight = max(
                usedHeight,
                visibleHeight
            )
            let targetY = CGFloat(min(max(0, topFraction), 1)) * max(0, contentHeight - visibleHeight)
            let currentX = scrollView.contentView.bounds.origin.x
            scrollView.contentView.scroll(to: NSPoint(x: currentX, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            textView.layoutManager?.invalidateDisplay(forCharacterRange: textView.visibleCharacterRangeForDisplayInvalidation())
            textView.needsDisplay = true
            postMinimapViewportIfNeeded(textView: textView, scrollView: scrollView, force: true)
        }

        @objc func moveToRange(_ notification: Notification) {
            if let targetWindow = notification.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
               let ownWindow = textView?.window?.windowNumber,
               targetWindow != ownWindow {
                return
            }
            guard let textView = textView else { return }
            guard let location = notification.userInfo?[EditorCommandUserInfo.rangeLocation] as? Int,
                  let length = notification.userInfo?[EditorCommandUserInfo.rangeLength] as? Int else { return }
            let textLength = (textView.string as NSString).length
            guard location >= 0, length >= 0, location + length <= textLength else { return }

            let range = NSRange(location: location, length: length)
            pendingHighlight?.cancel()
            textView.window?.makeFirstResponder(textView)
            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            scheduleHighlightIfNeeded(currentText: textView.string, immediate: true)
        }
    }
}

#endif
