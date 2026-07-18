#if os(macOS)
import Dispatch
import SwiftUI
import Foundation
import OSLog
import AppKit

// MARK: - Text View Observer Tokens

struct TextViewObserverToken: @unchecked Sendable {
    nonisolated(unsafe) let raw: NSObjectProtocol
}

extension NSTextView {
    func visibleCharacterRangeForDisplayInvalidation() -> NSRange {
        guard let layoutManager, let textContainer else {
            return NSRange(location: 0, length: (string as NSString).length)
        }
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else {
            return NSRange(location: 0, length: min((string as NSString).length, 1))
        }
        return characterRange
    }
}

@MainActor
final class AcceptingTextView: NSTextView {
    // MARK: - Editor State

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool {
        drawsBackground && backgroundColor.alphaComponent >= 1
    }
    private let vimModeDefaultsKey = "EditorVimModeEnabled"
    private let vimInterceptionDefaultsKey = "EditorVimInterceptionEnabled"
    private var isVimInsertMode: Bool = true
    private var vimObservers: [TextViewObserverToken] = []
    private var activityObservers: [TextViewObserverToken] = []
    private var didConfigureVimMode: Bool = false
    private var lastAppliedInvisiblePreference: Bool?
    private var defaultsObserver: TextViewObserverToken?
    private let dropReadChunkSize = 64 * 1024
    var isApplyingDroppedContent: Bool = false
    private var inlineSuggestion: String?
    private var inlineSuggestionLocation: Int?
    private var inlineSuggestionView: NSTextField?
    private var inlineSuggestionPositionUpdatePending: Bool = false
    var isApplyingInlineSuggestion: Bool = false
    var recentlyAcceptedInlineSuggestion: Bool = false
    var isApplyingPaste: Bool = false
    private struct BracketHighlightCacheKey: Equatable {
        let selectedLocation: Int
        let textLength: Int
        let containerSize: NSSize
    }
    private var bracketHighlightCacheKey: BracketHighlightCacheKey?
    private var bracketHighlightRects: [NSRect] = []
    private var selectionOverlaySuppressionDeadline: TimeInterval = 0
    private var selectionOverlaySuppressionGeneration: UInt64 = 0
    private var lastDisplayRefreshVisibleRect: NSRect = .null
    private var isVisibleDisplayRefreshScheduled: Bool = false
    private var pendingVisibleDisplayRefreshForce: Bool = false
    private var magnificationStartFontSize: CGFloat?
    private var accumulatedMagnification: CGFloat = 0
    private var lastMagnificationFontSize: CGFloat?
    var onContentLayoutRefresh: (() -> Void)?
    var markdownFormattingEnabled: Bool = false
    var autoIndentEnabled: Bool = true
    var autoCloseBracketsEnabled: Bool = true
    var emmetLanguage: String = "plain"
    var indentStyle: String = "spaces"
    var indentWidth: Int = 4 {
        didSet {
            if oldValue != indentWidth, showIndentationGuides {
                needsDisplay = true
            }
        }
    }
    var highlightCurrentLine: Bool = true {
        didSet {
            if oldValue != highlightCurrentLine {
                needsDisplay = true
            }
        }
    }
    var currentLineHighlightColor: NSColor = NSColor.systemBlue.withAlphaComponent(0.22) {
        didSet {
            if oldValue != currentLineHighlightColor {
                needsDisplay = true
            }
        }
    }
    var highlightMatchingBrackets: Bool = false {
        didSet {
            if oldValue != highlightMatchingBrackets {
                invalidateBracketHighlightCache()
                needsDisplay = true
            }
        }
    }
    var showIndentationGuides: Bool = false {
        didSet {
            if oldValue != showIndentationGuides {
                needsDisplay = true
            }
        }
    }
    private let editorInsetX: CGFloat = 12

    // We want the caret at the *start* of the paste.
    private var pendingPasteCaretLocation: Int?

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver.raw)
        }
        for observer in activityObservers {
            NotificationCenter.default.removeObserver(observer.raw)
        }
        for observer in vimObservers {
            NotificationCenter.default.removeObserver(observer.raw)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !didConfigureVimMode {
            configureVimMode()
            didConfigureVimMode = true
        }
        configureActivityObservers()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
        textContainerInset = NSSize(width: editorInsetX, height: 12)
        if defaultsObserver == nil {
            defaultsObserver = TextViewObserverToken(raw: NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.forceDisableInvisibleGlyphRendering(deep: true)
                }
            })
        }
        forceDisableInvisibleGlyphRendering(deep: true)
        scheduleVisibleDisplayRefresh(force: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Keep invisible/control marker rendering aligned with user preference on every redraw.
        forceDisableInvisibleGlyphRendering()
        super.draw(dirtyRect)
        drawMatchingBracketHighlightIfNeeded(drawFill: false, drawStroke: true, dirtyRect: dirtyRect)
        drawIndentationGuidesIfNeeded()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineHighlightIfNeeded(dirtyRect: rect)
        drawMatchingBracketHighlightIfNeeded(drawFill: true, drawStroke: false, dirtyRect: rect)
    }

    private func drawCurrentLineHighlightIfNeeded(dirtyRect: NSRect) {
        guard highlightCurrentLine,
              !isSuppressingSelectionOverlays,
              window?.firstResponder === self,
              let layoutManager,
              let textContainer else { return }

        let nsText = string as NSString
        let selected = selectedRange()
        guard selected.location != NSNotFound else { return }
        guard selectionIsNearVisibleRange(selected, layoutManager: layoutManager, textContainer: textContainer) else { return }
        let fallbackLineHeight = max((font?.ascender ?? 14) - (font?.descender ?? -4) + (font?.leading ?? 0), 1)

        let textContainerOrigin = textContainerOrigin
        let lineRect: NSRect
        if nsText.length == 0 {
            lineRect = NSRect(
                x: bounds.minX,
                y: textContainerOrigin.y,
                width: bounds.width,
                height: fallbackLineHeight
            )
        } else {
            let caretLocation = min(max(0, selected.location), nsText.length)
            let lineRange = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            )
            let glyphRect: NSRect
            if glyphRange.length > 0 {
                layoutManager.ensureLayout(forGlyphRange: glyphRange)
                glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            } else {
                let characterIndex = min(caretLocation, max(0, nsText.length - 1))
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
                layoutManager.ensureLayout(forGlyphRange: NSRange(location: glyphIndex, length: 1))
                glyphRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            }
            lineRect = NSRect(
                x: bounds.minX,
                y: textContainerOrigin.y + glyphRect.minY,
                width: bounds.width,
                height: max(glyphRect.height, fallbackLineHeight)
            )
        }

        guard lineRect.intersects(dirtyRect) else { return }
        currentLineHighlightColor.setFill()
        lineRect.fill()
    }

    func invalidateBracketHighlightCache() {
        bracketHighlightCacheKey = nil
        bracketHighlightRects = []
    }

    private func drawMatchingBracketHighlightIfNeeded(drawFill: Bool, drawStroke: Bool, dirtyRect: NSRect) {
        guard !isSuppressingSelectionOverlays else { return }
        let rects = matchingBracketHighlightRects()
        guard !rects.isEmpty else { return }

        let fillColor = NSColor.systemOrange.withAlphaComponent(0.24)
        let strokeColor = NSColor.systemOrange.withAlphaComponent(0.86)
        for rect in rects where rect.intersects(dirtyRect) {
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            if drawFill {
                fillColor.setFill()
                path.fill()
            }
            if drawStroke {
                strokeColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    private func matchingBracketHighlightRects() -> [NSRect] {
        guard highlightMatchingBrackets,
              let layoutManager,
              let textContainer else { return [] }

        let nsText = string as NSString
        let textLength = nsText.length
        guard textLength > 0,
              textLength < EditorRuntimeLimits.scopeComputationMaxUTF16Length else { return [] }

        let selected = selectedRange()
        guard selected.location != NSNotFound else { return [] }
        guard selectionIsNearVisibleRange(selected, layoutManager: layoutManager, textContainer: textContainer) else { return [] }
        let cacheKey = BracketHighlightCacheKey(
            selectedLocation: selected.location,
            textLength: textLength,
            containerSize: textContainer.containerSize
        )
        if cacheKey == bracketHighlightCacheKey {
            return bracketHighlightRects
        }
        guard let match = computeBracketScopeMatch(text: string, caretLocation: selected.location) else {
            bracketHighlightCacheKey = cacheKey
            bracketHighlightRects = []
            return []
        }
        let textContainerOrigin = textContainerOrigin
        var rects: [NSRect] = []
        for range in [match.openRange, match.closeRange] where isValidRange(range, utf16Length: textLength) {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { continue }
            layoutManager.ensureLayout(forGlyphRange: glyphRange)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textContainerOrigin.x - 2
            rect.origin.y += textContainerOrigin.y - 1
            rect.size.width = max(rect.width + 4, 8)
            rect.size.height = max(rect.height + 2, (font?.ascender ?? 14) - (font?.descender ?? -4))
            rects.append(rect)
        }
        bracketHighlightCacheKey = cacheKey
        bracketHighlightRects = rects
        return rects
    }

    private func selectionIsNearVisibleRange(
        _ selected: NSRange,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> Bool {
        let textLength = (string as NSString).length
        guard selected.location >= 0, selected.location <= textLength else { return false }
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect.insetBy(dx: 0, dy: -160),
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )
        guard visibleCharacterRange.length > 0 else { return true }
        let padding = 2_000
        let lowerBound = max(0, visibleCharacterRange.location - padding)
        let upperBound = min(textLength, NSMaxRange(visibleCharacterRange) + padding)
        return selected.location >= lowerBound && selected.location <= upperBound
    }

    private var isSuppressingSelectionOverlays: Bool {
        ProcessInfo.processInfo.systemUptime < selectionOverlaySuppressionDeadline
    }

    private func suppressSelectionOverlaysDuringScroll(duration: TimeInterval = 0.16) {
        guard highlightCurrentLine || highlightMatchingBrackets else { return }
        let now = ProcessInfo.processInfo.systemUptime
        selectionOverlaySuppressionDeadline = max(selectionOverlaySuppressionDeadline, now + duration)
        selectionOverlaySuppressionGeneration &+= 1
        let generation = selectionOverlaySuppressionGeneration
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03) { [weak self] in
            guard let self,
                  self.selectionOverlaySuppressionGeneration == generation,
                  !self.isSuppressingSelectionOverlays else { return }
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        cancelPendingPasteCaretEnforcement()
        clearInlineSuggestion()
        NotificationCenter.default.post(name: .editorPointerInteraction, object: self)
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains([.shift, .option]) {
            let delta = event.scrollingDeltaY
            if abs(delta) > 0.1 {
                let step: Double = delta > 0 ? 1 : -1
                NotificationCenter.default.post(name: .zoomEditorFontRequested, object: step)
                return
            }
        }
        cancelPendingPasteCaretEnforcement()
        suppressSelectionOverlaysDuringScroll()
        super.scrollWheel(with: event)
        scheduleInlineSuggestionPositionUpdate()
    }

    override func magnify(with event: NSEvent) {
        guard isEditable else {
            super.magnify(with: event)
            return
        }

        switch event.phase {
        case .began:
            magnificationStartFontSize = font?.pointSize ?? 14
            accumulatedMagnification = 0
            lastMagnificationFontSize = magnificationStartFontSize
        case .changed, .mayBegin:
            if magnificationStartFontSize == nil {
                magnificationStartFontSize = font?.pointSize ?? 14
                lastMagnificationFontSize = magnificationStartFontSize
                accumulatedMagnification = 0
            }
            guard let magnificationStartFontSize else { return }
            accumulatedMagnification += event.magnification
            let requestedSize = min(28, max(10, (magnificationStartFontSize + accumulatedMagnification * 10).rounded()))
            guard requestedSize != lastMagnificationFontSize else { return }
            let delta = requestedSize - (lastMagnificationFontSize ?? magnificationStartFontSize)
            lastMagnificationFontSize = requestedSize
            NotificationCenter.default.post(name: .zoomEditorFontRequested, object: Double(delta))
        case .ended, .cancelled:
            magnificationStartFontSize = nil
            accumulatedMagnification = 0
            lastMagnificationFontSize = nil
        default:
            break
        }
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome, UserDefaults.standard.bool(forKey: vimModeDefaultsKey) {
            // Re-enter NORMAL whenever Vim mode is active.
            isVimInsertMode = false
            postVimModeState()
        }
        return didBecome
    }

    override func layout() {
        super.layout()
        scheduleVisibleDisplayRefresh()
        scheduleInlineSuggestionPositionUpdate()
    }

    private func scheduleVisibleDisplayRefresh(force: Bool = false) {
        if isVisibleDisplayRefreshScheduled {
            pendingVisibleDisplayRefreshForce = pendingVisibleDisplayRefreshForce || force
            return
        }
        isVisibleDisplayRefreshScheduled = true
        pendingVisibleDisplayRefreshForce = force
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let shouldForce = self.pendingVisibleDisplayRefreshForce
            self.isVisibleDisplayRefreshScheduled = false
            self.pendingVisibleDisplayRefreshForce = false
            self.refreshVisibleDisplayAfterGeometryChange(force: shouldForce)
        }
    }

    private func refreshVisibleDisplayAfterGeometryChange(force: Bool = false) {
        guard window != nil,
              let layoutManager,
              let textContainer else { return }
        let rect = visibleRect
        guard rect.width > 0, rect.height > 0 else { return }

        if !force,
           lastDisplayRefreshVisibleRect.isNull == false,
           abs(lastDisplayRefreshVisibleRect.width - rect.width) < 0.5,
           abs(lastDisplayRefreshVisibleRect.height - rect.height) < 0.5,
           abs(lastDisplayRefreshVisibleRect.minX - rect.minX) < 0.5,
           abs(lastDisplayRefreshVisibleRect.minY - rect.minY) < 0.5 {
            return
        }

        lastDisplayRefreshVisibleRect = rect
        layoutManager.ensureLayout(for: textContainer)
        layoutManager.invalidateDisplay(forCharacterRange: visibleCharacterRangeForDisplayInvalidation())
        needsDisplay = true
    }

    func refreshDisplayAfterContentInstall() {
        lastDisplayRefreshVisibleRect = .null
        DispatchQueue.main.async { [weak self] in
            self?.refreshDisplayForInstalledContent()
        }
        // Sequoia can finish TextKit layout after the first post-load pass. Retry once
        // so an already-loaded document is never left showing only its line-number ruler.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.refreshDisplayForInstalledContent()
        }
    }

    private func refreshDisplayForInstalledContent() {
        guard window != nil,
              let layoutManager,
              let textContainer else {
            return
        }

        let textLength = (string as NSString).length
        if MacEditorContentInstallRefreshPolicy.shouldInvalidateFullRange(textLength: textLength) {
            let fullRange = NSRange(location: 0, length: textLength)
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            layoutManager.ensureLayout(for: textContainer)
            layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        } else {
            layoutManager.ensureLayout(for: textContainer)
            layoutManager.invalidateDisplay(forCharacterRange: visibleCharacterRangeForDisplayInvalidation())
        }
        needsDisplay = true
        onContentLayoutRefresh?()
    }
    // MARK: - Drag and Drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        let canReadFileURL = pb.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
        let canReadPlainText = pasteboardPlainString(from: pb)?.isEmpty == false
        return (canReadFileURL || canReadPlainText) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let nsurls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL],
           !nsurls.isEmpty {
            let urls = nsurls.map { $0 as URL }
            if urls.count == 1 {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls[0])
            } else {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls)
            }
            // Do not insert content; let higher-level controller open a new tab.
            return true
        }
        if let droppedString = pasteboardPlainString(from: pb), !droppedString.isEmpty {
            let sanitized = sanitizedPlainText(droppedString)
            let dropRange = insertionRangeForDrop(sender)
            isApplyingPaste = true
            if let storage = textStorage {
                storage.beginEditing()
                replaceCharacters(in: dropRange, with: sanitized)
                storage.endEditing()
            } else {
                let current = string as NSString
                if dropRange.location <= current.length &&
                    dropRange.location + dropRange.length <= current.length {
                    string = current.replacingCharacters(in: dropRange, with: sanitized)
                } else {
                    isApplyingPaste = false
                    return false
                }
            }
            isApplyingPaste = false

            NotificationCenter.default.post(name: .pastedText, object: sanitized)
            didChangeText()
            return true
        }
        return false
    }

    private func insertionRangeForDrop(_ sender: NSDraggingInfo) -> NSRange {
        let windowPoint = sender.draggingLocation
        let viewPoint = convert(windowPoint, from: nil)
        let insertionIndex = characterIndexForInsertion(at: viewPoint)
        let clamped = clampedRange(NSRange(location: insertionIndex, length: 0), forTextLength: (string as NSString).length)
        setSelectedRange(clamped)
        return clamped
    }

    private func applyDroppedContentInChunks(
        _ content: String,
        at selection: NSRange,
        fileName: String,
        largeFileMode: Bool,
        completion: @escaping (Bool, Int) -> Void
    ) {
        let nsContent = content as NSString
        let safeSelection = clampedRange(selection, forTextLength: (string as NSString).length)
        let total = nsContent.length
        if total == 0 {
            completion(true, 0)
            return
        }
        NotificationCenter.default.post(
            name: .droppedFileLoadProgress,
            object: nil,
            userInfo: [
                "fraction": 0.70,
                "fileName": "Applying file",
                "largeFileMode": largeFileMode
            ]
        )

        // Large payloads: prefer one atomic replace after yielding one runloop turn so
        // progress updates can render before the heavy text-system mutation begins.
        if total >= 300_000 {
            isApplyingDroppedContent = true
            NotificationCenter.default.post(
                name: .droppedFileLoadProgress,
                object: nil,
                userInfo: [
                    "fraction": 0.90,
                    "fileName": "Applying file",
                    "largeFileMode": largeFileMode,
                    "isDeterminate": true
                ]
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(false, 0)
                    return
                }

                let replaceSucceeded: Bool
                if let storage = self.textStorage {
                    let liveSafeSelection = self.clampedRange(safeSelection, forTextLength: storage.length)
                    let undoWasEnabled = self.undoManager?.isUndoRegistrationEnabled ?? false
                    if undoWasEnabled {
                        self.undoManager?.disableUndoRegistration()
                    }
                    storage.beginEditing()
                    if storage.length == 0 && liveSafeSelection.location == 0 && liveSafeSelection.length == 0 {
                        storage.mutableString.setString(content)
                    } else {
                        storage.mutableString.replaceCharacters(in: liveSafeSelection, with: content)
                    }
                    storage.endEditing()
                    restoreUndoRegistrationIfNeeded(self.undoManager, wasEnabled: undoWasEnabled)
                    replaceSucceeded = true
                } else {
                    let current = self.string as NSString
                    if safeSelection.location <= current.length &&
                        safeSelection.location + safeSelection.length <= current.length {
                        let replaced = current.replacingCharacters(in: safeSelection, with: content)
                        self.string = replaced
                        replaceSucceeded = true
                    } else {
                        replaceSucceeded = false
                    }
                }

                self.isApplyingDroppedContent = false
                NotificationCenter.default.post(
                    name: .droppedFileLoadProgress,
                    object: nil,
                    userInfo: [
                        "fraction": replaceSucceeded ? 1.0 : 0.0,
                        "fileName": replaceSucceeded ? "Reading file" : "Import failed",
                        "largeFileMode": largeFileMode,
                        "isDeterminate": true
                    ]
                )
                completion(replaceSucceeded, replaceSucceeded ? total : 0)
            }
            return
        }

        let replaceSucceeded: Bool
        if let storage = textStorage {
            let undoWasEnabled = undoManager?.isUndoRegistrationEnabled ?? false
            if undoWasEnabled {
                undoManager?.disableUndoRegistration()
            }
            storage.beginEditing()
            storage.mutableString.replaceCharacters(in: safeSelection, with: content)
            storage.endEditing()
            restoreUndoRegistrationIfNeeded(undoManager, wasEnabled: undoWasEnabled)
            replaceSucceeded = true
        } else {
            // Fallback for environments where textStorage is temporarily unavailable.
            let current = string as NSString
            if safeSelection.location <= current.length &&
                safeSelection.location + safeSelection.length <= current.length {
                let replaced = current.replacingCharacters(in: safeSelection, with: content)
                string = replaced
                replaceSucceeded = true
            } else {
                replaceSucceeded = false
            }
        }

        NotificationCenter.default.post(
            name: .droppedFileLoadProgress,
            object: nil,
            userInfo: [
                "fraction": replaceSucceeded ? 1.0 : 0.0,
                "fileName": replaceSucceeded ? "Reading file" : "Import failed",
                "largeFileMode": largeFileMode
            ]
        )

        completion(replaceSucceeded, replaceSucceeded ? total : 0)
    }

    private func clampedSelectionRange() -> NSRange {
        clampedRange(selectedRange(), forTextLength: (string as NSString).length)
    }

    private func clampedRange(_ range: NSRange, forTextLength length: Int) -> NSRange {
        guard length >= 0 else { return NSRange(location: 0, length: 0) }
        if range.location == NSNotFound {
            return NSRange(location: length, length: 0)
        }
        let safeLocation = min(max(0, range.location), length)
        let maxLen = max(0, length - safeLocation)
        let safeLength = min(max(0, range.length), maxLen)
        return NSRange(location: safeLocation, length: safeLength)
    }

    private func readDroppedFileData(
        at url: URL,
        totalBytes: Int64,
        progress: @escaping (Double) -> Void
    ) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var data = Data()
            if totalBytes > 0, totalBytes <= Int64(Int.max) {
                data.reserveCapacity(Int(totalBytes))
            }

            var loadedBytes: Int64 = 0
            var lastReported: Double = -1

            while true {
                let chunk = try handle.read(upToCount: dropReadChunkSize) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
                loadedBytes += Int64(chunk.count)

                if totalBytes > 0 {
                    let fraction = min(1.0, Double(loadedBytes) / Double(totalBytes))
                    if fraction - lastReported >= 0.02 || fraction >= 1.0 {
                        lastReported = fraction
                        DispatchQueue.main.async {
                            progress(fraction)
                        }
                    }
                }
            }

            if totalBytes > 0, lastReported < 1.0 {
                DispatchQueue.main.async {
                    progress(1.0)
                }
            }
            return data
        } catch {
            // Fallback path for URLs/FileHandle edge cases in sandboxed drag-drop.
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            DispatchQueue.main.async {
                progress(1.0)
            }
            return data
        }
    }

    private func decodeDroppedFileText(_ data: Data, fileURL: URL) -> String {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1251,
            .windowsCP1252,
            .isoLatin1
        ]
        for encoding in encodings {
            if let decoded = String(data: data, encoding: encoding) {
                return Self.sanitizePlainText(decoded)
            }
        }
        if let fallback = try? String(contentsOf: fileURL, encoding: .utf8) {
            return Self.sanitizePlainText(fallback)
        }
        return Self.sanitizePlainText(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Typing Helpers
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if !isApplyingInlineSuggestion {
            clearInlineSuggestion()
        }
        guard let s = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let sanitized = sanitizedPlainText(s)

        // Keep invisible/control marker rendering aligned with current preference.
        forceDisableInvisibleGlyphRendering()

        // Auto-indent by copying leading whitespace
        if sanitized == "\n" && autoIndentEnabled {
            let ns = (string as NSString)
            let sel = selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let currentLine = ns.substring(with: NSRange(
                location: lineRange.location,
                length: max(0, sel.location - lineRange.location)
            ))
            let indent = currentLine.prefix { $0 == " " || $0 == "\t" }
            let normalized = normalizedIndentation(String(indent))
            let listPrefix = continuedMarkdownListPrefix(for: currentLine, normalizedIndent: normalized)
            super.insertText("\n" + (listPrefix ?? normalized), replacementRange: replacementRange)
            return
        }

        // Auto-close common bracket/quote pairs
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"]
        if autoCloseBracketsEnabled, let closing = pairs[sanitized] {
            let sel = selectedRange()
            super.insertText(sanitized + closing, replacementRange: replacementRange)
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }

        super.insertText(sanitized, replacementRange: replacementRange)
    }

    static func sanitizePlainText(_ input: String) -> String {
        // Reuse model-level sanitizer to keep all text paths consistent.
        EditorTextSanitizer.sanitize(input)
    }

    private static func containsGlyphArtifacts(_ input: String) -> Bool {
        for scalar in input.unicodeScalars {
            let value = scalar.value
            if value == 0x2581 || (0x2400...0x243F).contains(value) {
                return true
            }
        }
        return false
    }

    private func sanitizedPlainText(_ input: String) -> String {
        Self.sanitizePlainText(input)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 || event.keyCode == 124 { // Tab or Right Arrow
            if acceptInlineSuggestion() {
                return
            }
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if markdownFormattingEnabled,
           flags == .command,
           let command = ["b": "bold", "i": "italic", "k": "link"][event.charactersIgnoringModifiers?.lowercased() ?? ""] {
            NotificationCenter.default.post(name: .markdownFormattingRequested, object: command)
            return
        }
        // Safety default: bypass Vim interception unless explicitly enabled.
        if !UserDefaults.standard.bool(forKey: vimInterceptionDefaultsKey) {
            super.keyDown(with: event)
            return
        }

        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            super.keyDown(with: event)
            return
        }

        let vimModeEnabled = UserDefaults.standard.bool(forKey: vimModeDefaultsKey)
        guard vimModeEnabled else {
            super.keyDown(with: event)
            return
        }

        if !isVimInsertMode {
            switch event.keyCode {
            case 123:
                moveLeft(nil)
                return
            case 124:
                moveRight(nil)
                return
            case 125:
                moveDown(nil)
                return
            case 126:
                moveUp(nil)
                return
            default:
                break
            }

            let key = event.charactersIgnoringModifiers ?? ""
            switch key {
            case "h":
                moveLeft(nil)
            case "j":
                moveDown(nil)
            case "k":
                moveUp(nil)
            case "l":
                moveRight(nil)
            case "w":
                moveWordForward(nil)
            case "b":
                moveWordBackward(nil)
            case "0":
                moveToBeginningOfLine(nil)
            case "$":
                moveToEndOfLine(nil)
            case "x":
                deleteForward(nil)
            case "p":
                paste(nil)
            case "i":
                isVimInsertMode = true
                postVimModeState()
            case "a":
                moveRight(nil)
                isVimInsertMode = true
                postVimModeState()
            case "\u{1B}":
                break
            default:
                break
            }
            return
        }

        // Escape exits insert mode.
        if event.keyCode == 53 || event.characters == "\u{1B}" {
            isVimInsertMode = false
            postVimModeState()
            return
        }

        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        if acceptInlineSuggestion() {
            return
        }
        if let expansion = EmmetExpander.expansionIfPossible(
            in: string,
            cursorUTF16Location: selectedRange().location,
            language: emmetLanguage
        ) {
            textStorage?.beginEditing()
            replaceCharacters(in: expansion.range, with: expansion.expansion)
            textStorage?.endEditing()
            let caretLocation = expansion.range.location + expansion.caretOffset
            setSelectedRange(NSRange(location: caretLocation, length: 0))
            didChangeText()
            return
        }
        // Keep Tab insertion deterministic and avoid platform-level invisible glyph rendering.
        let insertion: String
        if indentStyle == "tabs" {
            insertion = "\t"
        } else {
            insertion = String(repeating: " ", count: max(1, indentWidth))
        }
        super.insertText(sanitizedPlainText(insertion), replacementRange: selectedRange())
        forceDisableInvisibleGlyphRendering()
    }

    private func normalizedIndentation(_ indent: String) -> String {
        let width = max(1, indentWidth)
        switch indentStyle {
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

    private func drawIndentationGuidesIfNeeded() {
        guard showIndentationGuides,
              let layoutManager,
              let textContainer,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let text = string as NSString
        guard text.length > 0 else { return }

        let visibleRect = visibleRect.insetBy(dx: 0, dy: -80)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else { return }

        let guideWidth = max(1, indentWidth)
        let font = self.font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let columnWidth = NSString(string: " ").size(withAttributes: [.font: font]).width
        let containerOrigin = textContainerOrigin
        let color = (textColor ?? .labelColor).withAlphaComponent(0.14)

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1 / max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2))
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let charIndex = layoutManager.characterIndexForGlyph(at: lineGlyphRange.location)
            guard charIndex < text.length else { return }
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineEnd = min(text.length, lineRange.location + lineRange.length)
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
                let x = containerOrigin.x + (CGFloat(guideColumn) * columnWidth)
                let y1 = containerOrigin.y + usedRect.minY
                let y2 = containerOrigin.y + usedRect.maxY
                context.move(to: CGPoint(x: x, y: y1))
                context.addLine(to: CGPoint(x: x, y: y2))
            }
        }
        context.strokePath()
        context.restoreGState()
    }

    // Paste: capture insertion point and enforce caret position after paste across async updates.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let nsurls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL],
           !nsurls.isEmpty {
            let urls = nsurls.map { $0 as URL }
            if urls.count == 1 {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls[0])
            } else {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls)
            }
            return
        }
        if let urls = fileURLsFromPasteboard(pasteboard), !urls.isEmpty {
            if urls.count == 1 {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls[0])
            } else {
                NotificationCenter.default.post(name: .pastedFileURL, object: urls)
            }
            return
        }
        // Keep caret anchored at the current insertion location while paste async work settles.
        pendingPasteCaretLocation = selectedRange().location

        if let raw = pasteboardPlainString(from: pasteboard), !raw.isEmpty {
            if let pathURL = fileURLFromString(raw) {
                NotificationCenter.default.post(name: .pastedFileURL, object: pathURL)
                return
            }
            let sanitized = sanitizedPlainText(raw)
            isApplyingPaste = true
            textStorage?.beginEditing()
            replaceCharacters(in: selectedRange(), with: sanitized)
            textStorage?.endEditing()
            isApplyingPaste = false

            forceDisableInvisibleGlyphRendering()

            NotificationCenter.default.post(name: .pastedText, object: sanitized)
            didChangeText()

            schedulePasteCaretEnforcement()
            return
        }

        isApplyingPaste = true
        super.paste(sender)
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingPaste = false

            self?.forceDisableInvisibleGlyphRendering()
        }

        // Enforce caret after paste (multiple ticks beats late selection changes)
        schedulePasteCaretEnforcement()
    }

    private func pasteboardPlainString(from pasteboard: NSPasteboard) -> String? {
        if let raw = pasteboard.string(forType: .string), !raw.isEmpty {
            return raw
        }
        if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [NSString],
           let first = strings.first,
           first.length > 0 {
            return first as String
        }
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ),
           !attributed.string.isEmpty {
            return attributed.string
        }
        return nil
    }

    private func fileURLsFromPasteboard(_ pasteboard: NSPasteboard) -> [URL]? {
        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return [url]
        }
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let list = pasteboard.propertyList(forType: filenamesType) as? [String] {
            let urls = list.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty { return urls }
        }
        return nil
    }

    private func fileURLFromString(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Plain paths (with spaces or ~)
        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
        return nil
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateBracketHighlightCache()
        forceDisableInvisibleGlyphRendering(deep: true)
        if let storage = textStorage {
            let raw = storage.string
            if Self.containsGlyphArtifacts(raw) {
                let sanitized = Self.sanitizePlainText(raw)
                let sel = selectedRange()
                storage.beginEditing()
                storage.replaceCharacters(in: NSRange(location: 0, length: (raw as NSString).length), with: sanitized)
                storage.endEditing()
                setSelectedRange(NSRange(location: min(sel.location, (sanitized as NSString).length), length: 0))
            }
        }
        if !isApplyingInlineSuggestion {
            clearInlineSuggestion()
        }
        // Pasting triggers didChangeText; schedule enforcement again.
        schedulePasteCaretEnforcement()
    }

    private func forceDisableInvisibleGlyphRendering(deep: Bool = false) {
        let defaults = UserDefaults.standard
        let shouldShow = defaults.bool(forKey: "SettingsShowInvisibleCharacters")
        if defaults.bool(forKey: "NSShowAllInvisibles") != shouldShow {
            defaults.set(shouldShow, forKey: "NSShowAllInvisibles")
        }
        if defaults.bool(forKey: "NSShowControlCharacters") != shouldShow {
            defaults.set(shouldShow, forKey: "NSShowControlCharacters")
        }
        if layoutManager?.showsInvisibleCharacters != shouldShow {
            layoutManager?.showsInvisibleCharacters = shouldShow
        }
        if layoutManager?.showsControlCharacters != shouldShow {
            layoutManager?.showsControlCharacters = shouldShow
        }

        guard deep else { return }
        if lastAppliedInvisiblePreference == shouldShow {
            return
        }
        lastAppliedInvisiblePreference = shouldShow
        if let storage = textStorage {
            layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
        }
        needsDisplay = true
    }

    // MARK: - Activity, Suggestions, and Vim

    private func configureActivityObservers() {
        guard activityObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification
        ]
        for name in names {
            let token = TextViewObserverToken(raw: center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.forceDisableInvisibleGlyphRendering(deep: true)
                    self.scheduleVisibleDisplayRefresh(force: true)
                }
            })
            activityObservers.append(token)
        }
    }

    func showInlineSuggestion(_ suggestion: String, at location: Int) {
        guard !suggestion.isEmpty else {
            clearInlineSuggestion()
            return
        }
        inlineSuggestion = suggestion
        inlineSuggestionLocation = location
        if inlineSuggestionView == nil {
            let label = NSTextField(labelWithString: suggestion)
            label.isBezeled = false
            label.isEditable = false
            label.isSelectable = false
            label.drawsBackground = false
            label.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.6)
            label.font = font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            label.lineBreakMode = .byClipping
            label.maximumNumberOfLines = 1
            inlineSuggestionView = label
            addSubview(label)
        } else {
            inlineSuggestionView?.stringValue = suggestion
            inlineSuggestionView?.font = font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }
        scheduleInlineSuggestionPositionUpdate()
    }

    func clearInlineSuggestion() {
        inlineSuggestion = nil
        inlineSuggestionLocation = nil
        inlineSuggestionView?.removeFromSuperview()
        inlineSuggestionView = nil
    }

    private func acceptInlineSuggestion() -> Bool {
        guard let suggestion = inlineSuggestion,
              let loc = inlineSuggestionLocation else { return false }
        let sanitizedSuggestion = sanitizedPlainText(suggestion)
        guard !sanitizedSuggestion.isEmpty else {
            clearInlineSuggestion()
            return false
        }
        let sel = selectedRange()
        guard sel.length == 0, sel.location == loc else {
            clearInlineSuggestion()
            return false
        }
        isApplyingInlineSuggestion = true
        textStorage?.replaceCharacters(in: NSRange(location: loc, length: 0), with: sanitizedSuggestion)
        setSelectedRange(NSRange(location: loc + (sanitizedSuggestion as NSString).length, length: 0))
        isApplyingInlineSuggestion = false
        recentlyAcceptedInlineSuggestion = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.recentlyAcceptedInlineSuggestion = false
        }
        clearInlineSuggestion()
        return true
    }

    private func updateInlineSuggestionPosition() {
        guard let suggestion = inlineSuggestion,
              let loc = inlineSuggestionLocation,
              let label = inlineSuggestionView,
              let window else { return }
        let sel = selectedRange()
        if sel.location != loc || sel.length != 0 {
            clearInlineSuggestion()
            return
        }
        let rectInScreen = firstRect(forCharacterRange: NSRange(location: loc, length: 0), actualRange: nil)
        let rectInWindow = window.convertFromScreen(rectInScreen)
        let rectInView = convert(rectInWindow, from: nil)
        label.stringValue = suggestion
        label.sizeToFit()
        label.frame.origin = NSPoint(x: rectInView.origin.x, y: rectInView.origin.y)
    }

    private func scheduleInlineSuggestionPositionUpdate() {
        guard !inlineSuggestionPositionUpdatePending else { return }
        inlineSuggestionPositionUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inlineSuggestionPositionUpdatePending = false
            self.updateInlineSuggestionPosition()
        }
    }

    // Re-apply the desired caret position over multiple runloop ticks to beat late layout/async work.
    private func schedulePasteCaretEnforcement() {
        guard pendingPasteCaretLocation != nil else { return }

        // Cancel previously queued enforcement to avoid spamming
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyPendingPasteCaret), object: nil)

        // Run next turn
        perform(#selector(applyPendingPasteCaret), with: nil, afterDelay: 0)

        // Run again next runloop tick (beats "snap back" from late async work)
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingPasteCaret()
        }

        // Run once more with a tiny delay (beats slower async highlight passes)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.applyPendingPasteCaret()
        }
    }

    private func cancelPendingPasteCaretEnforcement() {
        pendingPasteCaretLocation = nil
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyPendingPasteCaret), object: nil)
    }

    @objc private func applyPendingPasteCaret() {
        guard let desired = pendingPasteCaretLocation else { return }

        let length = (string as NSString).length
        let loc = min(max(0, desired), length)
        let range = NSRange(location: loc, length: 0)

        // Set caret and keep it visible
        setSelectedRange(range)

        if let container = textContainer {
            layoutManager?.ensureLayout(for: container)
        }
        scrollRangeToVisible(range)

        // Important: clear only after we've enforced at least once.
        // The delayed calls will no-op once this is nil.
        pendingPasteCaretLocation = nil
    }

    private func postVimModeState() {
        NotificationCenter.default.post(
            name: .vimModeStateDidChange,
            object: nil,
            userInfo: ["insertMode": isVimInsertMode]
        )
    }

    private func insertBracketHelperToken(_ token: String) {
        guard isEditable else { return }
        clearInlineSuggestion()
        let selection = selectedRange()

        let pairMap: [String: (String, String)] = [
            "()": ("(", ")"),
            "{}": ("{", "}"),
            "[]": ("[", "]"),
            "\"\"": ("\"", "\""),
            "''": ("'", "'")
        ]

        if let pair = pairMap[token] {
            let insertion = pair.0 + pair.1
            textStorage?.replaceCharacters(in: selection, with: insertion)
            setSelectedRange(NSRange(location: selection.location + (pair.0 as NSString).length, length: 0))
            didChangeText()
            return
        }

        textStorage?.replaceCharacters(in: selection, with: token)
        setSelectedRange(NSRange(location: selection.location + (token as NSString).length, length: 0))
        didChangeText()
    }

    private func scalarName(for value: UInt32) -> String {
        switch value {
        case 0x20: return "SPACE"
        case 0x09: return "TAB"
        case 0x0A: return "LF"
        case 0x0D: return "CR"
        case 0x2581: return "LOWER_ONE_EIGHTH_BLOCK"
        default: return "U+\(String(format: "%04X", value))"
        }
    }

    private func inspectWhitespaceScalarsAtCaret() {
        let ns = string as NSString
        let length = ns.length
        let caret = min(max(selectedRange().location, 0), max(length - 1, 0))
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let line = ns.substring(with: lineRange)
        let lineOneBased = ns.substring(to: lineRange.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        var counts: [UInt32: Int] = [:]
        for scalar in line.unicodeScalars {
            let value = scalar.value
            let isWhitespace = scalar.properties.generalCategory == .spaceSeparator || value == 0x20 || value == 0x09
            let isLineBreak = value == 0x0A || value == 0x0D
            let isControlPicture = (0x2400...0x243F).contains(value)
            let isLowBlock = value == 0x2581
            if isWhitespace || isLineBreak || isControlPicture || isLowBlock {
                counts[value, default: 0] += 1
            }
        }

        let header = "Line \(lineOneBased) at UTF16@\(selectedRange().location), whitespace scalars:"
        let body: String
        if counts.isEmpty {
            body = "none detected"
        } else {
            let rows = counts.keys.sorted().map { key in
                "\(scalarName(for: key)) x\(counts[key] ?? 0)"
            }
            body = rows.joined(separator: ", ")
        }

        let windowNumber = window?.windowNumber ?? -1
        NotificationCenter.default.post(
            name: .whitespaceScalarInspectionResult,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.windowNumber: windowNumber,
                EditorCommandUserInfo.inspectionMessage: "\(header)\n\(body)"
            ]
        )
    }

    private func configureVimMode() {
        // Vim enabled starts in NORMAL; disabled uses regular insert typing.
        isVimInsertMode = !UserDefaults.standard.bool(forKey: vimModeDefaultsKey)
        postVimModeState()

        let observerRaw = NotificationCenter.default.addObserver(
            forName: .toggleVimModeRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Enter NORMAL when Vim mode is enabled; INSERT when disabled.
                let enabled = UserDefaults.standard.bool(forKey: self.vimModeDefaultsKey)
                self.isVimInsertMode = !enabled
                self.postVimModeState()
            }
        }
        let observer = TextViewObserverToken(raw: observerRaw)
        vimObservers.append(observer)

        let inspectorObserverRaw = NotificationCenter.default.addObserver(
            forName: .inspectWhitespaceScalarsRequested,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let targetWindowNumber = notif.userInfo?[EditorCommandUserInfo.windowNumber] as? Int
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let target = targetWindowNumber,
                   let own = self.window?.windowNumber,
                   target != own {
                    return
                }
                self.inspectWhitespaceScalarsAtCaret()
            }
        }
        let inspectorObserver = TextViewObserverToken(raw: inspectorObserverRaw)
        vimObservers.append(inspectorObserver)

        let bracketHelperObserverRaw = NotificationCenter.default.addObserver(
            forName: .insertBracketHelperTokenRequested,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let targetWindowNumber = notif.userInfo?[EditorCommandUserInfo.windowNumber] as? Int
            let bracketToken = notif.userInfo?[EditorCommandUserInfo.bracketToken] as? String
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let target = targetWindowNumber,
                   let own = self.window?.windowNumber,
                   target != own {
                    return
                }
                guard let token = bracketToken else { return }
                self.insertBracketHelperToken(token)
            }
        }
        let bracketHelperObserver = TextViewObserverToken(raw: bracketHelperObserverRaw)
        vimObservers.append(bracketHelperObserver)
    }

    private func trimTrailingWhitespaceIfEnabled() {
        let enabled = UserDefaults.standard.bool(forKey: "SettingsTrimTrailingWhitespace")
        guard enabled else { return }
        let original = self.string
        let lines = original.components(separatedBy: .newlines)
        var changed = false
        let trimmedLines = lines.map { line -> String in
            let trimmed = line.replacingOccurrences(of: #"[\t\x20]+$"#, with: "", options: .regularExpression)
            if trimmed != line { changed = true }
            return trimmed
        }
        guard changed else { return }
        let newString = trimmedLines.joined(separator: "\n")
        let oldSelected = self.selectedRange()
        self.textStorage?.beginEditing()
        self.string = newString
        self.textStorage?.endEditing()
        let newLoc = min(oldSelected.location, (newString as NSString).length)
        self.setSelectedRange(NSRange(location: newLoc, length: 0))
        self.didChangeText()
    }

}

#endif
