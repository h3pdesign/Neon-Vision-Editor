#if os(macOS)
import AppKit



/// MARK: - Types

private struct RulerObserverToken: @unchecked Sendable {
    let raw: NSObjectProtocol
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let inset: CGFloat = 6
    private var observers: [RulerObserverToken] = []
    private var cachedDigitCount: Int = 2
    private var cachedLineStarts: [Int] = [0]
    private var cachedTextLength: Int = 0
    private var needsLineCacheRebuild: Bool = true
    private var lineNumberColor: NSColor {
        NSColor.labelColor.withAlphaComponent(0.70)
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 48
        installObservers(textView: textView)
        updateRuleThicknessIfNeeded()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.ruleThickness = 48
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer.raw)
        }
    }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        rebuildLineCacheIfNeeded()

        let bg: NSColor = {
            guard let tv = textView else { return .windowBackgroundColor }
            let color = tv.backgroundColor
            if color.alphaComponent >= 0.99 {
                return color
            }
            if let windowColor = tv.window?.backgroundColor {
                return windowColor
            }
            return .windowBackgroundColor
        }()
        bg.setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.09).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let tv = textView,
            let lm = tv.layoutManager,
            let textContainer = tv.textContainer
        else { return }

        rebuildLineCacheIfNeeded()
        let fullString = tv.string as NSString
        let textLength = fullString.length
        let visibleRect = tv.visibleRect
        let tcOrigin = tv.textContainerOrigin
        guard textLength >= 0 else { return }
        if textLength == 0 {
            let numberString = NSString(string: "1")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: lineNumberColor
            ]
            let size = numberString.size(withAttributes: attributes)
            let drawPoint = NSPoint(x: bounds.maxX - size.width - inset, y: tcOrigin.y + 2)
            numberString.draw(at: drawPoint, withAttributes: attributes)
            return
        }

        let visibleRectInContainer = visibleRect.offsetBy(dx: -tcOrigin.x, dy: -tcOrigin.y)
        let visibleGlyphRange = lm.glyphRange(forBoundingRect: visibleRectInContainer, in: textContainer)
        guard visibleGlyphRange.location != NSNotFound else { return }

        var drawnLineStarts = Set<Int>()
        lm.enumerateLineFragments(forGlyphRange: visibleGlyphRange) { [self] _, usedRect, _, glyphRange, _ in
            guard glyphRange.location != NSNotFound else { return }
            let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.location != NSNotFound, charRange.location < textLength else { return }

            let lineRange = fullString.lineRange(for: NSRange(location: charRange.location, length: 0))
            let lineStart = lineRange.location
            if drawnLineStarts.contains(lineStart) { return }
            drawnLineStarts.insert(lineStart)

            let lineNumber = lineNumber(forCharacterLocation: lineStart)

            let numberString = NSString(string: "\(lineNumber)")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: self.font,
                .foregroundColor: self.lineNumberColor
            ]
            let size = numberString.size(withAttributes: attributes)

            let lineRectInView = NSRect(
                x: usedRect.origin.x + tcOrigin.x,
                y: usedRect.origin.y + tcOrigin.y,
                width: usedRect.size.width,
                height: usedRect.size.height
            )
            let originInRuler = self.convert(NSPoint(x: 0, y: lineRectInView.minY), from: tv)
            let drawY = originInRuler.y + (lineRectInView.height - size.height) / 2.0
            let drawPoint = NSPoint(x: self.bounds.maxX - size.width - self.inset, y: drawY)
            numberString.draw(at: drawPoint, withAttributes: attributes)
        }

        // Keep the last line number visible near end-of-document/bottom-scroll edge cases
        // where AppKit can report an empty visible glyph range.
        if drawnLineStarts.isEmpty, textLength > 0 {
            let lastLineNumber = max(1, cachedLineStarts.count)
            let numberString = NSString(string: "\(lastLineNumber)")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: lineNumberColor
            ]
            let size = numberString.size(withAttributes: attributes)
            let drawY = max(bounds.minY + 2, bounds.maxY - size.height - 6)
            let drawPoint = NSPoint(x: bounds.maxX - size.width - inset, y: drawY)
            numberString.draw(at: drawPoint, withAttributes: attributes)
        }
    }

    private func installObservers(textView: NSTextView) {
        let center = NotificationCenter.default
        observers.append(RulerObserverToken(raw: center.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.needsLineCacheRebuild = true
                self.updateRuleThicknessIfNeeded()
                self.needsDisplay = true
            }
        }))
        observers.append(RulerObserverToken(raw: center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateRuleThicknessIfNeeded()
                self.needsDisplay = true
            }
        }))
        observers.append(RulerObserverToken(raw: center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateRuleThicknessIfNeeded()
                self.needsDisplay = true
            }
        }))
        observers.append(RulerObserverToken(raw: center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateRuleThicknessIfNeeded()
                self.needsDisplay = true
            }
        }))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    @discardableResult
    private func updateRuleThicknessIfNeeded() -> Bool {
        rebuildLineCacheIfNeeded()
        let lineCount = max(1, cachedLineStarts.count)
        let digits = max(2, String(lineCount).count)
        let glyphWidth = NSString(string: "8").size(withAttributes: [.font: font]).width
        let targetThickness = ceil((glyphWidth * CGFloat(digits)) + (inset * 2) + 8)
        cachedDigitCount = digits
        if abs(ruleThickness - targetThickness) > 0.5 {
            ruleThickness = targetThickness
            scrollView?.tile()
            return true
        }
        return false
    }

    @MainActor
    func forceRulerLayoutRefresh() {
        needsLineCacheRebuild = true
        let didRetileFromThickness = updateRuleThicknessIfNeeded()
        if !didRetileFromThickness {
            scrollView?.tile()
        }
        needsDisplay = true
    }

    // Keep line-number lookup O(log n) while scrolling by caching UTF-16 line starts.
    private func rebuildLineCacheIfNeeded() {
        guard let tv = textView else { return }
        let text = tv.string
        if !needsLineCacheRebuild, cachedTextLength == (text as NSString).length {
            return
        }

        var starts: [Int] = [0]
        starts.reserveCapacity(max(16, cachedLineStarts.count))
        var utf16Index = 0
        for unit in text.utf16 {
            if unit == 10 { // '\n'
                starts.append(utf16Index + 1)
            }
            utf16Index += 1
        }

        cachedLineStarts = starts
        cachedTextLength = utf16Index
        needsLineCacheRebuild = false
    }

    private func lineNumber(forCharacterLocation location: Int) -> Int {
        guard !cachedLineStarts.isEmpty else { return 1 }
        let clampedLocation = max(0, min(location, cachedTextLength))
        var low = 0
        var high = cachedLineStarts.count - 1
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            if cachedLineStarts[mid] <= clampedLocation {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best + 1
    }
}
#endif
