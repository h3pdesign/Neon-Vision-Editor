import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit
import SwiftUI

@MainActor


/// MARK: - Tests

final class WindowTranslucencyTests: XCTestCase {
    func testNativeToolbarButtonsDoNotCreateSwiftUIHostsAndKeepTheirOwner() throws {
        let firstWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let secondWindow = NSWindow(contentRect: firstWindow.frame,
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        firstWindow.isReleasedWhenClosed = false
        secondWindow.isReleasedWhenClosed = false
        var firstActions: [String] = []
        var secondActions: [String] = []
        func configuration(_ action: @escaping (String) -> Void) -> MacDocumentToolbar {
            MacDocumentToolbar(owner: MacDocumentTabPolicy.makeWindowModel(),
                groups: [.init(id: "primary", items: ["open", "save"])], isVisible: true,
                label: { $0 }, control: { _ in XCTFail("Ordinary actions cannot construct a SwiftUI host"); return AnyView(EmptyView()) },
                overflow: { AnyView(Text($0)) },
                nativeButton: { .init(symbol: "folder", title: $0, help: $0) }, performNativeAction: action)
        }
        let first = MacDocumentToolbar.ToolbarCoordinator(configuration { firstActions.append($0) })
        let second = MacDocumentToolbar.ToolbarCoordinator(configuration { secondActions.append($0) })
        defer { first.release(); second.release(); firstWindow.close(); secondWindow.close() }
        first.bind(firstWindow)
        second.bind(secondWindow)
        XCTAssertTrue(first.hosts.isEmpty)
        XCTAssertTrue(second.hosts.isEmpty)
        let button = try XCTUnwrap(first.nativeButtons["open"])
        let secondButton = try XCTUnwrap(second.nativeButtons["open"])
        XCTAssertFalse(button === secondButton)
        button.performClick(nil)
        XCTAssertEqual(firstActions, ["open"])
        XCTAssertTrue(secondActions.isEmpty)
        first.bind(firstWindow)
        XCTAssertTrue(first.nativeButtons["open"] === button)
        secondButton.performClick(nil)
        XCTAssertEqual(secondActions, ["open"])
    }

    func testNativeToolbarUpdatesDisabledStateWithoutReplacingButton() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        var actions: [String] = []
        let configuration = MacDocumentToolbar(owner: MacDocumentTabPolicy.makeWindowModel(),
            groups: [.init(id: "primary", items: ["save"])], isVisible: true,
            label: { $0 }, control: { AnyView(Text($0)) }, overflow: { AnyView(Text($0)) },
            nativeButton: { .init(symbol: "square.and.arrow.down", title: $0, help: $0) },
            performNativeAction: { actions.append($0) })
        let coordinator = MacDocumentToolbar.ToolbarCoordinator(configuration)
        defer { coordinator.release(); window.close() }
        coordinator.bind(window)
        let button = try XCTUnwrap(coordinator.nativeButtons["save"])
        coordinator.configuration.nativeButton = { .init(symbol: "square.and.arrow.down", title: $0, help: $0, isEnabled: false) }
        coordinator.bind(window)
        XCTAssertTrue(coordinator.nativeButtons["save"] === button)
        XCTAssertFalse(button.isEnabled)
        button.performClick(nil)
        XCTAssertTrue(actions.isEmpty)
        coordinator.configuration = configuration
        coordinator.bind(window)
        button.performClick(nil)
        XCTAssertEqual(actions, ["save"])
        coordinator.configuration = MacDocumentToolbar(owner: configuration.owner, groups: [], isVisible: true,
            label: { $0 }, control: { AnyView(Text($0)) }, overflow: { AnyView(Text($0)) })
        coordinator.bind(window)
        XCTAssertTrue(coordinator.nativeButtons.isEmpty)
    }

    @MainActor private final class IdentifierChanges {
        var values: [[NSToolbarItem.Identifier]] = []
    }

    func testNativeToolbarInitialBindDoesNotPublishAnEmptyIntermediateLayout() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Identifier observation requires macOS 15") }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        MacDocumentToolbar.prepare(window)
        let toolbar = try XCTUnwrap(window.toolbar)
        let changes = IdentifierChanges()
        let observation = toolbar.observe(\.itemIdentifiers, options: [.new]) { _, change in
            MainActor.assumeIsolated { changes.values.append(change.newValue ?? []) }
        }
        let owner = MacDocumentTabPolicy.makeWindowModel()
        let configuration = MacDocumentToolbar(owner: owner,
            groups: [.init(id: "primary", items: ["open"])], isVisible: true,
            label: { $0 }, control: { AnyView(Text($0)) }, overflow: { AnyView(Text($0)) })
        let coordinator = MacDocumentToolbar.ToolbarCoordinator(configuration)
        defer { observation.invalidate(); coordinator.release(); window.close() }
        coordinator.bind(window)
        // AppKit emits intermediate per-item KVO notifications while applying
        // one diff. Assert the invariant, not its private notification count.
        XCTAssertFalse(changes.values.isEmpty)
        XCTAssertFalse(changes.values.contains(where: \.isEmpty),
            "Opening a document must not explicitly clear its toolbar before populating it")
        XCTAssertEqual(changes.values.last, [.flexibleSpace, .init("primary")])
        let initialChangeCount = changes.values.count
        coordinator.bind(window)
        XCTAssertEqual(changes.values.count, initialChangeCount, "Unchanged updates cannot relayout toolbar identifiers")
    }

    /// Symbols must not touch the rounded ends of their toolbar group.
    func testNativeToolbarGroupKeepsEdgePaddingAroundSymbols() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let configuration = MacDocumentToolbar(owner: MacDocumentTabPolicy.makeWindowModel(),
            groups: [.init(id: "primary", items: ["open", "save", "find"])],
            isVisible: true, label: { $0 }, control: { AnyView(Text($0)) }, overflow: { AnyView(Text($0)) },
            nativeButton: { .init(symbol: "folder", title: $0, help: $0) })
        let coordinator = MacDocumentToolbar.ToolbarCoordinator(configuration)
        defer { coordinator.release(); window.close() }
        coordinator.bind(window)
        let group = try XCTUnwrap(window.toolbar?.items.compactMap { $0 as? NSToolbarItemGroup }.first)
        let stack = try XCTUnwrap(group.view as? NSStackView)
        stack.frame.size = stack.fittingSize
        stack.layoutSubtreeIfNeeded()
        let buttons = stack.arrangedSubviews
        XCTAssertEqual(buttons.count, 3)
        let padding = MacDocumentToolbar.groupEdgePadding
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(buttons.first).frame.minX, padding - 0.5)
        XCTAssertLessThanOrEqual(try XCTUnwrap(buttons.last).frame.maxX, stack.bounds.width - padding + 0.5)
    }

    func testNativeToolbarActionChangesRetainUnchangedGroupsAndHostingViews() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let owner = MacDocumentTabPolicy.makeWindowModel()
        func configuration(_ actions: [String]) -> MacDocumentToolbar {
            MacDocumentToolbar(owner: owner, groups: [.init(id: "primary", items: actions)],
                isVisible: true, label: { $0 },
                control: { AnyView(Text($0)) }, overflow: { AnyView(Text($0)) })
        }
        let coordinator = MacDocumentToolbar.ToolbarCoordinator(configuration(["open", "save"]))
        defer { coordinator.release(); window.close() }
        coordinator.bind(window)
        let toolbar = try XCTUnwrap(window.toolbar)
        let group = try XCTUnwrap(toolbar.items.compactMap { $0 as? NSToolbarItemGroup }.first)
        let host = try XCTUnwrap(coordinator.hosts["primary"])
        coordinator.configuration = configuration(["save", "find"])
        coordinator.bind(window)
        XCTAssertTrue(toolbar.items.contains { $0 === group })
        XCTAssertTrue(coordinator.hosts["primary"] === host)
        XCTAssertEqual(group.subitems.map(\.itemIdentifier.rawValue), ["save", "find"])
        coordinator.configuration = configuration([])
        coordinator.bind(window)
        XCTAssertTrue(coordinator.hosts.isEmpty)
        XCTAssertEqual(toolbar.items.map(\.itemIdentifier), [.flexibleSpace])
        coordinator.configuration = configuration(["open"])
        coordinator.bind(window)
        XCTAssertEqual(toolbar.items.compactMap { $0 as? NSToolbarItemGroup }.first?.subitems.map(\.itemIdentifier.rawValue), ["open"])
    }

    func testNativeToolbarVisibilityBelongsToItsPhysicalWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let owner = MacDocumentTabPolicy.makeWindowModel()
        func configuration(visible: Bool) -> MacDocumentToolbar {
            MacDocumentToolbar(owner: owner, groups: [.init(id: "primary", items: ["test"])],
                isVisible: visible, label: { _ in "Test" },
                control: { _ in AnyView(Text("Test")) }, overflow: { _ in AnyView(Text("Test")) })
        }
        let coordinator = MacDocumentToolbar.ToolbarCoordinator(configuration(visible: false))
        defer { coordinator.release(); window.close() }
        coordinator.bind(window)
        XCTAssertFalse(window.toolbar?.isVisible ?? true)
        coordinator.configuration = configuration(visible: true)
        coordinator.bind(window)
        XCTAssertTrue(window.toolbar?.isVisible == true)
        coordinator.configuration = configuration(visible: false)
        coordinator.bind(window)
        XCTAssertFalse(window.toolbar?.isVisible ?? true)
    }

    private func applyTranslucency(_ enabled: Bool) {
        ContentView.MacEditorSurfacePolicy.configureRegisteredWindowTranslucency(enabled,
            opaqueEditorCanvas: UserDefaults.standard.object(forKey: "SettingsOpaqueEditorSurfaceMac") as? Bool ?? true,
            modeRaw: UserDefaults.standard.string(forKey: "SettingsMacTranslucencyMode") ?? "balanced",
            isDarkMode: false)
    }
    func testNativeTitlebarMaterialExistsBeforeSelectionAndSurvivesTranslucencyUpdates() {
        let candidate = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        candidate.isReleasedWhenClosed = false
        let owner = MacDocumentTabPolicy.makeWindowModel()
        candidate.titlebarAppearsTransparent = true
        candidate.backgroundColor = .clear
        MacDocumentTabPolicy.configureWindowChrome(candidate)
        XCTAssertFalse(candidate.titlebarAppearsTransparent, "Chrome must not wait for an editor frame or tab selection")
        XCTAssertEqual(candidate.backgroundColor, .windowBackgroundColor)
        WindowViewModelRegistry.shared.register(owner, for: candidate.windowNumber)
        defer { WindowViewModelRegistry.shared.unregister(windowNumber: candidate.windowNumber); candidate.close() }
        applyTranslucency(true)
        XCTAssertFalse(candidate.titlebarAppearsTransparent)
        XCTAssertEqual(candidate.backgroundColor, .windowBackgroundColor,
            "Native toolbar in-window blending must never sample a clear window backing")
        applyTranslucency(false)
        XCTAssertFalse(candidate.titlebarAppearsTransparent)
    }

    func testNativePrimaryAndChildChromeKeepTheSameBackingAcrossAppearanceChanges() {
        let primary = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        let child = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        let owners = [MacDocumentTabPolicy.makeWindowModel(), MacDocumentTabPolicy.makeWindowModel()]
        let windows = [primary, child]
        for (window, owner) in zip(windows, owners) {
            window.isReleasedWhenClosed = false
            WindowViewModelRegistry.shared.register(owner, for: window.windowNumber)
            MacDocumentTabPolicy.configureWindowChrome(window)
        }
        defer {
            for window in windows {
                WindowViewModelRegistry.shared.unregister(windowNumber: window.windowNumber)
                window.close()
            }
        }
        for dark in [false, true] {
            for enabled in [true, false, true] {
                for mode in ["frosted", "balanced", "vibrant"] {
                    ContentView.MacEditorSurfacePolicy.configureRegisteredWindowTranslucency(enabled,
                        opaqueEditorCanvas: true, modeRaw: mode, isDarkMode: dark)
                    // Registration/activation and preference updates must commute.
                    MacDocumentTabPolicy.configureWindowChrome(child)
                    XCTAssertEqual(primary.backgroundColor, child.backgroundColor)
                    XCTAssertEqual(primary.backgroundColor, .windowBackgroundColor)
                    XCTAssertEqual(primary.isOpaque, child.isOpaque)
                    XCTAssertFalse(primary.titlebarAppearsTransparent)
                    XCTAssertFalse(child.titlebarAppearsTransparent)
                }
            }
        }
    }

    func testSettingsPaneRetainsReleasedIntrinsicSizingWhenInactive() {
        let hosting = NSHostingView(rootView: NeonSettingsView.SettingsTabPage(
            title: "AI", systemImage: "brain", tag: "ai", selectedTag: "python",
            content: { AnyView(Text("Released pane content").frame(height: 900)) }
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(hosting.fittingSize.height, 900,
            "Keep the released native Settings sizing contract; inactive panes must remain real content")
    }

    func testFrostedGlassSliderMapsToExistingTranslucencyModes() {
        XCTAssertEqual(NeonSettingsView.MacTranslucencyModeOption.frosted.sliderValue, 0)
        XCTAssertEqual(NeonSettingsView.MacTranslucencyModeOption.subtle.sliderValue, 1)
        XCTAssertEqual(NeonSettingsView.MacTranslucencyModeOption.balanced.sliderValue, 2)
        XCTAssertEqual(NeonSettingsView.MacTranslucencyModeOption.light.sliderValue, 3)
        XCTAssertEqual(NeonSettingsView.MacTranslucencyModeOption.vibrant.sliderValue, 4)

        XCTAssertEqual(NeonSettingsView.MacTranslucencyModeOption.resolving(sliderValue: -1), .frosted)
        XCTAssertEqual(NeonSettingsView.MacTranslucencyModeOption.resolving(sliderValue: 2), .balanced)
        XCTAssertEqual(NeonSettingsView.MacTranslucencyModeOption.resolving(sliderValue: 8), .vibrant)

        XCTAssertEqual(ContentView.MacEditorSurfacePolicy.translucentSurfaceKind(modeRaw: "frosted"), .stronglyFrosted)
        XCTAssertEqual(ContentView.MacEditorSurfacePolicy.translucentSurfaceKind(modeRaw: "subtle"), .frosted)
        XCTAssertEqual(ContentView.MacEditorSurfacePolicy.translucentSurfaceKind(modeRaw: "balanced"), .balanced)
        XCTAssertEqual(ContentView.MacEditorSurfacePolicy.translucentSurfaceKind(modeRaw: "light"), .light)
        XCTAssertEqual(ContentView.MacEditorSurfacePolicy.translucentSurfaceKind(modeRaw: "vibrant"), .transparent)
    }

    func testTransparentCanvasWithoutTranslucentToggleUsesStrongFrostedSurface() {
        XCTAssertTrue(
            ContentView.MacEditorSurfacePolicy.nativeTranslucencyEnabled(
                translucent: false,
                opaqueEditorCanvas: false
            )
        )
        XCTAssertEqual(
            ContentView.MacEditorSurfacePolicy.effectiveTranslucencyModeRaw(
                translucent: false,
                opaqueEditorCanvas: false,
                selectedModeRaw: "vibrant"
            ),
            "frosted"
        )
        XCTAssertEqual(
            ContentView.MacEditorSurfacePolicy.effectiveTranslucencyModeRaw(
                translucent: true,
                opaqueEditorCanvas: false,
                selectedModeRaw: "light"
            ),
            "light"
        )
    }

    func testEditorWindowAllowsDraggingFromCustomHeaderBackground() {
        let testWindow = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        testWindow.isReleasedWhenClosed = false
        defer {
            testWindow.orderOut(nil)
            testWindow.close()
        }

        testWindow.isMovableByWindowBackground = false
        ContentView.MacEditorSurfacePolicy.configureWindowDragBehavior(testWindow)

        XCTAssertTrue(testWindow.isMovableByWindowBackground)
    }

    func testToolbarDragRegionAllowsWindowMovement() {
        let dragRegion = MacWindowDragRegionView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))

        XCTAssertTrue(dragRegion.mouseDownCanMoveWindow)
        XCTAssertTrue(dragRegion.acceptsFirstMouse(for: nil))
    }

    func testVirtualEditorCanvasRejectsWindowBackgroundDragging() {
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

        XCTAssertFalse(canvas.mouseDownCanMoveWindow)
    }

    func testNewWindowEditorBecomesInitialFirstResponder() {
        let testWindow = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        testWindow.isReleasedWhenClosed = false
        defer {
            testWindow.orderOut(nil)
            testWindow.close()
        }

        let editor = VirtualEditorScrollView(frame: testWindow.contentView?.bounds ?? .zero)
        editor.focusesEditorOnInitialWindowAttachment = true
        testWindow.contentView = editor

        XCTAssertTrue(testWindow.firstResponder === editor.documentView)
    }

    // Verifies that the translucency toggle updates registered editor windows without touching unrelated panels.
    func testApplyWindowTranslucencyUpdatesMacWindowFlags() {
        let defaults = UserDefaults.standard
        let originalMode = defaults.object(forKey: "SettingsMacTranslucencyMode")
        let originalOpaqueEditorCanvas = defaults.object(forKey: "SettingsOpaqueEditorSurfaceMac")
        defaults.set("balanced", forKey: "SettingsMacTranslucencyMode")
        defaults.set(true, forKey: "SettingsOpaqueEditorSurfaceMac")
        defer {
            if let originalMode {
                defaults.set(originalMode, forKey: "SettingsMacTranslucencyMode")
            } else {
                defaults.removeObject(forKey: "SettingsMacTranslucencyMode")
            }
            if let originalOpaqueEditorCanvas {
                defaults.set(originalOpaqueEditorCanvas, forKey: "SettingsOpaqueEditorSurfaceMac")
            } else {
                defaults.removeObject(forKey: "SettingsOpaqueEditorSurfaceMac")
            }
        }

        let testWindow = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        testWindow.isReleasedWhenClosed = false
        testWindow.orderFront(nil)
        let viewModel = EditorViewModel()
        WindowViewModelRegistry.shared.register(viewModel, for: testWindow.windowNumber)

        defer {
            WindowViewModelRegistry.shared.unregister(windowNumber: testWindow.windowNumber)
            testWindow.orderOut(nil)
            testWindow.close()
        }

        // Every macOS editor window is a native document tab: translucency
        // changes opacity only, while AppKit keeps the native titlebar chrome.
        applyTranslucency(true)
        XCTAssertFalse(testWindow.isOpaque)
        XCTAssertFalse(testWindow.titlebarAppearsTransparent)
        XCTAssertEqual(testWindow.backgroundColor, .windowBackgroundColor)

        applyTranslucency(false)
        XCTAssertTrue(testWindow.isOpaque)
        XCTAssertFalse(testWindow.titlebarAppearsTransparent)
        XCTAssertEqual(testWindow.backgroundColor, .windowBackgroundColor)
    }

    func testMacSettingsNativeContentSizingKeepsStandardWidth() {
        XCTAssertEqual(NeonSettingsView.macSettingsContentWidth, 900)
    }

    func testMacSettingsWindowTranslucencyLeavesNativeBackdropVisible() {
        let subtle = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: true,
            translucencyModeRaw: "subtle",
            appearanceRaw: "dark",
            effectiveColorScheme: .dark
        )
        let balanced = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: true,
            translucencyModeRaw: "balanced",
            appearanceRaw: "dark",
            effectiveColorScheme: .dark
        )
        let vibrant = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: true,
            translucencyModeRaw: "vibrant",
            appearanceRaw: "dark",
            effectiveColorScheme: .dark
        )
        let disabled = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: false,
            translucencyModeRaw: "vibrant",
            appearanceRaw: "dark",
            effectiveColorScheme: .dark
        )

        XCTAssertEqual(subtle.alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(balanced.alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(vibrant.alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(disabled, NSColor.windowBackgroundColor)
    }

    func testMacSettingsTitlebarUsesNativeMaterialWhileContentRemainsTranslucent() {
        let contentBackground = SettingsWindowConfigurator.settingsWindowBackgroundColor(
            translucentEnabled: true,
            translucencyModeRaw: "balanced",
            appearanceRaw: "system",
            effectiveColorScheme: .light
        )
        let titlebarBackground = SettingsWindowConfigurator.settingsTitlebarBackgroundColor(
            contentBackgroundColor: contentBackground,
            translucentEnabled: true
        )

        XCTAssertEqual(contentBackground.alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(titlebarBackground, contentBackground)
        XCTAssertEqual(titlebarBackground.alphaComponent, 0, accuracy: 0.001)
    }

    func testNativeBackdropMovesFromFrostedToTransparentInBothAppearances() {
        let view = NSVisualEffectView(frame: .zero)

        for isDarkMode in [false, true] {
            MacWindowBackdropView.configure(
                view,
                enabled: true,
                modeRaw: "frosted",
                isDarkMode: isDarkMode
            )
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(view.blendingMode, .behindWindow)
            XCTAssertEqual(view.material, .underWindowBackground)
            XCTAssertEqual(view.alphaValue, 1)
            XCTAssertEqual(view.appearance?.name, isDarkMode ? .darkAqua : .aqua)
            XCTAssertEqual(view.layer?.backgroundColor?.alpha ?? -1, 0.55, accuracy: 0.001)

            MacWindowBackdropView.configure(
                view,
                enabled: true,
                modeRaw: "subtle",
                isDarkMode: isDarkMode
            )
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(view.material, .underWindowBackground)
            XCTAssertEqual(view.alphaValue, 0.98, accuracy: 0.001)
            XCTAssertEqual(view.layer?.backgroundColor?.alpha ?? -1, 0.48, accuracy: 0.001)

            MacWindowBackdropView.configure(
                view,
                enabled: true,
                modeRaw: "balanced",
                isDarkMode: isDarkMode
            )
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(view.material, .underWindowBackground)
            XCTAssertEqual(view.alphaValue, 0.96, accuracy: 0.001)
            XCTAssertEqual(view.layer?.backgroundColor?.alpha ?? -1, 0.42, accuracy: 0.001)

            MacWindowBackdropView.configure(
                view,
                enabled: true,
                modeRaw: "light",
                isDarkMode: isDarkMode
            )
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(view.material, .underWindowBackground)
            XCTAssertEqual(view.alphaValue, 0.94, accuracy: 0.001)
            XCTAssertEqual(view.layer?.backgroundColor?.alpha ?? -1, 0.36, accuracy: 0.001)

            MacWindowBackdropView.configure(
                view,
                enabled: true,
                modeRaw: "vibrant",
                isDarkMode: isDarkMode
            )
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(view.material, .underWindowBackground)
            XCTAssertEqual(view.alphaValue, 0.92, accuracy: 0.001)
            XCTAssertEqual(view.layer?.backgroundColor?.alpha ?? -1, 0.30, accuracy: 0.001)
        }
    }

    func testSettingsSurfaceIgnoresThemeBackgroundWhenItCannotAffectTheWindow() {
        XCTAssertEqual(
            SettingsWindowConfigurator.relevantThemeBackgroundRaw(
                themeBackgroundRaw: "#112233",
                opaqueEditorCanvasEnabled: true,
                translucentEnabled: true
            ),
            ""
        )
        XCTAssertEqual(
            SettingsWindowConfigurator.relevantThemeBackgroundRaw(
                themeBackgroundRaw: "#112233",
                opaqueEditorCanvasEnabled: false,
                translucentEnabled: false
            ),
            ""
        )
        XCTAssertEqual(
            SettingsWindowConfigurator.relevantThemeBackgroundRaw(
                themeBackgroundRaw: "#112233",
                opaqueEditorCanvasEnabled: true,
                translucentEnabled: false
            ),
            "#112233"
        )
    }

    func testVirtualEditorScrollSurfaceDoesNotPaintOpaqueDefaultBackground() {
        let scrollView = VirtualEditorScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertEqual(scrollView.backgroundColor, .clear)
        XCTAssertFalse(scrollView.contentView.drawsBackground)
    }

    func testVirtualEditorHexColorPreviewParsesSupportedFormsAndRejectsPartialTokens() {
        let literals = VirtualEditorHexColorPreview.literals(
            in: "color: #abc; background: #12345678; invalid: #12345;",
            absoluteStart: 10
        )

        XCTAssertEqual(literals.map(\.token), ["#abc", "#12345678"])
        XCTAssertEqual(literals.map(\.range.location), [17, 35])
        XCTAssertEqual(literals.map(\.range.length), [4, 9])
        XCTAssertTrue(VirtualEditorHexColorPreview.isSupported(language: "HTML"))
        XCTAssertFalse(VirtualEditorHexColorPreview.isSupported(language: "swift"))
    }

    func testVirtualEditorHexColorPreviewPreservesShortFormOnlyWhenRepresentable() {
        let white = NSColor.white
        let black = NSColor.black

        XCTAssertEqual(VirtualEditorHexColorPreview.replacement(for: white, preserving: "#fff"), "#FFF")
        XCTAssertEqual(VirtualEditorHexColorPreview.replacement(for: black, preserving: "#ffff"), "#000F")
        XCTAssertEqual(VirtualEditorHexColorPreview.replacement(for: white, preserving: "#abcd"), "#FFFF")
    }

    func testVirtualEditorCoreTextDrawingOwnsCoordinateState() {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.translateBy(x: 0, y: 4)
        context.scaleBy(x: 1, y: -1)
        let inheritedPosition = CGPoint(x: 1, y: 1)
        context.textMatrix = CGAffineTransform(scaleX: -1, y: 1)
        context.textPosition = inheritedPosition
        let inheritedMatrix = context.textMatrix
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "A"))

        VirtualEditorCoreTextDrawing.draw(
            line,
            in: context,
            at: CGPoint(x: 2, y: 3),
            flippedCoordinates: true
        )

        XCTAssertEqual(context.textMatrix, inheritedMatrix)
        XCTAssertEqual(context.textPosition, inheritedPosition)

        let flippedMatrix = VirtualEditorCoreTextDrawing.textMatrix(forFlippedCoordinates: true)
        XCTAssertEqual(flippedMatrix.a, 1, accuracy: 0.001)
        XCTAssertEqual(flippedMatrix.d, -1, accuracy: 0.001)
        XCTAssertGreaterThan(context.ctm.d * flippedMatrix.d, 0)

        let unflippedMatrix = VirtualEditorCoreTextDrawing.textMatrix(forFlippedCoordinates: false)
        XCTAssertEqual(unflippedMatrix, .identity)
    }

    func testVirtualEditorCanvasUsesEditorThemeWhenTranslucencyIsDisabled() {
        let canvas = VirtualEditorCanvas(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()

        let actual = try! XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let expected = try! XCTUnwrap(NSColor(currentEditorTheme(colorScheme: .light).background).usingColorSpace(.deviceRGB))
        let bitmapComponentTolerance = 1.0 / 255.0
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: bitmapComponentTolerance)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: bitmapComponentTolerance)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: bitmapComponentTolerance)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: bitmapComponentTolerance)
    }

    func testTranslucentEditorPanesLeaveTheWindowSurfaceUncovered() {
        let translucent = ContentView.MacEditorSurfacePolicy.paneBackground(translucent: true, solid: .red)
        let opaque = ContentView.MacEditorSurfacePolicy.paneBackground(translucent: false, solid: .red)

        XCTAssertEqual(NSColor(translucent).alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(NSColor(opaque), NSColor(.red))
    }

    func testInterPaneBackgroundFollowsTranslucencyAndOpaqueEditorCanvas() {
        let translucent = ContentView.MacEditorSurfacePolicy.interPaneBackground(
            translucent: true,
            opaqueEditorCanvas: true,
            editor: .red,
            solid: .blue
        )
        let opaqueEditor = ContentView.MacEditorSurfacePolicy.interPaneBackground(
            translucent: false,
            opaqueEditorCanvas: true,
            editor: .red,
            solid: .blue
        )
        let opaqueWindow = ContentView.MacEditorSurfacePolicy.interPaneBackground(
            translucent: false,
            opaqueEditorCanvas: false,
            editor: .red,
            solid: .blue
        )

        XCTAssertEqual(NSColor(translucent).alphaComponent, 0, accuracy: 0.001)
        XCTAssertEqual(NSColor(opaqueEditor), NSColor(.red))
        XCTAssertEqual(NSColor(opaqueWindow), NSColor(.blue))
    }

    func testEditorSurfaceVisualMatrixMatchesAppearanceAndOpacityModes() throws {
        let lightWindow = ContentView.MacEditorSurfacePolicy.windowBackground(
            translucent: false,
            modeRaw: "balanced",
            isDarkMode: false
        )
        let darkWindow = ContentView.MacEditorSurfacePolicy.windowBackground(
            translucent: false,
            modeRaw: "balanced",
            isDarkMode: true
        )
        let lightEditor = NSColor(currentEditorTheme(colorScheme: .light).background)
        let darkEditor = NSColor(currentEditorTheme(colorScheme: .dark).background)

        let cases: [(String, Color, NSColor)] = [
            (
                "light opaque window",
                ContentView.MacEditorSurfacePolicy.interPaneBackground(
                    translucent: false,
                    opaqueEditorCanvas: false,
                    editor: Color(lightEditor),
                    solid: Color(lightWindow)
                ),
                lightWindow
            ),
            (
                "dark opaque window",
                ContentView.MacEditorSurfacePolicy.interPaneBackground(
                    translucent: false,
                    opaqueEditorCanvas: false,
                    editor: Color(darkEditor),
                    solid: Color(darkWindow)
                ),
                darkWindow
            ),
            (
                "light opaque editor",
                ContentView.MacEditorSurfacePolicy.interPaneBackground(
                    translucent: false,
                    opaqueEditorCanvas: true,
                    editor: Color(lightEditor),
                    solid: Color(lightWindow)
                ),
                lightEditor
            ),
            (
                "dark opaque editor",
                ContentView.MacEditorSurfacePolicy.interPaneBackground(
                    translucent: false,
                    opaqueEditorCanvas: true,
                    editor: Color(darkEditor),
                    solid: Color(darkWindow)
                ),
                darkEditor
            )
        ]

        for (name, color, expected) in cases {
            let actual = try XCTUnwrap(renderedPixel(color: NSColor(color)))
            assertColor(actual, matches: expected, message: name)
        }

        for isDarkMode in [false, true] {
            let translucent = ContentView.MacEditorSurfacePolicy.interPaneBackground(
                translucent: true,
                opaqueEditorCanvas: true,
                editor: isDarkMode ? Color(darkEditor) : Color(lightEditor),
                solid: Color(
                    ContentView.MacEditorSurfacePolicy.windowBackground(
                        translucent: false,
                        modeRaw: "balanced",
                        isDarkMode: isDarkMode
                    )
                )
            )
            let actual = try XCTUnwrap(renderedPixel(color: NSColor(translucent)))
            XCTAssertEqual(actual.alphaComponent, 0, accuracy: 1.0 / 255.0)
        }
    }

    private func renderedPixel(color: NSColor) -> NSColor? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
    }

    private func assertColor(_ actual: NSColor, matches expected: NSColor, message: String) {
        let expectedRGB = expected.usingColorSpace(.deviceRGB) ?? expected
        let tolerance = 1.0 / 255.0
        XCTAssertEqual(actual.redComponent, expectedRGB.redComponent, accuracy: tolerance, message)
        XCTAssertEqual(actual.greenComponent, expectedRGB.greenComponent, accuracy: tolerance, message)
        XCTAssertEqual(actual.blueComponent, expectedRGB.blueComponent, accuracy: tolerance, message)
        XCTAssertEqual(actual.alphaComponent, expectedRGB.alphaComponent, accuracy: tolerance, message)
    }
}
#endif
