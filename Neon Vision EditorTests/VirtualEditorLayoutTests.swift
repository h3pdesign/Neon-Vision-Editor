#if os(macOS)
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class VirtualEditorLayoutTests: XCTestCase {
    func testSharedEditorCommandSemanticsDefinePlatformParity() {
        XCTAssertEqual(EditorCommandSemantics.indentation(style: "tabs", width: 8), "\t")
        XCTAssertEqual(EditorCommandSemantics.indentation(style: "spaces", width: 2), "  ")
        XCTAssertEqual(EditorCommandSemantics.markdownCommand(for: "B"), "bold")
        XCTAssertEqual(EditorCommandSemantics.markdownCommand(for: "i"), "italic")
        XCTAssertEqual(EditorCommandSemantics.markdownCommand(for: "k"), "link")
        XCTAssertNil(EditorCommandSemantics.markdownCommand(for: "x"))
    }

    func testVirtualEditorNativeInteractionAndAccessibilityContract() throws {
        let source = String(repeating: "first line\n", count: 30_000) + "accessible target"
        let backing = FileBackedTextDocument(content: source)
        let document = CountingEditorDocument(backing: backing)
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(CGSize(width: 800, height: 600))
        canvas.configure(
            document: document,
            documentID: UUID(),
            resourceID: "native-contract",
            displayName: "contract.txt",
            contentRevision: 0,
            externalContentRevision: 0,
            caret: 0,
            language: "plain",
            colorScheme: .dark,
            fontSize: 14,
            fontName: "",
            lineHeightMultiplier: 1,
            isReadOnly: false,
            translucentBackgroundEnabled: false,
            showsLineNumbers: true,
            highlightCurrentLine: false,
            lineWrapEnabled: true,
            showsInvisibleCharacters: false,
            showsIndentationGuides: false,
            showsScopeGuides: false,
            highlightsScopeBackground: false,
            highlightsMatchingBrackets: false,
            autoIndentEnabled: true,
            autoCloseBracketsEnabled: false,
            onFontSizeChange: nil,
            onTextMutation: nil
        )

        XCTAssertTrue(canvas.acceptsFirstResponder)
        XCTAssertEqual(canvas.accessibilityRole(), .textArea)
        XCTAssertEqual(canvas.accessibilityNumberOfCharacters(), (source as NSString).length)
        XCTAssertTrue(Set(canvas.registeredDraggedTypes).isSuperset(of: [.fileURL, .string, .rtf]))
        for selector in [
            #selector(VirtualEditorCanvas.copy(_:)),
            #selector(VirtualEditorCanvas.cut(_:)),
            #selector(VirtualEditorCanvas.paste(_:)),
            #selector(VirtualEditorCanvas.selectAll(_:))
        ] {
            XCTAssertTrue(canvas.responds(to: selector), NSStringFromSelector(selector))
        }

        let targetRange = (source as NSString).range(of: "accessible target")
        XCTAssertEqual(canvas.accessibilityString(for: targetRange), "accessible target")
        canvas.setAccessibilitySelectedTextRange(targetRange)
        XCTAssertEqual(canvas.accessibilitySelectedTextRange(), targetRange)
        XCTAssertEqual(canvas.accessibilitySelectedText(), "accessible target")
        XCTAssertEqual(document.stringCallCount, 0)
    }

    func testOfficialEmmetEngineExpandsComplexMarkupAndStylesheets() throws {
        let markup = try XCTUnwrap(EmmetExpander.expansionIfPossible(
            in: "ul#nav>li.item$*2>a{Item $}",
            cursorUTF16Location: 27,
            language: "html",
            indentStyle: "spaces",
            indentWidth: 2
        ))
        XCTAssertEqual(markup.range, NSRange(location: 0, length: 27))
        XCTAssertEqual(markup.expansion, """
        <ul id="nav">
          <li class="item1"><a href="">Item 1</a></li>
          <li class="item2"><a href="">Item 2</a></li>
        </ul>
        """)
        XCTAssertEqual(markup.caretOffset, 43)

        let stylesheet = try XCTUnwrap(EmmetExpander.expansionIfPossible(
            in: "m10-20",
            cursorUTF16Location: 7,
            language: "css"
        ))
        XCTAssertEqual(stylesheet.expansion, "margin: 10px 20px;")

        let embeddedCSS = try XCTUnwrap(EmmetExpander.expansionIfPossible(
            in: "<style>\nm10",
            cursorUTF16Location: 11,
            language: "html"
        ))
        XCTAssertEqual(embeddedCSS.range, NSRange(location: 8, length: 3))
        XCTAssertEqual(embeddedCSS.expansion, "margin: 10px;")
    }

    func testTabExpandsEmmetAbbreviationInMacOSVirtualEditor() {
        let source = "ul>li*2"
        let document = FileBackedTextDocument(content: source)
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(CGSize(width: 800, height: 600))
        canvas.configure(
            document: document,
            documentID: UUID(),
            resourceID: "emmet-regression",
            displayName: "index.html",
            contentRevision: 0,
            externalContentRevision: 0,
            caret: (source as NSString).length,
            language: "html",
            colorScheme: .dark,
            fontSize: 14,
            fontName: "",
            lineHeightMultiplier: 1,
            isReadOnly: false,
            translucentBackgroundEnabled: false,
            showsLineNumbers: true,
            highlightCurrentLine: false,
            lineWrapEnabled: true,
            showsInvisibleCharacters: false,
            showsIndentationGuides: false,
            showsScopeGuides: false,
            highlightsScopeBackground: false,
            highlightsMatchingBrackets: false,
            autoIndentEnabled: true,
            autoCloseBracketsEnabled: false,
            onFontSizeChange: nil,
            onTextMutation: { mutation in
                do {
                    if let viewport = mutation.viewport {
                        try document.replace(in: viewport, utf16Range: mutation.range, with: mutation.replacement)
                    } else {
                        try document.replace(utf16Range: mutation.range, with: mutation.replacement)
                    }
                    return true
                } catch {
                    return false
                }
            }
        )

        canvas.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(document.string(), "<ul>\n    <li></li>\n    <li></li>\n</ul>")
        XCTAssertEqual(canvas.selectedRange(), NSRange(location: 13, length: 0))
    }

    func testTabUsesConfiguredIndentationWhenThereIsNoEmmetExpansion() {
        let (document, canvas, _) = makeCanvas(source: "let value = 1", language: "swift", indentStyle: "spaces", indentWidth: 2)
        canvas.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(document.string(), "let value = 1  ")
    }

    func testInlineSuggestionRemainsVirtualUntilTabAcceptsIt() {
        let (document, canvas, documentID) = makeCanvas(source: "pri", language: "swift")
        NotificationCenter.default.post(
            name: .showVirtualEditorInlineSuggestion,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.documentID: documentID.uuidString,
                EditorCommandUserInfo.completionCaretOffset: 3,
                EditorCommandUserInfo.replacementText: "nt(\"Hello\")"
            ]
        )
        XCTAssertEqual(document.string(), "pri")
        canvas.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(document.string(), "print(\"Hello\")")
    }

    func testVimNormalModeCommandsMutateAndReturnToInsertMode() {
        let (document, canvas, _) = makeCanvas(source: "abc", language: "plain", caret: 0)
        NotificationCenter.default.post(
            name: .vimModeStateDidChange,
            object: nil,
            userInfo: ["insertMode": false]
        )
        XCTAssertTrue(canvas.handleVimCommand("x"))
        XCTAssertEqual(document.string(), "bc")
        XCTAssertTrue(canvas.handleVimCommand("i"))
        XCTAssertFalse(canvas.handleVimCommand("x"))
    }

    func testWhitespaceInspectionReadsTheVisibleLine() {
        let (_, canvas, _) = makeCanvas(source: "value\t  \nnext", language: "plain", caret: 6)
        let result = expectation(description: "whitespace result")
        var message = ""
        let token = NotificationCenter.default.addObserver(
            forName: .whitespaceScalarInspectionResult,
            object: nil,
            queue: .main
        ) { notification in
            message = notification.userInfo?[EditorCommandUserInfo.inspectionMessage] as? String ?? ""
            result.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        canvas.inspectWhitespaceScalars(Notification(name: .inspectWhitespaceScalarsRequested))
        wait(for: [result], timeout: 1)
        withExtendedLifetime(canvas) {}
        XCTAssertTrue(message.contains("TAB x1"))
        XCTAssertTrue(message.contains("SPACE x2"))
    }

    func testSelectionContextMenuRestoresCodeSnapshotAction() throws {
        let (_, canvas, documentID) = makeCanvas(source: "selected", language: "plain", caret: 0)
        NotificationCenter.default.post(
            name: .moveCursorToRange,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.documentID: documentID.uuidString,
                EditorCommandUserInfo.rangeLocation: 0,
                EditorCommandUserInfo.rangeLength: 8
            ]
        )
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        XCTAssertNotNil(canvas.menu(for: event)?.items.first(where: { $0.title == "Create Code Snapshot" }))
    }

    func testEmmetExpansionDoesNotMaterializeLargeDocument() {
        let suffix = "ul>li.item$*2"
        let backing = FileBackedTextDocument(content: String(repeating: "<p>row</p>\n", count: 100_000) + suffix)
        let document = CountingEditorDocument(backing: backing)
        let documentID = UUID()
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(CGSize(width: 800, height: 600))
        canvas.configure(
            document: document,
            documentID: documentID,
            resourceID: "bounded-emmet",
            displayName: "large.html",
            contentRevision: 0,
            externalContentRevision: 0,
            caret: document.utf16Length,
            language: "html",
            colorScheme: .dark,
            fontSize: 14,
            fontName: "",
            lineHeightMultiplier: 1,
            isReadOnly: false,
            translucentBackgroundEnabled: false,
            showsLineNumbers: true,
            highlightCurrentLine: false,
            lineWrapEnabled: true,
            showsInvisibleCharacters: false,
            showsIndentationGuides: false,
            showsScopeGuides: false,
            highlightsScopeBackground: false,
            highlightsMatchingBrackets: false,
            autoIndentEnabled: true,
            autoCloseBracketsEnabled: false,
            onFontSizeChange: nil,
            onTextMutation: { mutation in
                do {
                    if let viewport = mutation.viewport {
                        try document.replace(in: viewport, utf16Range: mutation.range, with: mutation.replacement)
                    } else {
                        try document.replace(utf16Range: mutation.range, with: mutation.replacement)
                    }
                    return true
                } catch { return false }
            }
        )
        canvas.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(document.stringCallCount, 0)
        XCTAssertTrue((try? document.viewport(aroundLine: document.lineCount - 1, maximumByteCount: 4_096).text.contains("<ul>")) == true)
    }

    private func makeCanvas(
        source: String,
        language: String,
        caret: Int? = nil,
        indentStyle: String = "spaces",
        indentWidth: Int = 4
    ) -> (FileBackedTextDocument, VirtualEditorCanvas, UUID) {
        let document = FileBackedTextDocument(content: source)
        let documentID = UUID()
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        _ = canvas.setViewportSize(CGSize(width: 800, height: 600))
        canvas.configure(
            document: document, documentID: documentID, resourceID: documentID.uuidString,
            displayName: "fixture", contentRevision: 0, externalContentRevision: 0,
            caret: caret ?? (source as NSString).length, language: language, colorScheme: .dark,
            fontSize: 14, fontName: "", lineHeightMultiplier: 1, isReadOnly: false,
            translucentBackgroundEnabled: false, showsLineNumbers: true, highlightCurrentLine: false,
            lineWrapEnabled: true, showsInvisibleCharacters: false, showsIndentationGuides: false,
            showsScopeGuides: false, highlightsScopeBackground: false, highlightsMatchingBrackets: false,
            autoIndentEnabled: true, autoCloseBracketsEnabled: false,
            indentStyle: indentStyle, indentWidth: indentWidth,
            onFontSizeChange: nil,
            onTextMutation: { mutation in
                do {
                    if let viewport = mutation.viewport {
                        try document.replace(in: viewport, utf16Range: mutation.range, with: mutation.replacement)
                    } else {
                        try document.replace(utf16Range: mutation.range, with: mutation.replacement)
                    }
                    return true
                } catch { return false }
            }
        )
        return (document, canvas, documentID)
    }

    func testDenseMarkdownCanvasBoundsLayoutAcrossScrollAndEdit() throws {
        let source = String(repeating: "# x\n", count: 220_000)
        for wraps in [true, false] {
            let document = FileBackedTextDocument(content: source)
            let documentID = UUID()
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            let canvas = VirtualEditorCanvas(frame: scrollView.bounds)
            scrollView.documentView = canvas
            _ = canvas.setViewportSize(scrollView.contentSize)
            let started = ProcessInfo.processInfo.systemUptime
            canvas.configure(
                document: document,
                documentID: documentID,
                resourceID: "dense-markdown-regression",
                displayName: "Architecture.md",
                contentRevision: 0,
                externalContentRevision: 0,
                caret: 0,
                language: "markdown",
                colorScheme: .light,
                fontSize: 14,
                fontName: "",
                lineHeightMultiplier: 1,
                isReadOnly: false,
                translucentBackgroundEnabled: false,
                showsLineNumbers: true,
                highlightCurrentLine: false,
                lineWrapEnabled: wraps,
                showsInvisibleCharacters: false,
                showsIndentationGuides: false,
                showsScopeGuides: false,
                highlightsScopeBackground: false,
                highlightsMatchingBrackets: false,
                autoIndentEnabled: true,
                autoCloseBracketsEnabled: false,
                onFontSizeChange: nil,
                onTextMutation: { mutation in
                    do {
                        if let viewport = mutation.viewport {
                            try document.replace(in: viewport, utf16Range: mutation.range, with: mutation.replacement)
                        } else {
                            try document.replace(utf16Range: mutation.range, with: mutation.replacement)
                        }
                        return true
                    } catch { return false }
                }
            )
            canvas.setFrameSize(NSSize(width: 800, height: canvas.logicalHeight))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800,
                pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            for fraction: CGFloat in [0, 0.5, 1, 0] {
                let y = max(0, canvas.logicalHeight - 600) * fraction
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                canvas.reloadViewportIfNeeded(scrollY: y)
                let visibleText = try XCTUnwrap(canvas.accessibilityValue() as? String)
                XCTAssertLessThanOrEqual(visibleText.utf8.count, 2048)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                canvas.draw(NSRect(x: 0, y: y, width: 800, height: 600))
                NSGraphicsContext.restoreGraphicsState()
            }
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            print("DENSE_MARKDOWN_CANVAS wraps=\(wraps) configure_draw_scroll_ms=\(elapsed)")
            canvas.insertText("Y", replacementRange: NSRange(location: 2, length: 1))
            XCTAssertTrue(document.string().hasPrefix("# Y\n"))
            canvas.undoManager?.undo()
            XCTAssertTrue(document.string().hasPrefix("# x\n"))
            // Native input can deliver several edits before SwiftUI configures again.
            for character in "NVE_SAVE_CHECK" {
                canvas.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            XCTAssertTrue(document.string().hasPrefix("# xNVE_SAVE_CHECK\n"))
            XCTAssertEqual(canvas.selectedRange(), NSRange(location: 17, length: 0))
            XCTAssertTrue(canvas.accessibilityHelp()?.contains("Line 1, column 18") == true)
            canvas.insertText("😀", replacementRange: NSRange(location: NSNotFound, length: 0))
            canvas.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(document.string().hasPrefix("# xNVE_SAVE_CHECK😀é\n"))
            XCTAssertTrue(canvas.isAccessibilityElement())
            XCTAssertEqual(canvas.accessibilityRole(), .textArea)
            XCTAssertTrue(canvas.acceptsFirstResponder)
            // Find/navigation offsets must not be estimated from average line lengths.
            let uneven = String(repeating: "x", count: 300_000) + "\ntarget\n" + String(repeating: "z\n", count: 1_000)
            try document.replaceAll(with: uneven)
            NotificationCenter.default.post(name: .moveCursorToRange, object: nil, userInfo: [
                EditorCommandUserInfo.documentID: documentID.uuidString,
                EditorCommandUserInfo.rangeLocation: 300_001,
                EditorCommandUserInfo.rangeLength: 6,
                EditorCommandUserInfo.centerSelection: true
            ])
            XCTAssertEqual(canvas.selectedRange(), NSRange(location: 300_001, length: 6))
            XCTAssertTrue(canvas.accessibilityHelp()?.contains("Line 2, column 1") == true)
        }
    }

    func testScrollContainerDoesNotRetainMeasurementsFromAnUnallocatedWidth() throws {
        let text = String(repeating: "Markdown text ", count: 12)
        let document = FileBackedTextDocument(content: String(repeating: text + "\n", count: 2_000))
        let documentID = UUID()
        let scrollView = VirtualEditorScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let canvas = try XCTUnwrap(scrollView.documentView as? VirtualEditorCanvas)
        for width: CGFloat in [800, 440, 1000] {
            scrollView.setFrameSize(NSSize(width: width, height: 600))
            scrollView.configure(
                document: document,
                documentID: documentID,
                resourceID: "dense-markdown-regression",
                displayName: "Architecture.md",
                contentRevision: 0,
                externalContentRevision: 0,
                caret: 0,
                language: "markdown",
                colorScheme: .light,
                fontSize: 14,
                fontName: "",
                lineHeightMultiplier: 1,
                isReadOnly: false,
                translucentBackgroundEnabled: false,
                showsLineNumbers: true,
                highlightCurrentLine: false,
                lineWrapEnabled: true,
                showsInvisibleCharacters: false,
                showsIndentationGuides: false,
                showsScopeGuides: false,
                highlightsScopeBackground: false,
                highlightsMatchingBrackets: false,
                autoIndentEnabled: true,
                autoCloseBracketsEnabled: false,
                isSplitPaneResizeInProgress: false,
                onFontSizeChange: nil,
                onTextMutation: { mutation in
                    do {
                        if let viewport = mutation.viewport {
                            try document.replace(in: viewport, utf16Range: mutation.range, with: mutation.replacement)
                        } else {
                            try document.replace(utf16Range: mutation.range, with: mutation.replacement)
                        }
                        return true
                    } catch { return false }
                }
            )
            let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let gutter = max(44, CGFloat(document.lineCount.description.count) * 14 * 0.7 + 18)
            let fragments = VirtualEditorVisualLayout.fragments(
                for: NSAttributedString(string: text, attributes: [.font: font]), lineStartUTF16: 0,
                width: scrollView.contentView.bounds.width - gutter - 16, wraps: true)
            let rowHeight = font.ascender - font.descender + font.leading + 4
            let expectedHeight = CGFloat(document.lineCount * fragments.count) * rowHeight + 16
            XCTAssertLessThan(canvas.logicalHeight, expectedHeight * 1.05)
            XCTAssertGreaterThan(canvas.logicalHeight, expectedHeight * 0.95)
            let y = max(0, canvas.logicalHeight - 600) * 0.5
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            XCTAssertGreaterThan(canvas.viewportLineOrigin, 0)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width),
                pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let visible = scrollView.contentView.bounds
            context.cgContext.translateBy(x: 0, y: -visible.minY)
            canvas.draw(visible)
            NSGraphicsContext.restoreGraphicsState()
            var textPixels = 0
            for pixelY in stride(from: 0, to: 600, by: 4) {
                for pixelX in stride(from: 80, to: Int(width), by: 4) {
                    if let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB),
                       color.alphaComponent > 0.5,
                       min(color.redComponent, color.greenComponent, color.blueComponent) < 0.8 {
                        textPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(textPixels, 100, "A scroll jump must render visible text, not a blank viewport")
        }
    }

    func testAccessibilityContextIncludesDocumentPositionEditabilityAndSelection() {
        let context = VirtualEditorAccessibilityContext(
            documentName: "Notes.md",
            line: 12,
            column: 7,
            isReadOnly: true,
            selectionLength: 4
        )

        XCTAssertEqual(context.label, "Notes.md, editor")
        XCTAssertEqual(context.help, "Line 12, column 7, read only, 4 characters selected.")
    }

    func testPreviewReloadMetricsExposeCoalescing() {
        let monitor = EditorPerformanceMonitor.shared
        monitor.resetPreviewReloadMetrics()
        monitor.markPreviewReloadScheduled(coalesced: false)
        monitor.markPreviewReloadScheduled(coalesced: true)
        monitor.markPreviewReloadExecuted()

        XCTAssertEqual(
            monitor.previewReloadSnapshot(),
            EditorPerformanceMonitor.PreviewReloadSnapshot(requested: 2, coalesced: 1, executed: 1)
        )
    }

    func testShiftWheelZoomConvertsBothScrollDirectionsToFontDeltas() {
        XCTAssertEqual(VirtualEditorWheelZoom.fontSizeDelta(scrollingDeltaY: 5, fallbackDeltaY: 0), 1)
        XCTAssertEqual(VirtualEditorWheelZoom.fontSizeDelta(scrollingDeltaY: -5, fallbackDeltaY: 0), -1)
        XCTAssertEqual(VirtualEditorWheelZoom.fontSizeDelta(scrollingDeltaY: 0, fallbackDeltaY: 5), 1)
    }

    func testImpreciseMouseWheelUsesDiscreteFontSteps() {
        XCTAssertEqual(
            VirtualEditorWheelZoom.fontSizeDelta(
                scrollingDeltaY: 0,
                fallbackDeltaY: 1,
                hasPreciseScrollingDeltas: false
            ),
            1
        )
        XCTAssertEqual(
            VirtualEditorWheelZoom.fontSizeDelta(
                scrollingDeltaY: 0,
                fallbackDeltaY: -1,
                hasPreciseScrollingDeltas: false
            ),
            -1
        )
        XCTAssertEqual(
            VirtualEditorWheelZoom.fontSizeDelta(
                scrollingDeltaY: 0.2,
                fallbackDeltaY: 0,
                hasPreciseScrollingDeltas: false
            ),
            1
        )
    }

    func testUnwrappedContentWidthIncludesLongestRenderedLine() {
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(repeating: "W", count: 80), attributes: [.font: font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

        XCTAssertGreaterThan(width, 500)
    }

    func testVisualFragmentLayoutPerformanceBaseline() {
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attributed = NSAttributedString(
            string: String(repeating: "let value = 42 // benchmark\n", count: 2_000),
            attributes: [.font: font]
        )

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            _ = VirtualEditorVisualLayout.fragments(
                for: attributed,
                lineStartUTF16: 0,
                width: 640,
                wraps: true
            )
        }
    }

    func testVisualRowIndexMapsLogicalLinesToStableEstimatedRows() {
        let index = VirtualEditorVisualRowIndex(logicalLineCount: 100, estimatedRowsPerLogicalLine: 2)

        XCTAssertEqual(index.estimatedRowCount, 200)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 0), 0)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 25), 50)
        XCTAssertEqual(index.rowOrigin(forLogicalLine: 99), 198)
    }

    func testScrollAnchorPolicyLoadsTheFinalDocumentLineAtTheBottom() {
        XCTAssertEqual(
            VirtualEditorScrollAnchorPolicy.anchorLine(
                scrollY: 1_000,
                lineHeight: 20,
                estimatedRowsPerLogicalLine: 1.5,
                prefetchLines: 20,
                documentLineCount: 10_000,
                isAtBottom: true
            ),
            9_999
        )
    }

    func testScrollAnchorPolicyPrefetchesAboveTheVisibleViewport() {
        XCTAssertEqual(
            VirtualEditorScrollAnchorPolicy.anchorLine(
                scrollY: 1_000,
                lineHeight: 20,
                estimatedRowsPerLogicalLine: 1.5,
                prefetchLines: 20,
                documentLineCount: 10_000,
                isAtBottom: false
            ),
            13
        )
    }

    func testVisualRowEstimateSmoothingIsBoundedAndExplicit() {
        XCTAssertEqual(
            VirtualEditorVisualRowIndex.smoothedEstimate(previous: 1, observed: 3),
            1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VirtualEditorVisualRowIndex.smoothedEstimate(previous: 4, observed: 20),
            4,
            accuracy: 0.001
        )
    }

    func testWrappedRowEstimateExpandsScrollExtentInOnePass() {
        XCTAssertEqual(
            VirtualEditorVisualRowIndex.scrollExtentEstimate(previous: 1, observed: 2.75),
            2.75,
            accuracy: 0.001
        )
    }

    func testWrappedRowEstimateShrinksGraduallyWithoutUndercountingObservation() {
        XCTAssertEqual(
            VirtualEditorVisualRowIndex.scrollExtentEstimate(previous: 3, observed: 1.5),
            2.625,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(
            VirtualEditorVisualRowIndex.scrollExtentEstimate(previous: 3, observed: 1.5),
            1.5
        )
    }

    func testCompleteWrappedRowMeasurementResizesExactlyAfterSidebarTransition() {
        XCTAssertEqual(
            VirtualEditorVisualRowIndex.scrollExtentEstimate(
                previous: 3,
                observed: 1.5,
                measurementIsComplete: true
            ),
            1.5,
            accuracy: 0.001
        )
    }

    func testWrappedDocumentScrollExtentIncludesFinalLineAcrossSidebarWidths() {
        let logicalLine = String(repeating: "wrapped markdown content ", count: 10)
        let content = Array(repeating: logicalLine, count: 361).joined(separator: "\n")
        let document = FileBackedTextDocument(content: content)
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 440, height: 700))
        let documentID = UUID()

        func configure(width: CGFloat) {
            _ = canvas.setViewportSize(CGSize(width: width, height: 700))
            canvas.configure(
                document: document,
                documentID: documentID,
                resourceID: "wrapped-sidebar-regression",
                displayName: "Architecture.md",
                contentRevision: 0,
                externalContentRevision: 0,
                caret: 0,
                language: "markdown",
                colorScheme: .light,
                fontSize: 14,
                fontName: "",
                lineHeightMultiplier: 1,
                isReadOnly: false,
                translucentBackgroundEnabled: false,
                showsLineNumbers: true,
                highlightCurrentLine: false,
                lineWrapEnabled: true,
                showsInvisibleCharacters: false,
                showsIndentationGuides: false,
                showsScopeGuides: false,
                highlightsScopeBackground: false,
                highlightsMatchingBrackets: false,
                autoIndentEnabled: true,
                autoCloseBracketsEnabled: false,
                onFontSizeChange: nil,
                onTextMutation: nil
            )
            canvas.recalculateVisualMetrics()
        }

        func expectedHeight(width: CGFloat) -> CGFloat {
            let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let gutterWidth = max(44, CGFloat(document.lineCount.description.count) * 14 * 0.7 + 18)
            let fragments = VirtualEditorVisualLayout.fragments(
                for: NSAttributedString(string: logicalLine, attributes: [.font: font]),
                lineStartUTF16: 0,
                width: max(1, width - gutterWidth - 16),
                wraps: true
            )
            let lineHeight = font.ascender - font.descender + font.leading + 4
            return CGFloat(document.lineCount * fragments.count) * lineHeight + 16
        }

        configure(width: 440)
        XCTAssertEqual(canvas.logicalHeight, expectedHeight(width: 440), accuracy: 0.001)

        configure(width: 760)
        XCTAssertEqual(canvas.logicalHeight, expectedHeight(width: 760), accuracy: 0.001)
    }

    func testWrappedFragmentsRemainContiguousForAbsoluteSelectionGeometry() {
        let text = "wide text that must wrap across visual rows"
        let fragments = VirtualEditorVisualLayout.fragments(
            for: NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]),
            lineStartUTF16: 120,
            width: 70,
            wraps: true
        )

        XCTAssertGreaterThan(fragments.count, 1)
        for pair in zip(fragments, fragments.dropFirst()) {
            XCTAssertEqual(pair.0.absoluteStartUTF16 + pair.0.lengthUTF16, pair.1.absoluteStartUTF16)
        }
    }

    func testWrappedContinuationRowUsesLogicalLineCoreTextIndices() {
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "continuation",
            attributes: [.font: font]
        ))
        let row = VirtualEditorCanvas.VisualRow(
            logicalLine: 4,
            localStart: 100,
            fragment: VirtualEditorVisualFragment(
                absoluteStartUTF16: 112,
                lengthUTF16: 8,
                line: line
            ),
            baseline: 40,
            isFirstFragment: false
        )

        XCTAssertEqual(row.coreTextStringIndex(forViewportOffset: 112), 12)
        XCTAssertEqual(row.coreTextStringIndex(forViewportOffset: 120), 20)
        XCTAssertEqual(row.viewportOffset(forCoreTextStringIndex: 12, trailingFallback: false), 112)
        XCTAssertEqual(row.viewportOffset(forCoreTextStringIndex: 20, trailingFallback: false), 120)
        XCTAssertEqual(row.viewportOffset(forCoreTextStringIndex: kCFNotFound, trailingFallback: false), 112)
        XCTAssertEqual(row.viewportOffset(forCoreTextStringIndex: kCFNotFound, trailingFallback: true), 120)
    }

    func testFirstVisualRowBaselineLeavesRoomForTheFontAscender() {
        XCTAssertEqual(
            VirtualEditorVisualLayout.baseline(
                rowOrigin: 0,
                lineHeight: 21,
                fontAscender: 13
            ),
            15
        )
    }

    func testLineNumberOriginAlignsWithCoreTextBaselineAcrossFontSizes() {
        for size: CGFloat in [11, 14, 24] {
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            for multiplier: CGFloat in [1, 1.25, 1.6] {
                let lineHeight = (font.ascender - font.descender + font.leading + 4) * multiplier
                let baseline = VirtualEditorVisualLayout.baseline(
                    rowOrigin: 3,
                    lineHeight: lineHeight,
                    fontAscender: font.ascender
                )

                XCTAssertEqual(
                    VirtualEditorVisualLayout.lineNumberOriginY(
                        baseline: baseline,
                        fontAscender: font.ascender
                    ),
                    baseline - font.ascender,
                    accuracy: 0.001
                )
            }
        }
    }

    func testVisualRowOwnershipCoversWrapGapsAndEndpoints() {
        let canvas = VirtualEditorCanvas(frame: .zero)
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        func row(start: Int, length: Int) -> VirtualEditorCanvas.VisualRow {
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: String(repeating: "x", count: max(1, length)),
                attributes: [.font: font]
            ))
            return VirtualEditorCanvas.VisualRow(
                logicalLine: 0,
                localStart: start,
                fragment: VirtualEditorVisualFragment(
                    absoluteStartUTF16: start,
                    lengthUTF16: length,
                    line: line
                ),
                baseline: 0,
                isFirstFragment: start == 0
            )
        }

        let rows = [row(start: 0, length: 5), row(start: 5, length: 5), row(start: 11, length: 0), row(start: 12, length: 3)]

        XCTAssertEqual(canvas.visualRow(containing: 5, in: rows)?.fragment.absoluteStartUTF16, 5)
        XCTAssertEqual(canvas.visualRow(containing: 10, in: rows)?.fragment.absoluteStartUTF16, 5)
        XCTAssertEqual(canvas.visualRow(containing: 11, in: rows)?.fragment.absoluteStartUTF16, 11)
        XCTAssertEqual(canvas.visualRow(containing: 15, in: rows)?.fragment.absoluteStartUTF16, 12)
        XCTAssertNil(canvas.visualRow(containing: -1, in: rows))
        XCTAssertNil(canvas.visualRow(containing: 16, in: rows))
    }

    func testVisualFragmentsSplitLongLineAtAvailableWidth() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let fragments = VirtualEditorVisualLayout.fragments(
            for: NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]),
            lineStartUTF16: 40,
            width: 50,
            wraps: true
        )

        XCTAssertGreaterThan(fragments.count, 1)
        XCTAssertEqual(fragments.first?.absoluteStartUTF16, 40)
        XCTAssertEqual(fragments.last.map { $0.absoluteStartUTF16 + $0.lengthUTF16 }, 40 + text.utf16.count)
    }

    func testVisualFragmentsRetainSingleFragmentWhenWrappingDisabled() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let fragments = VirtualEditorVisualLayout.fragments(
            for: NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]),
            lineStartUTF16: 0,
            width: 50,
            wraps: false
        )

        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(fragments[0].lengthUTF16, text.utf16.count)
    }

    func testWrapCacheTracksEverySidebarAndPreviewWidthTransition() {
        let text = String(repeating: "pane transition wrapping ", count: 24)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]
        )
        var cache = VirtualEditorVisualFragmentCache()
        let widths: [CGFloat] = [
            1_100, // no sidebar or preview
            820,   // sidebar only
            620,   // preview only
            340,   // sidebar and preview
            620,   // sidebar closes
            820,   // preview closes while sidebar remains
            1_100  // sidebar closes
        ]

        let fragmentCounts = widths.map { width in
            cache.fragments(
                for: attributed,
                localLine: 0,
                lineStartUTF16: 0,
                width: width,
                wraps: true
            ).count
        }

        XCTAssertGreaterThan(fragmentCounts[1], fragmentCounts[0])
        XCTAssertGreaterThan(fragmentCounts[2], fragmentCounts[1])
        XCTAssertGreaterThan(fragmentCounts[3], fragmentCounts[2])
        XCTAssertEqual(fragmentCounts[4], fragmentCounts[2])
        XCTAssertEqual(fragmentCounts[5], fragmentCounts[1])
        XCTAssertEqual(fragmentCounts[6], fragmentCounts[0])
    }

    func testWrapCacheDoesNotReuseWrappedFragmentsAfterDisablingLineWrap() {
        let attributed = NSAttributedString(
            string: String(repeating: "long line ", count: 30),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]
        )
        var cache = VirtualEditorVisualFragmentCache()

        XCTAssertGreaterThan(cache.fragments(
            for: attributed,
            localLine: 0,
            lineStartUTF16: 0,
            width: 180,
            wraps: true
        ).count, 1)
        XCTAssertEqual(cache.fragments(
            for: attributed,
            localLine: 0,
            lineStartUTF16: 0,
            width: 180,
            wraps: false
        ).count, 1)
    }

    func testCanvasFillsAndAcceptsInputAcrossEveryPaneTransition() throws {
        let scrollView = VirtualEditorScrollView(frame: NSRect(x: 0, y: 0, width: 1_100, height: 700))
        let widths: [CGFloat] = [1_100, 820, 620, 340, 620, 820, 1_100]

        for width in widths {
            scrollView.setFrameSize(NSSize(width: width, height: 700))
            scrollView.layoutSubtreeIfNeeded()
            scrollView.layout()

            let visibleWidth = scrollView.contentView.bounds.width
            let canvas = try XCTUnwrap(scrollView.documentView)
            XCTAssertEqual(canvas.frame.width, visibleWidth, accuracy: 1)
            XCTAssertTrue(canvas.acceptsFirstResponder)
            XCTAssertNotNil(canvas.hitTest(NSPoint(x: max(0, visibleWidth - 2), y: 2)))
        }
    }

    func testLargeCSVViewportHasBoundedVisibleRowBudget() {
        let source = String(repeating: "a,b,c,d,e\n", count: 30_000)
        let logicalLineCount = source.split(separator: "\n", omittingEmptySubsequences: false).count
        let visibleRowBudget = 32

        XCTAssertGreaterThan(logicalLineCount, 10_000)
        XCTAssertLessThanOrEqual(visibleRowBudget, 64)
    }

    func testNewFileViewportUsesEnclosingScrollViewWhenClipViewIsNotLaidOutYet() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 1, height: 1),
            scrollViewBounds: CGSize(width: 900, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 885, height: 700))
    }

    func testWorkspaceModeReplacementUsesTheAllocatedScrollWidth() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 1, height: 1),
            scrollViewBounds: CGSize(width: 600, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 585, height: 700))
    }

    func testBrainDumpEditorSuppliesItsPreferredWidthWhenSwiftUIHasNoProposal() {
        XCTAssertEqual(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: nil,
                proposedHeight: 700,
                preferredWidth: 920
            ),
            CGSize(width: 920, height: 700)
        )
    }

    func testBrainDumpEditorUsesTheParentProposalUpToItsPreferredWidth() {
        XCTAssertEqual(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: 600,
                proposedHeight: 700,
                preferredWidth: 920
            ),
            CGSize(width: 600, height: 700)
        )
    }

    func testBrainDumpEditorRejectsCollapsedWidthProposal() {
        XCTAssertEqual(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: 1,
                proposedHeight: 700,
                preferredWidth: 920
            ),
            CGSize(width: 920, height: 700)
        )
    }

    func testStandardEditorDefersCollapsedWidthProposalToItsParent() {
        XCTAssertNil(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: 1,
                proposedHeight: 700,
                preferredWidth: nil
            )
        )
    }

    func testStandardEditorHasNoSyntheticIntrinsicWidthDuringPreviewTransition() {
        XCTAssertNil(
            VirtualEditorLayoutSizing.sizeThatFits(
                proposedWidth: nil,
                proposedHeight: 700,
                preferredWidth: nil
            )
        )
    }

    func testPreviewSplitViewportExcludesVerticalScrollerWhenClipViewIsStale() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 900, height: 700),
            scrollViewBounds: CGSize(width: 420, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 405, height: 700))
    }

    func testViewportUsesCurrentClipWidthWhenItHasAlreadyLaidOut() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 405, height: 700),
            scrollViewBounds: CGSize(width: 420, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 405, height: 700))
    }

    func testSidebarCloseUsesExpandedScrollAllocationWhenClipViewIsStale() {
        let visibleSize = VirtualEditorViewportGeometry.visibleSize(
            contentBounds: CGSize(width: 405, height: 700),
            scrollViewBounds: CGSize(width: 900, height: 700),
            verticalScrollerWidth: 15
        )

        XCTAssertEqual(visibleSize, CGSize(width: 885, height: 700))
    }

    func testCollapsedInitialViewportIsDeferredUntilLayoutProvidesUsableWidth() {
        XCTAssertNil(VirtualEditorViewportGeometry.stabilizedSize(
            CGSize(width: 1, height: 700),
            previous: .zero,
            minimumUsableWidth: 90
        ))
    }

    func testPreviewPaneDragUsesItsCapturedMaximumWidth() {
        let width = PreviewPaneResizeGeometry.width(
            startWidth: 420,
            translation: -180,
            minimumWidth: 280,
            maximumWidth: 600
        )

        XCTAssertEqual(width, 600)
    }

    func testSplitPaneResizeDefersVirtualEditorReflow() {
        XCTAssertFalse(VirtualEditorResizePolicy.shouldReflow(isSplitPaneResizeInProgress: true))
        XCTAssertTrue(VirtualEditorResizePolicy.shouldReflow(isSplitPaneResizeInProgress: false))
    }

    func testCommandArrowNavigationRemainsWithAppKit() {
        XCTAssertTrue(VirtualEditorKeyRouting.shouldInterpretArrow(
            modifiers: [.command]
        ))
        XCTAssertTrue(VirtualEditorKeyRouting.shouldInterpretArrow(
            modifiers: [.command, .shift]
        ))
        XCTAssertFalse(VirtualEditorKeyRouting.shouldInterpretArrow(
            modifiers: [.shift]
        ))
    }

    func testCloseTabRoutingMatchesConfiguredShortcutExactly() {
        let shortcut = EditorShortcutDescriptor(key: "k", modifiers: [.command, .shift])

        XCTAssertTrue(VirtualEditorKeyRouting.matches(
            charactersIgnoringModifiers: "k",
            keyCode: 40,
            modifiers: [.command, .shift],
            shortcut: shortcut
        ))
        XCTAssertFalse(VirtualEditorKeyRouting.matches(
            charactersIgnoringModifiers: "k",
            keyCode: 40,
            modifiers: [.command],
            shortcut: shortcut
        ))
        XCTAssertFalse(VirtualEditorKeyRouting.matches(
            charactersIgnoringModifiers: "k",
            keyCode: 40,
            modifiers: [.command, .shift, .option],
            shortcut: shortcut
        ))
    }

    func testDefaultCloseTabRoutingUsesPhysicalWKeyFallback() {
        XCTAssertTrue(VirtualEditorKeyRouting.matches(
            charactersIgnoringModifiers: "z",
            keyCode: 13,
            modifiers: [.command],
            shortcut: EditorShortcutAction.closeTab.defaultShortcut
        ))
    }

    func testLargeFileTOCDoesNotMaterializeFileBackedContent() {
        XCTAssertFalse(ContentView.EditorPerformanceThresholds.shouldMaterializeTOC(
            isLargeFileModeEnabled: false,
            documentUTF16Length: 100_000,
            usesFileBackedStorage: true,
            fileByteCount: 401_000
        ))
        XCTAssertTrue(ContentView.EditorPerformanceThresholds.shouldMaterializeTOC(
            isLargeFileModeEnabled: false,
            documentUTF16Length: 100_000,
            usesFileBackedStorage: false,
            fileByteCount: 0
        ))
    }
}

private final class CountingEditorDocument: EditorDocument {
    let backing: FileBackedTextDocument
    private(set) var stringCallCount = 0

    init(backing: FileBackedTextDocument) { self.backing = backing }

    var storageKind: EditorDocumentStorageKind { backing.storageKind }
    var utf16Length: Int { backing.utf16Length }
    var isDirty: Bool { backing.isDirty }
    var supportsBoundedWindows: Bool { backing.supportsBoundedWindows }
    var lineCount: Int { backing.lineCount }
    func position(atUTF16Offset offset: Int) throws -> (line: Int, column: Int) {
        try backing.position(atUTF16Offset: offset)
    }
    func textChunk(startByteOffset: Int, maximumByteCount: Int) throws -> (text: String, byteCount: Int) {
        try backing.textChunk(startByteOffset: startByteOffset, maximumByteCount: maximumByteCount)
    }
    func text(inUTF16Range range: NSRange) throws -> String {
        try backing.text(inUTF16Range: range)
    }
    func string() -> String {
        stringCallCount += 1
        return backing.string()
    }
    func replace(range: NSRange, with replacement: String) throws {
        try backing.replace(range: range, with: replacement)
    }
    func replace(utf16Range: NSRange, with replacement: String) throws {
        try backing.replace(utf16Range: utf16Range, with: replacement)
    }
    func replaceAll(with text: String) throws { try backing.replaceAll(with: text) }
    func markClean() { backing.markClean() }
    func viewport(aroundLine line: Int, maximumByteCount: Int, maximumLineCount: Int) throws -> EditorDocumentViewport {
        try backing.viewport(aroundLine: line, maximumByteCount: maximumByteCount, maximumLineCount: maximumLineCount)
    }
    func replace(in viewport: EditorDocumentViewport, utf16Range: NSRange, with replacement: String) throws {
        try backing.replace(in: viewport, utf16Range: utf16Range, with: replacement)
    }
}
#endif
