#if os(macOS)
import AppKit
import CoreText
import SwiftUI

struct VirtualEditorVisualFragment {
    let absoluteStartUTF16: Int
    let lengthUTF16: Int
    let line: CTLine
}

struct VirtualEditorVisualFragmentCache {
    private struct Entry {
        let width: CGFloat
        let wraps: Bool
        let fragments: [VirtualEditorVisualFragment]
    }

    private var entries: [Int: Entry] = [:]

    mutating func fragments(
        for attributed: NSAttributedString,
        localLine: Int,
        lineStartUTF16: Int,
        width: CGFloat,
        wraps: Bool
    ) -> [VirtualEditorVisualFragment] {
        if let cached = entries[localLine],
           abs(cached.width - width) < 0.5,
           cached.wraps == wraps {
            return cached.fragments
        }
        let fragments = VirtualEditorVisualLayout.fragments(
            for: attributed,
            lineStartUTF16: lineStartUTF16,
            width: width,
            wraps: wraps
        )
        entries[localLine] = Entry(width: width, wraps: wraps, fragments: fragments)
        return fragments
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        entries.removeAll(keepingCapacity: keepingCapacity)
    }
}

enum VirtualEditorVisualLayout {
    static func baseline(
        rowOrigin: Int,
        lineHeight: CGFloat,
        fontAscender: CGFloat,
        topInset: CGFloat = 2
    ) -> CGFloat {
        CGFloat(rowOrigin) * lineHeight + fontAscender + topInset
    }

    static func fragments(
        for attributed: NSAttributedString,
        lineStartUTF16: Int,
        width: CGFloat,
        wraps: Bool
    ) -> [VirtualEditorVisualFragment] {
        let length = attributed.length
        guard length > 0 else {
            return [VirtualEditorVisualFragment(
                absoluteStartUTF16: lineStartUTF16,
                lengthUTF16: 0,
                line: CTLineCreateWithAttributedString(attributed)
            )]
        }
        guard wraps else {
            return [VirtualEditorVisualFragment(
                absoluteStartUTF16: lineStartUTF16,
                lengthUTF16: length,
                line: CTLineCreateWithAttributedString(attributed)
            )]
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var result: [VirtualEditorVisualFragment] = []
        var location = 0
        while location < length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, location, max(1, width)))
            let safeCount = min(count, length - location)
            result.append(VirtualEditorVisualFragment(
                absoluteStartUTF16: lineStartUTF16 + location,
                lengthUTF16: safeCount,
                line: CTTypesetterCreateLine(typesetter, CFRange(location: location, length: safeCount))
            ))
            location += safeCount
        }
        return result
    }
}

enum VirtualEditorWheelZoom {
    static func fontSizeDelta(scrollingDeltaY: CGFloat, fallbackDeltaY: CGFloat) -> CGFloat {
        let rawDelta = abs(scrollingDeltaY) > 0.001 ? scrollingDeltaY : fallbackDeltaY
        return rawDelta * 0.2
    }
}

/// Bounded row accounting for wrapped text. Unloaded logical lines use an
/// estimate; the loaded viewport supplies exact fragment rows.
struct VirtualEditorVisualRowIndex {
    let logicalLineCount: Int
    let estimatedRowsPerLogicalLine: CGFloat

    var estimatedRowCount: Int {
        max(1, Int(ceil(CGFloat(max(1, logicalLineCount)) * estimatedRowsPerLogicalLine)))
    }

    func rowOrigin(forLogicalLine line: Int) -> Int {
        min(estimatedRowCount - 1, max(0, Int(floor(CGFloat(max(0, line)) * estimatedRowsPerLogicalLine))))
    }

    static func smoothedEstimate(previous: CGFloat, observed: CGFloat) -> CGFloat {
        min(4, max(1, previous * 0.75 + observed * 0.25))
    }
}

/// The macOS production editor surface. It intentionally does not use NSTextView
/// or TextKit: only a bounded EditorDocument viewport is decoded and laid out.
struct VirtualEditorView: NSViewRepresentable {
    let document: (any EditorDocument)?
    let documentID: UUID?
    let documentResourceID: String
    let contentRevision: Int
    let externalContentRevision: Int
    let storedCaretLocation: Int?
    let language: String
    let colorScheme: ColorScheme
    let fontSize: CGFloat
    let fontName: String
    let lineHeightMultiplier: CGFloat
    let isReadOnly: Bool
    let translucentBackgroundEnabled: Bool
    let showsLineNumbers: Bool
    let highlightCurrentLine: Bool
    let lineWrapEnabled: Bool
    let showsInvisibleCharacters: Bool
    let showsIndentationGuides: Bool
    let showsScopeGuides: Bool
    let highlightsScopeBackground: Bool
    let highlightsMatchingBrackets: Bool
    let autoIndentEnabled: Bool
    let autoCloseBracketsEnabled: Bool
    let isSplitPaneResizeInProgress: Bool
    let preferredLayoutWidth: CGFloat?
    let onFontSizeChange: ((CGFloat) -> Void)?
    let onTextMutation: ((EditorTextMutation) -> Bool)?

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: VirtualEditorScrollView, context: Context) -> CGSize? {
        VirtualEditorLayoutSizing.sizeThatFits(
            proposedWidth: proposal.width,
            proposedHeight: proposal.height,
            preferredWidth: preferredLayoutWidth
        )
    }

    func makeNSView(context: Context) -> VirtualEditorScrollView {
        let view = VirtualEditorScrollView()
        view.configure(
            document: document,
            documentID: documentID,
            resourceID: documentResourceID,
            contentRevision: contentRevision,
            externalContentRevision: externalContentRevision,
            caret: storedCaretLocation,
            language: language,
            colorScheme: colorScheme,
            fontSize: fontSize,
            fontName: fontName,
            lineHeightMultiplier: lineHeightMultiplier,
            isReadOnly: isReadOnly,
            translucentBackgroundEnabled: translucentBackgroundEnabled,
            showsLineNumbers: showsLineNumbers,
            highlightCurrentLine: highlightCurrentLine,
            lineWrapEnabled: lineWrapEnabled,
            showsInvisibleCharacters: showsInvisibleCharacters,
            showsIndentationGuides: showsIndentationGuides,
            showsScopeGuides: showsScopeGuides,
            highlightsScopeBackground: highlightsScopeBackground,
            highlightsMatchingBrackets: highlightsMatchingBrackets,
            autoIndentEnabled: autoIndentEnabled,
            autoCloseBracketsEnabled: autoCloseBracketsEnabled,
            isSplitPaneResizeInProgress: isSplitPaneResizeInProgress,
            onFontSizeChange: onFontSizeChange,
            onTextMutation: onTextMutation
        )
        return view
    }

    func updateNSView(_ nsView: VirtualEditorScrollView, context: Context) {
        nsView.configure(
            document: document,
            documentID: documentID,
            resourceID: documentResourceID,
            contentRevision: contentRevision,
            externalContentRevision: externalContentRevision,
            caret: storedCaretLocation,
            language: language,
            colorScheme: colorScheme,
            fontSize: fontSize,
            fontName: fontName,
            lineHeightMultiplier: lineHeightMultiplier,
            isReadOnly: isReadOnly,
            translucentBackgroundEnabled: translucentBackgroundEnabled,
            showsLineNumbers: showsLineNumbers,
            highlightCurrentLine: highlightCurrentLine,
            lineWrapEnabled: lineWrapEnabled,
            showsInvisibleCharacters: showsInvisibleCharacters,
            showsIndentationGuides: showsIndentationGuides,
            showsScopeGuides: showsScopeGuides,
            highlightsScopeBackground: highlightsScopeBackground,
            highlightsMatchingBrackets: highlightsMatchingBrackets,
            autoIndentEnabled: autoIndentEnabled,
            autoCloseBracketsEnabled: autoCloseBracketsEnabled,
            isSplitPaneResizeInProgress: isSplitPaneResizeInProgress,
            onFontSizeChange: onFontSizeChange,
            onTextMutation: onTextMutation
        )
    }
}

enum VirtualEditorLayoutSizing {
    static let minimumUsableWidth: CGFloat = 90

    static func sizeThatFits(
        proposedWidth: CGFloat?,
        proposedHeight: CGFloat?,
        preferredWidth: CGFloat?
    ) -> CGSize? {
        if let proposedWidth, proposedWidth >= minimumUsableWidth {
            return CGSize(
                width: min(proposedWidth, preferredWidth ?? proposedWidth),
                height: max(proposedHeight ?? 400, 1)
            )
        }
        guard let preferredWidth else { return nil }
        return CGSize(
            width: max(preferredWidth, minimumUsableWidth),
            height: max(proposedHeight ?? 400, 1)
        )
    }
}

enum VirtualEditorViewportGeometry {
    static func stabilizedSize(
        _ candidate: CGSize,
        previous: CGSize,
        minimumUsableWidth: CGFloat
    ) -> CGSize? {
        guard candidate.width < minimumUsableWidth else { return candidate }
        guard previous.width >= minimumUsableWidth else { return nil }
        return CGSize(width: previous.width, height: candidate.height)
    }

    static func visibleSize(
        contentBounds: CGSize,
        scrollViewBounds: CGSize,
        verticalScrollerWidth: CGFloat
    ) -> CGSize {
        // The clip view can retain the document's previous width while SwiftUI
        // has already changed the scroll view allocation. Only trust that
        // width once it agrees with the allocation; otherwise use the current
        // allocation so wrapping catches up after a sidebar closes as well as
        // while one opens. Excluding the vertical scroller also prevents
        // trailing glyphs from being placed underneath it.
        let allocatedContentWidth = max(1, scrollViewBounds.width - verticalScrollerWidth)
        let width: CGFloat
        if contentBounds.width > 1,
           abs(contentBounds.width - allocatedContentWidth) <= 1 {
            width = contentBounds.width
        } else if scrollViewBounds.width > 1 {
            width = allocatedContentWidth
        } else {
            width = contentBounds.width
        }
        let height = scrollViewBounds.height > 1 ? scrollViewBounds.height : contentBounds.height
        return CGSize(
            width: max(width, 1),
            height: max(height, 1)
        )
    }
}

enum VirtualEditorResizePolicy {
    static func shouldReflow(isSplitPaneResizeInProgress: Bool) -> Bool {
        !isSplitPaneResizeInProgress
    }
}

enum VirtualEditorKeyRouting {
    static func shouldInterpretArrow(modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(.command) || modifiers.contains(.control)
    }
}

@MainActor
final class VirtualEditorScrollView: NSScrollView {
    private let canvas = VirtualEditorCanvas()
    private var lastUsableViewportSize = CGSize.zero
    private var isSplitPaneResizeInProgress = false
    private var viewportGeometryRetryCount = 0
    private var isViewportGeometryRetryScheduled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        // The canvas owns the solid fallback fill. Keeping both scroll-view
        // layers clear is required in translucent mode; otherwise AppKit's
        // clip view paints its default white surface behind the canvas.
        MacOverlayScrollerPolicy.configure(self, clearBackground: true)
        borderType = .noBorder
        documentView = canvas
        contentView.postsBoundsChangedNotifications = true
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameDidChange),
            name: NSView.frameDidChangeNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEditorViewportCommand(_:)),
            name: .scrollEditorViewportToFraction,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEditorViewportRequest(_:)),
            name: .requestEditorViewport,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func handleEditorViewportCommand(_ notification: Notification) {
        guard let fraction = notification.userInfo?[EditorCommandUserInfo.viewportTopFraction] as? Double else { return }
        guard let requestedID = notification.userInfo?[EditorCommandUserInfo.documentID] as? String,
              requestedID == canvas.documentIdentifier else { return }
        let maximum = max(0, canvas.logicalHeight - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: CGFloat(min(max(fraction, 0), 1)) * maximum))
        reflectScrolledClipView(contentView)
        canvas.reloadViewportIfNeeded(scrollY: contentView.bounds.minY)
    }

    @objc private func handleEditorViewportRequest(_ notification: Notification) {
        guard let requestedID = notification.userInfo?[EditorCommandUserInfo.documentID] as? String,
              requestedID == canvas.documentIdentifier else { return }
        publishViewport()
    }

    override func magnify(with event: NSEvent) {
        canvas.adjustFontSize(by: event.magnification * 10)
    }

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.shift) else {
            super.scrollWheel(with: event)
            return
        }

        let delta = VirtualEditorWheelZoom.fontSizeDelta(
            scrollingDeltaY: event.scrollingDeltaY,
            fallbackDeltaY: event.deltaY
        )
        guard abs(delta) >= 0.01 else { return }
        canvas.adjustFontSize(by: delta)
    }

    func configure(
        document: (any EditorDocument)?, documentID: UUID?, resourceID: String, contentRevision: Int, externalContentRevision: Int,
        caret: Int?, language: String, colorScheme: ColorScheme, fontSize: CGFloat,
        fontName: String, lineHeightMultiplier: CGFloat,
        isReadOnly: Bool, translucentBackgroundEnabled: Bool, showsLineNumbers: Bool, highlightCurrentLine: Bool,
        lineWrapEnabled: Bool, showsInvisibleCharacters: Bool, showsIndentationGuides: Bool,
        showsScopeGuides: Bool, highlightsScopeBackground: Bool,
        highlightsMatchingBrackets: Bool, autoIndentEnabled: Bool, autoCloseBracketsEnabled: Bool,
        isSplitPaneResizeInProgress: Bool,
        onFontSizeChange: ((CGFloat) -> Void)?, onTextMutation: ((EditorTextMutation) -> Bool)?
    ) {
        self.isSplitPaneResizeInProgress = isSplitPaneResizeInProgress
        hasHorizontalScroller = !lineWrapEnabled
        MacOverlayScrollerPolicy.configure(self, clearBackground: true)
        canvas.configure(
            document: document, documentID: documentID, resourceID: resourceID, contentRevision: contentRevision, externalContentRevision: externalContentRevision,
            caret: caret, language: language, colorScheme: colorScheme,
            fontSize: fontSize, fontName: fontName, lineHeightMultiplier: lineHeightMultiplier,
            isReadOnly: isReadOnly,
            translucentBackgroundEnabled: translucentBackgroundEnabled,
            showsLineNumbers: showsLineNumbers, highlightCurrentLine: highlightCurrentLine,
            lineWrapEnabled: lineWrapEnabled, showsInvisibleCharacters: showsInvisibleCharacters,
            showsIndentationGuides: showsIndentationGuides,
            showsScopeGuides: showsScopeGuides,
            highlightsScopeBackground: highlightsScopeBackground,
            highlightsMatchingBrackets: highlightsMatchingBrackets,
            autoIndentEnabled: autoIndentEnabled,
            autoCloseBracketsEnabled: autoCloseBracketsEnabled,
            onFontSizeChange: onFontSizeChange, onTextMutation: onTextMutation
        )
        if let documentID {
            EditorPerformanceMonitor.shared.markSwiftUIEditorUpdated(tabID: documentID)
        }
        if VirtualEditorResizePolicy.shouldReflow(isSplitPaneResizeInProgress: isSplitPaneResizeInProgress) {
            updateCanvasGeometry()
        }
    }

    override func layout() {
        super.layout()
        updateCanvasGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        // SwiftUI can replace the surrounding hierarchy (for example when a
        // workspace mode hides every sidebar) before the scroll view receives
        // its final bounds. Restart the bounded retry budget at the AppKit
        // attachment point so the canvas is remeasured after that layout pass.
        viewportGeometryRetryCount = 0
        scheduleViewportGeometryRetry()
    }

    private func updateCanvasGeometry() {
        guard VirtualEditorResizePolicy.shouldReflow(isSplitPaneResizeInProgress: isSplitPaneResizeInProgress) else {
            return
        }
        guard let viewportSize = visibleViewportSize else {
            scheduleViewportGeometryRetry()
            return
        }
        viewportGeometryRetryCount = 0
        let didResize = canvas.setViewportSize(viewportSize)
        guard didResize || canvas.frame.width <= 1 else { return }
        canvas.recalculateVisualMetrics()
        canvas.setFrameSize(NSSize(width: canvas.contentWidth, height: canvas.logicalHeight))
    }

    private var visibleViewportSize: CGSize? {
        let candidate = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: contentView.bounds.size,
            scrollViewBounds: bounds.size,
            verticalScrollerWidth: scrollerStyle == .overlay
                ? 0
                : (verticalScroller?.frame.width ?? 0)
        )
        let stabilized = VirtualEditorViewportGeometry.stabilizedSize(
            candidate,
            previous: lastUsableViewportSize,
            minimumUsableWidth: canvas.minimumUsableViewportWidth
        )
        if stabilized != nil, candidate.width >= canvas.minimumUsableViewportWidth {
            lastUsableViewportSize = candidate
        }
        return stabilized
    }

    private func scheduleViewportGeometryRetry() {
        guard !isViewportGeometryRetryScheduled, viewportGeometryRetryCount < 3 else { return }
        isViewportGeometryRetryScheduled = true
        viewportGeometryRetryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            self.isViewportGeometryRetryScheduled = false
            self.updateCanvasGeometry()
        }
    }

    @objc private func frameDidChange() {
        updateCanvasGeometry()
    }

    @objc private func boundsDidChange() {
        let scrollY = contentView.bounds.minY
        let didScroll = abs(scrollY - canvas.lastScrollY) >= 0.5
        let didResize: Bool
        if VirtualEditorResizePolicy.shouldReflow(isSplitPaneResizeInProgress: isSplitPaneResizeInProgress),
           let viewportSize = visibleViewportSize {
            viewportGeometryRetryCount = 0
            didResize = canvas.setViewportSize(viewportSize)
        } else {
            scheduleViewportGeometryRetry()
            didResize = false
        }
        guard didScroll || didResize else { return }
        canvas.lastScrollY = scrollY
        let previousViewportOrigin = canvas.viewportLineOrigin
        canvas.reloadViewportIfNeeded(scrollY: scrollY)
        let didReloadViewport = previousViewportOrigin != canvas.viewportLineOrigin
        if didReloadViewport || didResize {
            canvas.recalculateVisualMetrics()
            canvas.setFrameSize(NSSize(width: canvas.contentWidth, height: canvas.logicalHeight))
            canvas.lastReloadAnchorLine = canvas.viewportLineOrigin
        }
        // A bounded viewport replacement invalidates the canvas while the clip
        // view is scrolling. Let AppKit coalesce the redraw with its normal
        // layout transaction instead of forcing synchronous layout and display
        // work into the scroll callback.
        canvas.needsLayout = true
        canvas.needsDisplay = true
        reflectScrolledClipView(contentView)
        publishViewport()
    }

    private func publishViewport() {
        let maximum = max(1, canvas.logicalHeight - contentView.bounds.height)
        NotificationCenter.default.post(
            name: .editorViewportDidChange,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.documentID: canvas.documentIdentifier as Any,
                EditorCommandUserInfo.viewportTopFraction: Double(contentView.bounds.minY / maximum),
                EditorCommandUserInfo.viewportHeightFraction: Double(contentView.bounds.height / max(1, canvas.logicalHeight))
            ]
        )
    }
}

@MainActor
final class VirtualEditorCanvas: NSView, NSTextInputClient {
    private var document: (any EditorDocument)?
    private var documentID: UUID?
    private var resourceID = ""
    private var language = "plain"
    private var scheme: ColorScheme = .light
    private var editorFontSize: CGFloat = 14
    private var editorFontName = ""
    private var lineHeightMultiplier: CGFloat = 1
    private var resolvedEditorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private var isReadOnly = false
    private var translucentBackgroundEnabled = false
    private var showsLineNumbers = true
    private var highlightCurrentLine = false
    private var lineWrapEnabled = true
    private var showsInvisibleCharacters = false
    private var showsIndentationGuides = false
    private var showsScopeGuides = false
    private var highlightsScopeBackground = false
    private var highlightsMatchingBrackets = false
    private var autoIndentEnabled = true
    private var autoCloseBracketsEnabled = false
    private var onFontSizeChange: ((CGFloat) -> Void)?
    private var onTextMutation: ((EditorTextMutation) -> Bool)?
    private var pendingFontSizeDelta: CGFloat = 0
    private var viewport: EditorDocumentViewport?
    private var viewportText = ""
    private var lineStarts: [Int] = [0]
    var viewportLineOrigin = 0
    private var absoluteCaret = 0
    private var selection = NSRange(location: 0, length: 0)
    private var markedText: String?
    private var markedTextRange = NSRange(location: NSNotFound, length: 0)
    private var markedTextSelectedRange = NSRange(location: 0, length: 0)
    private var selectionAnchor: Int?
    private let documentUndoManager = UndoManager()
    private var lastConfigurationKey = ""
    private var layoutCache: [Int: CTLine] = [:]
    private var attributedLineCache: [Int: NSAttributedString] = [:]
    private var visualFragmentCache = VirtualEditorVisualFragmentCache()
    private var visibleColors: [NSRange: NSColor] = [:]
    private var viewportSize: CGSize = .zero {
        didSet {
            guard viewportSize != oldValue else { return }
            visualFragmentCache.removeAll(keepingCapacity: true)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var lastScrollY: CGFloat = -1
    var lastReloadAnchorLine = -1
    private var estimatedRowsPerLogicalLine: CGFloat = 1
    private var lineHeight: CGFloat { max(1, (editorFont.ascender - editorFont.descender + editorFont.leading + 4) * lineHeightMultiplier) }
    private var editorFont: NSFont { resolvedEditorFont }
    private var gutterWidth: CGFloat { max(44, CGFloat(max(1, document?.lineCount ?? 1).description.count) * editorFontSize * 0.7 + 18) }
    var minimumUsableViewportWidth: CGFloat {
        let characterWidth = ("m" as NSString).size(withAttributes: [.font: editorFont]).width
        return gutterWidth + 16 + characterWidth * 4
    }
    private var visualRowIndex: VirtualEditorVisualRowIndex {
        VirtualEditorVisualRowIndex(logicalLineCount: document?.lineCount ?? 1, estimatedRowsPerLogicalLine: estimatedRowsPerLogicalLine)
    }
    var logicalHeight: CGFloat { CGFloat(visualRowIndex.estimatedRowCount) * lineHeight + 16 }
    private(set) var contentWidth: CGFloat = 1
    var documentIdentifier: String? { documentID?.uuidString }

    @discardableResult
    func setViewportSize(_ size: CGSize) -> Bool {
        guard viewportSize != size else { return false }
        viewportSize = size
        return true
    }

    func recalculateVisualMetrics() {
        guard lineWrapEnabled, !viewportText.isEmpty else {
            estimatedRowsPerLogicalLine = 1
            contentWidth = max(viewportSize.width, 1)
            if !lineWrapEnabled { contentWidth = unwrappedContentWidth() }
            return
        }
        let rows = visualRows()
        let logicalLines = max(1, lineStarts.count - 1)
        let observed = CGFloat(max(1, rows.count)) / CGFloat(logicalLines)
        if abs(observed - estimatedRowsPerLogicalLine) > 0.05 {
            estimatedRowsPerLogicalLine = VirtualEditorVisualRowIndex.smoothedEstimate(
                previous: estimatedRowsPerLogicalLine,
                observed: observed
            )
        }
        contentWidth = max(viewportSize.width, 1)
        invalidateIntrinsicContentSize()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { documentUndoManager }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { "Editor" }
    override func accessibilityValue() -> Any? { viewportText }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(self, selector: #selector(moveToLine(_:)), name: .moveCursorToLine, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moveToRange(_:)), name: .moveCursorToRange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(replaceRange(_:)), name: .replaceEditorRangeRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moveSelectedLines(_:)), name: .moveSelectedLinesRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(insertBracketHelperToken(_:)), name: .insertBracketHelperTokenRequested, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func moveToLine(_ notification: Notification) {
        guard matchesDocument(notification), let line = notification.object as? Int else { return }
        let targetLine = max(0, line - 1)
        reloadViewport(anchorLine: targetLine)
        let localLine = targetLine - viewportLineOrigin
        guard lineStarts.indices.contains(localLine) else { return }
        absoluteCaret = viewportLineOriginStartUTF16 + lineStarts[localLine]
        selection = NSRange(location: absoluteCaret, length: 0)
        selectionAnchor = nil
        recalculateVisualMetrics()
        setFrameSize(NSSize(width: contentWidth, height: logicalHeight))
        // The target line is known even when it is outside the currently
        // rendered rows. Do not call ensureCaretVisible here: caretPoint()
        // intentionally falls back to the top when the row is not rendered,
        // which would undo this exact-line scroll and spring back to line 1.
        ensureLineVisible(targetLine)
        publishCaret()
        needsDisplay = true
    }

    @objc private func moveToRange(_ notification: Notification) {
        guard matchesDocument(notification),
              let location = notification.userInfo?[EditorCommandUserInfo.rangeLocation] as? Int,
              let length = notification.userInfo?[EditorCommandUserInfo.rangeLength] as? Int else { return }
        let line = max(0, lineForAbsoluteOffset(location))
        reloadViewport(anchorLine: line)
        absoluteCaret = max(0, min(document?.utf16Length ?? location, location))
        selection = NSRange(location: absoluteCaret, length: max(0, min(length, (document?.utf16Length ?? absoluteCaret) - absoluteCaret)))
        selectionAnchor = absoluteCaret
        ensureCaretVisible()
        publishCaret()
        needsDisplay = true
    }

    @objc private func moveSelectedLines(_ notification: Notification) {
        guard matchesDocument(notification),
              let rawDirection = notification.object as? String,
              let direction = EditorLineMoveDirection(rawValue: rawDirection),
              let documentID,
              let viewport,
              !isReadOnly else { return }
        let viewportRange = NSRange(location: viewport.startUTF16Offset, length: viewport.text.utf16.count)
        guard NSLocationInRange(selection.location, viewportRange),
              NSMaxRange(selection) <= NSMaxRange(viewportRange) else { return }
        let localSelection = NSRange(
            location: selection.location - viewport.startUTF16Offset,
            length: selection.length
        )
        guard let result = editorLineMove(in: viewport.text, selectedRange: localSelection, direction: direction) else { return }
        let absoluteSelection = NSRange(
            location: viewport.startUTF16Offset + result.selectedRange.location,
            length: result.selectedRange.length
        )
        guard onTextMutation?(EditorTextMutation(
            documentID: documentID,
            range: result.replacementRange,
            replacement: result.replacement,
            viewport: viewport
        )) == true else { return }
        selection = absoluteSelection
        absoluteCaret = NSMaxRange(absoluteSelection)
        selectionAnchor = absoluteSelection.location
        reloadViewport(anchorLine: lineForAbsoluteOffset(absoluteCaret))
        ensureCaretVisible()
        publishCaret()
        needsDisplay = true
    }

    @objc private func replaceRange(_ notification: Notification) {
        guard matchesDocument(notification),
              let documentID,
              let location = notification.userInfo?[EditorCommandUserInfo.rangeLocation] as? Int,
              let length = notification.userInfo?[EditorCommandUserInfo.rangeLength] as? Int,
              let replacement = notification.userInfo?[EditorCommandUserInfo.replacementText] as? String,
              !isReadOnly else { return }
        let boundedLocation = max(0, min(document?.utf16Length ?? location, location))
        let boundedLength = max(0, min(length, (document?.utf16Length ?? boundedLocation) - boundedLocation))
        reloadViewport(anchorLine: lineForAbsoluteOffset(boundedLocation))
        guard let viewport else { return }
        guard boundedLocation >= viewport.startUTF16Offset,
              boundedLocation + boundedLength <= viewport.startUTF16Offset + viewport.text.utf16.count else {
            guard onTextMutation?(EditorTextMutation(
                documentID: documentID,
                range: NSRange(location: boundedLocation, length: boundedLength),
                replacement: replacement
            )) == true else {
                reloadViewport(anchorLine: viewport.lineRange.lowerBound)
                return
            }
            absoluteCaret = boundedLocation + replacement.utf16.count
            selection = NSRange(location: absoluteCaret, length: 0)
            reloadViewport(anchorLine: lineForAbsoluteOffset(absoluteCaret))
            publishCaret()
            return
        }
        selection = NSRange(location: boundedLocation, length: boundedLength)
        absoluteCaret = boundedLocation
        replaceSelection(with: replacement)
    }

    @objc private func insertBracketHelperToken(_ notification: Notification) {
        guard matchesDocument(notification),
              let token = notification.userInfo?[EditorCommandUserInfo.bracketToken] as? String,
              !token.isEmpty,
              !isReadOnly else { return }
        replaceSelection(with: token)
    }

    private func matchesDocument(_ notification: Notification) -> Bool {
        if let requestedWindow = notification.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
           window?.windowNumber != requestedWindow {
            return false
        }
        guard let requestedID = notification.userInfo?[EditorCommandUserInfo.documentID] as? String else { return true }
        return requestedID == documentIdentifier
    }

    private func newlineCount(inUTF16PrefixOf text: String, length: Int) -> Int {
        let nsText = text as NSString
        let safeLength = min(max(0, length), nsText.length)
        var count = 0
        for index in 0..<safeLength where nsText.character(at: index) == 10 {
            count += 1
        }
        return count
    }

    private func lineForAbsoluteOffset(_ offset: Int) -> Int {
        guard let document else { return 0 }
        if offset >= viewportLineOriginStartUTF16 && offset <= viewportLineOriginStartUTF16 + viewportText.utf16.count {
            return viewportLineOrigin + newlineCount(inUTF16PrefixOf: viewportText, length: offset - viewportLineOriginStartUTF16)
        }
        return min(document.lineCount - 1, max(0, Int(Double(offset) / Double(max(1, document.utf16Length)) * Double(document.lineCount))))
    }

    func configure(
        document: (any EditorDocument)?, documentID: UUID?, resourceID: String, contentRevision: Int, externalContentRevision: Int,
        caret: Int?, language: String, colorScheme: ColorScheme, fontSize: CGFloat,
        fontName: String, lineHeightMultiplier: CGFloat,
        isReadOnly: Bool, translucentBackgroundEnabled: Bool, showsLineNumbers: Bool, highlightCurrentLine: Bool,
        lineWrapEnabled: Bool, showsInvisibleCharacters: Bool, showsIndentationGuides: Bool,
        showsScopeGuides: Bool, highlightsScopeBackground: Bool,
        highlightsMatchingBrackets: Bool, autoIndentEnabled: Bool, autoCloseBracketsEnabled: Bool,
        onFontSizeChange: ((CGFloat) -> Void)?, onTextMutation: ((EditorTextMutation) -> Bool)?
    ) {
        let previousResourceID = self.resourceID
        let previousDocumentID = self.documentID
        let isNewDocument = previousResourceID != resourceID || previousDocumentID != documentID
        let key = "\(resourceID)|\(contentRevision)|\(externalContentRevision)|\(document?.utf16Length ?? 0)|\(language)|\(fontSize)|\(fontName)|\(lineHeightMultiplier)|\(colorScheme)|\(syntaxThemeKey(for: colorScheme))|\(document?.isDirty ?? false)|\(showsLineNumbers)|\(highlightCurrentLine)|\(lineWrapEnabled)|\(showsInvisibleCharacters)|\(showsIndentationGuides)|\(showsScopeGuides)|\(highlightsScopeBackground)|\(highlightsMatchingBrackets)|\(autoIndentEnabled)|\(autoCloseBracketsEnabled)"
        self.document = document
        self.documentID = documentID
        self.resourceID = resourceID
        self.language = language
        self.scheme = colorScheme
        self.editorFontName = fontName
        resolvedEditorFont = fontName.isEmpty
            ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : (NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular))
        self.lineHeightMultiplier = lineHeightMultiplier
        self.isReadOnly = isReadOnly
        self.translucentBackgroundEnabled = translucentBackgroundEnabled
        self.showsLineNumbers = showsLineNumbers
        self.highlightCurrentLine = highlightCurrentLine
        self.lineWrapEnabled = lineWrapEnabled
        self.showsInvisibleCharacters = showsInvisibleCharacters
        self.showsIndentationGuides = showsIndentationGuides
        self.showsScopeGuides = showsScopeGuides
        self.highlightsScopeBackground = highlightsScopeBackground
        self.highlightsMatchingBrackets = highlightsMatchingBrackets
        self.autoIndentEnabled = autoIndentEnabled
        self.autoCloseBracketsEnabled = autoCloseBracketsEnabled
        self.onFontSizeChange = onFontSizeChange
        self.onTextMutation = onTextMutation
        if abs(editorFontSize - fontSize) > 0.01 {
            editorFontSize = fontSize
            pendingFontSizeDelta = 0
            layoutCache.removeAll()
        }
        guard key != lastConfigurationKey else { return }
        lastConfigurationKey = key
        viewport = nil
        viewportText = ""
        lineStarts = [0]
        layoutCache.removeAll()
        attributedLineCache.removeAll()
        visualFragmentCache.removeAll()
        if isNewDocument {
            absoluteCaret = min(max(0, caret ?? 0), document?.utf16Length ?? 0)
            selection = NSRange(location: absoluteCaret, length: 0)
            selectionAnchor = nil
        } else {
            let documentLength = document?.utf16Length ?? absoluteCaret
            absoluteCaret = min(max(0, absoluteCaret), documentLength)
            let selectionLocation = min(max(0, selection.location), documentLength)
            let selectionLength = min(max(0, selection.length), documentLength - selectionLocation)
            selection = NSRange(location: selectionLocation, length: selectionLength)
        }
        reloadViewport(anchorLine: lineForAbsoluteOffset(absoluteCaret))
        recalculateVisualMetrics()
        setFrameSize(NSSize(width: contentWidth, height: logicalHeight))
        needsDisplay = true
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }

    override func draw(_ dirtyRect: NSRect) {
        if let documentID {
            EditorPerformanceMonitor.shared.markTabSwitchFirstDraw(tabID: documentID)
        }
        if !translucentBackgroundEnabled {
            let modeRaw = UserDefaults.standard.string(forKey: "SettingsMacTranslucencyMode") ?? "balanced"
            ContentView.MacEditorSurfacePolicy.windowBackground(
                translucent: false,
                modeRaw: modeRaw,
                isDarkMode: scheme == .dark
            ).setFill()
            dirtyRect.fill()
        }
        guard !lineStarts.isEmpty else { return }
        let dark = scheme == .dark
        let rows = visualRows()
        drawCurrentLineHighlight(rows: rows)
        drawSelectionBackground(rows: rows)
        for row in rows where row.baseline + lineHeight >= dirtyRect.minY && row.baseline <= dirtyRect.maxY {
            let context = NSGraphicsContext.current!.cgContext
            context.saveGState()
            if showsLineNumbers, row.isFirstFragment {
                let lineNumber = "\(row.logicalLine + 1)" as NSString
                let numberWidth = lineNumber.size(withAttributes: [.font: editorFont]).width
                lineNumber.draw(at: NSPoint(
                    x: gutterWidth - numberWidth - 8,
                    y: row.baseline - editorFont.ascender
                ), withAttributes: [.font: editorFont, .foregroundColor: NSColor.secondaryLabelColor])
            }
            context.textPosition = CGPoint(x: gutterWidth + 8, y: row.baseline)
            CTLineDraw(row.fragment.line, context)
            context.restoreGState()
            drawWhitespaceAndIndentationDecorations(for: row, dark: dark)
        }
        drawMarkedText(rows: rows)
        drawCaret(rows: rows)
    }

    private func drawMarkedText(rows: [VisualRow]) {
        guard let markedText, markedTextRange.location != NSNotFound else { return }
        let start = markedTextRange.location - viewportLineOriginStartUTF16
        guard start >= 0, start <= viewportText.utf16.count else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: editorFont,
            .foregroundColor: NSColor.textColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.controlAccentColor
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: markedText, attributes: attributes))
        let point = caretPoint(localLocation: start)
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.textPosition = CGPoint(x: point.x, y: point.y)
        CTLineDraw(line, context!)
        context?.restoreGState()
    }

    private func drawWhitespaceAndIndentationDecorations(for row: VisualRow, dark: Bool) {
        guard showsInvisibleCharacters || showsIndentationGuides else { return }
        let start = row.fragment.absoluteStartUTF16
        let length = min(row.fragment.lengthUTF16, max(0, viewportText.utf16.count - start))
        let line = (viewportText as NSString).substring(with: NSRange(location: start, length: length))
        let baseline = row.baseline
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let markerColor = (dark ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).withAlphaComponent(0.45)
        let characterWidth = ("m" as NSString).size(withAttributes: [.font: editorFont]).width
        let originX = gutterWidth + 8
        var column = 0
        for character in leadingWhitespace {
            let x = originX + CGFloat(column) * characterWidth
            if showsIndentationGuides, character == " " {
                markerColor.setFill()
                NSRect(x: x + characterWidth * 0.5, y: baseline - lineHeight + 3, width: 1, height: lineHeight - 5).fill()
            }
            if showsInvisibleCharacters {
                let marker = character == "\t" ? "⇥" : "·"
                (marker as NSString).draw(
                    at: NSPoint(x: x, y: baseline),
                    withAttributes: [.font: editorFont, .foregroundColor: markerColor]
                )
            }
            column += character == "\t" ? 4 : 1
        }
        guard showsInvisibleCharacters else { return }
        for (offset, character) in line.enumerated() where character == "\t" {
            if offset >= leadingWhitespace.count {
                ("⇥" as NSString).draw(
                    at: NSPoint(x: originX + CGFloat(offset) * characterWidth, y: baseline),
                    withAttributes: [.font: editorFont, .foregroundColor: markerColor]
                )
            }
        }
    }

    private func cachedLine(_ attributed: NSAttributedString, for line: Int) -> CTLine {
        if let cached = layoutCache[line] { return cached }
        let created = CTLineCreateWithAttributedString(attributed)
        layoutCache[line] = created
        if layoutCache.count > 700 {
            layoutCache.removeAll(keepingCapacity: true)
        }
        return created
    }

    struct VisualRow {
        let logicalLine: Int
        let localStart: Int
        let fragment: VirtualEditorVisualFragment
        let baseline: CGFloat
        let isFirstFragment: Bool
    }

    private func visualRows() -> [VisualRow] {
        // `bounds.width` is the document canvas width. During an AppKit resize
        // it still contains the previous pane allocation until after visual
        // metrics have been recalculated. The viewport is the current editor
        // allocation and is therefore the authoritative wrapping width.
        let availableWidth = max(1, viewportSize.width - gutterWidth - 16)
        var rows: [VisualRow] = []
        var baseline = VirtualEditorVisualLayout.baseline(
            rowOrigin: visualRowIndex.rowOrigin(forLogicalLine: viewportLineOrigin),
            lineHeight: lineHeight,
            fontAscender: editorFont.ascender
        )
        for localLine in lineStarts.indices {
            let estimatedBaseline = baseline
            let viewportMaxY = bounds.maxY + lineHeight * 2
            if estimatedBaseline > viewportMaxY {
                break
            }
            let start = lineStarts[localLine]
            let end = localLine + 1 < lineStarts.count ? lineStarts[localLine + 1] : viewportText.utf16.count
            let text = (viewportText as NSString)
                .substring(with: NSRange(location: start, length: max(0, end - start)))
                .trimmingCharacters(in: .newlines)
            let fragments = cachedVisualFragments(
                for: text,
                localLine: localLine,
                absoluteStart: start,
                width: availableWidth,
                dark: scheme == .dark
            )
            for (index, fragment) in fragments.enumerated() {
                rows.append(VisualRow(
                    logicalLine: viewportLineOrigin + localLine,
                    localStart: start,
                    fragment: fragment,
                    baseline: baseline,
                    isFirstFragment: index == 0
                ))
                baseline += lineHeight
            }
        }
        return rows
    }

    private func attributedLine(_ line: String, absoluteStart: Int, dark: Bool) -> NSAttributedString {
        let base = NSMutableAttributedString(string: line, attributes: [
            .font: editorFont,
            .foregroundColor: dark ? NSColor.textColor : NSColor.textColor
        ])
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard range.length > 0 else { return base }
        let theme = currentEditorTheme(colorScheme: scheme)
        let colors = SyntaxColors.from(theme: theme)
        for (pattern, color) in getSyntaxPatterns(for: language, colors: colors) {
            guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            for match in regex.matches(in: line, range: range) {
                base.addAttribute(.foregroundColor, value: NSColor(color), range: match.range)
            }
        }
        return base
    }

    private func cachedAttributedLine(
        _ line: String,
        localLine: Int,
        absoluteStart: Int,
        dark: Bool
    ) -> NSAttributedString {
        if let cached = attributedLineCache[localLine] {
            return cached
        }
        let created = attributedLine(line, absoluteStart: absoluteStart, dark: dark)
        attributedLineCache[localLine] = created
        return created
    }

    private func cachedVisualFragments(
        for line: String,
        localLine: Int,
        absoluteStart: Int,
        width: CGFloat,
        dark: Bool
    ) -> [VirtualEditorVisualFragment] {
        visualFragmentCache.fragments(
            for: cachedAttributedLine(
                line,
                localLine: localLine,
                absoluteStart: absoluteStart,
                dark: dark
            ),
            localLine: localLine,
            lineStartUTF16: absoluteStart,
            width: width,
            wraps: lineWrapEnabled
        )
    }

    func visualRow(containing localLocation: Int, in rows: [VisualRow]) -> VisualRow? {
        guard !rows.isEmpty else { return nil }

        // visualRows() is ordered by fragment start, so find the last row whose
        // start is at or before the location instead of scanning every row.
        var lower = 0
        var upper = rows.count
        while lower < upper {
            let midpoint = (lower + upper) / 2
            if rows[midpoint].fragment.absoluteStartUTF16 <= localLocation {
                lower = midpoint + 1
            } else {
                upper = midpoint
            }
        }
        let index = lower - 1
        guard rows.indices.contains(index) else { return nil }

        let row = rows[index]
        let start = row.fragment.absoluteStartUTF16
        let end = start + row.fragment.lengthUTF16
        guard localLocation >= start,
              (localLocation < end || ownsVisualRowEndpoint(
                  localLocation,
                  rowIndex: index,
                  end: end,
                  rows: rows
              )) else { return nil }
        return row
    }

    private func ownsVisualRowEndpoint(
        _ localLocation: Int,
        rowIndex: Int,
        end: Int,
        rows: [VisualRow]
    ) -> Bool {
        guard localLocation == end else { return false }
        return rowIndex == rows.count - 1 ||
            rows[rowIndex + 1].fragment.absoluteStartUTF16 > localLocation
    }

    private func syntaxThemeKey(for colorScheme: ColorScheme) -> String {
        let syntax = currentEditorTheme(colorScheme: colorScheme).syntax
        return [
            syntax.keyword, syntax.string, syntax.number, syntax.comment, syntax.attribute,
            syntax.variable, syntax.def, syntax.property, syntax.meta, syntax.tag,
            syntax.atom, syntax.builtin, syntax.type
        ].map { NSColor($0).description }.joined(separator: "|")
    }

    private func drawCurrentLineHighlight(rows: [VisualRow]) {
        guard highlightCurrentLine else { return }
        let local = absoluteCaret - viewportLineOriginStartUTF16
        guard let row = visualRow(containing: local, in: rows) else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        NSRect(x: gutterWidth, y: row.baseline - lineHeight + 2, width: max(0, bounds.width - gutterWidth), height: lineHeight).fill()
    }

    private func drawSelectionBackground(rows: [VisualRow]) {
        guard selection.length > 0 else { return }
        let selectedStart = selection.location - viewportLineOriginStartUTF16
        let selectedEnd = NSMaxRange(selection) - viewportLineOriginStartUTF16
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        for row in rows {
            let start = row.fragment.absoluteStartUTF16
            let end = start + row.fragment.lengthUTF16
            let left = max(start, selectedStart)
            let right = min(end, selectedEnd)
            guard left < right else { continue }
            let x = CGFloat(CTLineGetOffsetForStringIndex(row.fragment.line, left - start, nil))
            let rightX = CGFloat(CTLineGetOffsetForStringIndex(row.fragment.line, right - start, nil))
            NSRect(x: gutterWidth + 8 + x, y: row.baseline - lineHeight + 2, width: max(2, rightX - x), height: lineHeight).fill()
        }
    }

    private func drawCaret(rows: [VisualRow]) {
        guard selection.length == 0 else { return }
        let local = absoluteCaret - viewportLineOriginStartUTF16
        guard let row = visualRow(containing: local, in: rows) else { return }
        let x = CGFloat(CTLineGetOffsetForStringIndex(row.fragment.line, local - row.fragment.absoluteStartUTF16, nil))
        NSColor.controlAccentColor.setFill()
        NSRect(x: gutterWidth + 8 + x, y: row.baseline - lineHeight + 2, width: 1.5, height: lineHeight).fill()
    }

    private var viewportLineOriginStartUTF16: Int { viewport?.startUTF16Offset ?? 0 }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        absoluteCaret = documentOffset(at: point)
        selection = NSRange(location: absoluteCaret, length: 0)
        selectionAnchor = absoluteCaret
        publishCaret()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let selectionAnchor else { return }
        let caret = documentOffset(at: convert(event.locationInWindow, from: nil))
        absoluteCaret = caret
        selection = NSRange(location: min(selectionAnchor, caret), length: abs(selectionAnchor - caret))
        publishCaret()
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        adjustFontSize(by: event.magnification * 10)
    }

    fileprivate func adjustFontSize(by delta: CGFloat) {
        guard abs(delta) >= 0.01 else { return }
        pendingFontSizeDelta += delta
        let next = min(28, max(10, (editorFontSize + pendingFontSizeDelta).rounded()))
        guard next != editorFontSize else { return }
        pendingFontSizeDelta = 0
        onFontSizeChange?(next)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if VirtualEditorKeyRouting.shouldInterpretArrow(modifiers: modifiers) {
            interpretKeyEvents([event])
            return
        }
        let extending = event.modifierFlags.contains(.shift)
        let byWord = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case 123: moveCaret(byWord ? wordBoundary(from: absoluteCaret, direction: -1) - absoluteCaret : -1, extending: extending)
        case 124: moveCaret(byWord ? wordBoundary(from: absoluteCaret, direction: 1) - absoluteCaret : 1, extending: extending)
        case 125: moveCaretVertically(1, extending: extending)
        case 126: moveCaretVertically(-1, extending: extending)
        default: interpretKeyEvents([event])
        }
    }

    private func wordBoundary(from position: Int, direction: Int) -> Int {
        let local = max(0, min(viewportText.utf16.count, position - viewportLineOriginStartUTF16))
        let units = Array(viewportText.utf16)
        guard !units.isEmpty else { return position }
        var cursor = local
        let isWord: (UInt16) -> Bool = { unit in
            (48...57).contains(unit) || (65...90).contains(unit) || (97...122).contains(unit) || unit == 95
        }
        if direction < 0 {
            while cursor > 0 && !isWord(units[cursor - 1]) { cursor -= 1 }
            while cursor > 0 && isWord(units[cursor - 1]) { cursor -= 1 }
        } else {
            while cursor < units.count && !isWord(units[cursor]) { cursor += 1 }
            while cursor < units.count && isWord(units[cursor]) { cursor += 1 }
        }
        return viewportLineOriginStartUTF16 + cursor
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard !isReadOnly else { return }
        let value = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        guard !value.isEmpty else { return }
        if markedTextRange.location != NSNotFound {
            selection = markedTextRange
            absoluteCaret = markedTextRange.location
            markedText = nil
            markedTextRange = NSRange(location: NSNotFound, length: 0)
        } else if replacementRange.location != NSNotFound, replacementRange.length > 0 {
            selection = replacementRange
            absoluteCaret = replacementRange.location
        }
        if let pair = autoClosingPair(for: value) {
            replaceSelection(with: pair)
            absoluteCaret = max(0, absoluteCaret - 1)
            selection = NSRange(location: absoluteCaret, length: 0)
            publishCaret()
            needsDisplay = true
        } else if shouldSkipClosingDelimiter(value) {
            moveCaret(1, extending: false)
        } else {
            replaceSelection(with: value)
        }
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(deleteBackward(_:)): deleteBackward()
        case #selector(deleteForward(_:)): deleteForward()
        case #selector(insertNewline(_:)): insertNewline()
        case #selector(moveLeft(_:)): moveCaret(-1, extending: false)
        case #selector(moveRight(_:)): moveCaret(1, extending: false)
        case #selector(moveUp(_:)): moveCaretVertically(-1, extending: false)
        case #selector(moveDown(_:)): moveCaretVertically(1, extending: false)
        case #selector(copy(_:)): copySelection()
        case #selector(cut(_:)): cutSelection()
        case #selector(paste(_:)): pasteSelection()
        case #selector(selectAll(_:)): selectAllContent()
        case #selector(cancelOperation(_:)): unmarkText()
        default: super.doCommand(by: selector)
        }
    }

    @objc func cut(_ sender: Any?) { cutSelection() }
    @objc func copy(_ sender: Any?) { copySelection() }
    @objc func paste(_ sender: Any?) { pasteSelection() }
    override func selectAll(_ sender: Any?) { selectAllContent() }
    @objc func undo(_ sender: Any?) { documentUndoManager.undo() }
    @objc func redo(_ sender: Any?) { documentUndoManager.redo() }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        markedTextRange = NSRange(location: absoluteCaret, length: markedText?.utf16.count ?? 0)
        if selectedRange.location != NSNotFound {
            markedTextSelectedRange = selectedRange
            absoluteCaret = markedTextRange.location + min(selectedRange.location, markedTextRange.length)
        }
        needsDisplay = true
    }
    func unmarkText() {
        markedText = nil
        markedTextRange = NSRange(location: NSNotFound, length: 0)
        needsDisplay = true
    }
    func hasMarkedText() -> Bool { markedText != nil }
    func selectedRange() -> NSRange { selection }
    func markedRange() -> NSRange { markedTextRange }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .underlineColor, .foregroundColor, .backgroundColor]
    }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let document else { return nil }
        let documentLength = document.utf16Length
        let location = min(max(0, range.location), documentLength)
        let length = min(max(0, range.length), documentLength - location)
        let requested = NSRange(location: location, length: length)
        guard let viewport,
              location >= viewport.startUTF16Offset,
              NSMaxRange(requested) <= viewport.startUTF16Offset + viewport.text.utf16.count else {
            return nil
        }
        let local = NSRange(location: location - viewport.startUTF16Offset, length: length)
        actualRange?.pointee = requested
        return NSAttributedString(
            string: (viewport.text as NSString).substring(with: local),
            attributes: [.font: editorFont, .foregroundColor: NSColor.textColor]
        )
    }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let localLocation = max(0, min(viewportText.utf16.count, range.location - viewportLineOriginStartUTF16))
        actualRange?.pointee = NSRange(location: viewportLineOriginStartUTF16 + localLocation, length: 0)
        let localRect = NSRect(origin: caretPoint(localLocation: localLocation), size: .zero)
        return window.convertToScreen(convert(localRect, to: nil))
    }
    func characterIndex(for point: NSPoint) -> Int { documentOffset(at: convert(point, from: nil)) }

    private func replaceSelection(with value: String) {
        guard let document, let documentID else { return }
        let selectionEnd = NSMaxRange(selection)
        let viewportContainsSelection = viewport != nil &&
            selection.location >= viewportStartUTF16 &&
            selectionEnd <= viewportStartUTF16 + viewportText.utf16.count
        guard viewportContainsSelection else {
            let source = document.string() as NSString
            let location = min(max(0, selection.location), source.length)
            let length = min(max(0, selection.length), source.length - location)
            let original = source.substring(with: NSRange(location: location, length: length))
            guard onTextMutation?(EditorTextMutation(documentID: documentID, range: NSRange(location: location, length: length), replacement: value)) == true else { return }
            registerUndo(replacement: original, range: NSRange(location: location, length: value.utf16.count), inverseReplacement: value)
            absoluteCaret = location + value.utf16.count
            selection = NSRange(location: absoluteCaret, length: 0)
            selectionAnchor = nil
            reloadViewport(anchorLine: lineForAbsoluteOffset(absoluteCaret))
            publishCaret()
            publishTextChange()
            return
        }
        guard let viewport else { return }
        let local = max(0, min(selection.location - viewportStartUTF16, viewportText.utf16.count))
        let length = min(selection.length, max(0, viewportText.utf16.count - local))
        let range = NSRange(location: local, length: length)
        let original = (viewportText as NSString).substring(with: range)
        let absoluteRange = NSRange(location: selection.location, length: length)
        guard onTextMutation?(EditorTextMutation(documentID: documentID, range: range, replacement: value, viewport: viewport)) == true else {
            reloadViewport(anchorLine: viewportLineOrigin)
            return
        }
        registerUndo(
            replacement: original,
            range: NSRange(location: absoluteRange.location, length: value.utf16.count),
            inverseReplacement: value
        )
        absoluteCaret = selection.location + value.utf16.count
        selection = NSRange(location: absoluteCaret, length: 0)
        selectionAnchor = nil
        reloadViewport(anchorLine: viewportLineOrigin)
        _ = document
        publishCaret()
        publishTextChange()
    }

    private func autoClosingPair(for value: String) -> String? {
        guard autoCloseBracketsEnabled, selection.length == 0, value.utf16.count == 1 else { return nil }
        switch value {
        case "(": return "()"
        case "[": return "[]"
        case "{": return "{}"
        case "\"": return "\"\""
        case "'": return "''"
        default: return nil
        }
    }

    private func shouldSkipClosingDelimiter(_ value: String) -> Bool {
        guard autoCloseBracketsEnabled,
              value.utf16.count == 1,
              [")", "]", "}", "\"", "'"].contains(value),
              absoluteCaret >= viewportStartUTF16,
              absoluteCaret < viewportStartUTF16 + viewportText.utf16.count else { return false }
        return (viewportText as NSString).substring(with: NSRange(location: absoluteCaret - viewportStartUTF16, length: 1)) == value
    }

    private func insertNewline() {
        guard autoIndentEnabled,
              let viewport,
              absoluteCaret >= viewport.startUTF16Offset,
              absoluteCaret <= viewport.startUTF16Offset + viewportText.utf16.count else {
            replaceSelection(with: "\n")
            return
        }
        let localCaret = absoluteCaret - viewport.startUTF16Offset
        let text = viewportText as NSString
        guard let context = autoIndentReturnContext(
            in: text,
            proposedRange: NSRange(location: localCaret, length: selection.length),
            selectedRange: NSRange(location: localCaret, length: selection.length)
        ) else {
            replaceSelection(with: "\n")
            return
        }
        let indentation = context.linePrefix.prefix { $0 == " " || $0 == "\t" }
        replaceSelection(with: "\n" + indentation)
    }

    private func registerUndo(replacement: String, range: NSRange, inverseReplacement: String) {
        documentUndoManager.registerUndo(withTarget: self) { target in
            target.applyUndoableReplacement(
                replacement,
                range: range,
                inverseReplacement: inverseReplacement
            )
        }
        documentUndoManager.setActionName("Edit")
    }

    private func applyUndoableReplacement(_ replacement: String, range: NSRange, inverseReplacement: String) {
        guard let document, let documentID else { return }
        let location = max(0, min(document.utf16Length, range.location))
        let length = max(0, min(range.length, document.utf16Length - location))
        reloadViewport(anchorLine: lineForAbsoluteOffset(location))
        guard let viewport,
              location >= viewport.startUTF16Offset,
              location + length <= viewport.startUTF16Offset + viewport.text.utf16.count else { return }
        let localRange = NSRange(location: location - viewport.startUTF16Offset, length: length)
        guard onTextMutation?(EditorTextMutation(documentID: documentID, range: localRange, replacement: replacement, viewport: viewport)) == true else {
            reloadViewport(anchorLine: viewportLineOrigin)
            return
        }
        registerUndo(
            replacement: inverseReplacement,
            range: NSRange(location: location, length: replacement.utf16.count),
            inverseReplacement: replacement
        )
        absoluteCaret = location + replacement.utf16.count
        selection = NSRange(location: absoluteCaret, length: 0)
        selectionAnchor = nil
        reloadViewport(anchorLine: viewportLineOrigin)
        publishCaret()
        publishTextChange()
    }

    private var viewportStartUTF16: Int { viewport?.startUTF16Offset ?? 0 }

    private func utf16DeletionRange(at location: Int, direction: Int) -> NSRange? {
        guard let document else { return nil }
        let length = document.utf16Length
        guard location >= 0, location <= length, direction != 0 else { return nil }
        let candidate: NSRange
        if direction < 0 {
            guard location > 0 else { return nil }
            candidate = NSRange(location: location - 1, length: 1)
        } else {
            guard location < length else { return nil }
            candidate = NSRange(location: location, length: 1)
        }
        if viewport == nil ||
            candidate.location < viewportStartUTF16 ||
            NSMaxRange(candidate) > viewportStartUTF16 + viewportText.utf16.count {
            reloadViewport(anchorLine: lineForAbsoluteOffset(candidate.location))
        }
        guard let viewport,
              candidate.location >= viewport.startUTF16Offset,
              NSMaxRange(candidate) <= viewport.startUTF16Offset + viewport.text.utf16.count else { return candidate }
        let localLocation = candidate.location - viewport.startUTF16Offset
        let unit = (viewport.text as NSString).character(at: localLocation)
        if direction < 0,
           unit >= 0xDC00, unit <= 0xDFFF,
           localLocation > 0 {
            let previous = (viewport.text as NSString).character(at: localLocation - 1)
            if previous >= 0xD800, previous <= 0xDBFF {
                return NSRange(location: location - 2, length: 2)
            }
        } else if direction > 0,
                  unit >= 0xD800, unit <= 0xDBFF,
                  localLocation + 1 < (viewport.text as NSString).length {
            let next = (viewport.text as NSString).character(at: localLocation + 1)
            if next >= 0xDC00, next <= 0xDFFF {
                return NSRange(location: location, length: 2)
            }
        }
        return candidate
    }

    private func deleteBackward() {
        guard selection.length > 0 || absoluteCaret > 0 else { return }
        if selection.length == 0, let range = utf16DeletionRange(at: absoluteCaret, direction: -1) {
            selection = range
        }
        replaceSelection(with: "")
    }

    private func copySelection() {
        guard selection.length > 0 else { return }
        let local = selection.location - viewportStartUTF16
        guard local >= 0, NSMaxRange(selection) <= viewportStartUTF16 + viewportText.utf16.count else {
            guard let document else { return }
            let source = document.string() as NSString
            let location = min(max(0, selection.location), source.length)
            let length = min(max(0, selection.length), source.length - location)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(source.substring(with: NSRange(location: location, length: length)), forType: .string)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((viewportText as NSString).substring(with: NSRange(location: local, length: selection.length)), forType: .string)
    }

    private func cutSelection() {
        guard !isReadOnly else { return }
        copySelection()
        replaceSelection(with: "")
    }

    private func deleteForward() {
        guard selection.length > 0 || absoluteCaret < (document?.utf16Length ?? absoluteCaret) else { return }
        if selection.length == 0, let range = utf16DeletionRange(at: absoluteCaret, direction: 1) {
            selection = range
        }
        replaceSelection(with: "")
    }

    private func pasteSelection() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        replaceSelection(with: text)
    }

    private func selectAllContent() {
        let length = document?.utf16Length ?? viewportText.utf16.count
        selection = NSRange(location: 0, length: length)
        absoluteCaret = length
        selectionAnchor = 0
        needsDisplay = true
    }
    private func moveCaret(_ delta: Int, extending: Bool) {
        if !extending, selection.length > 0 {
            absoluteCaret = delta < 0 ? selection.location : NSMaxRange(selection)
            selection = NSRange(location: absoluteCaret, length: 0)
            selectionAnchor = nil
        } else {
            let next = nextCaretLocation(from: absoluteCaret, delta: delta)
            if extending {
                let anchor = selectionAnchor ?? absoluteCaret
                selectionAnchor = anchor
                absoluteCaret = next
                selection = NSRange(location: min(anchor, next), length: abs(anchor - next))
            } else {
                absoluteCaret = next
                selection = NSRange(location: absoluteCaret, length: 0)
                selectionAnchor = nil
            }
        }
        ensureCaretVisible()
        publishCaret()
        needsDisplay = true
    }

    private func nextCaretLocation(from location: Int, delta: Int) -> Int {
        guard delta == -1 || delta == 1, let document else {
            return location
        }
        if viewport == nil ||
            location < viewportStartUTF16 ||
            location > viewportStartUTF16 + viewportText.utf16.count {
            reloadViewport(anchorLine: lineForAbsoluteOffset(location))
        }
        guard let viewport,
              location >= viewport.startUTF16Offset,
              location <= viewport.startUTF16Offset + viewport.text.utf16.count else {
            return max(0, min(document.utf16Length, location + delta))
        }
        let local = location - viewport.startUTF16Offset
        let text = viewport.text as NSString
        if delta < 0, local >= 2 {
            let low = text.character(at: local - 1)
            let high = text.character(at: local - 2)
            if low >= 0xDC00, low <= 0xDFFF, high >= 0xD800, high <= 0xDBFF {
                return location - 2
            }
        } else if delta > 0, local + 1 < text.length {
            let high = text.character(at: local)
            let low = text.character(at: local + 1)
            if high >= 0xD800, high <= 0xDBFF, low >= 0xDC00, low <= 0xDFFF {
                return location + 2
            }
        }
        return max(0, min(document.utf16Length, location + delta))
    }

    private func moveCaretVertically(_ direction: Int, extending: Bool) {
        let local = max(0, absoluteCaret - viewportLineOriginStartUTF16)
        let currentLine = newlineCount(inUTF16PrefixOf: viewportText, length: local)
        let currentStart = lineStarts[min(currentLine, lineStarts.count - 1)]
        let column = local - currentStart
        let targetLine = currentLine + direction
        if targetLine < 0 || targetLine >= lineStarts.count {
            let documentLine = lineForAbsoluteOffset(absoluteCaret)
            let nextDocumentLine = min(max(0, documentLine + direction), max(0, (document?.lineCount ?? 1) - 1))
            guard nextDocumentLine != documentLine else { return }
            reloadViewport(anchorLine: nextDocumentLine)
            let localTarget = max(0, min(lineStarts.count - 1, nextDocumentLine - viewportLineOrigin))
            let targetStart = lineStarts[localTarget]
            let targetEnd = localTarget + 1 < lineStarts.count ? lineStarts[localTarget + 1] : viewportText.utf16.count
            let target = viewportLineOriginStartUTF16 + targetStart + min(column, max(0, targetEnd - targetStart))
            moveCaret(target - absoluteCaret, extending: extending)
            return
        }
        let targetStart = lineStarts[targetLine]
        let targetEnd = targetLine + 1 < lineStarts.count ? lineStarts[targetLine + 1] : viewportText.utf16.count
        let target = viewportLineOriginStartUTF16 + targetStart + min(column, max(0, targetEnd - targetStart))
        moveCaret(target - absoluteCaret, extending: extending)
    }

    private func ensureCaretVisible() {
        let local = absoluteCaret - viewportLineOriginStartUTF16
        guard local >= 0, local <= viewportText.utf16.count else { return }
        scrollToVisible(NSRect(origin: caretPoint(localLocation: local), size: NSSize(width: 4, height: lineHeight)))
    }

    private func ensureLineVisible(_ line: Int) {
        guard let scrollView = enclosingScrollView else { return }
        let row = visualRowIndex.rowOrigin(forLogicalLine: line)
        let y = CGFloat(row) * lineHeight + 8
        let visibleHeight = scrollView.contentView.bounds.height
        let maximumY = max(0, frame.height - visibleHeight)
        let targetY = min(max(0, y - visibleHeight * 0.35), maximumY)
        scrollView.contentView.scroll(to: NSPoint(
            x: scrollView.contentView.bounds.minX,
            y: targetY
        ))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func reloadViewportIfNeeded(scrollY: CGFloat) {
        let target = max(0, Int(scrollY / max(lineHeight, lineHeight * estimatedRowsPerLogicalLine)) - 20)
        guard target < viewportLineOrigin || target >= viewportLineOrigin + lineStarts.count - 20 else { return }
        reloadViewport(anchorLine: target)
    }

    private func reloadViewport(anchorLine: Int) {
        guard let document, let next = try? document.viewport(aroundLine: max(0, anchorLine), maximumByteCount: 256_000) else { return }
        if let documentID {
            EditorPerformanceMonitor.shared.markViewportLoaded(tabID: documentID)
        }
        viewport = next
        viewportText = next.text
        viewportLineOrigin = next.lineRange.lowerBound
        lineStarts = [0]
        attributedLineCache.removeAll(keepingCapacity: true)
        visualFragmentCache.removeAll(keepingCapacity: true)
        var offset = 0
        for scalar in viewportText.utf16 { offset += 1; if scalar == 10 { lineStarts.append(offset) } }
        contentWidth = lineWrapEnabled ? max(viewportSize.width, 1) : unwrappedContentWidth()
        layoutCache.removeAll(keepingCapacity: true)
        needsDisplay = true
    }

    private func unwrappedContentWidth() -> CGFloat {
        guard !viewportText.isEmpty else { return max(viewportSize.width, 1) }
        var maximum: CGFloat = 0
        for localLine in lineStarts.indices {
            let start = lineStarts[localLine]
            let end = localLine + 1 < lineStarts.count ? lineStarts[localLine + 1] : viewportText.utf16.count
            let text = (viewportText as NSString)
                .substring(with: NSRange(location: start, length: max(0, end - start)))
                .trimmingCharacters(in: .newlines)
            let line = CTLineCreateWithAttributedString(attributedLine(text, absoluteStart: start, dark: scheme == .dark))
            maximum = max(maximum, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        return max(viewportSize.width, gutterWidth + 16 + maximum)
    }

    private func caretPoint(localLocation: Int) -> CGPoint {
        let rows = visualRows()
        guard let row = visualRow(containing: localLocation, in: rows) else {
            return CGPoint(x: gutterWidth + 8, y: 8)
        }
        let x = CGFloat(CTLineGetOffsetForStringIndex(row.fragment.line, localLocation - row.fragment.absoluteStartUTF16, nil))
        return CGPoint(x: gutterWidth + 8 + x, y: row.baseline - lineHeight + 2)
    }

    private func documentOffset(at point: NSPoint) -> Int {
        guard let row = visualRows().min(by: { abs($0.baseline - point.y) < abs($1.baseline - point.y) }) else {
            return viewportLineOriginStartUTF16
        }
        let index = CTLineGetStringIndexForPosition(
            row.fragment.line,
            CGPoint(x: max(0, point.x - gutterWidth - 8), y: 0)
        )
        let localOffset = index == kCFNotFound
            ? (point.x <= gutterWidth + 8 ? 0 : row.fragment.lengthUTF16)
            : min(Int(index), row.fragment.lengthUTF16)
        return viewportLineOriginStartUTF16 + row.fragment.absoluteStartUTF16 + localOffset
    }

    private func publishTextChange() {
        guard let documentID, selection.length == 0 else { return }
        let localCaret = absoluteCaret - viewportLineOriginStartUTF16
        guard localCaret > 0, localCaret <= viewportText.utf16.count else { return }
        let start = max(0, localCaret - 1_200)
        let context = (viewportText as NSString).substring(with: NSRange(location: start, length: localCaret - start))
        NotificationCenter.default.post(
            name: .virtualEditorTextDidChange,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.documentID: documentID.uuidString,
                EditorCommandUserInfo.completionCaretOffset: absoluteCaret,
                EditorCommandUserInfo.completionContext: context
            ]
        )
    }

    private func publishCaret() {
        guard let documentID else { return }
        let localCaret = max(0, min(viewportText.utf16.count, absoluteCaret - viewportLineOriginStartUTF16))
        let localLine = newlineCount(inUTF16PrefixOf: viewportText, length: localCaret)
        let lineStart = lineStarts[min(localLine, max(0, lineStarts.count - 1))]
        let selectedText: String = {
            guard selection.length > 0,
                  selection.location >= viewportLineOriginStartUTF16,
                  NSMaxRange(selection) <= viewportLineOriginStartUTF16 + viewportText.utf16.count else { return "" }
            return (viewportText as NSString).substring(with: NSRange(location: selection.location - viewportLineOriginStartUTF16, length: selection.length))
        }()
        NotificationCenter.default.post(name: .caretPositionDidChange, object: nil, userInfo: [EditorCommandUserInfo.documentID: documentID.uuidString, "location": absoluteCaret, "line": viewportLineOrigin + localLine + 1, "column": localCaret - lineStart + 1])
        NotificationCenter.default.post(
            name: .editorSelectionDidChange,
            object: selectedText,
            userInfo: [
                EditorCommandUserInfo.documentID: documentID.uuidString,
                "range": NSValue(range: selection)
            ]
        )
    }
}
#endif
