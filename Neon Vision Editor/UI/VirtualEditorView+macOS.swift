#if os(macOS)
import AppKit
import CoreText
import SwiftUI

struct VirtualEditorHexColorLiteral: Equatable {
    let range: NSRange
    let token: String
    let color: NSColor
}

enum VirtualEditorHexColorPreview {
    private static let supportedLanguages: Set<String> = ["css", "html", "xml", "svg"]
    private static let literalRegex = try! NSRegularExpression(pattern: "#[0-9A-Fa-f]{3,8}")

    static func isSupported(language: String) -> Bool {
        supportedLanguages.contains(language.lowercased())
    }

    static func literals(in line: String, absoluteStart: Int) -> [VirtualEditorHexColorLiteral] {
        let source = line as NSString
        let matches = literalRegex.matches(in: line, range: NSRange(location: 0, length: source.length))
        return matches.compactMap { match in
            let token = source.substring(with: match.range)
            let digitCount = token.dropFirst().utf16.count
            guard [3, 4, 6, 8].contains(digitCount),
                  isBoundary(source, before: match.range.location),
                  isBoundary(source, after: NSMaxRange(match.range)),
                  let color = color(for: token) else { return nil }
            return VirtualEditorHexColorLiteral(
                range: NSRange(location: absoluteStart + match.range.location, length: match.range.length),
                token: token,
                color: color
            )
        }
    }

    static func replacement(for color: NSColor, preserving token: String) -> String? {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        let alpha = Int((rgb.alphaComponent * 255).rounded())
        let digitCount = token.dropFirst().utf16.count
        let includesAlpha = [4, 8].contains(digitCount)
        let full = includesAlpha
            ? String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
            : String(format: "#%02X%02X%02X", red, green, blue)
        if [3, 4].contains(digitCount),
           red % 17 == 0, green % 17 == 0, blue % 17 == 0,
           !includesAlpha || alpha % 17 == 0 {
            let components = [red, green, blue].map { String(format: "%X", $0 / 17) }
            return includesAlpha
                ? "#\(components.joined())\(String(format: "%X", alpha / 17))"
                : "#\(components.joined())"
        }
        return full
    }

    private static func color(for token: String) -> NSColor? {
        let digits = Array(token.dropFirst())
        let values: [Int]
        switch digits.count {
        case 3, 4:
            values = digits.map { Int(String(repeating: String($0), count: 2), radix: 16) ?? 0 }
        case 6, 8:
            values = stride(from: 0, to: digits.count, by: 2).map {
                Int(String(digits[$0..<$0 + 2]), radix: 16) ?? 0
            }
        default:
            return nil
        }
        let alpha = values.count == 4 ? values[3] : 255
        return NSColor(
            calibratedRed: CGFloat(values[0]) / 255,
            green: CGFloat(values[1]) / 255,
            blue: CGFloat(values[2]) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }

    private static func isBoundary(_ source: NSString, before index: Int) -> Bool {
        guard index > 0 else { return true }
        return !isHexDigit(source.character(at: index - 1))
    }

    private static func isBoundary(_ source: NSString, after index: Int) -> Bool {
        guard index < source.length else { return true }
        return !isHexDigit(source.character(at: index))
    }

    private static func isHexDigit(_ codeUnit: unichar) -> Bool {
        switch codeUnit {
        case 48...57, 65...70, 97...102:
            return true
        default:
            return false
        }
    }
}

@MainActor
private final class VirtualEditorColorPickerState {
    var literal: VirtualEditorHexColorLiteral

    init(literal: VirtualEditorHexColorLiteral) {
        self.literal = literal
    }
}

@MainActor
private final class VirtualEditorColorPickerViewController: NSViewController {
    let colorWell: NSColorWell
    var onColorChange: ((NSColor) -> Void)?

    init(color: NSColor, token: String, isReadOnly: Bool) {
        colorWell = NSColorWell(style: .expanded)
        super.init(nibName: nil, bundle: nil)
        colorWell.color = color
        colorWell.isEnabled = !isReadOnly
        colorWell.toolTip = "Edit \(token)"
        colorWell.setAccessibilityLabel("Color for \(token)")
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 220))
        let stack = NSStackView(views: [colorWell])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            colorWell.widthAnchor.constraint(equalToConstant: 256),
            colorWell.heightAnchor.constraint(equalToConstant: 196)
        ])
        view = container
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        onColorChange?(sender.color)
    }
}

struct VirtualEditorVisualFragment {
    let absoluteStartUTF16: Int
    let lengthUTF16: Int
    let line: CTLine
}

struct VirtualEditorViewportLine: Sendable {
    let localLine: Int
    let startUTF16: Int
    let text: String
}

nonisolated private struct VirtualEditorSyntaxSpan: Sendable {
    let range: NSRange
    let color: Color
}

nonisolated private struct VirtualEditorSyntaxLineCacheKey: Hashable, Sendable {
    let language: String
    let theme: String
    let text: String
}

private enum VirtualEditorSyntaxLineCache {
    nonisolated private static let maximumEntryCount = 2_048
    nonisolated private static let maximumCachedLineLength = 8_192
    nonisolated static let storage = NVELock<[VirtualEditorSyntaxLineCacheKey: [VirtualEditorSyntaxSpan]]>([:])

    nonisolated static func spans(for key: VirtualEditorSyntaxLineCacheKey) -> [VirtualEditorSyntaxSpan]? {
        guard key.text.utf16.count <= maximumCachedLineLength else { return nil }
        return storage.withLock { $0[key] }
    }

    nonisolated static func store(_ spans: [VirtualEditorSyntaxSpan], for key: VirtualEditorSyntaxLineCacheKey) {
        guard key.text.utf16.count <= maximumCachedLineLength else { return }
        storage.withLock { cache in
            if cache[key] == nil, cache.count >= maximumEntryCount, let evictionKey = cache.keys.first {
                cache.removeValue(forKey: evictionKey)
            }
            cache[key] = spans
        }
    }
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

    static func lineNumberOriginY(baseline: CGFloat, fontAscender: CGFloat) -> CGFloat {
        baseline - fontAscender
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
    static func fontSizeDelta(
        scrollingDeltaY: CGFloat,
        fallbackDeltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool = true
    ) -> CGFloat {
        let rawDelta = abs(scrollingDeltaY) > 0.001 ? scrollingDeltaY : fallbackDeltaY
        if !hasPreciseScrollingDeltas, abs(rawDelta) > 0.001 {
            return rawDelta.sign == .minus ? -1 : 1
        }
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

    /// Growing the scroll extent must happen in one pass. A smoothed increase
    /// can leave wrapped rows beyond AppKit's reachable document height until
    /// another unrelated resize occurs. Shrinking remains gradual so ordinary
    /// viewport samples do not make the scrollbar jump inward.
    static func scrollExtentEstimate(
        previous: CGFloat,
        observed: CGFloat,
        measurementIsComplete: Bool = false
    ) -> CGFloat {
        guard observed.isFinite else { return max(1, previous) }
        let safeObserved = max(1, observed)
        if measurementIsComplete { return safeObserved }
        guard safeObserved < previous else { return safeObserved }
        return max(safeObserved, previous * 0.75 + safeObserved * 0.25)
    }
}

enum VirtualEditorScrollAnchorPolicy {
    static func anchorLine(
        scrollY: CGFloat,
        lineHeight: CGFloat,
        estimatedRowsPerLogicalLine: CGFloat,
        prefetchLines: Int,
        documentLineCount: Int,
        isAtBottom: Bool
    ) -> Int {
        if isAtBottom {
            return max(0, documentLineCount - 1)
        }

        let rowHeight = max(1, lineHeight * max(1, estimatedRowsPerLogicalLine))
        return max(0, Int(scrollY / rowHeight) - max(0, prefetchLines))
    }
}

/// The macOS production editor surface. It intentionally does not use NSTextView
/// or TextKit: only a bounded EditorDocument viewport is decoded and laid out.
struct VirtualEditorView: NSViewRepresentable {
    let document: (any EditorDocument)?
    let documentID: UUID?
    let documentResourceID: String
    let documentDisplayName: String
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
    let indentStyle: String
    let indentWidth: Int
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
            displayName: documentDisplayName,
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
            indentStyle: indentStyle,
            indentWidth: indentWidth,
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
            displayName: documentDisplayName,
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
            indentStyle: indentStyle,
            indentWidth: indentWidth,
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

enum VirtualEditorCoreTextDrawing {
    static func textMatrix(forFlippedCoordinates isFlipped: Bool) -> CGAffineTransform {
        isFlipped ? CGAffineTransform(scaleX: 1, y: -1) : .identity
    }

    static func draw(
        _ line: CTLine,
        in context: CGContext,
        at textPosition: CGPoint,
        flippedCoordinates: Bool
    ) {
        let inheritedTextMatrix = context.textMatrix
        let inheritedTextPosition = context.textPosition
        context.saveGState()
        defer {
            context.restoreGState()
            context.textMatrix = inheritedTextMatrix
            context.textPosition = inheritedTextPosition
        }
        context.textMatrix = textMatrix(forFlippedCoordinates: flippedCoordinates)
        context.textPosition = textPosition
        CTLineDraw(line, context)
    }
}

enum VirtualEditorResizePolicy {
    static func shouldReflow(isSplitPaneResizeInProgress: Bool) -> Bool {
        !isSplitPaneResizeInProgress
    }
}

enum VirtualEditorKeyRouting {
    // Carbon virtual key code for the physical W key.
    private static let physicalWKeyCode: UInt16 = 13

    static func matches(_ event: NSEvent, shortcut: EditorShortcutDescriptor) -> Bool {
        matches(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            shortcut: shortcut
        )
    }

    static func matches(
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        shortcut: EditorShortcutDescriptor
    ) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        var resolvedModifiers: EditorShortcutModifiers = []
        if flags.contains(.command) { resolvedModifiers.insert(.command) }
        if flags.contains(.shift) { resolvedModifiers.insert(.shift) }
        if flags.contains(.option) { resolvedModifiers.insert(.alternate) }
        if flags.contains(.control) { resolvedModifiers.insert(.control) }
        guard resolvedModifiers == shortcut.modifiers else { return false }

        switch shortcut.key {
        case "←": return keyCode == 123
        case "→": return keyCode == 124
        case "↓": return keyCode == 125
        case "↑": return keyCode == 126
        case "w" where keyCode == physicalWKeyCode:
            return true
        default:
            return charactersIgnoringModifiers?.lowercased() == shortcut.key.lowercased()
        }
    }

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
            fallbackDeltaY: event.deltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
        guard abs(delta) >= 0.01 else { return }
        canvas.adjustFontSize(by: delta)
    }

    func configure(
        document: (any EditorDocument)?, documentID: UUID?, resourceID: String, displayName: String,
        contentRevision: Int, externalContentRevision: Int,
        caret: Int?, language: String, colorScheme: ColorScheme, fontSize: CGFloat,
        fontName: String, lineHeightMultiplier: CGFloat,
        isReadOnly: Bool, translucentBackgroundEnabled: Bool, showsLineNumbers: Bool, highlightCurrentLine: Bool,
        lineWrapEnabled: Bool, showsInvisibleCharacters: Bool, showsIndentationGuides: Bool,
        showsScopeGuides: Bool, highlightsScopeBackground: Bool,
        highlightsMatchingBrackets: Bool, autoIndentEnabled: Bool, autoCloseBracketsEnabled: Bool,
        indentStyle: String = "spaces", indentWidth: Int = 4,
        isSplitPaneResizeInProgress: Bool,
        onFontSizeChange: ((CGFloat) -> Void)?, onTextMutation: ((EditorTextMutation) -> Bool)?
    ) {
        self.isSplitPaneResizeInProgress = isSplitPaneResizeInProgress
        hasHorizontalScroller = !lineWrapEnabled
        MacOverlayScrollerPolicy.configure(self, clearBackground: true)
        canvas.configure(
            document: document, documentID: documentID, resourceID: resourceID, displayName: displayName,
            contentRevision: contentRevision, externalContentRevision: externalContentRevision,
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
            indentStyle: indentStyle,
            indentWidth: indentWidth,
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

struct VirtualEditorAccessibilityContext: Equatable {
    let documentName: String
    let line: Int
    let column: Int
    let isReadOnly: Bool
    let selectionLength: Int

    var label: String { "\(documentName), editor" }

    var help: String {
        let editability = isReadOnly ? "read only" : "editable"
        let selectionStatus = selectionLength > 0
            ? "\(selectionLength) characters selected"
            : "no selection"
        return "Line \(line), column \(column), \(editability), \(selectionStatus)."
    }
}

@MainActor
final class VirtualEditorCanvas: NSView, NSTextInputClient {
    private enum Geometry {
        static let gutterTextInset: CGFloat = 8
        static let lineNumberTrailingInset: CGFloat = 8
    }

    private var document: (any EditorDocument)?
    private var documentID: UUID?
    private var resourceID = ""
    private var language = "plain"
    private var scheme: ColorScheme = .light
    private var resolvedEditorTheme = currentEditorTheme(colorScheme: .light)
    private var resolvedSyntaxColors = SyntaxColors.from(theme: currentEditorTheme(colorScheme: .light))
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
    private var indentStyle = "spaces"
    private var indentWidth = 4
    private var isVimInsertMode = true
    private var inlineSuggestion: String?
    private var inlineSuggestionLocation: Int?
    private var onFontSizeChange: ((CGFloat) -> Void)?
    private var onTextMutation: ((EditorTextMutation) -> Bool)?
    private var pendingFontSizeDelta: CGFloat = 0
    private var viewport: EditorDocumentViewport?
    private var viewportText = ""
    private var lineStarts: [Int] = [0]
    private var viewportLines: [VirtualEditorViewportLine] = []
    var viewportLineOrigin = 0
    private var absoluteCaret = 0
    private var selection = NSRange(location: 0, length: 0)
    private var findMatchRanges: [NSRange] = []
    private var selectedFindMatchRange: NSRange?
    private var markedText: String?
    private var markedTextRange = NSRange(location: NSNotFound, length: 0)
    private var markedTextSelectedRange = NSRange(location: 0, length: 0)
    private var selectionAnchor: Int?
    private var pendingDragPublication: DispatchWorkItem?
    private let documentUndoManager = UndoManager()
    private var lastConfigurationKey = ""
    private var documentDisplayName = "Untitled"
    private var layoutCache: [Int: CTLine] = [:]
    private var attributedLineCache: [Int: NSAttributedString] = [:]
    private var visualFragmentCache = VirtualEditorVisualFragmentCache()
    private var visualRowsSnapshot: (key: String, rows: [VisualRow])?
    private var syntaxSpansByLine: [Int: [VirtualEditorSyntaxSpan]] = [:]
    private(set) var syntaxHighlightTask: Task<Void, Never>?
    private var htmlContextDocument: ObjectIdentifier?
    private var htmlContextGeneration: UInt64?
    private var htmlContexts: [Int: HTMLSyntaxState] = [:]
    private var syntaxHighlightGeneration = 0
    private var visibleColors: [NSRange: NSColor] = [:]
    private var colorPickerPopover: NSPopover?
    private var viewportSize: CGSize = .zero {
        didSet {
            guard viewportSize != oldValue else { return }
            if viewportSize.width != oldValue.width { hasValidVisualMetrics = false }
            visualFragmentCache.removeAll(keepingCapacity: true)
            visualRowsSnapshot = nil
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var lastScrollY: CGFloat = -1
    var lastReloadAnchorLine = -1
    private var estimatedRowsPerLogicalLine: CGFloat = 1
    private var hasValidVisualMetrics = false
    private var configuredContentRevision: Int?
    private var configuredExternalContentRevision: Int?
    private let viewportMaximumByteCount = 256_000
    private let editRefreshMaximumByteCount = 128_000
    private let visualMetricSampleLineLimit = 512
    private var lineHeight: CGFloat { max(1, (editorFont.ascender - editorFont.descender + editorFont.leading + 4) * lineHeightMultiplier) }
    private var editorFont: NSFont { resolvedEditorFont }
    private var gutterWidth: CGFloat {
        let lineNumberWidth = CGFloat(max(1, document?.lineCount ?? 1).description.count) * editorFontSize * 0.7
        let colorPreviewAllowance: CGFloat = VirtualEditorHexColorPreview.isSupported(language: language) ? 18 : 0
        return max(44, lineNumberWidth + 18 + colorPreviewAllowance)
    }
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
        // A one-point fallback width is not a measurement of this viewport.
        // Wait for allocation, and never blend estimates from different widths.
        guard viewportSize.width >= minimumUsableViewportWidth else { return }
        guard lineWrapEnabled, !viewportText.isEmpty else {
            estimatedRowsPerLogicalLine = 1
            contentWidth = max(viewportSize.width, 1)
            if !lineWrapEnabled { contentWidth = unwrappedContentWidth() }
            return
        }
        let measurement = EditorPerformanceMonitor.shared.measureVirtualEditorLayout {
            measuredRowsPerLogicalLine()
        }
        let observed = measurement.rowsPerLogicalLine
        if !hasValidVisualMetrics || abs(observed - estimatedRowsPerLogicalLine) > 0.05 {
            estimatedRowsPerLogicalLine = VirtualEditorVisualRowIndex.scrollExtentEstimate(
                previous: estimatedRowsPerLogicalLine,
                observed: observed,
                measurementIsComplete: measurement.isComplete || !hasValidVisualMetrics
            )
            hasValidVisualMetrics = true
            visualRowsSnapshot = nil
        }
        contentWidth = max(viewportSize.width, 1)
        invalidateIntrinsicContentSize()
    }

    private func measuredRowsPerLogicalLine() -> (rowsPerLogicalLine: CGFloat, isComplete: Bool) {
        guard !viewportLines.isEmpty else { return (1, true) }
        let availableWidth = max(1, viewportSize.width - gutterWidth - 16)
        let step = max(1, Int(ceil(Double(viewportLines.count) / Double(visualMetricSampleLineLimit))))
        var sampledLineCount = 0
        var measuredRowCount = 0
        var index = 0
        while index < viewportLines.count, sampledLineCount < visualMetricSampleLineLimit {
            let viewportLine = viewportLines[index]
            measuredRowCount += cachedVisualFragments(
                for: viewportLine.text,
                localLine: viewportLine.localLine,
                absoluteStart: viewportLine.startUTF16,
                width: availableWidth
            ).count
            sampledLineCount += 1
            index += step
        }
        let coversWholeDocument = viewport?.lineRange.lowerBound == 0
            && (viewport?.lineRange.upperBound ?? -1) >= max(0, (document?.lineCount ?? 1) - 1)
        let isComplete = coversWholeDocument && sampledLineCount == viewportLines.count
        return (
            CGFloat(max(1, measuredRowCount)) / CGFloat(max(1, sampledLineCount)),
            isComplete
        )
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { documentUndoManager }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { accessibilityContext.label }
    override func accessibilityValue() -> Any? { viewportText }
    override func accessibilityHelp() -> String? { accessibilityContext.help }
    override func accessibilityNumberOfCharacters() -> Int { document?.utf16Length ?? 0 }
    override func accessibilityVisibleCharacterRange() -> NSRange {
        NSRange(location: viewportStartUTF16, length: viewportText.utf16.count)
    }
    override func accessibilitySelectedTextRange() -> NSRange { selection }
    override func accessibilitySelectedText() -> String? {
        guard selection.length > 0 else { return "" }
        return try? document?.text(inUTF16Range: selection)
    }
    override func accessibilityString(for range: NSRange) -> String? {
        try? document?.text(inUTF16Range: range)
    }
    override func setAccessibilitySelectedTextRange(_ range: NSRange) {
        guard let document else { return }
        let location = min(max(0, range.location), document.utf16Length)
        let length = min(max(0, range.length), document.utf16Length - location)
        selection = NSRange(location: location, length: length)
        absoluteCaret = NSMaxRange(selection)
        selectionAnchor = selection.length > 0 ? selection.location : nil
        reloadViewport(anchorLine: lineForAbsoluteOffset(absoluteCaret))
        ensureCaretVisible()
        publishCaret()
        needsDisplay = true
    }

    private var accessibilityContext: VirtualEditorAccessibilityContext {
        if (absoluteCaret < viewportLineOriginStartUTF16 || absoluteCaret > viewportLineOriginStartUTF16 + viewportText.utf16.count),
           let position = try? document?.position(atUTF16Offset: absoluteCaret) {
            return VirtualEditorAccessibilityContext(
                documentName: documentDisplayName, line: position.line + 1,
                column: position.column + 1, isReadOnly: isReadOnly, selectionLength: selection.length)
        }
        let localCaret = max(0, min(viewportText.utf16.count, absoluteCaret - viewportLineOriginStartUTF16))
        let localLine = newlineCount(inUTF16PrefixOf: viewportText, length: localCaret)
        let lineStart = lineStarts[min(localLine, max(0, lineStarts.count - 1))]
        return VirtualEditorAccessibilityContext(
            documentName: documentDisplayName,
            line: viewportLineOrigin + localLine + 1,
            column: localCaret - lineStart + 1,
            isReadOnly: isReadOnly,
            selectionLength: selection.length
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(self, selector: #selector(moveToLine(_:)), name: .moveCursorToLine, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moveToRange(_:)), name: .moveCursorToRange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateFindHighlights(_:)), name: .updateEditorFindHighlights, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(replaceRange(_:)), name: .replaceEditorRangeRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moveSelectedLines(_:)), name: .moveSelectedLinesRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(insertBracketHelperToken(_:)), name: .insertBracketHelperTokenRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(inspectWhitespaceScalars(_:)), name: .inspectWhitespaceScalarsRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateVimMode(_:)), name: .vimModeStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showInlineSuggestion(_:)), name: .showVirtualEditorInlineSuggestion, object: nil)
        registerForDraggedTypes([.fileURL, .URL, .string, .rtf])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        syntaxHighlightTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func moveToLine(_ notification: Notification) {
        guard matchesDocument(notification), let line = notification.object as? Int else { return }
        clearInlineSuggestion()
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
        clearInlineSuggestion()
        let line = max(0, lineForAbsoluteOffset(location))
        reloadViewport(anchorLine: line)
        absoluteCaret = max(0, min(document?.utf16Length ?? location, location))
        selection = NSRange(location: absoluteCaret, length: max(0, min(length, (document?.utf16Length ?? absoluteCaret) - absoluteCaret)))
        selectionAnchor = absoluteCaret
        if notification.userInfo?[EditorCommandUserInfo.centerSelection] as? Bool == true {
            ensureLineVisible(line)
        } else {
            ensureCaretVisible()
        }
        publishCaret()
        needsDisplay = true
    }

    @objc private func updateFindHighlights(_ notification: Notification) {
        if let targetDocumentID = notification.userInfo?[EditorCommandUserInfo.documentID] as? String,
           documentID?.uuidString != targetDocumentID {
            return
        }
        findMatchRanges = (notification.userInfo?[EditorCommandUserInfo.findMatchRanges] as? [NSValue] ?? [])
            .map(\.rangeValue)
        selectedFindMatchRange = (notification.userInfo?[EditorCommandUserInfo.selectedFindMatchRange] as? NSValue)?.rangeValue
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
        return (try? document.position(atUTF16Offset: offset).line) ?? 0
    }

    func configure(
        document: (any EditorDocument)?, documentID: UUID?, resourceID: String, displayName: String,
        contentRevision: Int, externalContentRevision: Int,
        caret: Int?, language: String, colorScheme: ColorScheme, fontSize: CGFloat,
        fontName: String, lineHeightMultiplier: CGFloat,
        isReadOnly: Bool, translucentBackgroundEnabled: Bool, showsLineNumbers: Bool, highlightCurrentLine: Bool,
        lineWrapEnabled: Bool, showsInvisibleCharacters: Bool, showsIndentationGuides: Bool,
        showsScopeGuides: Bool, highlightsScopeBackground: Bool,
        highlightsMatchingBrackets: Bool, autoIndentEnabled: Bool, autoCloseBracketsEnabled: Bool,
        indentStyle: String = "spaces", indentWidth: Int = 4,
        onFontSizeChange: ((CGFloat) -> Void)?, onTextMutation: ((EditorTextMutation) -> Bool)?
    ) {
        let previousResourceID = self.resourceID
        let previousDocumentID = self.documentID
        let isNewDocument = previousResourceID != resourceID || previousDocumentID != documentID
        let key = "\(resourceID)|\(document?.utf16Length ?? 0)|\(language)|\(fontSize)|\(fontName)|\(lineHeightMultiplier)|\(colorScheme)|\(syntaxThemeKey(for: colorScheme))|\(editorBaseThemeKey(for: colorScheme))|\(document?.isDirty ?? false)|\(translucentBackgroundEnabled)|\(showsLineNumbers)|\(highlightCurrentLine)|\(lineWrapEnabled)|\(showsInvisibleCharacters)|\(showsIndentationGuides)|\(showsScopeGuides)|\(highlightsScopeBackground)|\(highlightsMatchingBrackets)|\(autoIndentEnabled)|\(autoCloseBracketsEnabled)|\(indentStyle)|\(indentWidth)"
        let contentChanged = configuredContentRevision != contentRevision || configuredExternalContentRevision != externalContentRevision
        self.document = document
        self.documentID = documentID
        self.resourceID = resourceID
        self.documentDisplayName = displayName
        self.language = language
        self.scheme = colorScheme
        self.resolvedEditorTheme = currentEditorTheme(colorScheme: colorScheme)
        self.resolvedSyntaxColors = SyntaxColors.from(theme: resolvedEditorTheme)
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
        self.indentStyle = indentStyle
        self.indentWidth = max(1, indentWidth)
        self.onFontSizeChange = onFontSizeChange
        self.onTextMutation = onTextMutation
        if isNewDocument {
            colorPickerPopover?.close()
            colorPickerPopover = nil
            clearInlineSuggestion()
            isVimInsertMode = !vimModeIsEnabled
        }
        if abs(editorFontSize - fontSize) > 0.01 {
            editorFontSize = fontSize
            pendingFontSizeDelta = 0
            layoutCache.removeAll()
        }
        if key == lastConfigurationKey {
            configuredContentRevision = contentRevision
            configuredExternalContentRevision = externalContentRevision
            guard contentChanged else { return }
            clearInlineSuggestion()
            reloadViewport(anchorLine: lineForAbsoluteOffset(absoluteCaret), maximumByteCount: editRefreshMaximumByteCount)
            recalculateVisualMetrics()
            setFrameSize(NSSize(width: contentWidth, height: logicalHeight))
            needsLayout = true
            needsDisplay = true
            return
        }
        guard key != lastConfigurationKey else { return }
        lastConfigurationKey = key
        hasValidVisualMetrics = false
        configuredContentRevision = contentRevision
        configuredExternalContentRevision = externalContentRevision
        viewport = nil
        viewportText = ""
        lineStarts = [0]
        layoutCache.removeAll()
        attributedLineCache.removeAll()
        visualFragmentCache.removeAll()
        visualRowsSnapshot = nil
        syntaxSpansByLine.removeAll(keepingCapacity: true)
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
        if isNewDocument {
            // Publish after the representable update so the status bar reflects
            // the selected document without mutating SwiftUI during configure.
            Task { @MainActor [weak self] in
                guard let self, self.documentID == documentID else { return }
                self.publishCaret()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        defer {
            if let documentID {
                EditorPerformanceMonitor.shared.markTabSwitchFirstDraw(tabID: documentID)
            }
        }
        context.saveGState()
        context.clip(to: dirtyRect)
        defer { context.restoreGState() }
        if !translucentBackgroundEnabled {
            NSColor(resolvedEditorTheme.background).setFill()
            dirtyRect.fill()
        }
        guard !lineStarts.isEmpty else { return }
        let dark = scheme == .dark
        let rows = visualRows()
        drawCurrentLineHighlight(rows: rows)
        drawFindMatchBackgrounds(rows: rows)
        drawSelectionBackground(rows: rows)
        for row in rows where row.baseline + lineHeight >= dirtyRect.minY && row.baseline <= dirtyRect.maxY {
            context.saveGState()
            if showsLineNumbers, row.isFirstFragment {
                let lineNumber = "\(row.logicalLine + 1)" as NSString
                let numberWidth = lineNumber.size(withAttributes: [.font: editorFont]).width
                lineNumber.draw(at: NSPoint(
                    x: gutterWidth - numberWidth - Geometry.lineNumberTrailingInset,
                    y: VirtualEditorVisualLayout.lineNumberOriginY(
                        baseline: row.baseline,
                        fontAscender: editorFont.ascender
                    )
                ), withAttributes: [
                    .font: editorFont,
                    .foregroundColor: NSColor(resolvedEditorTheme.text).withAlphaComponent(0.58)
                ])
            }
            VirtualEditorCoreTextDrawing.draw(
                row.fragment.line,
                in: context,
                at: CGPoint(x: gutterWidth + Geometry.gutterTextInset, y: row.baseline),
                flippedCoordinates: isFlipped
            )
            context.restoreGState()
            drawWhitespaceAndIndentationDecorations(for: row, dark: dark)
        }
        drawHexColorSwatches(rows: rows, dirtyRect: dirtyRect)
        drawMarkedText(rows: rows, context: context)
        drawInlineSuggestion(rows: rows, context: context)
        drawCaret(rows: rows)
    }

    private func drawInlineSuggestion(rows: [VisualRow], context: CGContext) {
        guard let inlineSuggestion,
              let inlineSuggestionLocation,
              selection.length == 0,
              absoluteCaret == inlineSuggestionLocation else { return }
        let local = inlineSuggestionLocation - viewportLineOriginStartUTF16
        guard let row = visualRow(containing: local, in: rows) else { return }
        let x = CGFloat(CTLineGetOffsetForStringIndex(
            row.fragment.line,
            row.coreTextStringIndex(forViewportOffset: local),
            nil
        ))
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: inlineSuggestion,
            attributes: [
                .font: editorFont,
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.6)
            ]
        ))
        VirtualEditorCoreTextDrawing.draw(
            line,
            in: context,
            at: CGPoint(x: gutterWidth + Geometry.gutterTextInset + x, y: row.baseline),
            flippedCoordinates: isFlipped
        )
    }

    private func drawHexColorSwatches(rows: [VisualRow], dirtyRect: NSRect) {
        guard VirtualEditorHexColorPreview.isSupported(language: language) else { return }
        for target in hexColorSwatchTargets(rows: rows) where target.rect.intersects(dirtyRect) {
            target.literal.color.setFill()
            let path = NSBezierPath(roundedRect: target.rect, xRadius: 2.5, yRadius: 2.5)
            path.fill()
            NSColor.separatorColor.withAlphaComponent(0.75).setStroke()
            path.lineWidth = 0.75
            path.stroke()
        }
    }

    private func drawMarkedText(rows: [VisualRow], context: CGContext) {
        guard let markedText, markedTextRange.location != NSNotFound else { return }
        let start = markedTextRange.location - viewportLineOriginStartUTF16
        guard start >= 0, start <= viewportText.utf16.count else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: editorFont,
            .foregroundColor: NSColor(resolvedEditorTheme.text),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor(resolvedEditorTheme.cursor)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: markedText, attributes: attributes))
        let point = caretPoint(localLocation: start)
        VirtualEditorCoreTextDrawing.draw(
            line,
            in: context,
            at: point,
            flippedCoordinates: isFlipped
        )
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
        let originX = gutterWidth + Geometry.gutterTextInset
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

        private var fragmentStartInLine: Int {
            fragment.absoluteStartUTF16 - localStart
        }

        private var fragmentEndInLine: Int {
            fragmentStartInLine + fragment.lengthUTF16
        }

        func coreTextStringIndex(forViewportOffset offset: Int) -> Int {
            min(max(offset - localStart, fragmentStartInLine), fragmentEndInLine)
        }

        func viewportOffset(forCoreTextStringIndex index: CFIndex, trailingFallback: Bool) -> Int {
            guard index != kCFNotFound else {
                return trailingFallback
                    ? fragment.absoluteStartUTF16 + fragment.lengthUTF16
                    : fragment.absoluteStartUTF16
            }
            return localStart + min(max(Int(index), fragmentStartInLine), fragmentEndInLine)
        }
    }

    private func visualRows() -> [VisualRow] {
        // `bounds.width` is the document canvas width. During an AppKit resize
        // it still contains the previous pane allocation until after visual
        // metrics have been recalculated. The viewport is the current editor
        // allocation and is therefore the authoritative wrapping width.
        let availableWidth = max(1, viewportSize.width - gutterWidth - 16)
        let snapshotKey = [
            lastConfigurationKey,
            String(configuredContentRevision ?? 0),
            String(configuredExternalContentRevision ?? 0),
            String(viewportLineOrigin),
            String(Int((availableWidth * 2).rounded())),
            String(Int(((enclosingScrollView?.contentView.bounds.maxY ?? viewportSize.height) * 2).rounded())),
            String(Int((lineHeight * 100).rounded()))
        ].joined(separator: "|")
        if let visualRowsSnapshot, visualRowsSnapshot.key == snapshotKey {
            return visualRowsSnapshot.rows
        }
        var rows: [VisualRow] = []
        var baseline = VirtualEditorVisualLayout.baseline(
            rowOrigin: visualRowIndex.rowOrigin(forLogicalLine: viewportLineOrigin),
            lineHeight: lineHeight,
            fontAscender: editorFont.ascender
        )
        for viewportLine in viewportLines {
            let estimatedBaseline = baseline
            let viewportMaxY = (enclosingScrollView?.contentView.bounds.maxY ?? viewportSize.height) + lineHeight * 2
            if estimatedBaseline > viewportMaxY {
                break
            }
            let fragments = cachedVisualFragments(
                for: viewportLine.text,
                localLine: viewportLine.localLine,
                absoluteStart: viewportLine.startUTF16,
                width: availableWidth
            )
            for (index, fragment) in fragments.enumerated() {
                rows.append(VisualRow(
                    logicalLine: viewportLineOrigin + viewportLine.localLine,
                    localStart: viewportLine.startUTF16,
                    fragment: fragment,
                    baseline: baseline,
                    isFirstFragment: index == 0
                ))
                baseline += lineHeight
            }
        }
        visualRowsSnapshot = (snapshotKey, rows)
        return rows
    }

    func attributedLine(_ line: String, localLine: Int) -> NSAttributedString {
        let base = NSMutableAttributedString(string: line, attributes: [
            .font: editorFont,
            .foregroundColor: NSColor(resolvedEditorTheme.text)
        ])
        let utf16Length = (line as NSString).length
        for span in syntaxSpansByLine[localLine] ?? [] where isSyntaxHighlightRangeValid(span.range, utf16Length: utf16Length) {
            base.addAttribute(.foregroundColor, value: NSColor(span.color), range: span.range)
        }
        return base
    }

    private func cachedAttributedLine(
        _ line: String,
        localLine: Int
    ) -> NSAttributedString {
        if let cached = attributedLineCache[localLine] {
            return cached
        }
        let created = attributedLine(line, localLine: localLine)
        attributedLineCache[localLine] = created
        return created
    }

    private func cachedVisualFragments(
        for line: String,
        localLine: Int,
        absoluteStart: Int,
        width: CGFloat
    ) -> [VirtualEditorVisualFragment] {
        visualFragmentCache.fragments(
            for: cachedAttributedLine(
                line,
                localLine: localLine
            ),
            localLine: localLine,
            lineStartUTF16: absoluteStart,
            width: width,
            wraps: lineWrapEnabled
        )
    }

    func visualRow(containing localLocation: Int, in rows: [VisualRow]) -> VisualRow? {
        guard let index = visualRowIndex(containing: localLocation, in: rows) else { return nil }
        return rows[index]
    }

    private func visualRowIndex(containing localLocation: Int, in rows: [VisualRow]) -> Int? {
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
        return index
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

    private func editorBaseThemeKey(for colorScheme: ColorScheme) -> String {
        let theme = currentEditorTheme(colorScheme: colorScheme)
        return [theme.text, theme.background, theme.cursor, theme.selection]
            .map { NSColor($0).description }
            .joined(separator: "|")
    }

    private func drawCurrentLineHighlight(rows: [VisualRow]) {
        guard highlightCurrentLine else { return }
        let local = absoluteCaret - viewportLineOriginStartUTF16
        guard let row = visualRow(containing: local, in: rows) else { return }
        NSColor(resolvedEditorTheme.selection)
            .withAlphaComponent(0.12)
            .setFill()
        NSRect(x: gutterWidth, y: row.baseline - lineHeight + 2, width: max(0, bounds.width - gutterWidth), height: lineHeight).fill()
    }

    private func drawSelectionBackground(rows: [VisualRow]) {
        guard selection.length > 0 else { return }
        let selectedStart = selection.location - viewportLineOriginStartUTF16
        let selectedEnd = NSMaxRange(selection) - viewportLineOriginStartUTF16
        NSColor(resolvedEditorTheme.selection)
            .withAlphaComponent(0.32)
            .setFill()
        for row in rows {
            let start = row.fragment.absoluteStartUTF16
            let end = start + row.fragment.lengthUTF16
            let left = max(start, selectedStart)
            let right = min(end, selectedEnd)
            guard left < right else { continue }
            let x = CGFloat(CTLineGetOffsetForStringIndex(
                row.fragment.line,
                row.coreTextStringIndex(forViewportOffset: left),
                nil
            ))
            let rightX = CGFloat(CTLineGetOffsetForStringIndex(
                row.fragment.line,
                row.coreTextStringIndex(forViewportOffset: right),
                nil
            ))
            NSRect(x: gutterWidth + Geometry.gutterTextInset + x, y: row.baseline - lineHeight + 2, width: max(2, rightX - x), height: lineHeight).fill()
        }
    }

    private func drawFindMatchBackgrounds(rows: [VisualRow]) {
        guard !findMatchRanges.isEmpty else { return }
        let viewportStart = viewportLineOriginStartUTF16
        let visibleStart = rows.first?.fragment.absoluteStartUTF16 ?? 0
        let visibleEnd = rows.last.map { $0.fragment.absoluteStartUTF16 + $0.fragment.lengthUTF16 } ?? 0
        for match in findMatchRanges where match.length > 0 {
            let selected = match == selectedFindMatchRange
            (selected ? NSColor.systemBlue : NSColor.systemYellow)
                .withAlphaComponent(selected ? 0.42 : 0.28)
                .setFill()
            let matchStart = match.location - viewportStart
            let matchEnd = NSMaxRange(match) - viewportStart
            guard matchEnd > visibleStart, matchStart < visibleEnd else { continue }
            for row in rows {
                let rowStart = row.fragment.absoluteStartUTF16
                let rowEnd = rowStart + row.fragment.lengthUTF16
                let left = max(rowStart, matchStart)
                let right = min(rowEnd, matchEnd)
                guard left < right else { continue }
                let x = CGFloat(CTLineGetOffsetForStringIndex(
                    row.fragment.line,
                    row.coreTextStringIndex(forViewportOffset: left),
                    nil
                ))
                let rightX = CGFloat(CTLineGetOffsetForStringIndex(
                    row.fragment.line,
                    row.coreTextStringIndex(forViewportOffset: right),
                    nil
                ))
                NSRect(
                    x: gutterWidth + Geometry.gutterTextInset + x,
                    y: row.baseline - lineHeight + 2,
                    width: max(2, rightX - x),
                    height: lineHeight
                ).fill()
            }
        }
    }

    private func drawCaret(rows: [VisualRow]) {
        guard selection.length == 0 else { return }
        let local = absoluteCaret - viewportLineOriginStartUTF16
        guard let row = visualRow(containing: local, in: rows) else { return }
        let x = CGFloat(CTLineGetOffsetForStringIndex(
            row.fragment.line,
            row.coreTextStringIndex(forViewportOffset: local),
            nil
        ))
        NSColor(resolvedEditorTheme.cursor).setFill()
        NSRect(x: gutterWidth + Geometry.gutterTextInset + x, y: row.baseline - lineHeight + 2, width: 1.5, height: lineHeight).fill()
    }

    private var viewportLineOriginStartUTF16: Int { viewport?.startUTF16Offset ?? 0 }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        clearInlineSuggestion()
        let point = convert(event.locationInWindow, from: nil)
        if let target = hexColorSwatchTargets(rows: visualRows()).first(where: { $0.rect.contains(point) }) {
            presentColorPicker(for: target.literal, relativeTo: target.rect)
            return
        }
        colorPickerPopover?.close()
        colorPickerPopover = nil
        absoluteCaret = documentOffset(at: point)
        selection = NSRange(location: absoluteCaret, length: 0)
        selectionAnchor = absoluteCaret
        publishCaret()
        needsDisplay = true
    }

    private struct HexColorSwatchTarget {
        let literal: VirtualEditorHexColorLiteral
        let rect: NSRect
    }

    private func hexColorSwatchTargets(rows: [VisualRow]) -> [HexColorSwatchTarget] {
        guard VirtualEditorHexColorPreview.isSupported(language: language) else { return [] }
        var targets: [HexColorSwatchTarget] = []
        var linesWithSwatches: Set<Int> = []
        for row in rows where row.isFirstFragment {
            let localLine = row.logicalLine - viewportLineOrigin
            guard viewportLines.indices.contains(localLine) else { continue }
            let viewportLine = viewportLines[localLine]
            let literals = VirtualEditorHexColorPreview.literals(
                in: viewportLine.text,
                absoluteStart: viewportLine.startUTF16
            )
            guard !literals.isEmpty, !linesWithSwatches.contains(row.logicalLine) else { continue }
            let lineNumber = "\(row.logicalLine + 1)" as NSString
            let numberWidth = lineNumber.size(withAttributes: [.font: editorFont]).width
            let swatchSize: CGFloat = 10
            let rect = NSRect(
                x: max(2, gutterWidth - numberWidth - Geometry.lineNumberTrailingInset - 14),
                y: row.baseline - lineHeight + 5,
                width: swatchSize,
                height: swatchSize
            )
            targets.append(HexColorSwatchTarget(literal: literals[0], rect: rect))
            linesWithSwatches.insert(row.logicalLine)
        }
        return targets
    }

    private func presentColorPicker(for literal: VirtualEditorHexColorLiteral, relativeTo rect: NSRect) {
        colorPickerPopover?.close()
        let state = VirtualEditorColorPickerState(literal: literal)
        let picker = VirtualEditorColorPickerViewController(
            color: literal.color,
            token: literal.token,
            isReadOnly: isReadOnly
        )
        picker.onColorChange = { [weak self, weak picker] color in
            guard let self,
                  let replacement = VirtualEditorHexColorPreview.replacement(for: color, preserving: state.literal.token),
                  replacement != state.literal.token else { return }
            self.selection = state.literal.range
            self.absoluteCaret = state.literal.range.location
            guard self.replaceSelection(with: replacement) else { return }
            state.literal = VirtualEditorHexColorLiteral(
                range: NSRange(location: state.literal.range.location, length: replacement.utf16.count),
                token: replacement,
                color: color
            )
            picker?.view.window?.makeFirstResponder(picker?.colorWell)
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = picker
        popover.contentSize = NSSize(width: 280, height: 220)
        colorPickerPopover = popover
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxX)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let selectionAnchor else { return }
        let caret = documentOffset(at: convert(event.locationInWindow, from: nil))
        absoluteCaret = caret
        selection = NSRange(location: min(selectionAnchor, caret), length: abs(selectionAnchor - caret))
        scheduleDragPublication()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        pendingDragPublication?.cancel()
        pendingDragPublication = nil
        publishCaret()
        super.mouseUp(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        let hasFile = pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return hasFile || plainString(from: pasteboard)?.isEmpty == false ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if publishFileURLs(from: pasteboard) { return true }
        guard !isReadOnly,
              let raw = plainString(from: pasteboard),
              !raw.isEmpty else { return false }
        absoluteCaret = documentOffset(at: convert(sender.draggingLocation, from: nil))
        selection = NSRange(location: absoluteCaret, length: 0)
        selectionAnchor = nil
        let sanitized = EditorTextSanitizer.sanitize(raw)
        guard replaceSelection(with: sanitized) else { return false }
        NotificationCenter.default.post(name: .pastedText, object: sanitized)
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if !isReadOnly {
            menu.addItem(withTitle: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        if !isReadOnly {
            menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        for item in menu.items { item.target = self }
        if selection.length > 0 {
            menu.addItem(.separator())
            let snapshot = NSMenuItem(
                title: "Create Code Snapshot",
                action: #selector(createCodeSnapshotFromSelection(_:)),
                keyEquivalent: ""
            )
            snapshot.target = self
            snapshot.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Create Code Snapshot"
            )
            menu.addItem(snapshot)
        }
        return menu
    }

    @objc private func createCodeSnapshotFromSelection(_ sender: Any?) {
        guard selection.length > 0 else { return }
        publishCaret()
        NotificationCenter.default.post(name: .editorRequestCodeSnapshotFromSelection, object: nil)
    }

    private func scheduleDragPublication() {
        guard pendingDragPublication == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDragPublication = nil
            self.publishCaret()
        }
        pendingDragPublication = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
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
        if VirtualEditorKeyRouting.matches(
            event,
            shortcut: ShortcutPreferences.shortcut(for: .closeTab)
        ) {
            requestCloseSelectedTab()
            return
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if language == "markdown",
           modifiers == .command,
           let command = EditorCommandSemantics.markdownCommand(for: event.charactersIgnoringModifiers) {
            NotificationCenter.default.post(name: .markdownFormattingRequested, object: command)
            return
        }
        if modifiers.isEmpty,
           (event.keyCode == 48 || event.keyCode == 124),
           acceptInlineSuggestion() {
            return
        }
        if vimModeIsEnabled,
           !modifiers.contains(.command),
           !modifiers.contains(.option),
           !modifiers.contains(.control) {
            if !isVimInsertMode {
                if handleVimCommand(event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode) { return }
            } else if event.keyCode == 53 || event.characters == "\u{1B}" {
                isVimInsertMode = false
                postVimModeState()
                clearInlineSuggestion()
                return
            }
        }
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

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, vimModeIsEnabled {
            isVimInsertMode = false
            postVimModeState()
        }
        return accepted
    }

    @discardableResult
    func handleVimCommand(_ key: String, keyCode: UInt16? = nil) -> Bool {
        guard !isVimInsertMode else { return false }
        switch keyCode {
        case 123: moveCaret(-1, extending: false); return true
        case 124: moveCaret(1, extending: false); return true
        case 125: moveCaretVertically(1, extending: false); return true
        case 126: moveCaretVertically(-1, extending: false); return true
        default: break
        }
        switch key {
        case "h": moveCaret(-1, extending: false)
        case "j": moveCaretVertically(1, extending: false)
        case "k": moveCaretVertically(-1, extending: false)
        case "l": moveCaret(1, extending: false)
        case "w": moveCaret(to: wordBoundary(from: absoluteCaret, direction: 1), extending: false)
        case "b": moveCaret(to: wordBoundary(from: absoluteCaret, direction: -1), extending: false)
        case "0": moveToLineBoundary(end: false)
        case "$": moveToLineBoundary(end: true)
        case "x": deleteForward()
        case "p": pasteSelection()
        case "i": isVimInsertMode = true; postVimModeState()
        case "a": moveCaret(1, extending: false); isVimInsertMode = true; postVimModeState()
        case "\u{1B}": break
        default: break
        }
        return true
    }

    private func moveToLineBoundary(end: Bool) {
        let local = max(0, min(viewportText.utf16.count, absoluteCaret - viewportLineOriginStartUTF16))
        let source = viewportText as NSString
        let lineRange = source.lineRange(for: NSRange(location: local, length: 0))
        var target = end ? NSMaxRange(lineRange) : lineRange.location
        while end, target > lineRange.location,
              source.character(at: target - 1) == 10 || source.character(at: target - 1) == 13 {
            target -= 1
        }
        moveCaret(to: viewportLineOriginStartUTF16 + target, extending: false)
    }

    private func requestCloseSelectedTab() {
        var userInfo: [AnyHashable: Any] = [:]
        if let windowNumber = window?.windowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = windowNumber
        }
        NotificationCenter.default.post(
            name: .closeSelectedTabRequested,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
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
        clearInlineSuggestion()
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
        case #selector(insertTab(_:)):
            if !acceptInlineSuggestion(), !expandEmmetAtCaret() { insertConfiguredIndentation() }
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

    private var vimModeIsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "EditorVimModeEnabled")
            && UserDefaults.standard.bool(forKey: "EditorVimInterceptionEnabled")
    }

    @objc private func updateVimMode(_ notification: Notification) {
        guard notification.object == nil || notification.object as AnyObject? === self else { return }
        isVimInsertMode = notification.userInfo?["insertMode"] as? Bool ?? !vimModeIsEnabled
        clearInlineSuggestion()
    }

    private func postVimModeState() {
        NotificationCenter.default.post(
            name: .vimModeStateDidChange,
            object: self,
            userInfo: ["insertMode": isVimInsertMode]
        )
    }

    @objc private func showInlineSuggestion(_ notification: Notification) {
        guard matchesDocument(notification),
              let suggestion = notification.userInfo?[EditorCommandUserInfo.replacementText] as? String,
              let location = notification.userInfo?[EditorCommandUserInfo.completionCaretOffset] as? Int,
              !suggestion.isEmpty,
              selection.length == 0,
              absoluteCaret == location else { return }
        inlineSuggestion = EditorTextSanitizer.sanitize(suggestion)
        inlineSuggestionLocation = location
        needsDisplay = true
    }

    private func clearInlineSuggestion() {
        guard inlineSuggestion != nil || inlineSuggestionLocation != nil else { return }
        inlineSuggestion = nil
        inlineSuggestionLocation = nil
        needsDisplay = true
    }

    @discardableResult
    private func acceptInlineSuggestion() -> Bool {
        guard let suggestion = inlineSuggestion,
              inlineSuggestionLocation == absoluteCaret,
              selection.length == 0 else {
            clearInlineSuggestion()
            return false
        }
        clearInlineSuggestion()
        return replaceSelection(with: suggestion)
    }

    private func insertConfiguredIndentation() {
        let insertion = EditorCommandSemantics.indentation(style: indentStyle, width: indentWidth)
        replaceSelection(with: insertion)
    }

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
            attributes: [.font: editorFont, .foregroundColor: NSColor(currentEditorTheme(colorScheme: scheme).text)]
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

    @discardableResult
    private func replaceSelection(with value: String) -> Bool {
        guard let document, let documentID else { return false }
        clearInlineSuggestion()
        let selectionEnd = NSMaxRange(selection)
        let viewportContainsSelection = viewport != nil &&
            selection.location >= viewportStartUTF16 &&
            selectionEnd <= viewportStartUTF16 + viewportText.utf16.count
        guard viewportContainsSelection else {
            let location = min(max(0, selection.location), document.utf16Length)
            let length = min(max(0, selection.length), document.utf16Length - location)
            guard let original = try? document.text(inUTF16Range: NSRange(location: location, length: length)) else {
                return false
            }
            guard onTextMutation?(EditorTextMutation(documentID: documentID, range: NSRange(location: location, length: length), replacement: value)) == true else { return false }
            registerUndo(replacement: original, range: NSRange(location: location, length: value.utf16.count), inverseReplacement: value)
            absoluteCaret = location + value.utf16.count
            selection = NSRange(location: absoluteCaret, length: 0)
            selectionAnchor = nil
            reloadViewport(anchorLine: lineForAbsoluteOffset(absoluteCaret), maximumByteCount: editRefreshMaximumByteCount)
            publishCaret()
            publishTextChange()
            return true
        }
        guard let viewport else { return false }
        let local = max(0, min(selection.location - viewportStartUTF16, viewportText.utf16.count))
        let length = min(selection.length, max(0, viewportText.utf16.count - local))
        let range = NSRange(location: local, length: length)
        let original = (viewportText as NSString).substring(with: range)
        let absoluteRange = NSRange(location: selection.location, length: length)
        guard onTextMutation?(EditorTextMutation(documentID: documentID, range: range, replacement: value, viewport: viewport)) == true else {
            reloadViewport(anchorLine: viewportLineOrigin)
            return false
        }
        registerUndo(
            replacement: original,
            range: NSRange(location: absoluteRange.location, length: value.utf16.count),
            inverseReplacement: value
        )
        absoluteCaret = absoluteRange.location + value.utf16.count
        selection = NSRange(location: absoluteCaret, length: 0)
        selectionAnchor = nil
        // The next native key event can arrive before SwiftUI configures again.
        // Refresh byte/UTF-16 coordinates before publishing or accepting input.
        reloadViewport(anchorLine: lineForAbsoluteOffset(absoluteRange.location), maximumByteCount: editRefreshMaximumByteCount)
        publishCaret()
        publishTextChange()
        return true
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

    private func expandEmmetAtCaret() -> Bool {
        guard !isReadOnly,
              selection.length == 0,
              let viewport,
              absoluteCaret >= viewport.startUTF16Offset,
              absoluteCaret <= viewport.startUTF16Offset + viewportText.utf16.count,
              let expansion = EmmetExpander.expansionIfPossible(
                in: viewportText,
                cursorUTF16Location: absoluteCaret - viewport.startUTF16Offset,
                language: language,
                indentStyle: indentStyle,
                indentWidth: indentWidth
              ) else { return false }

        let previousCaret = absoluteCaret
        let previousSelection = selection
        let absoluteRange = NSRange(
            location: viewport.startUTF16Offset + expansion.range.location,
            length: expansion.range.length
        )
        absoluteCaret = absoluteRange.location
        selection = absoluteRange
        guard replaceSelection(with: expansion.expansion) else {
            absoluteCaret = previousCaret
            selection = previousSelection
            return false
        }

        absoluteCaret = absoluteRange.location + expansion.caretOffset
        selection = NSRange(location: absoluteCaret, length: 0)
        publishCaret()
        needsDisplay = true
        return true
    }

    @objc func inspectWhitespaceScalars(_ notification: Notification) {
        if let targetWindowNumber = notification.userInfo?[EditorCommandUserInfo.windowNumber] as? Int,
           let ownWindowNumber = window?.windowNumber,
           targetWindowNumber != ownWindowNumber { return }
        let localCaret = max(0, min(viewportText.utf16.count, absoluteCaret - viewportLineOriginStartUTF16))
        let source = viewportText as NSString
        let lineRange = source.lineRange(for: NSRange(location: localCaret, length: 0))
        let line = source.substring(with: lineRange)
        var counts: [UInt32: Int] = [:]
        for scalar in line.unicodeScalars {
            let value = scalar.value
            let isWhitespace = scalar.properties.generalCategory == .spaceSeparator || value == 0x20 || value == 0x09
            if isWhitespace || value == 0x0A || value == 0x0D || (0x2400...0x243F).contains(value) || value == 0x2581 {
                counts[value, default: 0] += 1
            }
        }
        let body = counts.isEmpty
            ? "none detected"
            : counts.keys.sorted().map { "\(whitespaceScalarName($0)) x\(counts[$0] ?? 0)" }.joined(separator: ", ")
        NotificationCenter.default.post(
            name: .whitespaceScalarInspectionResult,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.windowNumber: window?.windowNumber ?? -1,
                EditorCommandUserInfo.inspectionMessage:
                    "Line \(lineForAbsoluteOffset(absoluteCaret) + 1) at UTF16@\(absoluteCaret), whitespace scalars:\n\(body)"
            ]
        )
    }

    private func whitespaceScalarName(_ value: UInt32) -> String {
        switch value {
        case 0x20: return "SPACE"
        case 0x09: return "TAB"
        case 0x0A: return "LF"
        case 0x0D: return "CR"
        case 0x2581: return "LOWER_ONE_EIGHTH_BLOCK"
        default: return "U+\(String(format: "%04X", value))"
        }
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
        let normalizedIndent = String(indentation)
        let listPrefix = continuedMarkdownListPrefix(
            for: context.linePrefix,
            normalizedIndent: normalizedIndent
        )
        replaceSelection(with: "\n" + (listPrefix ?? normalizedIndent))
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
        reloadViewport(anchorLine: lineForAbsoluteOffset(location), maximumByteCount: editRefreshMaximumByteCount)
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
            let location = min(max(0, selection.location), document.utf16Length)
            let length = min(max(0, selection.length), document.utf16Length - location)
            guard let selectedText = try? document.text(inUTF16Range: NSRange(location: location, length: length)) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText, forType: .string)
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
        let pasteboard = NSPasteboard.general
        if publishFileURLs(from: pasteboard) { return }
        guard let text = plainString(from: pasteboard) else { return }
        if let fileURL = fileURL(from: text) {
            NotificationCenter.default.post(name: .pastedFileURL, object: fileURL)
            return
        }
        let sanitized = EditorTextSanitizer.sanitize(text)
        guard replaceSelection(with: sanitized) else { return }
        NotificationCenter.default.post(name: .pastedText, object: sanitized)
    }

    @discardableResult
    private func publishFileURLs(from pasteboard: NSPasteboard) -> Bool {
        guard let values = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL], !values.isEmpty else { return false }
        let urls = values.map { $0 as URL }
        NotificationCenter.default.post(name: .pastedFileURL, object: urls.count == 1 ? urls[0] : urls)
        return true
    }

    private func plainString(from pasteboard: NSPasteboard) -> String? {
        if let raw = pasteboard.string(forType: .string), !raw.isEmpty { return raw }
        if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [NSString],
           let first = strings.first, first.length > 0 {
            return first as String
        }
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ), !attributed.string.isEmpty {
            return attributed.string
        }
        return nil
    }

    private func fileURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
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
            applyCaretLocation(nextCaretLocation(from: absoluteCaret, delta: delta), extending: extending)
        }
        finishCaretMovement()
    }

    private func moveCaret(to location: Int, extending: Bool) {
        applyCaretLocation(location, extending: extending)
        finishCaretMovement()
    }

    private func applyCaretLocation(_ location: Int, extending: Bool) {
        let next = max(0, min(document?.utf16Length ?? location, location))
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

    private func finishCaretMovement() {
        clearInlineSuggestion()
        ensureCaretVisible()
        publishCaret()
        needsDisplay = true
    }

    private func nextCaretLocation(from location: Int, delta: Int) -> Int {
        guard let document else {
            return location
        }
        guard delta == -1 || delta == 1 else {
            return max(0, min(document.utf16Length, location + delta))
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

    private func caretLocation(in row: VisualRow, atX x: CGFloat) -> Int {
        let lineIndex = CTLineGetStringIndexForPosition(
            row.fragment.line,
            CGPoint(x: max(0, x), y: 0)
        )
        let viewportOffset = row.viewportOffset(
            forCoreTextStringIndex: lineIndex,
            trailingFallback: true
        )
        return viewportLineOriginStartUTF16 + viewportOffset
    }

    private func moveCaretVertically(_ direction: Int, extending: Bool) {
        let local = max(0, absoluteCaret - viewportLineOriginStartUTF16)
        let rows = visualRows()
        let currentRowIndex = visualRowIndex(containing: local, in: rows)
        let preferredX: CGFloat? = currentRowIndex.map { index in
            let row = rows[index]
            return CGFloat(CTLineGetOffsetForStringIndex(
                row.fragment.line,
                row.coreTextStringIndex(forViewportOffset: local),
                nil
            ))
        }
        if let currentRowIndex {
            let targetRowIndex = currentRowIndex + direction
            if rows.indices.contains(targetRowIndex) {
                moveCaret(
                    to: caretLocation(in: rows[targetRowIndex], atX: preferredX ?? 0),
                    extending: extending
                )
                return
            }
        }

        let currentLine = lineForAbsoluteOffset(absoluteCaret)
        let currentLocalLine = min(lineStarts.count - 1, newlineCount(inUTF16PrefixOf: viewportText, length: local))
        let column = local - lineStarts[currentLocalLine]
        let targetLine = currentLine + direction
        guard targetLine >= 0, targetLine < (document?.lineCount ?? 1) else { return }
        reloadViewport(anchorLine: targetLine)

        if let preferredX {
            let targetRows = visualRows().filter { $0.logicalLine == targetLine }
            let targetRow = direction > 0 ? targetRows.first : targetRows.last
            if let targetRow {
                moveCaret(to: caretLocation(in: targetRow, atX: preferredX), extending: extending)
                return
            }
        }

        let localLine = max(0, min(lineStarts.count - 1, targetLine - viewportLineOrigin))
        let targetStart = lineStarts[localLine]
        let targetEnd = localLine + 1 < lineStarts.count ? lineStarts[localLine + 1] : viewportText.utf16.count
        moveCaret(
            to: viewportLineOriginStartUTF16 + targetStart + min(column, max(0, targetEnd - targetStart)),
            extending: extending
        )
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
        let visibleHeight = enclosingScrollView?.contentView.bounds.height ?? 0
        let maximumY = max(0, logicalHeight - visibleHeight)
        let isAtBottom = scrollY >= maximumY - max(1, lineHeight)
        let target = VirtualEditorScrollAnchorPolicy.anchorLine(
            scrollY: scrollY,
            lineHeight: lineHeight,
            estimatedRowsPerLogicalLine: estimatedRowsPerLogicalLine,
            prefetchLines: 20,
            documentLineCount: document?.lineCount ?? 1,
            isAtBottom: isAtBottom
        )
        guard target < viewportLineOrigin || target >= viewportLineOrigin + lineStarts.count - 20 else { return }
        reloadViewport(anchorLine: target)
    }

    private func reloadViewport(anchorLine: Int, maximumByteCount: Int? = nil) {
        guard let document, let next = try? document.viewport(
            aroundLine: max(0, anchorLine),
            maximumByteCount: maximumByteCount ?? viewportMaximumByteCount,
            maximumLineCount: 512
        ) else { return }
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
        let nsViewportText = viewportText as NSString
        viewportLines = lineStarts.indices.map { localLine in
            let start = lineStarts[localLine]
            let end = localLine + 1 < lineStarts.count ? lineStarts[localLine + 1] : nsViewportText.length
            return VirtualEditorViewportLine(
                localLine: localLine,
                startUTF16: start,
                text: nsViewportText
                    .substring(with: NSRange(location: start, length: max(0, end - start)))
                    .trimmingCharacters(in: .newlines)
            )
        }
        scheduleSyntaxHighlighting()
        visualRowsSnapshot = nil
        contentWidth = lineWrapEnabled ? max(viewportSize.width, 1) : unwrappedContentWidth()
        layoutCache.removeAll(keepingCapacity: true)
        needsDisplay = true
    }

    private func unwrappedContentWidth() -> CGFloat {
        guard !viewportText.isEmpty else { return max(viewportSize.width, 1) }
        var maximum: CGFloat = 0
        for viewportLine in viewportLines {
            let line = CTLineCreateWithAttributedString(attributedLine(
                viewportLine.text,
                localLine: viewportLine.localLine
            ))
            maximum = max(maximum, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        return max(viewportSize.width, gutterWidth + 16 + maximum)
    }

    /// Read immutable chunks on the document's owning actor, then scan off actor.
    /// Cached viewport boundaries avoid rescanning a prefix when scrolling back.
    private func htmlContext(before target: EditorDocumentViewport, colors: SyntaxColors) async throws -> HTMLSyntaxState {
        guard let document else { return HTMLSyntaxState() }
        let identity = ObjectIdentifier(document)
        if htmlContextDocument != identity || htmlContextGeneration != target.generation {
            htmlContexts = [0: HTMLSyntaxState()]
            htmlContextDocument = identity
            htmlContextGeneration = target.generation
        }
        let start = htmlContexts.keys.filter { $0 <= target.startByteOffset }.max() ?? 0
        var state = htmlContexts[start] ?? HTMLSyntaxState()
        var offset = start
        var pending = ""
        while offset < target.startByteOffset {
            try Task.checkCancellation()
            let chunk = try document.textChunk(startByteOffset: offset, maximumByteCount: min(64 * 1024, target.startByteOffset - offset))
            guard chunk.byteCount > 0 else { throw FileBackedTextDocument.Error.invalidRange }
            offset += chunk.byteCount
            let source = pending + chunk.text
            let initialState = state
            let isFinal = offset == target.startByteOffset
            let worker = Task.detached(priority: .userInitiated) {
                let text = source as NSString
                let length = isFinal ? text.length : HTMLSyntaxHighlighter.safePrefixLength(text)
                var nextState = initialState
                _ = HTMLSyntaxHighlighter.ranges(in: text, range: NSRange(location: 0, length: length), state: &nextState, colors: colors, emitColors: false)
                return (nextState, text.substring(from: length))
            }
            (state, pending) = await worker.value
            try Task.checkCancellation()
        }
        if htmlContexts.count >= 128 { htmlContexts = [0: HTMLSyntaxState()] }
        htmlContexts[target.startByteOffset] = state
        return state
    }

    private func scheduleSyntaxHighlighting() {
        syntaxHighlightTask?.cancel()
        syntaxHighlightGeneration &+= 1
        let generation = syntaxHighlightGeneration
        let lines = viewportLines
        let syntaxLanguage = language
        let syntaxTheme = syntaxThemeKey(for: scheme)
        let colors = resolvedSyntaxColors
        let patterns = getSyntaxPatterns(for: syntaxLanguage, colors: colors)
        let htmlText = viewportText
        let htmlViewport = isHTMLLikeSyntaxLanguage(syntaxLanguage) ? viewport : nil
        syntaxHighlightTask = Task { [weak self] in
            let initialHTMLState: HTMLSyntaxState?
            if let htmlViewport {
                do { initialHTMLState = try await self?.htmlContext(before: htmlViewport, colors: colors) }
                catch { return }
            } else { initialHTMLState = nil }
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                var result: [Int: [VirtualEditorSyntaxSpan]] = [:]
                result.reserveCapacity(lines.count)
                if var state = initialHTMLState {
                    let text = htmlText as NSString
                    let ranges = HTMLSyntaxHighlighter.ranges(in: text, range: NSRange(location: 0, length: text.length), state: &state, colors: colors)
                    for (range, color) in ranges {
                        guard !Task.isCancelled else { return result }
                        var low = 0
                        var high = lines.count
                        while low < high {
                            let middle = (low + high) / 2
                            if lines[middle].startUTF16 <= range.location { low = middle + 1 }
                            else { high = middle }
                        }
                        var index = max(0, low - 1)
                        while index < lines.count && lines[index].startUTF16 < NSMaxRange(range) {
                            let line = lines[index]
                            let overlap = NSIntersectionRange(range, NSRange(location: line.startUTF16, length: line.text.utf16.count))
                            if overlap.length > 0 {
                                result[line.localLine, default: []].append(VirtualEditorSyntaxSpan(
                                    range: NSRange(location: overlap.location - line.startUTF16, length: overlap.length), color: color))
                            }
                            index += 1
                        }
                    }
                    return result
                }
                for line in lines {
                    guard !Task.isCancelled else { return result }
                    let cacheKey = VirtualEditorSyntaxLineCacheKey(
                        language: syntaxLanguage,
                        theme: syntaxTheme,
                        text: line.text
                    )
                    if let cachedSpans = VirtualEditorSyntaxLineCache.spans(for: cacheKey) {
                        if !cachedSpans.isEmpty { result[line.localLine] = cachedSpans }
                        continue
                    }
                    let range = NSRange(location: 0, length: (line.text as NSString).length)
                    guard range.length > 0 else {
                        VirtualEditorSyntaxLineCache.store([], for: cacheKey)
                        continue
                    }
                    var lineSpans: [VirtualEditorSyntaxSpan] = []
                    for (pattern, color) in patterns {
                        guard !Task.isCancelled else { return result }
                        guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                        lineSpans.append(contentsOf: regex.matches(in: line.text, range: range).map {
                            VirtualEditorSyntaxSpan(range: $0.range, color: color)
                        })
                    }
                    VirtualEditorSyntaxLineCache.store(lineSpans, for: cacheKey)
                    if !lineSpans.isEmpty { result[line.localLine] = lineSpans }
                }
                return result
            }
            let spans = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, !Task.isCancelled, generation == self.syntaxHighlightGeneration else { return }
            self.syntaxSpansByLine = spans
            self.attributedLineCache.removeAll(keepingCapacity: true)
            self.visualFragmentCache.removeAll(keepingCapacity: true)
            self.visualRowsSnapshot = nil
            self.layoutCache.removeAll(keepingCapacity: true)
            self.needsDisplay = true
        }
    }

    private func caretPoint(localLocation: Int) -> CGPoint {
        let rows = visualRows()
        guard let row = visualRow(containing: localLocation, in: rows) else {
            return CGPoint(x: gutterWidth + Geometry.gutterTextInset, y: 8)
        }
        let x = CGFloat(CTLineGetOffsetForStringIndex(
            row.fragment.line,
            row.coreTextStringIndex(forViewportOffset: localLocation),
            nil
        ))
        return CGPoint(x: gutterWidth + Geometry.gutterTextInset + x, y: row.baseline - lineHeight + 2)
    }

    private func documentOffset(at point: NSPoint) -> Int {
        guard let row = visualRows().min(by: { abs($0.baseline - point.y) < abs($1.baseline - point.y) }) else {
            return viewportLineOriginStartUTF16
        }
        let index = CTLineGetStringIndexForPosition(
            row.fragment.line,
            CGPoint(x: max(0, point.x - gutterWidth - Geometry.gutterTextInset), y: 0)
        )
        let localOffset = row.viewportOffset(
            forCoreTextStringIndex: index,
            trailingFallback: point.x > gutterWidth + Geometry.gutterTextInset
        )
        return viewportLineOriginStartUTF16 + localOffset
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
