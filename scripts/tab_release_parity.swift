#if os(macOS) && NVE_TAB_PARITY_APP
import AppKit
import Darwin
import SwiftUI
import WebKit

/// Compile this identical harness against the published tag with
/// NVE_RELEASE_BASELINE and against the development checkout without it.
/// It may only run in a separately identified, disposable application host.
@MainActor
final class TabReleaseParityRunner {
    static var documentModels: [EditorViewModel] = []
    static func toolbarReady(in window: NSWindow?) -> Bool {
        return window?.toolbar?.isVisible == true && window?.toolbar?.items.isEmpty == false
    }
    static func canRecordDraw(tabID: UUID, contentRevision: Int?, window: NSWindow?) -> Bool {
        guard toolbarReady(in: window), let contentRevision, let tab = documentModels.lazy.compactMap({ model in
            model.tabs.first { $0.id == tabID }
        }).first else { return false }
        return !tab.isLoadingContent && tab.contentRevision == contentRevision
    }
    weak var window: NSWindow?
    var started = false
    private struct Document {
        let model: EditorViewModel
        let window: NSWindow
        let id: UUID
        let url: URL
    }

    func run(source: EditorViewModel, parent: NSWindow, anchor: URL, startedAt: TimeInterval) async throws {
        guard ProcessInfo.processInfo.environment["NVE_RUN_TAB_PARITY"] == "1",
              Bundle.main.bundleIdentifier?.hasPrefix("h3p.NeonTabParity.") == true else {
            fatalError("Requires the explicitly enabled disposable parity app")
        }
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "SettingsShowWelcomeTourAutomatically")
        defaults.set(false, forKey: "ReopenLastSession")
        defaults.set(false, forKey: "SettingsAICompletionEnabled")
        let previewMode = ProcessInfo.processInfo.environment["NVE_PARITY_PREVIEW_MODE"] ?? "preview"
        defaults.set(previewMode, forKey: SettingsPreferenceKey.markdownPreviewDefaultMode)
        let support = SupportPurchaseManager(loadProducts: { [] }, canMakePayments: { false })
        _ = support
        let updates = AppUpdateManager(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        updates.setAutoCheckEnabled(false)
        let monitor = EditorPerformanceMonitor.shared
        let root = anchor.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
#if NVE_RELEASE_BASELINE
        let variant = "release"
#else
        let variant = "native"
        let store = MacDocumentWindowTabs.shared
#endif
        var documents: [Document] = []
        var childModels: [EditorViewModel] = []
        var childWindows: [NSWindow] = []
        defer {
#if !NVE_RELEASE_BASELINE
            childModels.forEach { store.unregister($0) }
            store.unregister(source)
#endif
            childWindows.forEach { $0.close() }
            parent.close()
            try? FileManager.default.removeItem(at: root)
        }
        func wait(_ condition: () -> Bool, window: NSWindow, message: String) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + 15
            while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
                window.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(1))
            }
            if !condition() {
                let c = canvas(in: window.contentView)
                FileHandle.standardError.write(Data("DIAG \(message) title=\(window.title) visible=\(window.isVisible) occl=\(window.occlusionState.rawValue) key=\(window.isKeyWindow) active=\(NSApp.isActive) canvas=\(c != nil) pending=\(c?.isViewportActivationPending as Any) toolbar=\(Self.toolbarReady(in: window)) events=\(monitor.recentTabSwitchEvents(limit: 1).count) content=\(type(of: window.contentView!))\n".utf8))
            }
            XCTAssertTrue(condition(), message)
        }
        func ready(_ item: Document) -> Bool {
            guard item.model.selectedTabID == item.id,
                  item.model.selectedTab?.isLoadingContent == false,
                  let canvas = canvas(in: item.window.contentView),
                  !canvas.isViewportActivationPending else { return false }
            // An absent/broken toolbar is not a performance optimization.
            guard Self.toolbarReady(in: item.window) else { return false }
            return canvas.accessibilityNumberOfCharacters() == item.model.selectedTab?.document.utf16Length
        }
        func draw(_ item: Document) async throws -> Double {
            try await wait({ ready(item) }, window: item.window, message: "Loaded document must have an installed viewport")
            if monitor.recentTabSwitchEvents(limit: 1).isEmpty {
                canvas(in: item.window.contentView)?.needsDisplay = true
            }
            try await wait({ !monitor.recentTabSwitchEvents(limit: 1).isEmpty }, window: item.window,
                message: "The real canvas must draw, not only select a tab")
            return Double(try XCTUnwrap(monitor.recentTabSwitchEvents(limit: 1).last).elapsedMilliseconds)
        }
        func emit(_ metric: String, _ samples: [Double]) {
            let record: [String: Any] = ["evidence_version": 2, "variant": variant, "preview": previewMode,
                "metric": metric, "samples": samples]
            let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            // Unbuffered: a watchdog _exit must not discard completed records.
            FileHandle.standardOutput.write(Data("TAB_RELEASE_PARITY \(String(decoding: data, as: UTF8.self))\n".utf8))
        }
        // Preload the same anchor so startup measures window/editor setup, not
        // different session-recovery policies or first-file replacement rules.
        let startupID = try XCTUnwrap(source.selectedTabID)
        let startup = Document(model: source, window: parent, id: startupID, url: anchor)
        let startupDraw = try await draw(startup)
        emit("startup_editor_draw_ms", [startupDraw])
        // Backing-store memory depends on the display; paired runs must match.
        let screen = parent.screen
        print("TAB_RELEASE_PARITY_ENV screen=\(screen?.frame.size ?? .zero) scale=\(screen?.backingScaleFactor ?? 0) edr=\(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 0) window=\(parent.frame.size)")
        try await Task.sleep(for: .milliseconds(500))
        let memoryBefore = residentBytes()
        var openStarted: TimeInterval = 0
        var beforeWindowMilliseconds: Double = 0
        var fixtures = [
            ("Small.swift", String(repeating: "let number = 42\n", count: 100)),
            ("Unicode.json", "[" + Array(repeating: "{\"text\":\"café 中文 😀\",\"number\":123}", count: 8_000).joined(separator: ",") + "]"),
            ("Large.md", String(repeating: "## Heading **bold** `code`\n\nMarkdown text café 中文 😀.\n", count: 12_000)),
            ("Large.swift", String(repeating: "let number = 42 // parity benchmark\n", count: 100_000))
        ]
        if ProcessInfo.processInfo.environment["NVE_PARITY_RENDER_DIR"] != nil,
           let count = Int(ProcessInfo.processInfo.environment["NVE_RENDER_MARKDOWN_LINES"] ?? "") {
            fixtures[2].1 = String(repeating: "## Heading **bold** `code`\n\nMarkdown text café 中文 😀.\n", count: count)
        }
        if ProcessInfo.processInfo.environment["NVE_TAB_PARITY_PROFILE_COLD"] == "1" {
            // A different workload for stack sampling, never acceptance timing.
            FileHandle.standardOutput.write(Data("TAB_RELEASE_PARITY_DIAGNOSTIC_PAUSE cold-profile\n".utf8))
            fixtures = (0..<20).map { ("Cold\($0).swift", String(repeating: "let number = 42\n", count: 100)) }
        }
        for (name, text) in fixtures {
            let url = root.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            monitor.clearRecentTabSwitchEvents()
            openStarted = ProcessInfo.processInfo.systemUptime
            XCTAssertTrue(source.openFile(url: url))
#if NVE_RELEASE_BASELINE
            let id = try XCTUnwrap(source.selectedTabID)
            beforeWindowMilliseconds = (ProcessInfo.processInfo.systemUptime - openStarted) * 1_000
            monitor.beginTabSwitch(tabID: id)
            documents.append(Document(model: source, window: parent, id: id, url: url))
#else
            let owner = try XCTUnwrap(store.models.first { $0.selectedTab?.fileURL == url })
            Self.documentModels.append(owner)
            let id = try XCTUnwrap(owner.selectedTabID)
            beforeWindowMilliseconds = (ProcessInfo.processInfo.systemUptime - openStarted) * 1_000
            monitor.beginTabSwitch(tabID: id)
            try await wait({ NSApp.windows.contains { $0.title == url.lastPathComponent } },
                window: parent, message: "Native document window created")
            let candidate = try XCTUnwrap(NSApp.windows.first { $0.title == url.lastPathComponent })
            childModels.append(owner)
            childWindows.append(candidate)
            documents.append(Document(model: owner, window: candidate, id: id, url: url))
#endif
            let item = try XCTUnwrap(documents.last)
            emit("open_\(name)_ms", [beforeWindowMilliseconds + (try await draw(item))])
            try await Task.sleep(for: .milliseconds(500))
        }
        if let directory = ProcessInfo.processInfo.environment["NVE_PARITY_RENDER_DIR"] {
            // Rendered diagnostics deliberately change the workload and must
            // never be accepted as release-performance evidence.
            print("TAB_RELEASE_PARITY_DIAGNOSTIC_PAUSE render")
            let directory = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            func firstView<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
                guard let view else { return nil }
                if let match = view as? T { return match }
                return view.subviews.lazy.compactMap { firstView(type, in: $0) }.first
            }
            /// A source editor must fill its pane, not collapse to one centered line.
            func checkEditorFillsPane(_ item: Document, _ label: String) {
                guard let scroll = firstView(VirtualEditorScrollView.self, in: item.window.contentView) else {
                    print("RENDER_EDITOR \(label) file=\(item.url.lastPathComponent) missing")
                    XCTFail("The selected source document must install its editor (\(label) \(item.url.lastPathComponent))")
                    return
                }
                // Available height: the content area that hosts the editor panes,
                // minus any pane header stacked above this editor's row.
                var ancestor = scroll.superview
                var paneColumn: NSStackView?
                while let view = ancestor, !String(describing: type(of: view)).contains("ContentContainer") {
                    if paneColumn == nil, let stack = view as? NSStackView, stack.orientation == .vertical { paneColumn = stack }
                    ancestor = view.superview
                }
                let paneHeader = paneColumn?.arrangedSubviews.filter { !scroll.isDescendant(of: $0) }
                    .reduce(0) { $0 + $1.frame.height } ?? 0
                let available = (ancestor?.bounds.height ?? item.window.contentLayoutRect.height) - paneHeader
                let frame = scroll.convert(scroll.bounds, to: nil)
                print("RENDER_EDITOR \(label) file=\(item.url.lastPathComponent) frame=\(frame) available=\(available) viewport=\(item.window.contentLayoutRect) hidden=\(scroll.isHiddenOrHasHiddenAncestor)")
                XCTAssertTrue(!scroll.isHiddenOrHasHiddenAncestor && ancestor != nil && abs(frame.height - available) <= 2,
                    "The selected editor must be visible and fill its pane (\(label) \(item.url.lastPathComponent))")
            }
#if !NVE_RELEASE_BASELINE
            // YAML regression fixture, then a new tab followed by selecting the previous one.
            let yamlURL = root.appendingPathComponent("Review.yaml")
            try "# yaml-language-server: $schema=https://example.com/schema.json\n# Keep review available on demand.\nreviews:\n  auto_review:\n    enabled: false\n    auto_incremental_review: false\n".write(to: yamlURL, atomically: true, encoding: .utf8)
            XCTAssertTrue(source.openFile(url: yamlURL))
            try await wait({ NSApp.windows.contains { $0.title == "Review.yaml" } }, window: parent, message: "YAML window created")
            let yamlOwner = try XCTUnwrap(store.models.first { $0.selectedTab?.fileURL == yamlURL })
            let yamlWindow = try XCTUnwrap(NSApp.windows.first { $0.title == "Review.yaml" })
            Self.documentModels.append(yamlOwner)
            childModels.append(yamlOwner)
            childWindows.append(yamlWindow)
            let yaml = Document(model: yamlOwner, window: yamlWindow, id: try XCTUnwrap(yamlOwner.selectedTabID), url: yamlURL)
            documents.append(yaml)
            _ = try await draw(yaml)
            try await Task.sleep(for: .milliseconds(300))
            checkEditorFillsPane(yaml, "opened")
            let shortSwiftURL = root.appendingPathComponent("Short.swift")
            try "import Foundation\nlet answer = 42\n".write(to: shortSwiftURL, atomically: true, encoding: .utf8)
            XCTAssertTrue(source.openFile(url: shortSwiftURL))
            try await wait({ NSApp.windows.contains { $0.title == "Short.swift" } }, window: parent, message: "Short Swift window created")
            let shortOwner = try XCTUnwrap(store.models.first { $0.selectedTab?.fileURL == shortSwiftURL })
            let shortWindow = try XCTUnwrap(NSApp.windows.first { $0.title == "Short.swift" })
            Self.documentModels.append(shortOwner)
            childModels.append(shortOwner)
            childWindows.append(shortWindow)
            let shortSwift = Document(model: shortOwner, window: shortWindow, id: try XCTUnwrap(shortOwner.selectedTabID), url: shortSwiftURL)
            documents.append(shortSwift)
            _ = try await draw(shortSwift)
            try await Task.sleep(for: .milliseconds(300))
            checkEditorFillsPane(shortSwift, "opened")
            let ownersBeforeNewTab = Set(store.models.map(ObjectIdentifier.init))
            let windowsBeforeNewTab = Set(NSApp.windows.map(ObjectIdentifier.init))
            shortOwner.addNewTab()
            try await wait({ store.models.contains { !ownersBeforeNewTab.contains(ObjectIdentifier($0)) } },
                window: parent, message: "New tab created")
            let newOwner = try XCTUnwrap(store.models.first { !ownersBeforeNewTab.contains(ObjectIdentifier($0)) })
            childModels.append(newOwner)
            try await wait({ store.selectedModel === newOwner && newOwner.selectedTab != nil }, window: parent, message: "New tab selected")
            // Track the new tab's window so cleanup closes it.
            childWindows.append(contentsOf: NSApp.windows.filter {
                !windowsBeforeNewTab.contains(ObjectIdentifier($0)) && $0.tabbingIdentifier == MacDocumentTabPolicy.tabbingIdentifier
            })
            XCTAssertTrue(childWindows.contains { $0.tabGroup?.selectedWindow === $0 }, "The new tab's window must be tracked for cleanup")
            try await Task.sleep(for: .milliseconds(500))
            for previous in documents.reversed() {
                // Select exactly as the tab bar does, without forcing a redraw.
                previous.window.tabGroup?.selectedWindow = previous.window
                try await Task.sleep(for: .milliseconds(400))
                checkEditorFillsPane(previous, "after-new-tab")
            }
#endif
            var startupTitlebar: [String] = []
            for item in [startup] + documents {
                item.window.tabGroup?.selectedWindow = item.window
                item.window.makeKeyAndOrderFront(nil)
                NSApp.activate()
                item.window.contentView?.layoutSubtreeIfNeeded()
                item.window.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                func regions(_ view: NSView) -> [NSView] {
                    (view.identifier?.rawValue.hasPrefix("NeonDocumentRegion.") == true ? [view] : [])
                        + view.subviews.flatMap(regions)
                }
                let content = try XCTUnwrap(item.window.contentView)
                if item.url.pathExtension != "md" { checkEditorFillsPane(item, "render") }
                if item.url.pathExtension == "md" {
                    func previewWebView() -> WKWebView? {
                        func web(_ view: NSView) -> WKWebView? {
                            if let view = view as? WKWebView { return view }
                            return view.subviews.lazy.compactMap(web).first
                        }
                        return regions(content).first { $0.identifier?.rawValue == "NeonDocumentRegion.markdown" }.flatMap(web)
                    }
                    func heading() async -> String {
                        guard let web = previewWebView() else { return "" }
                        return await withCheckedContinuation { continuation in
                            web.evaluateJavaScript("document.querySelector('h1,h2')?.textContent ?? ''") { value, _ in
                                continuation.resume(returning: value as? String ?? "")
                            }
                        }
                    }
                    var renderedHeading = ""
                    let deadline = ProcessInfo.processInfo.systemUptime + 8
                    while ProcessInfo.processInfo.systemUptime < deadline {
                        renderedHeading = await heading()
                        if renderedHeading.contains("Heading") { break }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    XCTAssertTrue(renderedHeading.contains("Heading"), "Markdown must finish rendering, not remain on Preparing preview")
                    XCTAssertTrue(item.model.applyTabContentEdit(tabID: item.id, range: NSRange(location: 0, length: 0),
                        replacement: "# Live preview verification\n\n"), "Fixture edit must apply to its own document")
                    let editDeadline = ProcessInfo.processInfo.systemUptime + 8
                    while ProcessInfo.processInfo.systemUptime < editDeadline {
                        renderedHeading = await heading()
                        if renderedHeading.contains("Live preview verification") { break }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    XCTAssertTrue(renderedHeading.contains("Live preview verification"), "The visible preview must update after an edit")
                    let web = try XCTUnwrap(previewWebView())
                    print("RENDER_WEB frame=\(web.frame) bounds=\(web.bounds) visible=\(web.visibleRect) hidden=\(web.isHiddenOrHasHiddenAncestor)")
                    XCTAssertTrue(web.visibleRect.height > 100 && web.visibleRect.width > 100,
                        "A populated DOM must also have a visible, noncollapsed viewport")
                    let snapshot = try await web.takeSnapshot(configuration: nil)
                    if let data = snapshot.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: data),
                       let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: directory.appendingPathComponent("Markdown-WebKit.png"))
                    }
                    print("RENDER_FUNCTIONAL Markdown initial render and live edit passed")
                }
                for region in regions(content) {
                    print("RENDER_REGION file=\(item.url.lastPathComponent) id=\(region.identifier!.rawValue) frame=\(region.frame) viewport=\(item.window.contentLayoutRect)")
                    XCTAssertTrue(region.bounds.height >= item.window.contentLayoutRect.height * 0.8,
                        "Optional panes must fill the document's height, not collapse to their header")
                }
                if let frameView = item.window.contentView?.superview {
                    // Titlebar chrome is drawn by the theme frame, outside contentView.
                    func chrome(_ view: NSView, depth: Int) {
                        guard depth < 10 else { return }
                        let effect = (view as? NSVisualEffectView).map { " material=\($0.material.rawValue) state=\($0.state.rawValue) blending=\($0.blendingMode.rawValue)" } ?? ""
                        print("RENDER_CHROME file=\(item.url.lastPathComponent) \(String(repeating: ".", count: depth))\(String(describing: type(of: view)).prefix(60)) frame=\(view.frame) hidden=\(view.isHidden) alpha=\(view.alphaValue) layerBG=\(view.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB).map { String(format: "%.3f/%.3f/%.3f/%.3f", $0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent) } } ?? "nil")\(effect)")
                        view.subviews.forEach { chrome($0, depth: depth + 1) }
                    }
                    print("RENDER_CHROME_WINDOW file=\(item.url.lastPathComponent) class=\(type(of: item.window)) background=\(item.window.backgroundColor) opaque=\(item.window.isOpaque) toolbarStyle=\(item.window.toolbarStyle.rawValue) separator=\(item.window.titlebarSeparatorStyle.rawValue) content=\(type(of: item.window.contentView!)) contentFrame=\(item.window.contentView!.frame) layoutRect=\(item.window.contentLayoutRect)")
                    chrome(frameView, depth: 0)
                    if let content = item.window.contentView,
                       let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                        // Layer render of the content beneath the titlebar (no compositor materials).
                        content.cacheDisplay(in: content.bounds, to: bitmap)
                        func sample(_ x: Int, _ y: Int) -> String {
                            let scale = Double(bitmap.pixelsWide) / content.bounds.width
                            guard let color = bitmap.colorAt(x: Int(Double(x) * scale), y: Int(Double(y) * scale))?.usingColorSpace(.sRGB) else { return "nil" }
                            return String(format: "%.3f/%.3f/%.3f/%.3f", color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
                        }
                        print("RENDER_PIXELS file=\(item.url.lastPathComponent) titlebar(300,20)=\(sample(300, 20)) titlebar(1300,70)=\(sample(1300, 70)) tabbar(700,70)=\(sample(700, 70)) content(300,400)=\(sample(300, 400))")
                        let titlebar = [sample(300, 20), sample(1300, 70), sample(700, 70)]
                        if item.url == startup.url { startupTitlebar = titlebar }
                        XCTAssertTrue(titlebar == startupTitlebar,
                            "Every tab must draw the same backdrop under the titlebar as the scene-created first tab")
                        if let png = bitmap.representation(using: .png, properties: [:]) {
                            try? png.write(to: directory.appendingPathComponent("layers-" + item.url.lastPathComponent + ".png"))
                        }
                    }
                }
                print("RENDER_WINDOW file=\(item.url.lastPathComponent) number=\(item.window.windowNumber) mask=\(item.window.styleMask.rawValue) transparent=\(item.window.titlebarAppearsTransparent) appearance=\(item.window.effectiveAppearance.name.rawValue) active=\(NSApp.isActive) key=\(item.window.isKeyWindow)")
                if ProcessInfo.processInfo.environment["NVE_PARITY_SKIP_CAPTURE"] == "1" { continue }
                let screenshot = directory.appendingPathComponent(item.url.lastPathComponent + ".png")
                if ProcessInfo.processInfo.environment["NVE_PARITY_EXTERNAL_CAPTURE"] == "1" {
                    // Capture from the authorized test runner, not this newly
                    // signed disposable app's separate screen-recording identity.
                    print("RENDER_CAPTURE_READY \(item.window.windowNumber) \(screenshot.path)")
                    let acknowledgement = screenshot.appendingPathExtension("captured")
                    let deadline = ProcessInfo.processInfo.systemUptime + 10
                    while !FileManager.default.fileExists(atPath: acknowledgement.path),
                          ProcessInfo.processInfo.systemUptime < deadline {
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    XCTAssertTrue(FileManager.default.fileExists(atPath: acknowledgement.path),
                        "The test runner could not capture its owned fixture window")
                    continue
                }
                let status: Int32 = await withCheckedContinuation { continuation in
                    let number = item.window.windowNumber
                    DispatchQueue.global(qos: .userInitiated).async {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        process.arguments = ["-x", "-l", String(number), screenshot.path]
                        do {
                            try process.run()
                            process.waitUntilExit()
                            continuation.resume(returning: process.terminationStatus)
                        } catch { continuation.resume(returning: -1) }
                    }
                }
                XCTAssertTrue(status == 0, "Rendered capture requires screen-recording permission")
            }
            if let hold = Double(ProcessInfo.processInfo.environment["NVE_PARITY_HOLD_SECONDS"] ?? "") {
                // Diagnostic only: keep the owned fixture windows open for inspection.
                print("RENDER_HOLDING \(hold)")
                try await Task.sleep(for: .seconds(hold))
            }
            return
        }
        var warm: [Double] = []
        let profileWarm = ProcessInfo.processInfo.environment["NVE_TAB_PARITY_PROFILE_WARM"] == "1"
        if profileWarm {
            // Diagnostic sampling changes the workload and cannot qualify as
            // release-parity evidence (the checker rejects this marker).
            FileHandle.standardOutput.write(Data("TAB_RELEASE_PARITY_DIAGNOSTIC_PAUSE warm-profile\n".utf8))
        }
        for _ in 0..<(profileWarm ? 100 : 3) {
            for item in documents.reversed() {
#if NVE_RELEASE_BASELINE
                guard source.selectedTabID != item.id else { continue }
#else
                guard item.window.tabGroup?.selectedWindow !== item.window else { continue }
#endif
                monitor.clearRecentTabSwitchEvents()
                monitor.beginTabSwitch(tabID: item.id)
#if NVE_RELEASE_BASELINE
                source.selectTab(id: item.id)
#else
                item.window.tabGroup?.selectedWindow = item.window
                item.window.makeKeyAndOrderFront(nil)
#endif
                canvas(in: item.window.contentView)?.needsDisplay = true
                warm.append(try await draw(item))
                if profileWarm, let event = monitor.recentTabSwitchEvents(limit: 1).last {
                    print("TAB_SWITCH_STAGE file=\(item.url.lastPathComponent) total=\(event.elapsedMilliseconds) swiftui=\(event.swiftUIUpdateMilliseconds ?? -1) viewport=\(event.viewportMilliseconds ?? -1)")
                }
            }
        }
        emit("warm_switch_ms", warm)
        for item in documents {
#if NVE_RELEASE_BASELINE
            source.selectTab(id: item.id)
#else
            item.window.tabGroup?.selectedWindow = item.window
            item.window.makeKeyAndOrderFront(nil)
#endif
            try await wait({ ready(item) }, window: item.window, message: "Selected document ready for input")
            try await Task.sleep(for: .milliseconds(250))
            let editor = try XCTUnwrap(canvas(in: item.window.contentView))
            var typing: [Double] = []
            for _ in 0..<8 {
                let previousLength = item.model.selectedTab!.document.utf16Length
                monitor.clearRecentTabSwitchEvents()
                monitor.beginTabSwitch(tabID: item.id)
                editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
                try await wait({ item.model.selectedTab?.document.utf16Length == previousLength + 1 },
                    window: item.window, message: "Typing must mutate the intended document")
                typing.append(try await draw(item))
            }
            emit("typing_\(item.url.lastPathComponent)_ms", typing)
            var resizing: [Double] = []
            for width in [1300.0, 1100, 1400] {
                monitor.clearRecentTabSwitchEvents()
                monitor.beginTabSwitch(tabID: item.id)
                item.window.setContentSize(NSSize(width: width, height: 900))
                editor.needsDisplay = true
                resizing.append(try await draw(item))
            }
            emit("resize_\(item.url.lastPathComponent)_ms", resizing)
            if let scroll = editor.enclosingScrollView as? VirtualEditorScrollView {
                var scrolling: [Double] = []
                for fraction in [0.1, 0.5, 0.9, 0.0] {
                    monitor.clearRecentTabSwitchEvents()
                    monitor.beginTabSwitch(tabID: item.id)
                    let maximum = max(0, editor.frame.height - scroll.contentView.bounds.height)
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * fraction))
                    scroll.updateForVisibleBoundsChange()
                    editor.needsDisplay = true
                    scrolling.append(try await draw(item))
                }
                emit("scroll_\(item.url.lastPathComponent)_ms", scrolling)
            } else {
                XCTFail("The full editor must contain its native scrolling implementation")
            }
            let saveStarted = ProcessInfo.processInfo.systemUptime
            item.model.saveFile(tabID: item.id)
            try await wait({ item.model.tabs.first(where: { $0.id == item.id })?.isDirty == false },
                window: item.window, message: "Save must complete without losing the edited document")
            emit("save_\(item.url.lastPathComponent)_ms", [(ProcessInfo.processInfo.systemUptime - saveStarted) * 1_000])
        }
        emit("retained_editor_resident_growth_bytes", [Double(max(0, residentBytes() - memoryBefore))])
        if ProcessInfo.processInfo.environment["NVE_TAB_PARITY_ALLOCATION_PAUSE"] == "1" {
            FileHandle.standardOutput.write(Data("TAB_RELEASE_PARITY_DIAGNOSTIC_PAUSE pid=\(ProcessInfo.processInfo.processIdentifier)\n".utf8))
            try await Task.sleep(for: .seconds(30))
        }
        for item in documents.reversed() {
            let started = ProcessInfo.processInfo.systemUptime
#if NVE_RELEASE_BASELINE
            source.closeTab(tabID: item.id)
            try await wait({ !source.tabs.contains(where: { $0.id == item.id }) }, window: parent,
                message: "Clean tab must close")
#else
            item.window.performClose(nil)
            try await wait({ !item.window.isVisible }, window: parent, message: "Clean native tab must close")
#endif
            emit("close_dispatch_ms", [(ProcessInfo.processInfo.systemUptime - started) * 1_000])
        }
        // A many-file open exercises the document-loading part of restoration;
        // it deliberately does not claim bookmark/provider recovery coverage.
        documents.removeAll()
        var batchURLs: [URL] = []
        for index in 0..<12 {
            let url = root.appendingPathComponent("Batch\(index).swift")
            try fixtures[0].1.write(to: url, atomically: true, encoding: .utf8)
            batchURLs.append(url)
        }
        let batchStarted = ProcessInfo.processInfo.systemUptime
        for url in batchURLs { XCTAssertTrue(source.openFile(url: url)) }
        try await wait({
#if NVE_RELEASE_BASELINE
            batchURLs.allSatisfy { url in source.tabs.contains { $0.fileURL == url && !$0.isLoadingContent } }
#else
            batchURLs.allSatisfy { url in store.models.contains { $0.selectedTab?.fileURL == url && $0.selectedTab?.isLoadingContent == false } }
#endif
        }, window: parent, message: "Every file in the batch must finish loading")
        emit("batch_12_all_loaded_ms", [(ProcessInfo.processInfo.systemUptime - batchStarted) * 1_000])
    }

    private func canvas(in view: NSView?) -> VirtualEditorCanvas? {
        guard let view else { return nil }
        if let canvas = view as? VirtualEditorCanvas { return canvas }
        return view.subviews.lazy.compactMap { self.canvas(in: $0) }.first
    }

    private func residentBytes() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        XCTAssertEqual(result, KERN_SUCCESS)
        return Int64(info.resident_size)
    }
}
@MainActor
private func XCTAssertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "") {
    guard condition() else {
        FileHandle.standardError.write(Data("TAB_RELEASE_PARITY_ERROR \(message)\n".utf8))
        preconditionFailure(message)
    }
}
@MainActor
private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b) }
/// Unbuffered diagnostics: watchdog/assertion exits must not discard evidence.
private func print(_ items: Any...) {
    FileHandle.standardOutput.write(Data((items.map { "\($0)" }.joined(separator: " ") + "\n").utf8))
}
@MainActor
private func XCTFail(_ message: String) { fatalError(message) }
@MainActor
private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw ParityError.missingValue }
    return value
}
private enum ParityError: Error { case missingValue }

@MainActor
@main
struct TabReleaseParityApp: App {
    @State private var model: EditorViewModel
    private let runner = TabReleaseParityRunner()
    private let anchor: URL
    private let startedAt: TimeInterval
    private let support: SupportPurchaseManager
    private let updates: AppUpdateManager

    init() {
        precondition(ProcessInfo.processInfo.environment["NVE_RUN_TAB_PARITY"] == "1")
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("h3p.NeonTabParity.") == true)
        let hold = Double(ProcessInfo.processInfo.environment["NVE_PARITY_HOLD_SECONDS"] ?? "") ?? 0
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 80 + hold) {
            FileHandle.standardError.write(Data("TAB_RELEASE_PARITY_ERROR disposable app exceeded watchdog\n".utf8))
            _exit(124)
        }
        let defaults = UserDefaults.standard
        // An aborted run leaves session files and unsaved drafts in this
        // disposable domain; restoring them replaces the anchor document.
        defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        defaults.set(false, forKey: SettingsPreferenceKey.showWelcomeTourAutomatically)
        defaults.set(false, forKey: "SettingsReopenLastSession")
        defaults.set(false, forKey: "SettingsOpenWithBlankDocument")
        defaults.set(false, forKey: "ToolbarCollapsed")
        defaults.set(false, forKey: "SettingsToolbarUseCustomMac")
#if !NVE_RELEASE_BASELINE
        defaults.set(ProcessInfo.processInfo.environment["NVE_PARITY_RENDER_DIR"] != nil,
            forKey: MacDocumentTabPolicy.projectSidebarVisibilityPreferenceKey)
        defaults.set(ProcessInfo.processInfo.environment["NVE_PARITY_RENDER_DIR"] != nil && ProcessInfo.processInfo.environment["NVE_PARITY_OPAQUE"] != "1", forKey: "EnableTranslucentWindow")
        // Rendered checks include the code minimap beside short documents.
        defaults.set(ProcessInfo.processInfo.environment["NVE_PARITY_RENDER_DIR"] != nil, forKey: "SettingsShowCodeMinimap")
#endif
        defaults.set("standard", forKey: "SettingsToolbarPresetMac")
        defaults.set(ProcessInfo.processInfo.environment["NVE_PARITY_PREVIEW_MODE"] ?? "preview",
            forKey: SettingsPreferenceKey.markdownPreviewDefaultMode)
#if NVE_RELEASE_BASELINE
        let source = EditorViewModel()
#else
        let source = MacDocumentTabPolicy.makeWindowModel()
#endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tab-parity-\(UUID())")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        anchor = root.appendingPathComponent("Anchor.txt")
        let content = "Parity benchmark anchor\n"
        try! content.write(to: anchor, atomically: true, encoding: .utf8)
        source.updateTabContent(tabID: source.selectedTabID!, content: content)
        source.markTabSaved(tabID: source.selectedTabID!, fileURL: anchor)
#if !NVE_RELEASE_BASELINE
        if ProcessInfo.processInfo.environment["NVE_PARITY_RENDER_DIR"] != nil {
            try! "# Preview card\n\nIndependent project cards.\n".write(to: root.appendingPathComponent("Cards.md"), atomically: true, encoding: .utf8)
            let project = MacDocumentWindowTabs.shared.projectPreviewSession(for: source)
            project.setProjectRoot(root)
            project.isPresented = true
        }
#endif
        _model = State(initialValue: source)
        TabReleaseParityRunner.documentModels = [source]
        support = SupportPurchaseManager(loadProducts: { [] }, canMakePayments: { false })
        updates = AppUpdateManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        updates.setAutoCheckEnabled(false)
        startedAt = ProcessInfo.processInfo.systemUptime
        EditorPerformanceMonitor.shared.clearRecentTabSwitchEvents()
        EditorPerformanceMonitor.shared.beginTabSwitch(tabID: source.selectedTabID!)
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if NVE_RELEASE_BASELINE
            ContentView(startupBehavior: .standard)
                .environment(model).environmentObject(support).environmentObject(updates)
#else
            // Mirror PrimaryWindowContentView and its scene-level modifiers.
            ParityNativeEditorSurface(model: model, support: support, updates: updates)
                .modifier(EditorSceneStorageModifier())
                .tint(.blue)
                .preferredColorScheme(ReleaseRuntimePolicy.preferredColorScheme(for: "system"))
                .frame(minWidth: 600, minHeight: 400)
#endif
            }
                .background(ParityWindowProbe { runner.window = $0 })
                .task {
                    guard !runner.started else { return }
                    runner.started = true
                    do {
                        let deadline = ProcessInfo.processInfo.systemUptime + 10
                        while runner.window == nil, ProcessInfo.processInfo.systemUptime < deadline {
                            try await Task.sleep(for: .milliseconds(1))
                        }
                        let window = try XCTUnwrap(runner.window)
                        // Directly launched disposable apps can otherwise stay
                        // background-throttled, which is not editor latency.
                        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                            reason: "Foreground native-tab benchmark")
                        defer { ProcessInfo.processInfo.endActivity(activity) }
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate()
                        try await runner.run(source: model, parent: window, anchor: anchor, startedAt: startedAt)
                        print("TAB_RELEASE_PARITY_COMPLETE")
                        NSApp.terminate(nil)
                    } catch {
                        FileHandle.standardError.write(Data("TAB_RELEASE_PARITY_ERROR \(error)\n".utf8))
                        exit(1)
                    }
                }
        }
        .defaultSize(width: 1400, height: 900)
    }
}

#if !NVE_RELEASE_BASELINE
@MainActor
private struct ParityNativeEditorSurface: View {
    let model: EditorViewModel
    let support: SupportPurchaseManager
    let updates: AppUpdateManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        NativeEditorSurface(configuration: NativeEditorSurfaceConfiguration(
            model: model, startupBehavior: .standard, safeModeMessage: nil,
            frameAutosaveName: nil, initialLayout: nil, support: support, updates: updates,
            showGrokError: .constant(false), grokErrorMessage: .constant(""),
            actions: NativeEditorWindowActions(openWindow: openWindow, openSettings: openSettings)))
        .frame(minWidth: 600, minHeight: 400)
    }
}
#endif

@MainActor
private struct ParityWindowProbe: NSViewRepresentable {
    var found: (NSWindow) -> Void
    final class Probe: NSView {
        var found: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found?(window) }
        }
    }
    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.found = found
        return probe
    }
    func updateNSView(_ view: Probe, context: Context) {}
}

#endif
