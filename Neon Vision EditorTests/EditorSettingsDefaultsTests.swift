import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class EditorSettingsDefaultsTests: XCTestCase {
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
