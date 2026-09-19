import XCTest
#if os(macOS)
import AppKit
import SwiftUI
#endif
@testable import Neon_Vision_Editor

@MainActor
final class EditorSettingsDefaultsTests: XCTestCase {
#if os(macOS)
    func testMacSettingsTabRoutePersistsAndPublishesRequestedTab() async throws {
        final class Capture: @unchecked Sendable {
            var tab: String?
        }

        let suiteName = "MacSettingsTabRouteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let notificationCenter = NotificationCenter()
        let capture = Capture()
        let observer = notificationCenter.addObserver(
            forName: MacSettingsTabRoute.didRequestTab,
            object: nil,
            queue: nil
        ) { notification in
            capture.tab = notification.object as? String
        }
        defer {
            notificationCenter.removeObserver(observer)
            defaults.removePersistentDomain(forName: suiteName)
        }

        MacSettingsTabRoute.request(
            "themes",
            defaults: defaults,
            notificationCenter: notificationCenter
        )

        XCTAssertEqual(
            EditorPreferenceWriter.shared.object(
                forKey: SettingsPreferenceKey.activeTab,
                defaults: defaults
            ) as? String,
            "themes"
        )
        await EditorPreferenceWriter.shared.flush()
        XCTAssertEqual(defaults.string(forKey: SettingsPreferenceKey.activeTab), "themes")
        XCTAssertEqual(capture.tab, "themes")
    }

    func testMacSettingsOpeningAndTabSwitchingStayResponsive() async throws {
        let defaults = UserDefaults.standard
        let previousTab = defaults.object(forKey: SettingsPreferenceKey.activeTab)
        defer {
            if let previousTab {
                defaults.set(previousTab, forKey: SettingsPreferenceKey.activeTab)
            } else {
                defaults.removeObject(forKey: SettingsPreferenceKey.activeTab)
            }
        }
        defaults.set("general", forKey: SettingsPreferenceKey.activeTab)

        let startedOpening = ProcessInfo.processInfo.systemUptime
        let root = NeonSettingsView()
            .environment(EditorViewModel())
            .environmentObject(SupportPurchaseManager(loadProducts: { [] }, canMakePayments: { false }))
            .environmentObject(AppUpdateManager())
        let rootConstructionElapsed = ProcessInfo.processInfo.systemUptime - startedOpening
        let hosting = NSHostingView(rootView: root)
        let hostingConstructionElapsed = ProcessInfo.processInfo.systemUptime - startedOpening - rootConstructionElapsed
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        if let visibleFrame = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.midX - window.frame.width / 2,
                    y: visibleFrame.midY - window.frame.height / 2
                )
            )
        }
        let initialOrigin = window.frame.origin
        let windowConstructionElapsed = ProcessInfo.processInfo.systemUptime
            - startedOpening
            - rootConstructionElapsed
            - hostingConstructionElapsed
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        let openingElapsed = ProcessInfo.processInfo.systemUptime - startedOpening
        XCTAssertEqual(window.frame.origin.x, initialOrigin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, initialOrigin.y, accuracy: 1)
        defer {
            window.orderOut(nil)
            window.close()
        }

        let startedSwitching = ProcessInfo.processInfo.systemUptime
        var requestDurations: [TimeInterval] = []
        var layoutDurations: [String: TimeInterval] = [:]
        var paneHeights: [String: CGFloat] = [:]
        let tabs = [
            "general", "editor", "toolbar", "python", "templates", "themes",
            "support", "ai", "remote", "shortcuts", "updates"
        ]
        for tab in tabs {
            let tabStarted = ProcessInfo.processInfo.systemUptime
            MacSettingsTabRoute.request(tab)
            requestDurations.append(ProcessInfo.processInfo.systemUptime - tabStarted)
            try await Task.sleep(for: .milliseconds(50))
            let layoutStarted = ProcessInfo.processInfo.systemUptime
            hosting.layoutSubtreeIfNeeded()
            paneHeights[tab] = hosting.fittingSize.height
            layoutDurations[tab] = ProcessInfo.processInfo.systemUptime - layoutStarted
        }
        let switchingElapsed = ProcessInfo.processInfo.systemUptime - startedSwitching

        XCTAssertLessThan(
            openingElapsed,
            1.5,
            "Constructing and opening Settings must not synchronously initialize every pane "
                + "(root: \(rootConstructionElapsed)s, hosting: \(hostingConstructionElapsed)s, "
                + "window: \(windowConstructionElapsed)s)"
        )
        XCTAssertTrue(
            requestDurations.allSatisfy { $0 < 0.1 },
            "Selecting a Settings tab must return within one interaction frame"
        )
        XCTAssertEqual(paneHeights.count, tabs.count)
        XCTAssertTrue(
            paneHeights.values.allSatisfy { $0 > 0 },
            "Every Settings pane must expose a complete intrinsic height: \(paneHeights)"
        )
        XCTAssertGreaterThan(
            Set(paneHeights.values.map { Int($0.rounded()) }).count,
            3,
            "Settings panes must retain their individual intrinsic heights: \(paneHeights)"
        )
        XCTAssertLessThan(
            switchingElapsed,
            2.0,
            "Switching through every Settings pane must remain interactive; layout durations: \(layoutDurations)"
        )
    }

    func testMacSettingsUsesNativeContentSizingBounds() {
        XCTAssertEqual(NeonSettingsView.macSettingsContentWidth, 900)
    }

    func testMacSettingsRestoresNativeTitlebarMaterial() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.toolbar = NSToolbar(identifier: "settings-header-regression")
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.title = "General"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .systemRed
        if #available(macOS 13.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        SettingsWindowConfigurator.restoreNativeTitlebarMaterial(on: window)

        XCTAssertEqual(window.toolbarStyle, .preference)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.title, "")
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.backgroundColor, NSColor.systemRed)
        if #available(macOS 13.0, *) {
            XCTAssertEqual(window.titlebarSeparatorStyle, .automatic)
        }
    }

    func testMacSettingsConfiguresWindowWhenBridgeIsAttached() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let attachmentView = SettingsWindowAttachmentView(frame: .zero)
        var attachedWindow: NSWindow?
        attachmentView.onWindowAttached = { attachedWindow = $0 }

        window.contentView?.addSubview(attachmentView)

        XCTAssertTrue(attachedWindow === window)
    }

    func testMacSettingsTabKeepsIntrinsicContentWhenInactive() {
        let page = NeonSettingsView.SettingsTabPage(
            title: "General",
            systemImage: "gearshape",
            tag: "general",
            selectedTag: "themes",
            content: { AnyView(Color.clear.frame(width: 640, height: 480)) }
        )
        let hosting = NSHostingView(rootView: page)

        XCTAssertGreaterThanOrEqual(
            hosting.fittingSize.height,
            480,
            "An inactive macOS Settings pane must keep its intrinsic size available to the native TabView"
        )
    }
#endif

    func testSupportAlertQueuesReplacementUntilFrameworkDismissal() {
        var state = SupportStatusAlertPresentation()
        state.receive("First")
        XCTAssertTrue(state.isPresented)
        state.receive("Second")
        XCTAssertEqual(state.message, "First")
        state.isPresented = false
        state.didDismiss()
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.message, "Second")
        state.receive(nil)
        state.didDismiss()
        XCTAssertFalse(state.isPresented)
        XCTAssertNil(state.message)
    }

    func testSupportAlertCoalescesLatestStatusAndDoesNotReopenAcknowledgedMessage() {
        var state = SupportStatusAlertPresentation()
        state.receive("First")
        state.receive("Second")
        state.receive("Latest")
        state.isPresented = false
        state.didDismiss()
        XCTAssertEqual(state.message, "Latest")
        state.receive("Latest")
        state.isPresented = false
        state.didDismiss()
        XCTAssertFalse(state.isPresented)
        XCTAssertNil(state.message)
        state.didDismiss()
        XCTAssertFalse(state.isPresented)
    }

    func testSupportAlertClearDiscardsPendingStatus() {
        var state = SupportStatusAlertPresentation()
        state.receive("First")
        state.receive("Pending")
        state.receive(nil)
        state.didDismiss()
        XCTAssertFalse(state.isPresented)
        XCTAssertNil(state.message)
        state.receive("Fresh")
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.message, "Fresh")
    }

    func testWelcomeTourAutomaticPresentationCanBeDisabledPermanently() {
        XCTAssertFalse(
            WelcomeTourPresentationPolicy.shouldPresentAutomatically(
                isEnabled: false,
                isNormalLaunch: true,
                hasSeenTour: false,
                seenRelease: "",
                currentRelease: "1.7.0"
            )
        )
        XCTAssertFalse(
            WelcomeTourPresentationPolicy.shouldPresentAutomatically(
                isEnabled: false,
                isNormalLaunch: true,
                hasSeenTour: true,
                seenRelease: "1.6.1",
                currentRelease: "1.7.0"
            )
        )
        XCTAssertTrue(
            WelcomeTourPresentationPolicy.shouldPresentAutomatically(
                isEnabled: true,
                isNormalLaunch: true,
                hasSeenTour: true,
                seenRelease: "1.6.1",
                currentRelease: "1.7.0"
            )
        )
        XCTAssertFalse(
            WelcomeTourPresentationPolicy.shouldPresentAutomatically(
                isEnabled: true,
                isNormalLaunch: true,
                hasSeenTour: true,
                seenRelease: "1.7.0",
                currentRelease: "1.7.0"
            )
        )
        XCTAssertFalse(
            WelcomeTourPresentationPolicy.shouldPresentAutomatically(
                isEnabled: true,
                isNormalLaunch: false,
                hasSeenTour: false,
                seenRelease: "",
                currentRelease: "1.7.0"
            )
        )
    }

    func testFocusedObservationSnapshotsOnlyCompareOwnedState() {
        XCTAssertEqual(
            ContentView.TabChromeObservationSnapshot(structureRevision: 3, metadataRevision: 7),
            ContentView.TabChromeObservationSnapshot(structureRevision: 3, metadataRevision: 7)
        )
        XCTAssertEqual(
            ContentView.ProjectNavigationObservationSnapshot(rootURL: URL(fileURLWithPath: "/tmp/project"), indexReady: true),
            ContentView.ProjectNavigationObservationSnapshot(rootURL: URL(fileURLWithPath: "/tmp/project"), indexReady: true)
        )
        XCTAssertEqual(
            ContentView.EditorObservationSnapshot(contentRevision: 11),
            ContentView.EditorObservationSnapshot(contentRevision: 11)
        )
        XCTAssertEqual(
            ContentView.PreviewObservationSnapshot(projectEnabled: true, contentFilter: "markdown"),
            ContentView.PreviewObservationSnapshot(projectEnabled: true, contentFilter: "markdown")
        )
        XCTAssertEqual(
            ContentView.WindowSessionObservationSnapshot(persistenceRevision: 5),
            ContentView.WindowSessionObservationSnapshot(persistenceRevision: 5)
        )
    }

    func testCodeTemplateCatalogProvidesUsefulDefaultsForEverySupportedLanguage() throws {
        XCTAssertEqual(Set(CodeTemplateCatalog.supportedLanguages).count, CodeTemplateCatalog.supportedLanguages.count)

        for language in CodeTemplateCatalog.supportedLanguages {
            let template = try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: language), language)
            XCTAssertFalse(template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, language)
            XCTAssertTrue(template.hasSuffix("\n"), language)
            XCTAssertNotEqual(template, "TODO\n", language)
        }
    }

    func testCodeTemplateCatalogUsesPracticalLanguageSpecificStarters() throws {
        XCTAssertTrue(try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: "swift")).contains("CommandLine.arguments"))
        XCTAssertTrue(try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: "python")).contains("if __name__ == \"__main__\""))
        XCTAssertTrue(try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: "html")).contains("name=\"viewport\""))
        XCTAssertTrue(try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: "bash")).contains("set -euo pipefail"))
        XCTAssertNil(CodeTemplateCatalog.defaultTemplate(for: "unknown"))
    }

    func testStructuredCodeTemplatesAreValidJSON() throws {
        for language in ["json", "ipynb"] {
            let template = try XCTUnwrap(CodeTemplateCatalog.defaultTemplate(for: language))
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(template.utf8)), language)
        }
    }

    func testFreshEditorSettingsDefaultsStayReviewSafe() {
        let defaults = UserDefaults.standard
        let keys = [
            "SettingsLineWrapEnabled",
            "SettingsEditorFontSize",
            "SettingsLineHeight"
        ]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let previousValue = previousValues[key] ?? nil {
                    defaults.set(previousValue, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        keys.forEach(defaults.removeObject)

        let contentView = ContentView()
        XCTAssertTrue(contentView.settingsLineWrapEnabled)
        XCTAssertEqual(contentView.editorFontSize, 14)
        XCTAssertEqual(contentView.editorLineHeight, 1.0)
    }

    func testEditorFontSizeSetterClampsPinchUpdatesToSupportedRange() {
        let defaults = UserDefaults.standard
        let key = "SettingsEditorFontSize"
        let previousValue = defaults.object(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        let contentView = ContentView()

        contentView.setEditorFontSize(18)
        XCTAssertEqual(contentView.editorFontSize, 18)

        contentView.setEditorFontSize(40)
        XCTAssertEqual(contentView.editorFontSize, 28)

        contentView.setEditorFontSize(4)
        XCTAssertEqual(contentView.editorFontSize, 10)
    }

#if os(iOS)
    func testKeyboardToolbarIsOnForNewSettingsAndHonorsSavedOffChoice() {
        let defaults = UserDefaults.standard
        let key = "SettingsShowKeyboardAccessoryBarIOS"
        let previousValue = defaults.object(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        XCTAssertTrue(ContentView().showKeyboardAccessoryBarIOS)
        defaults.set(false, forKey: key)
        XCTAssertFalse(ContentView().showKeyboardAccessoryBarIOS)
    }

    func testIPadShiftScrollConvertsBothScrollDirectionsToFontDeltas() {
        XCTAssertEqual(iPadShiftScrollFontSizeDelta(contentOffsetDeltaY: -25), 1, accuracy: 0.0001)
        XCTAssertEqual(iPadShiftScrollFontSizeDelta(contentOffsetDeltaY: 25), -1, accuracy: 0.0001)
    }

    func testPencilSelectionRangeSupportsForwardReverseAndClampedDrags() {
        XCTAssertEqual(
            EditorPencilInputPolicy.selectionAnchorPoint(
                current: CGPoint(x: 42, y: 18),
                translation: CGPoint(x: 7, y: -3)
            ),
            CGPoint(x: 35, y: 21)
        )
        XCTAssertEqual(
            EditorPencilInputPolicy.selectionRange(anchor: 3, current: 9, textLength: 12),
            NSRange(location: 3, length: 6)
        )
        XCTAssertEqual(
            EditorPencilInputPolicy.selectionRange(anchor: 9, current: 3, textLength: 12),
            NSRange(location: 3, length: 6)
        )
        XCTAssertEqual(
            EditorPencilInputPolicy.selectionRange(anchor: -4, current: 18, textLength: 12),
            NSRange(location: 0, length: 12)
        )
    }

    func testPencilUndoPolicyHonorsSystemShortcutAndCompletedSqueeze() {
        XCTAssertFalse(EditorPencilInputPolicy.shouldPerformUndo(for: .ignore))
        XCTAssertFalse(EditorPencilInputPolicy.shouldPerformUndo(for: .runSystemShortcut))
        XCTAssertTrue(EditorPencilInputPolicy.shouldPerformUndo(for: .showContextualPalette))
        XCTAssertFalse(EditorPencilInputPolicy.shouldPerformUndo(for: UIPencilInteraction.Phase.began))
        XCTAssertFalse(EditorPencilInputPolicy.shouldPerformUndo(for: UIPencilInteraction.Phase.changed))
        XCTAssertTrue(EditorPencilInputPolicy.shouldPerformUndo(for: UIPencilInteraction.Phase.ended))
    }

    func testLineStartIndexAppliesSingleLineEditWithoutRescanningDocument() {
        let original = "one\ntwo\nthree"
        let starts = EditorLineStartIndex.offsets(in: original)

        XCTAssertEqual(
            EditorLineStartIndex.applying(
                replacementRange: NSRange(location: 5, length: 1),
                replacement: "W",
                to: starts
            ),
            starts
        )
    }

    func testLineStartIndexAppliesInsertedAndRemovedNewlines() {
        let starts = EditorLineStartIndex.offsets(in: "one\ntwo\nthree")
        let inserted = EditorLineStartIndex.applying(
            replacementRange: NSRange(location: 5, length: 0),
            replacement: "x\ny",
            to: starts
        )
        XCTAssertEqual(inserted, EditorLineStartIndex.offsets(in: "one\ntx\nywo\nthree"))

        let removed = EditorLineStartIndex.applying(
            replacementRange: NSRange(location: 3, length: 1),
            replacement: "",
            to: starts
        )
        XCTAssertEqual(removed, EditorLineStartIndex.offsets(in: "onetwo\nthree"))
    }

    func testLineStartIndexMatchesFullScanAcrossUnicodeMutations() {
        let original = "a😀\nbé\n末"
        let starts = EditorLineStartIndex.offsets(in: original)
        let boundaries = original.indices.map { original[..<$0].utf16.count } + [original.utf16.count]
        let replacements = ["", "x", "\n", "😀\nq"]

        for lowerIndex in boundaries.indices {
            for upperIndex in lowerIndex..<boundaries.count {
                let lower = boundaries[lowerIndex]
                let upper = boundaries[upperIndex]
                let range = NSRange(location: lower, length: upper - lower)
                for replacement in replacements {
                    let expectedText = (original as NSString).replacingCharacters(in: range, with: replacement)
                    XCTAssertEqual(
                        EditorLineStartIndex.applying(
                            replacementRange: range,
                            replacement: replacement,
                            to: starts
                        ),
                        EditorLineStartIndex.offsets(in: expectedText),
                        "Mismatch for range \(range) and replacement \(replacement.debugDescription)"
                    )
                }
            }
        }
    }

    func testNoWrapWidthCacheInvalidatesOnlyForMeaningfulTextMetricsChanges() {
        let textView = EditorInputTextView()
        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        var computations = 0

        func width() -> CGFloat {
            textView.cachedNoWrapWidth(visibleWidth: 600, tabWidth: 4, font: font) {
                computations += 1
                return 2_000
            }
        }

        XCTAssertEqual(width(), 2_000)
        XCTAssertEqual(width(), 2_000)
        XCTAssertEqual(computations, 1)

        textView.invalidateTextMetrics()
        XCTAssertEqual(width(), 2_000)
        XCTAssertEqual(computations, 2)
    }

    func testVimLineStartCacheTracksDocumentRevision() {
        let textView = EditorInputTextView()
        textView.text = "one\ntwo"
        textView.invalidateTextMetrics()
        XCTAssertEqual(textView.cachedLineStartOffsets(), [0, 4])
        XCTAssertEqual(textView.cachedLineStartOffsets(), [0, 4])

        textView.text = "one\ntwo\nthree"
        textView.invalidateTextMetrics()
        XCTAssertEqual(textView.cachedLineStartOffsets(), [0, 4, 8])
    }

    func testVimLineStartCacheAppliesInteractiveEditIncrementally() {
        let textView = EditorInputTextView()
        textView.text = "one\ntwo\nthree"
        textView.invalidateTextMetrics()
        XCTAssertEqual(textView.cachedLineStartOffsets(), [0, 4, 8])

        textView.text = "one\nsecond line\nthree"
        textView.applyTextMetricsMutation(
            range: NSRange(location: 4, length: 3),
            replacement: "second line"
        )

        XCTAssertEqual(textView.cachedLineStartOffsets(), [0, 4, 16])
    }

    func testLargeTextFormattingRangeIsBoundedAndClamped() {
        XCTAssertEqual(
            EditorLargeTextFormatting.updateRange(
                visibleRange: NSRange(location: 100_000, length: 2_000),
                textLength: 500_000,
                padding: 8_000
            ),
            NSRange(location: 92_000, length: 18_000)
        )
        XCTAssertEqual(
            EditorLargeTextFormatting.updateRange(
                visibleRange: NSRange(location: 498_000, length: 5_000),
                textLength: 500_000,
                padding: 8_000
            ),
            NSRange(location: 490_000, length: 10_000)
        )
    }
#endif

    func testAutomaticWritingAssistanceFollowsDocumentLanguage() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.set(EditorWritingAssistanceMode.automatic.rawValue, forKey: SettingsPreferenceKey.writingAssistanceMode)

        XCTAssertEqual(
            EditorWritingAssistanceProfile.resolved(language: "markdown", defaults: defaults),
            EditorWritingAssistanceProfile(autocorrection: true, autocapitalization: true, spellChecking: true)
        )
        XCTAssertEqual(
            EditorWritingAssistanceProfile.resolved(language: "swift", defaults: defaults),
            EditorWritingAssistanceProfile(autocorrection: false, autocapitalization: false, spellChecking: false)
        )
    }

    func testCustomWritingAssistanceOverridesLanguageDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.set(EditorWritingAssistanceMode.custom.rawValue, forKey: SettingsPreferenceKey.writingAssistanceMode)
        defaults.set(true, forKey: SettingsPreferenceKey.spellCheckingEnabled)

        XCTAssertEqual(
            EditorWritingAssistanceProfile.resolved(language: "swift", defaults: defaults),
            EditorWritingAssistanceProfile(autocorrection: false, autocapitalization: false, spellChecking: true)
        )
    }
}
