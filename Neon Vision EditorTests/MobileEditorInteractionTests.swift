#if os(iOS)
import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

@MainActor
final class MobileEditorInteractionTests: XCTestCase {
    private func editor(
        _ text: String,
        wrap: Bool = false,
        documentID: UUID? = nil,
        language: String = "plain text",
        onTextMutation: ((EditorTextMutation) -> Void)? = nil
    ) -> CustomTextEditor {
        CustomTextEditor(text: .constant(text), document: nil, documentID: documentID,
            documentResourceID: "mobile-regression", storedCaretLocation: nil,
            externalEditRevision: 0, language: language, colorScheme: .light,
            ignoreBackgroundOverrides: false,
            fontSize: 16, isLineWrapEnabled: .constant(wrap), isLargeFileMode: false,
            showsCodeMinimap: false, translucentBackgroundEnabled: false,
            showKeyboardAccessoryBar: false, showLineNumbers: true,
            formattingPreferences: .init(boldKeywords: false, italicComments: false,
                underlineLinks: false, boldMarkdownHeadings: false),
            showInvisibleCharacters: false, highlightCurrentLine: false,
            highlightMatchingBrackets: false, showIndentationGuides: false,
            showScopeGuides: false, highlightScopeBackground: false,
            indentStyle: "spaces", indentWidth: 4, autoIndentEnabled: false,
            autoCloseBracketsEnabled: false, highlightRefreshToken: 0,
            isTabLoadingContent: false, isReadOnly: false,
            onFontSizeChange: nil, onTextMutation: onTextMutation)
    }

    private func withEditor(_ text: String, body: (LineNumberedTextViewContainer) -> Void) {
        let host = UIHostingController(rootView: editor(text))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        func find(_ view: UIView) -> LineNumberedTextViewContainer? {
            if let container = view as? LineNumberedTextViewContainer { return container }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let container = find(host.view) else { return XCTFail("Missing editor") }
        body(container)
        window.isHidden = true
    }

    func testUnwrappedLongLineKeepsLastGlyphReachable() {
        withEditor(String(repeating: "W", count: 5_000)) { container in
            let view = container.textView
            view.layoutManager.ensureLayout(for: view.textContainer)
            let last = view.layoutManager.glyphIndexForCharacter(at: view.textStorage.length - 1)
            let rect = view.layoutManager.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: view.textContainer)
            XCTAssertGreaterThan(rect.width, 0, "The final character must not be clipped away")
            XCTAssertLessThanOrEqual(rect.maxX, view.textContainer.size.width)
            XCTAssertGreaterThan(view.textContainer.size.width, 40_000)
        }
    }

    func testUnwrappedUnicodeLineFitsItsActualTypographicWidth() {
        let source = String(repeating: "漢", count: 5_000)
        withEditor(source) { container in
            let view = container.textView
            let expected = (source as NSString).size(withAttributes: [.font: view.font!]).width
            XCTAssertGreaterThanOrEqual(view.textContainer.size.width, expected)
        }
    }

    func testNoWrapTypingDoesNotJumpViewportWhenCapacityGrows() {
        withEditor(String(repeating: "W", count: 5_000)) { container in
            let view = container.textView
            XCTAssertTrue(view.becomeFirstResponder())
            view.selectedRange = NSRange(location: 0, length: 0)
            view.layoutIfNeeded()
            let initialOffset = view.contentOffset

            for _ in 0..<20 {
                view.insertText("x")
                view.layoutIfNeeded()
                XCTAssertEqual(view.contentOffset.x, initialOffset.x, accuracy: 0.5)
                XCTAssertEqual(view.contentOffset.y, initialOffset.y, accuracy: 0.5)
            }
        }
    }

    func testEmptyNoWrapDocumentDoesNotExposeArbitraryHorizontalCanvas() {
        withEditor("") { container in
            let view = container.textView
            XCTAssertLessThanOrEqual(view.contentSize.width, view.bounds.width + 1)
            XCTAssertFalse(view.alwaysBounceHorizontal)
            XCTAssertFalse(view.showsHorizontalScrollIndicator)
        }
    }

    func testBottomInsetReservesThreeLines() {
        withEditor("one\ntwo") { container in
            XCTAssertGreaterThanOrEqual(container.textView.textContainerInset.bottom,
                (container.textView.font?.lineHeight ?? 0) * 3)
        }
    }

    func testTripleTapRecognizerExistsWithoutDelayingOrdinaryTouches() {
        withEditor("one\ntwo") { container in
            let taps = (container.textView.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }
            XCTAssertTrue(taps.contains { $0.numberOfTapsRequired == 3 && !$0.delaysTouchesBegan })
        }
    }

    func testIOSPointerSelectionDoesNotEnableTextDragInteraction() {
        XCTAssertFalse(EditorPointerSelectionPolicy.shouldEnableTextDragInteraction(for: .pad))
        XCTAssertFalse(EditorPointerSelectionPolicy.shouldEnableTextDragInteraction(for: .phone))
    }

    func testLogicalLineSelectionPreservesUnicodeAndIncludesLineEnding() {
        let view = EditorInputTextView()
        view.text = "😀 first\r\nsecond\n"
        view.selectLogicalLine(at: 3)
        XCTAssertEqual((view.text as NSString).substring(with: view.selectedRange), "😀 first\r\n")
        view.selectLogicalLine(at: view.textStorage.length)
        XCTAssertEqual(view.selectedRange, NSRange(location: view.textStorage.length, length: 0))
        view.isSelectable = false
        view.selectLogicalLine(at: 0)
        XCTAssertEqual(view.selectedRange.length, 0)
        XCTAssertEqual(view.accessibilityCustomActions?.first?.name, "Select Line")
    }

    func testStoredCaretUpdateDoesNotCollapseTripleTapSelection() {
        XCTAssertFalse(CustomTextEditor.shouldRestoreStoredCaret(
            didSwitchDocumentResource: false,
            didChangeStoredCaretLocation: true,
            selectionLength: 12
        ))
        XCTAssertTrue(CustomTextEditor.shouldRestoreStoredCaret(
            didSwitchDocumentResource: false,
            didChangeStoredCaretLocation: true,
            selectionLength: 0
        ))
        XCTAssertTrue(CustomTextEditor.shouldRestoreStoredCaret(
            didSwitchDocumentResource: true,
            didChangeStoredCaretLocation: false,
            selectionLength: 12
        ))
    }

    func testActiveTypingUpdatesLineNumbersImmediately() {
        withEditor("one\ntwo") { container in
            let view = container.textView
            view.becomeFirstResponder()
            view.selectedRange = NSRange(location: 3, length: 0)
            view.insertText("\n")
            XCTAssertEqual(container.lineNumberView.lineStarts, EditorLineStartIndex.offsets(in: view.text))
        }
    }

    func testCaretHasThreeLinesOfRoomAfterTypingAtEOF() {
        withEditor(String(repeating: "line\n", count: 50)) { container in
            let view = container.textView
            XCTAssertTrue(view.becomeFirstResponder())
            view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
            view.layoutIfNeeded()
            view.revealCaretWithContext()
            let scrolled = expectation(description: "UIKit completes its pending layout and scroll")
            DispatchQueue.main.async { scrolled.fulfill() }
            wait(for: [scrolled], timeout: 2)
            let caret = view.caretRect(for: view.endOfDocument)
            XCTAssertGreaterThanOrEqual(view.bounds.maxY - caret.maxY, view.editingLineHeight * 3 - 1,
                "firstResponder=\(view.isFirstResponder) bounds=\(view.bounds) content=\(view.contentSize) caret=\(caret) inset=\(view.textContainerInset)")
        }
    }

    func testEmptyGutterAndHorizontalScrollRenderNumbers() {
        for text in ["", "short\n" + String(repeating: "W", count: 5_000)] {
            withEditor(text) { container in
                container.textView.contentOffset.x = text.isEmpty ? 0 : 2_000
                container.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: container.lineNumberView.bounds).image { _ in
                    container.lineNumberView.draw(container.lineNumberView.bounds)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = text.isEmpty ? "Empty gutter" : "Horizontally scrolled gutter"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertNotNil(image.cgImage)
                let blank = UIGraphicsImageRenderer(bounds: container.lineNumberView.bounds).image { _ in }
                XCTAssertNotEqual(image.pngData(), blank.pngData(), "The gutter must paint a line number")
            }
        }
    }

    func testLongLineBeyondFormerSamplingLimitIsNotClipped() {
        let source = String(repeating: "short\n", count: 20_001) + String(repeating: "W", count: 5_000)
        let start = ProcessInfo.processInfo.systemUptime
        withEditor(source) { container in
            XCTAssertGreaterThan(container.textView.textContainer.size.width, 40_000)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("Mobile long-line fixture (125 KB) open: \(elapsed) seconds")
        XCTAssertLessThan(elapsed, 3)
    }

    func testLargeDocumentLineIndexUpdatesWithoutDocumentMutationCallback() {
        let source = String(repeating: "line\n", count: 52_000)
        let container = LineNumberedTextViewContainer(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        container.layoutIfNeeded()
        container.textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        // Match CustomTextEditor's TextKit 1 setup before installing the fixture.
        container.textView.layoutManager.allowsNonContiguousLayout = true
        let coordinator = editor(source).makeCoordinator()
        coordinator.container = container
        coordinator.textView = container.textView
        container.textView.text = source
        container.updateLineNumbers(for: source, fontSize: 16)
        // An undo/programmatic replacement has no shouldChange delta.
        container.textView.text = "\n" + source
        coordinator.textViewDidChange(container.textView)
        XCTAssertEqual(container.lineNumberView.lineStarts.count, 52_002)
        XCTAssertEqual(container.lineNumberView.lineStarts[1], 1)
    }

    func testLargeSQLReplaceAllUsesOneNativeBatchAndPreservesSelection() throws {
        let documentID = UUID()
        let sqlLine = "SELECT value FROM demo WHERE id = 123; -- PLSQL fixture\n"
        let segment = String(repeating: sqlLine, count: 270) + "TARGET_TOKEN\n"
        let source = String(repeating: segment, count: 40)
        let replacement = source.replacingOccurrences(of: "TARGET_TOKEN", with: "REPLACED")
        XCTAssertGreaterThan(source.utf8.count, 600_000)
        XCTAssertEqual(source.components(separatedBy: "TARGET_TOKEN").count - 1, 40)

        var receivedMutations: [EditorTextMutation] = []
        let editor = editor(
            source,
            documentID: documentID,
            language: "sql",
            onTextMutation: { receivedMutations.append($0) }
        )
        let coordinator = editor.makeCoordinator()
        let container = LineNumberedTextViewContainer(frame: CGRect(x: 0, y: 0, width: 1_024, height: 768))
        coordinator.container = container
        coordinator.textView = container.textView
        container.textView.delegate = coordinator
        container.textView.text = source
        container.textView.selectedRange = NSRange(location: 12_345, length: 0)

        let matchRanges = ReleaseRuntimePolicy.findMatches(
            in: source,
            query: "TARGET_TOKEN",
            useRegex: false,
            caseSensitive: true
        ).ranges
        NotificationCenter.default.post(
            name: .replaceEditorRangesRequested,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.documentID: documentID.uuidString,
                EditorCommandUserInfo.replacementRanges: matchRanges.map { NSValue(range: $0) },
                EditorCommandUserInfo.replacementTexts: Array(repeating: "REPLACED", count: matchRanges.count)
            ]
        )

        XCTAssertEqual(container.textView.text, replacement)
        XCTAssertEqual(container.textView.selectedRange, NSRange(location: 12_345, length: 0))
        XCTAssertEqual(receivedMutations.count, 40)
        XCTAssertEqual(receivedMutations.first?.replacement, "REPLACED")
        XCTAssertEqual(receivedMutations.last?.replacement, "REPLACED")
        XCTAssertTrue(isProgrammingSyntaxLanguage("sql"))
        XCTAssertTrue(supportsViewportSyntaxHighlighting(language: "sql", textLength: source.utf16.count))
    }

    func testReplaceAllBatchRegistersOneUndoableAction() throws {
        let documentID = UUID()
        let source = "one TARGET two TARGET"
        var modelText = source
        let editor = editor(source, documentID: documentID) { mutation in
            modelText = (modelText as NSString).replacingCharacters(
                in: mutation.range,
                with: mutation.replacement
            )
        }
        let coordinator = editor.makeCoordinator()
        let container = LineNumberedTextViewContainer(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        coordinator.container = container
        coordinator.textView = container.textView
        container.textView.delegate = coordinator
        container.textView.text = source
        let host = UIViewController()
        host.view.addSubview(container)
        let window = UIWindow(frame: container.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let ranges = ReleaseRuntimePolicy.findMatches(
            in: source,
            query: "TARGET",
            useRegex: false,
            caseSensitive: true
        ).ranges
        NotificationCenter.default.post(
            name: .replaceEditorRangesRequested,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.documentID: documentID.uuidString,
                EditorCommandUserInfo.replacementRanges: ranges.map { NSValue(range: $0) },
                EditorCommandUserInfo.replacementTexts: ["X", "X"]
            ]
        )

        XCTAssertEqual(container.textView.text, "one X two X")
        XCTAssertEqual(modelText, "one X two X")
        let undoManager = try XCTUnwrap(container.textView.undoManager)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(container.textView.text, source)
        XCTAssertEqual(modelText, source)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()
        XCTAssertEqual(container.textView.text, "one X two X")
        XCTAssertEqual(modelText, "one X two X")
    }
}
#endif
