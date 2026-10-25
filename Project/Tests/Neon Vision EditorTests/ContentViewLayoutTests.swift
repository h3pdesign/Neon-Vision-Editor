import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
@testable import Neon_Vision_Editor

final class ContentViewLayoutTests: XCTestCase {
#if os(macOS) || os(iOS)
    @MainActor
    func testSettingsFontDropdownKeepsLongNamesInsideItsAllocatedWidth() async {
        for name in ["System", "ITFDevanagariMarathi-Medium", "AmericanTypewriter-CondensedLight", "日本語フォント-Regular",
                     String(repeating: "LongFontFamily", count: 6)] {
            for width: CGFloat in [150, 280] {
                let frames = await settingsFontDropdownFrames(name: name, width: width, maxWidth: width)
                XCTAssertGreaterThan(frames.picker.width, 0)
                XCTAssertGreaterThanOrEqual(frames.picker.minX, frames.slot.minX,
                    "The selected name must not push Settings off the leading edge: \(name)")
                XCTAssertLessThanOrEqual(frames.picker.maxX, frames.slot.maxX + 0.5,
                    "The selected name must stay inside its dropdown, not overlap adjacent controls: \(name)")
            }
        }
    }

    @MainActor
    func testSettingsFontDropdownHonorsFlexibleRowsAndAccessibilityTextSize() async {
        for width: CGFloat in [150, 280, 500] {
            let frames = await settingsFontDropdownFrames(name: "AmericanTypewriter-CondensedLight",
                width: width, maxWidth: .infinity, dynamicTypeSize: .accessibility3)
            XCTAssertLessThanOrEqual(frames.picker.maxX, frames.slot.maxX + 0.5)
            XCTAssertLessThanOrEqual(frames.slot.maxX, frames.container.maxX + 0.5,
                "A flexible Settings control must not widen the page at accessibility text sizes")
            XCTAssertGreaterThanOrEqual(frames.choose.minX, frames.slot.maxX,
                "The adjacent action must remain outside the selected font control")
        }
    }

    @MainActor
    func testUnconstrainedToolbarDropdownRetainsIntrinsicWidth() async {
        let frames = await settingsFontDropdownFrames(name: String(repeating: "LongFontFamily", count: 6),
            width: 150, maxWidth: nil)
        XCTAssertGreaterThan(frames.picker.width, 150,
            "Menus explicitly requesting intrinsic width must retain their existing behavior")
    }

    @MainActor
    private func settingsFontDropdownFrames(name: String, width: CGFloat, maxWidth: CGFloat?,
                                           dynamicTypeSize: DynamicTypeSize = .large) async -> (picker: CGRect, slot: CGRect, choose: CGRect, container: CGRect) {
        let measured = expectation(description: "Font dropdown measured")
        var pickerFrame = CGRect.zero
        var slotFrame = CGRect.zero
        var chooseFrame = CGRect.zero
        var containerFrame = CGRect.zero
        var fulfilled = false
        func finishIfReady() {
            if !fulfilled, pickerFrame.width > 0, slotFrame.width > 0, containerFrame.width > 0,
               chooseFrame.width > 0 || maxWidth == nil {
                fulfilled = true
                measured.fulfill()
            }
        }
        let view = HStack(spacing: 12) {
            Picker("Font", selection: .constant(name)) {
                Text(name).tag(name)
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
                pickerFrame = $0
                finishIfReady()
            }
            .neonSettingsDropdown(maxWidth: maxWidth)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
                slotFrame = $0
                finishIfReady()
            }
            Button("Choose…") {}
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
                    chooseFrame = $0
                    finishIfReady()
                }
        }
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .frame(width: width + 110, height: 80, alignment: .leading)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
            containerFrame = $0
            finishIfReady()
        }
#if os(macOS)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width + 110, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        hosting.layoutSubtreeIfNeeded()
#else
        let controller = UIHostingController(rootView: view)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: width + 110, height: 80))
        }
        window.frame = CGRect(x: 0, y: 0, width: width + 110, height: 80)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
#endif
        await fulfillment(of: [measured], timeout: 3)
        return (pickerFrame, slotFrame, chooseFrame, containerFrame)
    }
#endif
#if os(iOS)
    @MainActor
    func testBottomChromeMeasuresToolbarHeightInsteadOfTouchingStatus() async {
        for toolbarHeight: CGFloat in [52, 68] {
            let frames = await bottomChromeFrames(toolbarHeight: toolbarHeight)
            XCTAssertEqual(frames.toolbar.minY - frames.status.maxY, 12, accuracy: 0.5)
            XCTAssertEqual(frames.container.maxY - frames.toolbar.maxY, 8, accuracy: 0.5)
        }
    }

    func testPhoneStatusClearsTheKeyboardShortcutBarOnlyWhileItIsShown() {
        // iPhone draws the shortcut bar inside the editor above the keyboard.
        XCTAssertEqual(IOSFloatingStatusPolicy.bottomInset(
            isPhone: true, keyboardVisible: true, accessoryBarShown: true, accessoryBarHeight: 46), 46)
        XCTAssertEqual(IOSFloatingStatusPolicy.bottomInset(
            isPhone: true, keyboardVisible: true, accessoryBarShown: false, accessoryBarHeight: 46), 0)
        XCTAssertEqual(IOSFloatingStatusPolicy.bottomInset(
            isPhone: true, keyboardVisible: false, accessoryBarShown: true, accessoryBarHeight: 46), 0)
        // iPad uses the keyboard's input accessory, already inside the keyboard safe area.
        XCTAssertEqual(IOSFloatingStatusPolicy.bottomInset(
            isPhone: false, keyboardVisible: true, accessoryBarShown: true, accessoryBarHeight: 46), 0)
    }

    @MainActor
    func testKeyboardChromeDoesNotAddAccessoryHeightTwice() async {
        let frames = await bottomChromeFrames(toolbarHeight: nil)
        XCTAssertEqual(frames.container.maxY - frames.status.maxY, 8, accuracy: 0.5)
    }

    @MainActor
    func testBottomToolbarUsesMeasuredContainerWidthOnFirstLayout() async {
        for width: CGFloat in [320, 402, 500] {
            let frames = await bottomChromeFrames(toolbarHeight: 52, containerWidth: width)
            XCTAssertEqual(frames.container.width, width, accuracy: 0.5)
            XCTAssertEqual(frames.toolbar.width, ContentView.IPhoneBottomToolbarWidthPolicy.width(availableWidth: width), accuracy: 0.5)
        }
    }

    @MainActor
    private func bottomChromeFrames(toolbarHeight: CGFloat?, containerWidth: CGFloat = 500) async -> (container: CGRect, status: CGRect, toolbar: CGRect) {
        let measured = expectation(description: "Bottom chrome measured")
        var statusFrame = CGRect.zero
        var toolbarFrame = CGRect.zero
        var containerFrame = CGRect.zero
        var fulfilled = false
        func finishIfReady() {
            if !fulfilled, containerFrame.height > 0, statusFrame.height > 0, toolbarHeight == nil || toolbarFrame.height > 0 {
                fulfilled = true
                measured.fulfill()
            }
        }
        let status = Color.red.frame(width: 120, height: 30)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
                statusFrame = $0
                finishIfReady()
            }
        let toolbar: (CGFloat) -> AnyView? = { width in
            toolbarHeight.map { height in
                AnyView(Color.blue.frame(width: ContentView.IPhoneBottomToolbarWidthPolicy.width(availableWidth: width), height: height)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
                        toolbarFrame = $0
                        finishIfReady()
                    })
            }
        }
        let view = Color.clear.frame(width: containerWidth, height: 500)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
                containerFrame = $0
                finishIfReady()
            }
            .modifier(MobileFloatingStatusOverlayModifier(showsStatus: true, centered: true, bottomInset: 0, status: AnyView(status), bottomToolbar: toolbar))
        let controller = UIHostingController(rootView: view)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: containerWidth, height: 500))
        }
        window.frame = CGRect(x: 0, y: 0, width: containerWidth, height: 500)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = CGRect(x: 0, y: 0, width: containerWidth, height: 500)
        controller.view.layoutIfNeeded()
        await fulfillment(of: [measured], timeout: 3)
        withExtendedLifetime(controller) {}
        return (containerFrame, statusFrame, toolbarFrame)
    }
#endif
    @MainActor
    func testSecondaryContentRequestInvalidatesForSeparatorChangeWithoutAnEdit() {
        let id = UUID()
        let csv = ContentView.SecondaryContentRequest(
            context: .init(tabID: id, fileURL: nil, language: "csv"),
            revision: 1, delimitedMode: .table, delimitedTableEnabled: true, plistMode: .text,
            crashMode: .text, logMode: .text
        )
        let tsv = ContentView.SecondaryContentRequest(
            context: .init(tabID: id, fileURL: nil, language: "tsv"),
            revision: 1, delimitedMode: .table, delimitedTableEnabled: true, plistMode: .text,
            crashMode: .text, logMode: .text
        )
        XCTAssertNotEqual(csv, tsv, "Changing the delimiter must replace the parse task even without editing text.")
    }

    @MainActor
    func testSecondaryContentRequestDistinguishesTabsWithIdenticalRevisions() {
        func request(_ id: UUID, revision: Int = 0) -> ContentView.SecondaryContentRequest {
            .init(context: .init(tabID: id, fileURL: nil, language: "csv"),
                  revision: revision, delimitedMode: .table, delimitedTableEnabled: true, plistMode: .text,
                  crashMode: .text, logMode: .text)
        }
        let id = UUID()
        XCTAssertEqual(request(id), request(id), "An unchanged request must not restart parsing.")
        XCTAssertNotEqual(request(id), request(UUID()), "New tabs commonly have the same content revision.")
        XCTAssertNotEqual(request(id), request(id, revision: 1), "Edits must replace the parse task.")
    }

    @MainActor
    func testDisablingTableViewInvalidatesSecondaryContentRequest() {
        let context = ContentView.SecondaryContentContext(tabID: UUID(), fileURL: nil, language: "csv")
        let enabled = ContentView.SecondaryContentRequest(context: context, revision: 1,
            delimitedMode: .table, delimitedTableEnabled: true, plistMode: .text,
            crashMode: .text, logMode: .text)
        let disabled = ContentView.SecondaryContentRequest(context: context, revision: 1,
            delimitedMode: .table, delimitedTableEnabled: false, plistMode: .text,
            crashMode: .text, logMode: .text)
        XCTAssertNotEqual(enabled, disabled, "Changing the preference must cancel obsolete table parsing.")
    }

    func testRegularWidthSplitUsesAppOwnedChrome() {
        XCTAssertTrue(
            IOSSplitChromePolicy.usesAppOwnedChrome(
                usesUnifiedTopHost: true,
                usesSplitView: true
            )
        )
    }

    func testSingleColumnLayoutKeepsUnifiedChromeWithEditor() {
        XCTAssertFalse(
            IOSSplitChromePolicy.usesAppOwnedChrome(
                usesUnifiedTopHost: true,
                usesSplitView: false
            )
        )
    }

    func testSplitLayoutWithoutUnifiedHostKeepsPlatformChrome() {
        XCTAssertFalse(
            IOSSplitChromePolicy.usesAppOwnedChrome(
                usesUnifiedTopHost: false,
                usesSplitView: true
            )
        )
    }

    func testAdaptiveLayoutUsesSizeClassInsteadOfPhoneIdiomAssumptions() {
        XCTAssertTrue(
            IOSAdaptiveLayoutPolicy.usesRegularLayout(
                horizontalSizeClass: .regular,
                containerWidth: 390
            )
        )
        XCTAssertFalse(
            IOSAdaptiveLayoutPolicy.usesRegularLayout(
                horizontalSizeClass: .compact,
                containerWidth: 1_024
            )
        )
    }

    func testPhoneToolbarAdaptsAcrossOuterInnerAndSplitViewTraits() {
        for sizeClass in [UserInterfaceSizeClass.compact, .regular, .compact] {
            let regular = IOSAdaptiveLayoutPolicy.usesRegularLayout(
                horizontalSizeClass: sizeClass, containerWidth: 900
            )
            XCTAssertEqual(IOSAdaptiveLayoutPolicy.usesCompactPhoneToolbar(
                isPhone: true, regularLayout: regular
            ), sizeClass == .compact)
            XCTAssertFalse(IOSAdaptiveLayoutPolicy.usesCompactPhoneToolbar(
                isPhone: false, regularLayout: regular
            ), "Existing iPad toolbar presentation must not change")
        }
    }

    func testAdaptiveLayoutFallsBackToMeasuredWidthBeforeSizeClassArrives() {
        XCTAssertFalse(
            IOSAdaptiveLayoutPolicy.usesRegularLayout(
                horizontalSizeClass: nil,
                containerWidth: 390
            )
        )
        XCTAssertTrue(
            IOSAdaptiveLayoutPolicy.usesRegularLayout(
                horizontalSizeClass: nil,
                containerWidth: 744
            )
        )
    }

    // Geometry measured on the iOS 27.1 iPhone Duo simulator's outer display.
    private let duoOuterSize = CGSize(width: 382, height: 644)
    private let duoOuterInsets = EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84)
    private let duoOuterOcclusions = [
        CGRect(x: 399.67, y: 29.33, width: 37, height: 37),
        CGRect(x: 382, y: 0, width: 84, height: 174)
    ]

    func testVerticalToolbarFillsTrailingColumnBelowStatusBar() throws {
        let column = try XCTUnwrap(IOSVerticalToolbarPolicy.columnFrame(
            edge: .trailing,
            containerSize: duoOuterSize,
            safeAreaInsets: duoOuterInsets,
            occlusions: duoOuterOcclusions
        ))
        XCTAssertEqual(column, CGRect(x: 382, y: 182, width: 84, height: 462))
        XCTAssertGreaterThanOrEqual(column.minX, duoOuterSize.width, "Toolbar must not cover editor content")
    }

    func testVerticalToolbarStaysHorizontalWithoutSystemVerticalEdge() {
        XCTAssertNil(IOSVerticalToolbarPolicy.columnFrame(
            edge: nil,
            containerSize: duoOuterSize,
            safeAreaInsets: duoOuterInsets,
            occlusions: duoOuterOcclusions
        ))
    }

    func testVerticalToolbarMirrorsToLeadingEdge() throws {
        let column = try XCTUnwrap(IOSVerticalToolbarPolicy.columnFrame(
            edge: .leading,
            containerSize: duoOuterSize,
            safeAreaInsets: EdgeInsets(top: 0, leading: 84, bottom: 34, trailing: 0),
            occlusions: [CGRect(x: -84, y: 0, width: 84, height: 174)]
        ))
        XCTAssertEqual(column, CGRect(x: -84, y: 182, width: 84, height: 462))
    }

    func testVerticalToolbarUsesMinimumWidthInsideNarrowInsetAndAvoidsBottomOcclusion() throws {
        let column = try XCTUnwrap(IOSVerticalToolbarPolicy.columnFrame(
            edge: .trailing,
            containerSize: CGSize(width: 800, height: 600),
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 20),
            occlusions: [
                CGRect(x: 790, y: 500, width: 30, height: 30),
                CGRect(x: 100, y: 0, width: 40, height: 400)
            ]
        ))
        XCTAssertEqual(column, CGRect(x: 760, y: 0, width: 60, height: 492))
    }

    func testVerticalToolbarFallsBackWhenColumnIsTooShort() {
        XCTAssertNil(IOSVerticalToolbarPolicy.columnFrame(
            edge: .trailing,
            containerSize: CGSize(width: 382, height: 300),
            safeAreaInsets: duoOuterInsets,
            occlusions: [CGRect(x: 382, y: 0, width: 84, height: 140)]
        ))
        XCTAssertNil(IOSVerticalToolbarPolicy.columnFrame(
            edge: .trailing,
            containerSize: .zero,
            safeAreaInsets: duoOuterInsets,
            occlusions: []
        ))
    }

    func testSecondaryPaneWidthScalesAndRemainsBounded() {
        XCTAssertEqual(IOSAdaptiveLayoutPolicy.secondaryPaneIdealWidth(containerWidth: 390), 280)
        XCTAssertEqual(IOSAdaptiveLayoutPolicy.secondaryPaneIdealWidth(containerWidth: 900), 360)
        XCTAssertEqual(IOSAdaptiveLayoutPolicy.secondaryPaneIdealWidth(containerWidth: 1_600), 520)
    }

    func testFindChromeSuppressesFloatingAndPinnedStatus() {
        XCTAssertFalse(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: false,
                findPresented: true,
                pinnedPresentation: false
            )
        )
        XCTAssertFalse(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: true,
                findPresented: true,
                pinnedPresentation: true
            )
        )
    }

    func testFloatingStatusUsesOnlyItsRequestedPresentation() {
        XCTAssertTrue(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: false,
                findPresented: false,
                pinnedPresentation: false
            )
        )
        XCTAssertTrue(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: true,
                findPresented: false,
                pinnedPresentation: true
            )
        )
    }

    func testPhoneStatusHidesWithMinimizedToolbarAndReturnsOnScrollUp() {
        XCTAssertFalse(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: false,
                findPresented: false,
                pinnedPresentation: false,
                phoneToolbarMinimized: true
            )
        )
        XCTAssertTrue(
            IOSFloatingStatusPolicy.isVisible(
                brainDumpLayoutEnabled: false,
                shouldPinToTop: false,
                findPresented: false,
                pinnedPresentation: false,
                phoneToolbarMinimized: false
            )
        )
    }

    func testIPadBottomToolbarWidthAdaptsToWindowSize() {
#if os(iOS)
        let width: (CGFloat, Bool) -> CGFloat = { ContentView.IPadBottomToolbarWidthPolicy.width(availableWidth: $0, minimized: $1) }
        XCTAssertEqual(width(768, false), 522.24, accuracy: 0.01)
        XCTAssertEqual(width(1_024, false), 696.32, accuracy: 0.01)
        XCTAssertEqual(width(1_366, false), 760)
        XCTAssertEqual(width(400, false), 336)
        XCTAssertEqual(width(768, true), 176)
#endif
    }

    func testIPadBottomToolbarDoesNotReserveUnusedActionSpace() {
#if os(iOS)
        XCTAssertEqual(ContentView.IPadBottomToolbarWidthPolicy.width(availableWidth: 1_024, minimized: false, contentWidth: 442), 442)
        XCTAssertEqual(ContentView.IPadBottomToolbarWidthPolicy.width(availableWidth: 400, minimized: false, contentWidth: 442), 336)
        XCTAssertEqual(ContentView.IPadBottomToolbarWidthPolicy.width(availableWidth: 0, minimized: false, contentWidth: 442), 0)
        XCTAssertEqual(ContentView.IPadBottomToolbarWidthPolicy.width(availableWidth: 1_024, minimized: true, contentWidth: 442), 176)
#endif
    }

    func testIPhoneBottomToolbarUsesStandardEdgeMargins() {
#if os(iOS)
        let standardWidth = ContentView.IPhoneBottomToolbarWidthPolicy.width(availableWidth: 390)
        XCTAssertEqual(standardWidth, 300)
        XCTAssertEqual(ContentView.IPhoneBottomToolbarWidthPolicy.width(availableWidth: 402), 300)
        XCTAssertEqual(ContentView.IPhoneBottomToolbarWidthPolicy.width(availableWidth: 320), 296)
        let fiveInitialItemsEnd = 12 + (MobileToolbarPresentationPolicy.labeledItemWidth * 5) + (6 * 4)
        XCTAssertLessThanOrEqual(fiveInitialItemsEnd, standardWidth)
        XCTAssertGreaterThan(fiveInitialItemsEnd + 6, standardWidth)
#endif
    }

    func testPhoneStatusStartsCompactAndStaysAtBottomWithKeyboard() {
        XCTAssertEqual(
            IOSFloatingStatusPolicy.itemLimit(
                isPhoneBottomToolbar: true,
                compactEditing: false,
                expanded: false,
                regularLimit: 3
            ),
            1
        )
        XCTAssertNil(
            IOSFloatingStatusPolicy.itemLimit(
                isPhoneBottomToolbar: true,
                compactEditing: false,
                expanded: true,
                regularLimit: 3
            )
        )
        XCTAssertFalse(
            IOSFloatingStatusPolicy.shouldPinToTop(
                isPhoneBottomToolbar: true,
                compactLayout: true,
                keyboardVisible: true
            )
        )
        XCTAssertTrue(
            IOSFloatingStatusPolicy.shouldPinToTop(
                isPhoneBottomToolbar: false,
                compactLayout: true,
                keyboardVisible: true
            )
        )
    }

    func testMobileFindChromeSuppressesMarkdownFormattingChrome() {
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldShow(
                isMarkdown: true,
                isReadOnlyPreview: false,
                brainDumpLayoutEnabled: false,
                isLoadingContent: false,
                findPresented: true,
                findOccupiesEditorChrome: true
            )
        )
    }

    func testSeparateFindWindowDoesNotSuppressMarkdownFormattingChrome() {
        XCTAssertTrue(
            MarkdownFormattingChromePolicy.shouldShow(
                isMarkdown: true,
                isReadOnlyPreview: false,
                brainDumpLayoutEnabled: false,
                isLoadingContent: false,
                findPresented: true,
                findOccupiesEditorChrome: false
            )
        )
    }

    func testWholeWindowMarkdownReadingHidesEditingFormattingChrome() {
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldShow(
                isMarkdown: true,
                isReadOnlyPreview: false,
                brainDumpLayoutEnabled: false,
                isLoadingContent: false,
                findPresented: false,
                findOccupiesEditorChrome: false,
                isReadingViewVisible: true
            )
        )
    }

    func testCollapsedPhoneFormattingChromeOverlaysEditorWithoutReservingARow() {
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldReserveMobileFormattingRow(
                isPhone: true,
                shouldShow: true,
                isCollapsed: true
            )
        )
        XCTAssertTrue(
            MarkdownFormattingChromePolicy.shouldReserveMobileFormattingRow(
                isPhone: true,
                shouldShow: true,
                isCollapsed: true,
                keepCollapsedBelowTabs: true
            )
        )
        XCTAssertTrue(
            MarkdownFormattingChromePolicy.shouldReserveMobileFormattingRow(
                isPhone: true,
                shouldShow: true,
                isCollapsed: false
            )
        )
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldReserveMobileFormattingRow(
                isPhone: false,
                shouldShow: true,
                isCollapsed: false
            )
        )
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.shouldRenderInEditorStack(
                shouldShow: true,
                overlaysEditor: true,
                reservesChromeRow: true
            )
        )
    }

    func testFormattingControlUsesGlassWhenEitherWindowOrToolbarTranslucencyIsEnabled() {
        XCTAssertTrue(
            MarkdownFormattingChromePolicy.usesTranslucentControlSurface(
                isCollapsed: true,
                liquidGlassEnabled: false,
                windowTranslucent: true
            )
        )
        XCTAssertTrue(
            MarkdownFormattingChromePolicy.usesTranslucentControlSurface(
                isCollapsed: false,
                liquidGlassEnabled: true,
                windowTranslucent: false
            )
        )
        XCTAssertFalse(
            MarkdownFormattingChromePolicy.usesTranslucentControlSurface(
                isCollapsed: false,
                liquidGlassEnabled: false,
                windowTranslucent: false
            )
        )
    }
}
