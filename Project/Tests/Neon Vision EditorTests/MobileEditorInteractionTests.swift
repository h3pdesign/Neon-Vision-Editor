#if os(iOS)
import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

@MainActor
final class MobileEditorInteractionTests: XCTestCase {
    func testLargeSyntaxScrollPolicy() {
        let defaults = UserDefaults.standard
        let syntaxKey = "SettingsLargeFileSyntaxHighlighting"
        let openKey = "SettingsLargeFileOpenMode"
        let previousSyntax = defaults.object(forKey: syntaxKey)
        let previousOpen = defaults.object(forKey: openKey)
        defer {
            if let previousSyntax { defaults.set(previousSyntax, forKey: syntaxKey) }
            else { defaults.removeObject(forKey: syntaxKey) }
            if let previousOpen { defaults.set(previousOpen, forKey: openKey) }
            else { defaults.removeObject(forKey: openKey) }
        }

        defaults.set("minimal", forKey: syntaxKey)
        defaults.set("deferred", forKey: openKey)
        for language in ["swift", "typescript", "python", "html", "json", "csv"] {
            XCTAssertTrue(
                shouldRefreshViewportSyntaxOnScroll(language: language, textLength: 2_500_000),
                "Expected a bounded scrolling highlight pass for \(language)"
            )
        }
        XCTAssertFalse(shouldRefreshViewportSyntaxOnScroll(language: "markdown", textLength: 2_500_000))

        defaults.set("off", forKey: syntaxKey)
        XCTAssertFalse(shouldRefreshViewportSyntaxOnScroll(language: "swift", textLength: 2_500_000))

        defaults.set("minimal", forKey: syntaxKey)
        defaults.set("plainText", forKey: openKey)
        XCTAssertFalse(shouldRefreshViewportSyntaxOnScroll(language: "swift", textLength: 2_500_000))
    }

    func testReadableToolbarGlassUsesSystemAdaptiveNativeGlass() throws {
        let view = UIVisualEffectView()
        IOSReadableGlassAppearance.apply(to: view)

        if #available(iOS 26.0, *) {
            let glass = try XCTUnwrap(view.effect as? UIGlassEffect)
            XCTAssertNil(glass.tintColor)
        } else {
            XCTAssertNotNil(view.effect)
        }
    }

    private func editor(
        _ text: String,
        wrap: Bool = false,
        documentID: UUID? = nil,
        language: String = "plain text",
        isLargeFileMode: Bool = false,
        showKeyboardAccessoryBar: Bool = false,
        softwareKeyboardVisible: Bool = false,
        onTextMutation: ((EditorTextMutation) -> Void)? = nil
    ) -> CustomTextEditor {
        CustomTextEditor(text: .constant(text), document: nil, documentID: documentID,
            documentResourceID: "mobile-regression", storedCaretLocation: nil,
            externalEditRevision: 0, language: language, colorScheme: .light,
            ignoreBackgroundOverrides: false,
            fontSize: 16, isLineWrapEnabled: .constant(wrap), isLargeFileMode: isLargeFileMode,
            showsCodeMinimap: false, translucentBackgroundEnabled: false,
            showKeyboardAccessoryBar: showKeyboardAccessoryBar,
            softwareKeyboardVisible: softwareKeyboardVisible, showLineNumbers: true,
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

    private func withEditor(
        _ text: String,
        showKeyboardAccessoryBar: Bool = false,
        softwareKeyboardVisible: Bool = false,
        body: (LineNumberedTextViewContainer) -> Void
    ) {
        let host = UIHostingController(rootView: editor(
            text,
            showKeyboardAccessoryBar: showKeyboardAccessoryBar,
            softwareKeyboardVisible: softwareKeyboardVisible
        ))
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return XCTFail("Missing iPhone window scene")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
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

    func testHTMLSyntaxHighlightingRendersOnIPhoneAndSupportsLargeViewports() async throws {
        XCTAssertTrue(supportsViewportSyntaxHighlighting(language: "html", textLength: 2_500_000))
        let source = "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p><DT><A HREF=\"https://example.com\">Example</A></DL>"
        let host = UIHostingController(
            rootView: editor(source, language: "html", isLargeFileMode: true)
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        func findEditor(in view: UIView) -> EditorInputTextView? {
            if let editor = view as? EditorInputTextView { return editor }
            return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
        }
        let textView = try XCTUnwrap(findEditor(in: host.view))
        let deadline = Date().addingTimeInterval(2)
        var colors: Set<UIColor> = []
        while colors.count < 2, Date() < deadline {
            colors.removeAll()
            textView.textStorage.enumerateAttribute(
                .foregroundColor,
                in: NSRange(location: 0, length: textView.textStorage.length)
            ) { value, _, _ in
                if let color = value as? UIColor { colors.insert(color) }
            }
            if colors.count < 2 {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        XCTAssertGreaterThanOrEqual(colors.count, 2)
        window.isHidden = true
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

    func testPhoneKeyboardToolbarUsesClearEditorOverlay() {
        withEditor("Code behind toolbar", showKeyboardAccessoryBar: true, softwareKeyboardVisible: true) { container in
            let view = container.textView
            XCTAssertTrue(view.becomeFirstResponder())
            guard let accessory = container.keyboardAccessoryOverlay,
                  accessory.subviews.count == 1,
                  let glass = accessory.subviews.first as? UIVisualEffectView,
                  let scroll = glass.contentView.subviews.compactMap({ $0 as? UIScrollView }).first else {
                return XCTFail("Missing keyboard glass overlay")
            }
            XCTAssertNil(view.inputAccessoryView, "The keyboard host must not own the phone toolbar")
            XCTAssertTrue(accessory.superview === container)
            XCTAssertFalse(accessory.isOpaque)
            XCTAssertEqual(accessory.backgroundColor, .clear)
            XCTAssertFalse(glass.isOpaque)
            XCTAssertEqual(glass.layer.cornerRadius, 21)
            XCTAssertTrue(glass.clipsToBounds)
            XCTAssertFalse(scroll.isOpaque)
            XCTAssertEqual(scroll.backgroundColor, .clear)
            if #available(iOS 26.0, *) {
                XCTAssertTrue(glass.effect is UIGlassEffect)
            }
        }
    }

    func testIPadKeyboardAccessoryDoesNotCoverNativeGlassWithLegacyBlur() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        withEditor("Code behind toolbar", showKeyboardAccessoryBar: true) { container in
            let view = container.textView
            view.setBracketAccessoryVisible(true)
            guard let accessory = view.inputAccessoryView,
                  let glass = accessory.subviews.first as? UIVisualEffectView else {
                return XCTFail("Missing iPad keyboard glass")
            }
            if #available(iOS 26.0, *) {
                XCTAssertEqual(accessory.subviews.count, 1)
                XCTAssertTrue(glass.effect is UIGlassEffect)
                view.setKeyboardAccessoryBackgroundColor(.red)
                XCTAssertEqual(accessory.backgroundColor, .clear)
            }
        }
    }

    func testKeyboardShortcutActionsFollowTheirVisibilitySetting() {
        let defaults = UserDefaults.standard
        let enabledKey = "SettingsKeyboardShortcutAccessoryBarIOS"
        let actionsKey = KeyboardAccessoryAction.storageKey
        let previousEnabled = defaults.object(forKey: enabledKey)
        let previousActions = defaults.object(forKey: actionsKey)
        defer {
            if let previousEnabled { defaults.set(previousEnabled, forKey: enabledKey) }
            else { defaults.removeObject(forKey: enabledKey) }
            if let previousActions { defaults.set(previousActions, forKey: actionsKey) }
            else { defaults.removeObject(forKey: actionsKey) }
        }
        defaults.set(KeyboardAccessoryAction.storageValue(for: KeyboardAccessoryAction.defaultActions), forKey: actionsKey)
        defaults.set(false, forKey: enabledKey)

        withEditor("Code behind toolbar", showKeyboardAccessoryBar: true, softwareKeyboardVisible: true) { container in
            let view = container.textView
            XCTAssertTrue(view.becomeFirstResponder())
            func shortcutButtons(in root: UIView?) -> [UIButton] {
                guard let root else { return [] }
                let current = (root as? UIButton).flatMap {
                    $0.accessibilityIdentifier?.hasPrefix("keyboard-accessory-") == true ? $0 : nil
                }
                return (current.map { [$0] } ?? []) + root.subviews.flatMap { shortcutButtons(in: $0) }
            }
            let accessory = UIDevice.current.userInterfaceIdiom == .phone
                ? container.keyboardAccessoryOverlay : view.inputAccessoryView
            XCTAssertTrue(shortcutButtons(in: accessory).isEmpty)

            defaults.set(true, forKey: enabledKey)
            view.setBracketAccessoryVisible(true)
            let updatedAccessory = UIDevice.current.userInterfaceIdiom == .phone
                ? container.keyboardAccessoryOverlay : view.inputAccessoryView
            XCTAssertFalse(shortcutButtons(in: updatedAccessory).isEmpty)
        }
    }

    func testPhoneKeyboardOverlayRemainsClearAcrossRebuilds() {
        withEditor("Code behind toolbar", showKeyboardAccessoryBar: true, softwareKeyboardVisible: true) { container in
            let view = container.textView
            let editorBackground = UIColor(red: 0.92, green: 0.84, blue: 0.96, alpha: 1)
            view.setKeyboardAccessoryBackgroundColor(editorBackground)
            XCTAssertTrue(view.becomeFirstResponder())
            assertAccessoryBackground(container, matches: editorBackground)

            view.setBracketAccessoryVisible(false)
            XCTAssertTrue(container.keyboardAccessoryOverlay?.isHidden ?? true)
            view.setBracketAccessoryVisible(true)
            assertAccessoryBackground(container, matches: editorBackground)
            container.setSoftwareKeyboardVisible(false)
            XCTAssertTrue(container.keyboardAccessoryOverlay?.isHidden ?? true)
        }
    }

    func testKeyboardOverlayAnchorsToKeyboardLayoutGuide() {
        withEditor(
            String(repeating: "Editor content behind glass\n", count: 30),
            showKeyboardAccessoryBar: true,
            softwareKeyboardVisible: true
        ) { container in
            let view = container.textView
            XCTAssertTrue(view.becomeFirstResponder())
            container.layoutIfNeeded()
            guard let overlay = container.keyboardAccessoryOverlay else {
                return XCTFail("Missing editor keyboard overlay")
            }
            XCTAssertNotNil(container.window)
            XCTAssertNotNil(overlay.window)
            XCTAssertFalse(overlay.isHidden)
            XCTAssertGreaterThan(overlay.bounds.height, 40)
            XCTAssertLessThan(overlay.frame.minY, container.bounds.height)
            XCTAssertTrue(overlay.window === container.window)
            XCTAssertEqual(overlay.frame.maxY, container.keyboardLayoutGuide.layoutFrame.minY, accuracy: 1)
        }
    }

    private func assertAccessoryBackground(_ container: LineNumberedTextViewContainer, matches editorBackground: UIColor) {
        guard let accessory = container.keyboardAccessoryOverlay,
              let glass = accessory.subviews.first as? UIVisualEffectView else {
            return XCTFail("Missing glass keyboard overlay")
        }
        XCTAssertFalse(accessory.isHidden)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(accessory.backgroundColor, .clear)
            XCTAssertTrue(glass.effect is UIGlassEffect)
        } else if UIAccessibility.isReduceTransparencyEnabled {
            XCTAssertEqual(accessory.backgroundColor, editorBackground)
            XCTAssertNil(glass.effect)
        } else {
            XCTAssertEqual(accessory.backgroundColor, .clear)
            XCTAssertTrue(glass.effect is UIBlurEffect)
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
