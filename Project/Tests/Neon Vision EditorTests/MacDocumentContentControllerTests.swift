#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class MacDocumentContentControllerTests: XCTestCase {
    func testWebKitPreviewReceivesTheHeightBelowItsHeader() throws {
        let controller = MacDocumentLayout.Controller()
        var layout = MacDocumentLayout(primary: .init(id: "source", content: { AnyView(EmptyView()) }),
            source: sourceConfiguration(), availablePreviewWidthChanged: { _ in })
        layout.preview = .init(id: "markdown", content: {
            AnyView(HStack(spacing: 0) {
                Color.clear.frame(width: 11)
                VStack(spacing: 0) {
                    Text("Preview").frame(height: 40)
                    MarkdownPreviewWebView(html: "<h1>Preview content</h1>", baseURL: nil,
                        allowsContentJavaScript: false, documentID: nil, synchronizedScrollFraction: nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 280, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 4).padding(.trailing, 4).padding(.bottom, 4)
                .frame(width: 400)
            })
        })
        controller.update(layout)
        controller.view.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        controller.view.layoutSubtreeIfNeeded()
        let web = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? WKWebView }.first)
        XCTAssertEqual(web.frame.width, 396, accuracy: 1)
        XCTAssertEqual(web.frame.height, 852, accuracy: 1)
    }
    func testSidebarAndPreviewFillTheDocumentHeightInsteadOfTheirIntrinsicHeight() throws {
        let controller = MacDocumentLayout.Controller()
        let source = sourceConfiguration()
        var layout = MacDocumentLayout(primary: .init(id: "source", content: { AnyView(EmptyView()) }),
            source: source, availablePreviewWidthChanged: { _ in })
        func panel(_ title: String, width: CGFloat) -> AnyView {
            AnyView(VStack(spacing: 0) {
                Text(title).frame(height: 40)
                GeometryReader { _ in Color.blue }
            }.frame(width: width))
        }
        layout.trailingSidebar = .init(id: "project", content: { panel("Project", width: 320) })
        layout.preview = .init(id: "preview", content: { panel("Preview", width: 400) })
        controller.update(layout)
        controller.view.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        controller.view.layoutSubtreeIfNeeded()
        let hosts = descendants(controller.view).compactMap { $0 as? NSHostingView<AnyView> }
        XCTAssertEqual(hosts.count, 2)
        for host in hosts {
            XCTAssertEqual(host.frame.height, 900, accuracy: 1,
                "A full-height pane must receive the viewport height, not its header's ideal height")
        }
        XCTAssertEqual(hosts.map { $0.frame.width }.sorted(), [320, 400])
        controller.view.frame.size.height = 600
        controller.view.layoutSubtreeIfNeeded()
        for host in hosts { XCTAssertEqual(host.frame.height, 600, accuracy: 1) }
    }

    func testUnattachedInsetEditorNeverGetsNegativeGeometry() throws {
        let controller = MacDocumentContentController()
        var configuration = sourceConfiguration()
        configuration.contentInsets = NSEdgeInsets(top: 40, left: 24, bottom: 40, right: 24)
        configuration.maximumEditorWidth = 920
        controller.update(configuration)
        controller.view.frame = .zero
        controller.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(controller.primaryController?.editorView)
        XCTAssertGreaterThanOrEqual(editor.frame.width, 0)
        XCTAssertGreaterThanOrEqual(editor.frame.height, 0)
        controller.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(editor.frame.width, 920, accuracy: 1)
        XCTAssertEqual(editor.frame.height, 620, accuracy: 1)
    }

    func testCardsAndSidebarKeepFullHeightWhenPreviewIsToggled() throws {
        let controller = MacDocumentLayout.Controller()
        var layout = MacDocumentLayout(primary: .init(id: "source", content: { AnyView(EmptyView()) }),
            source: sourceConfiguration(), availablePreviewWidthChanged: { _ in })
        func panel(_ width: CGFloat) -> AnyView {
            AnyView(VStack(spacing: 0) {
                Text("Header").frame(height: 40)
                ScrollView { Text("Contents").frame(height: 1600) }
            }.frame(width: width))
        }
        layout.trailingSidebar = .init(id: "project", content: { panel(320) })
        layout.trailingPreview = .init(id: "cards", content: { panel(480) })
        controller.update(layout)
        controller.view.frame = NSRect(x: 0, y: 0, width: 1800, height: 900)
        controller.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(controller.sourceController?.primaryController?.editorView)
        for visible in [true, false, true, false] {
            layout.preview = visible ? .init(id: "preview", content: { panel(400) }) : nil
            controller.update(layout)
            controller.view.layoutSubtreeIfNeeded()
            let hosts = descendants(controller.view).compactMap { $0 as? NSHostingView<AnyView> }
            XCTAssertEqual(hosts.count, visible ? 3 : 2)
            XCTAssertTrue(controller.sourceController?.primaryController?.editorView === editor)
            for host in hosts { XCTAssertEqual(host.frame.height, 900, accuracy: 1) }
        }
    }

    func testWindowAttachesSourceControllerWithoutAFullSizeHostingWrapper() throws {
        let controller = MacDocumentLayout.Controller()
        var configuration = MacDocumentLayout(primary: .init(id: "source", content: {
            XCTFail("A source document must use its native controller, not a full-size hosting view")
            return AnyView(EmptyView())
        }), source: sourceConfiguration(), availablePreviewWidthChanged: { _ in })
        controller.update(configuration)
        let source = try XCTUnwrap(controller.sourceController)
        let editor = try XCTUnwrap(source.primaryController?.editorView)
        XCTAssertFalse(descendants(controller.view).contains { $0 is NSHostingView<AnyView> })
        configuration.preview = .init(id: "preview", content: { AnyView(Text("Preview").frame(width: 200)) })
        controller.update(configuration)
        XCTAssertTrue(controller.sourceController === source)
        XCTAssertTrue(source.primaryController?.editorView === editor)
        XCTAssertEqual(descendants(controller.view).filter { $0 is NSHostingView<AnyView> }.count, 1)
    }

    func testFormattingOverlayDoesNotCoverTheNativeEditorHitArea() throws {
        let controller = MacDocumentContentController()
        var configuration = sourceConfiguration()
        configuration.formattingOverlay = { AnyView(Button("Format") {}.frame(width: 80, height: 32)) }
        controller.update(configuration)
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.view.layoutSubtreeIfNeeded()
        let overlay = try XCTUnwrap(descendants(controller.view).first { $0 is NSHostingView<AnyView> })
        XCTAssertEqual(overlay.frame, NSRect(x: 720, y: 468, width: 80, height: 32))
        XCTAssertFalse(overlay.frame.contains(NSPoint(x: 200, y: 200)))
        let hit = controller.view.hitTest(NSPoint(x: 200, y: 200))
        XCTAssertNotNil(hit)
        XCTAssertFalse(hit === overlay || hit?.isDescendant(of: overlay) == true)
    }

    func testWindowLayoutCreatesOnlyVisibleRegionsAndKeepsPrimaryHost() throws {
        let controller = MacDocumentLayout.Controller()
        var constructed = 0
        var configuration = MacDocumentLayout(primary: .init(id: "source", content: { AnyView(Text("Source")) }),
            availablePreviewWidthChanged: { _ in })
        controller.update(configuration)
        let primary = try XCTUnwrap(descendants(controller.view).first { $0 is NSHostingView<AnyView> })
        XCTAssertEqual(descendants(controller.view).filter { $0 is NSHostingView<AnyView> }.count, 1)
        weak var preview: NSView?
        autoreleasepool {
            configuration.preview = .init(id: "preview", content: {
                constructed += 1
                return AnyView(Text("Preview").frame(width: 200))
            })
            controller.update(configuration)
            XCTAssertEqual(constructed, 1)
            let hosts = descendants(controller.view).filter { $0 is NSHostingView<AnyView> }
            XCTAssertEqual(hosts.count, 2)
            XCTAssertTrue(hosts.contains { $0 === primary })
            preview = hosts.first { $0 !== primary }
            configuration.preview = nil
            controller.update(configuration)
        }
        XCTAssertEqual(constructed, 1)
        XCTAssertNil(preview)
        XCTAssertTrue(descendants(controller.view).contains { $0 === primary })
    }

    func testWindowLayoutDefersWidthPublicationUntilAfterLayout() async {
        let controller = MacDocumentLayout.Controller()
        var widths: [CGFloat] = []
        let configuration = MacDocumentLayout(primary: .init(id: "source", content: { AnyView(Text("Source")) }),
            availablePreviewWidthChanged: { widths.append($0) })
        controller.update(configuration)
        XCTAssertTrue(widths.isEmpty)
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(widths.isEmpty, "A native layout callback must not mutate SwiftUI state synchronously")
        await Task.yield()
        XCTAssertEqual(widths.last, 800)
        controller.update(configuration)
        controller.view.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertEqual(widths, [800])
    }

    func testSourceEditorHasNoHostingGraphAndRetainsCanvasAcrossUpdates() throws {
        let controller = MacDocumentContentController()
        let configuration = sourceConfiguration()
        controller.update(configuration)
        let pane = try XCTUnwrap(controller.primaryController)
        let editor = try XCTUnwrap(pane.editorView)
        let canvas = try XCTUnwrap(editor.documentView)
        for _ in 0..<20 { controller.update(configuration) }
        XCTAssertTrue(controller.primaryController === pane)
        XCTAssertTrue(pane.editorView === editor)
        XCTAssertTrue(editor.documentView === canvas)
        XCTAssertFalse(descendants(controller.view).contains { $0 is NSHostingView<AnyView> },
            "The ordinary text canvas and its layout must not be wrapped in a SwiftUI host")
    }

    func testSecondaryEditorIsLazyAndReleasedWhenClosed() throws {
        let controller = MacDocumentContentController()
        var configuration = sourceConfiguration()
        controller.update(configuration)
        XCTAssertNil(controller.secondaryController)
        let primary = try XCTUnwrap(controller.primaryController)
        weak var secondary: MacDocumentContentController.EditorPaneController?
        autoreleasepool {
            configuration.secondary = sourceConfiguration().primary
            controller.update(configuration)
            secondary = controller.secondaryController
            XCTAssertNotNil(secondary?.editorView)
            XCTAssertFalse(primary.editorView === secondary?.editorView)
            XCTAssertEqual(primary.view.superview?.accessibilityLabel(), NSLocalizedString("Split editor", comment: ""))
            configuration.secondary = nil
            controller.update(configuration)
        }
        XCTAssertNil(controller.secondaryController)
        XCTAssertNil(secondary)
        XCTAssertTrue(controller.primaryController === primary)
    }

    func testReadingModeDoesNotEagerlyCreateSourceEditor() {
        let controller = MacDocumentContentController()
        var configuration = sourceConfiguration()
        var constructed = 0
        configuration.replacement = { constructed += 1; return AnyView(Text("Reading")) }
        controller.update(configuration)
        XCTAssertEqual(constructed, 1)
        XCTAssertNil(controller.primaryController)
        configuration.replacement = nil
        controller.update(configuration)
        XCTAssertNotNil(controller.primaryController?.editorView)
        XCTAssertEqual(constructed, 1)
    }

    func testSourceReadingSourceKeepsNativeCanvasAndReleasesReadingHost() throws {
        let controller = MacDocumentContentController()
        var configuration = sourceConfiguration()
        controller.update(configuration)
        let editor = try XCTUnwrap(controller.primaryController?.editorView)
        weak var replacement: NSView?
        autoreleasepool {
            configuration.replacement = { AnyView(Text("Reading")) }
            controller.update(configuration)
            XCTAssertNil(editor.window)
            replacement = descendants(controller.view).first { $0 is NSHostingView<AnyView> }
            XCTAssertNotNil(replacement)
            configuration.replacement = nil
            controller.update(configuration)
        }
        XCTAssertTrue(controller.primaryController?.editorView === editor)
        XCTAssertNil(replacement)
    }

    func testMinimapAndStatusHostsAreAbsentUntilRequestedAndReleasedWhenHidden() throws {
        let controller = MacDocumentContentController()
        var configuration = sourceConfiguration()
        controller.update(configuration)
        XCTAssertFalse(descendants(controller.view).contains { $0 is NSHostingView<AnyView> })
        var minimapConstructions = 0
        var statusConstructions = 0
        configuration.primary?.minimap = {
            minimapConstructions += 1
            return AnyView(Text("Map").frame(width: 144))
        }
        configuration.status = { statusConstructions += 1; return AnyView(Text("Status")) }
        controller.update(configuration)
        XCTAssertEqual(minimapConstructions, 1)
        XCTAssertEqual(statusConstructions, 1)
        XCTAssertEqual(descendants(controller.view).filter { $0 is NSHostingView<AnyView> }.count, 2)
        configuration.primary?.minimap = nil
        configuration.status = nil
        controller.update(configuration)
        XCTAssertEqual(minimapConstructions, 1)
        XCTAssertEqual(statusConstructions, 1)
        XCTAssertFalse(descendants(controller.view).contains { $0 is NSHostingView<AnyView> })
    }

    func testLayoutGivesNativeEditorRemainingSpaceAfterAccessories() throws {
        let controller = MacDocumentContentController()
        var configuration = sourceConfiguration()
        configuration.header = { AnyView(Text("Header").frame(height: 32)) }
        configuration.status = { AnyView(Text("Status").frame(height: 24)) }
        configuration.find = { AnyView(Text("Find").frame(height: 44)) }
        controller.update(configuration)
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(controller.primaryController?.editorView)
        XCTAssertEqual(editor.frame.width, 800, accuracy: 1)
        XCTAssertEqual(editor.frame.height, 400, accuracy: 1)
        configuration.header = nil
        configuration.find = nil
        controller.update(configuration)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(editor.frame.height, 476, accuracy: 1)
    }

    /// A short document's minimap has a one-line natural height. It must fill
    /// the pane beside the editor, not shrink the editor row to that line.
    func testShortDocumentMinimapDoesNotCollapseTheEditorRow() throws {
        let controller = MacDocumentContentController()
        var configuration = sourceConfiguration()
        configuration.primary?.minimap = { AnyView(Color.clear.frame(width: 120, height: 20)) }
        configuration.status = { AnyView(Text("Status").frame(height: 24)) }
        controller.update(configuration)
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(controller.primaryController?.editorView)
        XCTAssertEqual(editor.frame.height, 476, accuracy: 1, "The editor must fill the height above the status bar")
        let minimap = try XCTUnwrap(descendants(controller.view).first { $0 is NSHostingView<AnyView> && $0.frame.width == 120 })
        XCTAssertEqual(minimap.frame.height, editor.frame.height, accuracy: 1, "The minimap spans the editor's height")
    }

    func testTwoDocumentsNeverShareTheirCanvas() throws {
        let first = MacDocumentContentController()
        let second = MacDocumentContentController()
        first.update(sourceConfiguration())
        second.update(sourceConfiguration())
        XCTAssertFalse(try XCTUnwrap(first.primaryController?.editorView) === XCTUnwrap(second.primaryController?.editorView))
    }

    private func sourceConfiguration() -> MacDocumentContentController.Configuration {
        let id = UUID()
        let editor = VirtualEditorView(document: FileBackedTextDocument(content: "let value = 1\n"),
            documentID: id, documentResourceID: id.uuidString, documentDisplayName: "Fixture.swift",
            contentRevision: 0, externalContentRevision: 0, storedCaretLocation: 0, language: "swift",
            colorScheme: .light, themeRefreshToken: 0, fontSize: 14, fontName: "", lineHeightMultiplier: 1,
            isReadOnly: false, translucentBackgroundEnabled: false, showsLineNumbers: true,
            highlightCurrentLine: true, lineWrapEnabled: true, showsInvisibleCharacters: false,
            showsIndentationGuides: false, showsScopeGuides: false, highlightsScopeBackground: false,
            highlightsMatchingBrackets: true, autoIndentEnabled: true, autoCloseBracketsEnabled: true,
            indentStyle: "spaces", indentWidth: 4, isSplitPaneResizeInProgress: false,
            preferredLayoutWidth: nil, focusesEditorOnInitialWindowAttachment: false,
            onFontSizeChange: nil, onTextMutation: nil)
        return .init(primary: .init(editor: editor))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
#endif
