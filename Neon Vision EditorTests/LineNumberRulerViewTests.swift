import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit

@MainActor
final class LineNumberRulerViewTests: XCTestCase {
    func testGutterStartsAtThreeDigitsAndDoesNotShrinkAfterLargerDocument() {
        let scrollView = configuredScrollView()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler

        textView.string = String(repeating: "line\n", count: 12)
        ruler.forceRulerLayoutRefresh()
        let threeDigitThickness = ruler.ruleThickness

        textView.string = String(repeating: "line\n", count: 1_000)
        ruler.forceRulerLayoutRefresh()
        let fourDigitThickness = ruler.ruleThickness

        textView.string = "line\n"
        ruler.forceRulerLayoutRefresh()

        XCTAssertGreaterThan(fourDigitThickness, threeDigitThickness)
        XCTAssertEqual(ruler.ruleThickness, fourDigitThickness, accuracy: 0.5)
        XCTAssertTrue(ruler.isOpaque)
    }

    func testEnablingWrapConstrainsPreviouslyWideDocumentAndResetsHorizontalOffset() {
        let scrollView = configuredScrollView()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 1_600, height: 400))
        textView.string = String(repeating: "a very long editor line ", count: 80)
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.tile()

        applyMacEditorWrapMode(isWrapped: false, textView: textView, scrollView: scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 300, y: 0))
        textView.setFrameOrigin(NSPoint(x: 48, y: 0))

        applyMacEditorWrapMode(isWrapped: true, textView: textView, scrollView: scrollView)

        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertEqual(scrollView.horizontalScrollElasticity, .none)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
        XCTAssertLessThanOrEqual(textView.frame.width, scrollView.contentSize.width + 0.5)
        XCTAssertEqual(textView.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.x,
            editorLeadingHorizontalOrigin(for: textView, in: scrollView),
            accuracy: 0.5
        )
    }

    func testNoWrapHorizontalScrollingUsesTheTranslucentRulerBackdrop() {
        let scrollView = configuredScrollView()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 1_200, height: 400))
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(
            textView: textView,
            scrollView: scrollView,
            usesTranslucentBackground: true
        )
        scrollView.verticalRulerView = ruler
        scrollView.tile()
        applyMacEditorWrapMode(isWrapped: false, textView: textView, scrollView: scrollView)

        XCTAssertFalse(ruler.isOpaque)
        XCTAssertTrue(ruler.hasTranslucentBackdropAttached)
        XCTAssertLessThan(scrollView.contentView.frame.minX, ruler.frame.maxX - 0.5)
        let leadingX = editorLeadingHorizontalOrigin(for: textView, in: scrollView)
        XCTAssertLessThan(leadingX, 0)
        scrollView.contentView.scroll(to: NSPoint(x: 300, y: 0))
        scrollView.tile()
        XCTAssertFalse(ruler.isOpaque)
    }

    private func configuredScrollView() -> NSScrollView {
        NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }
}
#endif
