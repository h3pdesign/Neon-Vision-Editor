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

    func testKeyboardAccessoryUsesSharedLiquidGlassPreference() {
        let enabledView = UIVisualEffectView()
        IOSAdaptiveChromePreference.apply(to: enabledView, enabled: true)
        if #available(iOS 26.0, *) {
            XCTAssertTrue(enabledView.effect is UIGlassEffect)
        } else {
            XCTAssertNotNil(enabledView.effect)
        }

        let disabledView = UIVisualEffectView()
        IOSAdaptiveChromePreference.apply(to: disabledView, enabled: false)
        XCTAssertNil(disabledView.effect)
        XCTAssertEqual(disabledView.backgroundColor, .secondarySystemBackground)
    }

    private func editor(
        _ text: String,
        wrap: Bool = false,
        documentID: UUID? = nil,
        storedCaretLocation: Int? = nil,
        language: String = "plain text",
        isLargeFileMode: Bool = false,
        showKeyboardAccessoryBar: Bool = false,
        softwareKeyboardVisible: Bool = false,
        formattingPreferences: EditorFormattingPreferences = .init(
            boldKeywords: false,
            italicComments: false,
            underlineLinks: false,
            boldMarkdownHeadings: false
        ),
        onTextMutation: ((EditorTextMutation) -> Void)? = nil
    ) -> CustomTextEditor {
        CustomTextEditor(text: .constant(text), document: nil, documentID: documentID,
            documentResourceID: "mobile-regression", storedCaretLocation: storedCaretLocation,
            externalEditRevision: 0, language: language, colorScheme: .light,
            ignoreBackgroundOverrides: false,
            fontSize: 16, isLineWrapEnabled: .constant(wrap), isLargeFileMode: isLargeFileMode,
            showsCodeMinimap: false, translucentBackgroundEnabled: false,
            showKeyboardAccessoryBar: showKeyboardAccessoryBar,
            softwareKeyboardVisible: softwareKeyboardVisible, showLineNumbers: true,
            formattingPreferences: formattingPreferences,
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
        initiallyWrapped: Bool = false,
        language: String = "plain text",
        showKeyboardAccessoryBar: Bool = false,
        softwareKeyboardVisible: Bool = false,
        body: (LineNumberedTextViewContainer) -> Void
    ) {
        let host = UIHostingController(rootView: editor(
            text,
            wrap: initiallyWrapped,
            language: language,
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
        if initiallyWrapped {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.rootView = editor(text, wrap: false, language: language)
            host.view.layoutIfNeeded()
        }
        func find(_ view: UIView) -> LineNumberedTextViewContainer? {
            if let container = view as? LineNumberedTextViewContainer { return container }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let container = find(host.view) else { return XCTFail("Missing editor") }
        body(container)
        window.isHidden = true
    }

    func testLargeJSONInstallsCompleteUnicodeBufferWithoutClaimingFocus() async throws {
        try await assertLargeJSONInstallation(
            "[\n" + String(repeating: "{\"name\":\"😀 sample\",\"value\":123},\n", count: 80_000) + "null\n]"
        )
    }

    func testMinifiedJSONInstallsCompleteBufferWithoutBlockingRunLoop() async throws {
        try await assertLargeJSONInstallation(
            "{\"items\":[" + String(repeating: "{\"id\":123,\"text\":\"sample\",\"active\":true},", count: 65_000)
                + "{\"text\":\"😀\"}]}"
        )
    }

    func testChunkedJSONOpeningIncludesDelayedWidthWork() async throws {
        try await assertLargeJSONInstallation(
            "[\n" + String(repeating: "{\"name\":\"😀 sample\",\"value\":123},\n", count: 80_000) + "null\n]",
            largeFileMode: true
        )
    }

    func testExtremelyLongUnicodeJSONBelowSyntaxCutoffRemainsResponsive() async throws {
        try await assertLargeJSONInstallation("\"" + String(repeating: "😀", count: 500_000) + "\"")
    }

    func testExtremelyLongUnicodeJSONAboveSyntaxCutoffRemainsResponsive() async throws {
        try await assertLargeJSONInstallation("\"" + String(repeating: "😀", count: 650_000) + "\"")
    }

    func testOpeningProbeIncludesWorkBeforeFirstRunLoopTick() {
        let probe = OpeningProbe()
        probe.start()
        // Deliberately block only this test to prove the measurement cannot omit
        // synchronous presentation simply because its timer has not fired yet.
        Thread.sleep(forTimeInterval: 0.03)
        probe.stop()
        XCTAssertGreaterThanOrEqual(probe.longestGap, 0.03)
        XCTAssertGreaterThanOrEqual(probe.elapsed, probe.longestGap)
    }

    private func assertLargeJSONInstallation(_ source: String, largeFileMode: Bool = false) async throws {
        executionTimeAllowance = 60
        let defaults = UserDefaults.standard
        let key = "SettingsLargeFileOpenMode"
        let previous = defaults.object(forKey: key)
        defaults.set("deferred", forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let probe = OpeningProbe()
        probe.start()
        defer { probe.stop() }
        // Ordinary multi-megabyte documents do not use the 100 MB large-file flag.
        let host = UIHostingController(rootView: editor(source, language: "json", isLargeFileMode: largeFileMode))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        func find(_ view: UIView) -> LineNumberedTextViewContainer? {
            if let container = view as? LineNumberedTextViewContainer { return container }
            return view.subviews.lazy.compactMap(find).first
        }
        let container = try XCTUnwrap(find(host.view))
        let coordinator = try XCTUnwrap(container.textView.delegate as? CustomTextEditor.Coordinator)
        let expectedLength = (source as NSString).length
        let presentation = probe.elapsed
        while container.textView.textStorage.length < expectedLength, probe.elapsed < 30 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let bufferInstalled = probe.elapsed
        while coordinator.hasPendingLargeTextWork, probe.elapsed < 30 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let widthSettled = probe.elapsed
        host.view.layoutIfNeeded()
        // Display-link callbacks are display opportunities, not a physical
        // first-pixel measurement. Include two after the final width/layout work.
        let targetFrames = probe.displayTicks + 2
        while probe.displayTicks < targetFrames, probe.elapsed < 30 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        probe.stop()
        let metrics: [String: Any] = [
            "utf8Bytes": source.utf8.count, "utf16Units": expectedLength,
            "largeFileMode": largeFileMode, "presentationSeconds": presentation,
            "bufferInstalledSeconds": bufferInstalled, "widthSettledSeconds": widthSettled,
            "firstDisplayTickSeconds": probe.firstDisplayTick ?? -1,
            "settledDisplaySeconds": probe.elapsed, "longestMainRunLoopGapSeconds": probe.longestGap,
            "displayTicks": probe.displayTicks, "widthWorkStillPending": coordinator.hasPendingLargeTextWork
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "Editor opening responsiveness"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(coordinator.hasPendingLargeTextWork, "Opening includes delayed width work")
        XCTAssertGreaterThanOrEqual(probe.displayTicks, targetFrames, "Include post-layout display cycles")
        XCTAssertTrue(container.textView.text == source, "The complete document must survive chunk installation")
        XCTAssertTrue(container.textView.isEditable)
        XCTAssertFalse(container.textView.isFirstResponder)
        XCTAssertLessThan(probe.elapsed, 30, "Presentation, installation and delayed layout must finish")
        XCTAssertLessThan(probe.longestGap, 1.0, "The entire opening interval must yield to the main run loop")
    }

    @MainActor
    private final class OpeningProbe: NSObject {
        private var timer: Timer?
        private var displayLink: CADisplayLink?
        private var startedAt = ProcessInfo.processInfo.systemUptime
        private var previousTick = ProcessInfo.processInfo.systemUptime
        private var stoppedAt: TimeInterval?
        private(set) var longestGap = 0.0
        private(set) var displayTicks = 0
        private(set) var firstDisplayTick: TimeInterval?
        var elapsed: TimeInterval { (stoppedAt ?? ProcessInfo.processInfo.systemUptime) - startedAt }

        func start() {
            startedAt = ProcessInfo.processInfo.systemUptime
            previousTick = startedAt
            let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            let link = CADisplayLink(target: self, selector: #selector(displayTick))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        private func tick() {
            let now = ProcessInfo.processInfo.systemUptime
            longestGap = max(longestGap, now - previousTick)
            previousTick = now
        }

        @objc private func displayTick() {
            if firstDisplayTick == nil { firstDisplayTick = elapsed }
            displayTicks += 1
        }

        func stop() {
            guard stoppedAt == nil else { return }
            tick()
            stoppedAt = ProcessInfo.processInfo.systemUptime
            timer?.invalidate()
            timer = nil
            displayLink?.invalidate()
            displayLink = nil
        }
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

    func testUnwrappedTextRendersAcrossViewportAfterHorizontalScroll() {
        assertUnwrappedViewportRenders(language: "markdown", initiallyWrapped: true)
    }

    func testUnwrappedHTMLRendersAcrossViewportWithoutKeyboard() {
        assertUnwrappedViewportRenders(language: "html", initiallyWrapped: false)
    }

    private func assertUnwrappedViewportRenders(language: String, initiallyWrapped: Bool) {
        let row = language == "html"
            ? "<a href=\"https://example.com/" + String(repeating: "long-path/", count: 100) + "\">Link</a>\n"
            : "### " + String(repeating: "**Wissenschaftliche Prüfung** und öffentliche Darstellung ", count: 20) + "\n"
        withEditor(String(repeating: row, count: 200), initiallyWrapped: initiallyWrapped, language: language) { container in
            let view = container.textView
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            view.textColor = .black
            view.backgroundColor = .white
            view.textStorage.addAttribute(.foregroundColor, value: UIColor.black,
                                          range: NSRange(location: 0, length: view.textStorage.length))
            XCTAssertFalse(view.isFirstResponder)
            for offset: CGFloat in [0, 100, 220] {
                view.setEditorContentOffset(CGPoint(x: offset, y: 300), animated: false)
                view.setNeedsLayout()
                container.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                XCTAssertEqual(view.editorContentOffset.x, offset, accuracy: 0.5, "Horizontal scrolling must retain its offset")
                XCTAssertEqual(view.contentOffset.x, 0, accuracy: 0.5, "Only the outer viewport owns horizontal scrolling")
                XCTAssertGreaterThanOrEqual(view.bounds.width, view.textContainer.size.width)
                let renderer = UIGraphicsImageRenderer(bounds: container.bounds)
                let snapshot = renderer.image { _ in
                    container.drawHierarchy(in: container.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: snapshot)
                attachment.name = "No wrap horizontal offset \(offset)"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                guard let image = snapshot.cgImage else {
                    return XCTFail("Missing rendered pixels")
                }
                var pixels = [UInt8](repeating: 255, count: image.width * image.height * 4)
                let context = CGContext(data: &pixels, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let scale = snapshot.scale
                let region = CGRect(x: container.bounds.width - 70, y: 15, width: 40, height: 150)
                var inkPixels = 0
                for y in Int(region.minY * scale)..<Int(region.maxY * scale) {
                    for x in Int(region.minX * scale)..<Int(region.maxX * scale) {
                        let index = y * image.width * 4 + x * 4
                        if pixels[index] < 100 && pixels[index + 1] < 100 && pixels[index + 2] < 100 {
                            inkPixels += 1
                        }
                    }
                }
                XCTAssertGreaterThan(inkPixels, 100, "Text must reach the right viewport edge at offset \(offset)")
            }
        }
    }

    func testLargeDocumentModeRespectsEnabledLineWrap() throws {
        let host = UIHostingController(rootView: editor(
            String(repeating: "wrapped text ", count: 2_000),
            wrap: true,
            isLargeFileMode: true
        ))
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

        XCTAssertEqual(textView.textContainer.lineBreakMode, .byWordWrapping)
        XCTAssertTrue(textView.textContainer.widthTracksTextView)
        XCTAssertLessThan(textView.textContainer.size.width, 1_000)
        window.isHidden = true
    }

    func testLargeWrappedHTMLResponsiveInstallStaysWithinBudget() async throws {
        let defaults = UserDefaults.standard
        let key = "SettingsLargeFileOpenMode"
        let previousMode = defaults.object(forKey: key)
        defaults.set("deferred", forKey: key)
        defer {
            if let previousMode { defaults.set(previousMode, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let row = "<article class=\"item\"><a href=\"https://example.com/path\">Large HTML row</a></article>\n"
        // Match the 10–20 MB documents reported on iPhone rather than testing
        // only a small file that happens to cross the responsive-mode cutoff.
        let source = String(repeating: row, count: 180_000)
        let expectedLength = (source as NSString).length
        let started = ProcessInfo.processInfo.systemUptime
        let host = UIHostingController(rootView: editor(
            source,
            wrap: true,
            language: "html",
            isLargeFileMode: true
        ))
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
        let deadline = Date().addingTimeInterval(8)
        while textView.textStorage.length < expectedLength, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        XCTAssertEqual(textView.textStorage.length, expectedLength)
        XCTAssertLessThan(elapsed, 3.0, "Responsive installation took \(elapsed)s")
        XCTAssertEqual(textView.textContainer.lineBreakMode, .byWordWrapping)
        window.isHidden = true
    }

    func testChunkedNoWrapInstallKeepsLongLinesHorizontallyReachable() async throws {
        let defaults = UserDefaults.standard
        let key = "SettingsLargeFileOpenMode"
        let previousMode = defaults.object(forKey: key)
        defaults.set("deferred", forKey: key)
        defer {
            if let previousMode { defaults.set(previousMode, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        let longLine = String(repeating: "W", count: 5_000)
        let source = longLine + "\n" + String(repeating: "short line\n", count: 110_000)
        let expectedLength = (source as NSString).length
        let host = UIHostingController(rootView: editor(
            source,
            wrap: false,
            language: "markdown",
            isLargeFileMode: true
        ))
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
        let deadline = Date().addingTimeInterval(5)
        while textView.textStorage.length < expectedLength, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        textView.layoutIfNeeded()

        XCTAssertEqual(textView.textStorage.length, expectedLength)
        XCTAssertEqual(textView.textContainer.lineBreakMode, .byClipping)
        XCTAssertFalse(textView.textContainer.widthTracksTextView)
        XCTAssertGreaterThan(textView.textContainer.size.width, 40_000)
        let horizontalScrollView = try XCTUnwrap(textView.editorContainer?.horizontalScrollView)
        textView.editorContainer?.layoutIfNeeded()
        XCTAssertGreaterThan(horizontalScrollView.contentSize.width, horizontalScrollView.bounds.width)
        XCTAssertTrue(horizontalScrollView.isScrollEnabled)
        XCTAssertTrue(horizontalScrollView.showsHorizontalScrollIndicator)
        XCTAssertEqual(textView.bounds.width, horizontalScrollView.contentSize.width, accuracy: 1)
        window.isHidden = true
    }

    func testChunkedNoWrapCaretRestoreStartsAtLeadingEdge() async throws {
        let defaults = UserDefaults.standard
        let key = "SettingsLargeFileOpenMode"
        let previousMode = defaults.object(forKey: key)
        defaults.set("deferred", forKey: key)
        defer {
            if let previousMode { defaults.set(previousMode, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        let longLine = String(repeating: "W", count: 5_000)
        let source = longLine + "\n" + String(repeating: "short line\n", count: 110_000)
        let expectedLength = (source as NSString).length
        let host = UIHostingController(rootView: editor(
            source,
            wrap: false,
            storedCaretLocation: 4_500,
            language: "markdown",
            isLargeFileMode: true
        ))
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
        let deadline = Date().addingTimeInterval(5)
        while textView.textStorage.length < expectedLength, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        // Allow the immediate syntax pass to apply and restore its viewport.
        try await Task.sleep(for: .milliseconds(100))
        textView.layoutIfNeeded()

        XCTAssertEqual(textView.textStorage.length, expectedLength)
        XCTAssertEqual(textView.selectedRange.location, 4_500)
        XCTAssertEqual(textView.contentOffset.x, 0, accuracy: 0.5)
        XCTAssertGreaterThan(textView.textContainer.size.width, 40_000)
        window.isHidden = true
    }

    func testLineWrapChangeAppliesWhilePhoneKeyboardIsActiveAndPersistsAfterDismissal() throws {
        final class WrapState {
            var enabled = false
        }
        let state = WrapState()
        let wrapBinding = Binding(
            get: { state.enabled },
            set: { state.enabled = $0 }
        )
        func root(keyboardVisible: Bool) -> CustomTextEditor {
            CustomTextEditor(
                text: .constant(String(repeating: "keyboard wrap transition ", count: 500)),
                document: nil,
                documentID: nil,
                documentResourceID: "keyboard-wrap-transition",
                storedCaretLocation: nil,
                externalEditRevision: 0,
                language: "html",
                colorScheme: .light,
                ignoreBackgroundOverrides: false,
                fontSize: 16,
                isLineWrapEnabled: wrapBinding,
                isLargeFileMode: false,
                showsCodeMinimap: false,
                translucentBackgroundEnabled: false,
                showKeyboardAccessoryBar: true,
                softwareKeyboardVisible: keyboardVisible,
                showLineNumbers: true,
                formattingPreferences: .init(
                    boldKeywords: false,
                    italicComments: false,
                    underlineLinks: false,
                    boldMarkdownHeadings: false
                ),
                showInvisibleCharacters: false,
                highlightCurrentLine: false,
                highlightMatchingBrackets: false,
                showIndentationGuides: false,
                showScopeGuides: false,
                highlightScopeBackground: false,
                indentStyle: "spaces",
                indentWidth: 4,
                autoIndentEnabled: false,
                autoCloseBracketsEnabled: false,
                highlightRefreshToken: 0,
                isTabLoadingContent: false,
                isReadOnly: false,
                onFontSizeChange: nil,
                onTextMutation: nil
            )
        }

        let host = UIHostingController(rootView: root(keyboardVisible: true))
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
        XCTAssertTrue(textView.becomeFirstResponder())
        XCTAssertEqual(textView.textContainer.lineBreakMode, .byClipping)

        textView.setEditorContentOffset(CGPoint(x: 220, y: 0), animated: false)
        XCTAssertEqual(textView.editorContentOffset.x, 220, accuracy: 0.5)
        state.enabled = true
        host.rootView = root(keyboardVisible: true)
        host.view.layoutIfNeeded()

        XCTAssertEqual(textView.textContainer.lineBreakMode, .byWordWrapping)
        XCTAssertTrue(textView.textContainer.widthTracksTextView)
        XCTAssertEqual(textView.editorContentOffset.x, 0, accuracy: 0.5)
        XCTAssertEqual(textView.bounds.width, textView.editorViewport.width, accuracy: 1)
        XCTAssertFalse(textView.editorContainer?.horizontalScrollView.isScrollEnabled ?? true)

        textView.resignFirstResponder()
        host.rootView = root(keyboardVisible: false)
        host.view.layoutIfNeeded()

        XCTAssertEqual(textView.textContainer.lineBreakMode, .byWordWrapping)
        XCTAssertTrue(textView.textContainer.widthTracksTextView)
        window.isHidden = true
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

    func testLinkUnderlineFormattingAppliesOnIPhoneAndIPad() async throws {
        let source = "[Documentation](https://example.com)"
        let host = UIHostingController(rootView: editor(
            source,
            language: "markdown",
            formattingPreferences: .init(
                boldKeywords: false,
                italicComments: false,
                underlineLinks: true,
                boldMarkdownHeadings: false
            )
        ))
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
        let linkRange = (source as NSString).range(of: "Documentation")
        let deadline = Date().addingTimeInterval(2)
        var underlineStyle = 0
        while underlineStyle == 0, Date() < deadline {
            underlineStyle = textView.textStorage.attribute(
                .underlineStyle,
                at: linkRange.location,
                effectiveRange: nil
            ) as? Int ?? 0
            if underlineStyle == 0 {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        XCTAssertEqual(underlineStyle, NSUnderlineStyle.single.rawValue)
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
            let initialOffset = view.editorContentOffset

            for _ in 0..<20 {
                view.insertText("x")
                view.layoutIfNeeded()
                XCTAssertEqual(view.editorContentOffset.x, initialOffset.x, accuracy: 0.5)
                XCTAssertEqual(view.editorContentOffset.y, initialOffset.y, accuracy: 0.5)
            }
        }
    }

    func testNoWrapCaretRevealScrollsTheDrawingCanvas() {
        withEditor(String(repeating: "W", count: 500)) { container in
            let view = container.textView
            XCTAssertTrue(view.becomeFirstResponder())
            view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
            view.insertText("x")
            container.layoutIfNeeded()
            view.revealCaretWithContext()
            let caret = view.caretRect(for: view.endOfDocument)
            XCTAssertGreaterThan(view.editorContentOffset.x, 0)
            XCTAssertGreaterThanOrEqual(caret.minX, view.editorViewport.minX - 1)
            XCTAssertLessThanOrEqual(caret.maxX, view.editorViewport.maxX + 1)
            XCTAssertEqual(view.contentOffset.x, 0, accuracy: 0.5)
        }
    }

    func testEmptyNoWrapDocumentDoesNotExposeArbitraryHorizontalCanvas() {
        withEditor("") { container in
            let view = container.textView
            XCTAssertLessThanOrEqual(view.contentSize.width, view.bounds.width + 1)
            XCTAssertFalse(view.alwaysBounceHorizontal)
            XCTAssertFalse(view.showsHorizontalScrollIndicator)
            XCTAssertLessThanOrEqual(container.horizontalScrollView.contentSize.width, container.horizontalScrollView.bounds.width + 1)
        }
    }

    func testBottomInsetReservesThreeLines() {
        withEditor("one\ntwo") { container in
            XCTAssertGreaterThanOrEqual(container.textView.textContainerInset.bottom,
                (container.textView.font?.lineHeight ?? 0) * 3)
        }
    }

    func testPhoneKeyboardToolbarUsesAdaptiveEditorOverlay() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: IOSAdaptiveChromePreference.storageKey)
        defaults.set(true, forKey: IOSAdaptiveChromePreference.storageKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: IOSAdaptiveChromePreference.storageKey)
            } else {
                defaults.removeObject(forKey: IOSAdaptiveChromePreference.storageKey)
            }
        }
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

    func testPhoneKeyboardToolbarRebuildsWhenLiquidGlassSettingChanges() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: IOSAdaptiveChromePreference.storageKey)
        defaults.set(true, forKey: IOSAdaptiveChromePreference.storageKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: IOSAdaptiveChromePreference.storageKey)
            } else {
                defaults.removeObject(forKey: IOSAdaptiveChromePreference.storageKey)
            }
        }

        withEditor("Code behind toolbar", showKeyboardAccessoryBar: true, softwareKeyboardVisible: true) { container in
            let view = container.textView
            XCTAssertTrue(view.becomeFirstResponder())
            guard let initialGlass = container.keyboardAccessoryOverlay?.subviews.first as? UIVisualEffectView else {
                return XCTFail("Missing initial keyboard glass overlay")
            }
            XCTAssertNotNil(initialGlass.effect)

            defaults.set(false, forKey: IOSAdaptiveChromePreference.storageKey)
            view.setBracketAccessoryVisible(true)
            guard let updatedGlass = container.keyboardAccessoryOverlay?.subviews.first as? UIVisualEffectView else {
                return XCTFail("Missing rebuilt keyboard overlay")
            }
            XCTAssertNil(updatedGlass.effect)
            XCTAssertEqual(updatedGlass.backgroundColor, .secondarySystemBackground)
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
                container.textView.setEditorContentOffset(CGPoint(x: text.isEmpty ? 0 : 2_000, y: 0), animated: false)
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
        let measurementStart = ProcessInfo.processInfo.systemUptime
        let width = measuredEditorTextWidth(source, attributes: [.font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)])
        XCTAssertGreaterThan(width, 40_000)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - measurementStart, 1, "Width measurement")
        let start = ProcessInfo.processInfo.systemUptime
        withEditor(source) { container in
            XCTAssertGreaterThan(container.textView.textContainer.size.width, 40_000)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("Mobile long-line fixture (125 KB) open: \(elapsed) seconds")
        XCTAssertLessThan(elapsed, 3)
    }

    func testLineWidthMeasurementPreservesUnicodeAndTabAdvances() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
            .kern: 1.5
        ]
        let lines = ["short", "日本語😀\tend", String(repeating: "W", count: 100)]
        let expected = lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max()!
        XCTAssertEqual(measuredEditorTextWidth(lines.joined(separator: "\n"), attributes: attributes), expected, accuracy: 0.01)
        XCTAssertEqual(measuredEditorTextWidth("", attributes: attributes), 0)
    }

    func testCancelledWidthMeasurementSkipsDocumentScan() async {
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return measuredEditorTextWidth(String(repeating: "line\n", count: 100_000), attributes: [:])
        }
        let width = await worker.value
        XCTAssertEqual(width, 0)
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
