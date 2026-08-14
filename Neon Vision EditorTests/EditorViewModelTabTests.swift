import Observation
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class EditorViewModelTabTests: XCTestCase {
    func testDraftSnapshotPreservesLineEndingAndDecodesOlderSnapshots() throws {
        let snapshot = ContentView.SavedDraftTabSnapshot(
            name: "Windows.txt",
            content: "one\ntwo",
            language: "plain",
            fileURLString: nil,
            lineEndingRawValue: TextLineEnding.crlf.rawValue
        )
        let roundTrip = try JSONDecoder().decode(
            ContentView.SavedDraftTabSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(roundTrip.lineEndingRawValue, TextLineEnding.crlf.rawValue)

        let legacyData = try XCTUnwrap(
            #"{"name":"Legacy.txt","content":"one\ntwo","language":"plain","fileURLString":null}"#
                .data(using: .utf8)
        )
        let legacy = try JSONDecoder().decode(ContentView.SavedDraftTabSnapshot.self, from: legacyData)
        XCTAssertNil(legacy.lineEndingRawValue)
    }

    func testDraftSnapshotRoundTripsOptionalFileBackedSessionState() throws {
        let record = FileBackedTextDocument.RestoreRecord(
            fileURL: URL(fileURLWithPath: "/tmp/large.txt"),
            encodingIdentifier: .utf8,
            lineEnding: .lf,
            byteCount: 123,
            modificationDate: Date(timeIntervalSinceReferenceDate: 42),
            isRemoteEligible: false
        )
        let state = FileBackedTextDocument.SessionState(
            restoreRecord: record,
            sourceFingerprint: 99,
            edits: [.init(location: 5, length: 2, replacement: "new")]
        )
        let snapshot = ContentView.SavedDraftTabSnapshot(
            name: "large.txt",
            content: "new",
            language: "plain",
            fileURLString: record.fileURL.absoluteString,
            storageMode: .fileBacked,
            fileBackedSessionState: state
        )

        let roundTrip = try JSONDecoder().decode(
            ContentView.SavedDraftTabSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(roundTrip.storageMode, .fileBacked)
        XCTAssertEqual(roundTrip.fileBackedSessionState, state)
    }

    func testRemoteTabCannotAttachFileBackedStorage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "remote\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try FileBackedTextDocument(url: url)
        let tab = TabData(
            name: "remote.txt",
            content: "remote\n",
            language: "plain",
            fileURL: nil,
            remotePreviewPath: "/remote/remote.txt",
            remoteRevisionToken: "revision-1"
        )

        tab.attachFileBackedDocument(document)

        XCTAssertFalse(tab.usesFileBackedStorage)
        XCTAssertNil(tab.fileBackedDocument)
        XCTAssertEqual(tab.remoteRevisionToken, "revision-1")
    }

    func testInstallingLoadedFileBackedDocumentPreservesBoundedStorage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try String(repeating: "large source line\n", count: 20_000).write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let tab = TabData(name: "large.txt", content: "stale", language: "plain", fileURL: url)
        let document = try FileBackedTextDocument(url: url)

        XCTAssertTrue(tab.installLoadedFileBackedDocument(document))
        XCTAssertTrue(tab.usesFileBackedStorage)
        XCTAssertFalse(tab.isDirty)
        XCTAssertEqual(try tab.document.viewport(aroundLine: 10, maximumByteCount: 256).text.contains("large source line"), true)
    }

    func testBoundedUTF8EncodingDetectionDoesNotRequireFullTextProjection() {
        XCTAssertEqual(EditorViewModel.boundedUTF8Encoding(from: Data("prefix 😀".utf8))?.identifier, .utf8)
        XCTAssertEqual(EditorViewModel.boundedUTF8Encoding(from: Data([0xEF, 0xBB, 0xBF, 0x61]))?.identifier, .utf8WithBOM)
        XCTAssertNil(EditorViewModel.boundedUTF8Encoding(from: Data([0xC3, 0x28])))
    }

    func testBoundedFileEncodingDetectionIncludesUTF16AndLegacyEncodings() throws {
        let utf16 = TextEncodingDescriptor(identifier: .utf16BigEndianWithBOM)

        let detectedUTF16 = try XCTUnwrap(FileBackedTextDocument.boundedEncoding(from: try XCTUnwrap(utf16.encodedData(for: "first\n"))))
        XCTAssertEqual(detectedUTF16.identifier, .utf16BigEndianWithBOM)
        XCTAssertEqual(
            FileBackedTextDocument.boundedEncoding(from: Data([0xC0, 0xCF, 0xC8, 0xD2, 0xC5, 0xD2]))?.identifier,
            .windowsCP1251
        )
    }

    func testUTF8AndUTF16EncodingsAreEligibleForLocalBoundedStorage() {
        let url = URL(fileURLWithPath: "/tmp/bounded-encoding-test.txt")
        let identifiers: [TextEncodingDescriptor.Identifier] = [
            .utf8, .utf8WithBOM, .utf16LittleEndian, .utf16LittleEndianWithBOM,
            .utf16BigEndian, .utf16BigEndianWithBOM
        ]
        for identifier in identifiers {
            XCTAssertTrue(
                EditorViewModel.isFileBackedEligible(
                    url: url,
                    encoding: TextEncodingDescriptor(identifier: identifier),
                    isRemote: false,
                    isPartialPreview: false
                ),
                identifier.rawValue
            )
        }
        XCTAssertFalse(EditorViewModel.isFileBackedEligible(url: url, encoding: .utf8, isRemote: true, isPartialPreview: false))
        XCTAssertFalse(EditorViewModel.isFileBackedEligible(url: url, encoding: .utf8, isRemote: false, isPartialPreview: true))
        XCTAssertTrue(EditorViewModel.isFileBackedEligible(url: url, encoding: TextEncodingDescriptor(identifier: .windowsCP1251), isRemote: false, isPartialPreview: false))
    }

    func testProductionLoaderSelectsBoundedStorageForUTF16AndLegacyFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cases: [(String, TextEncodingDescriptor)] = [
            ("utf16.txt", TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM)),
            ("cp1251.txt", TextEncodingDescriptor(identifier: .windowsCP1251)),
            ("cp1252.txt", TextEncodingDescriptor(identifier: .windowsCP1252)),
            ("latin1.txt", TextEncodingDescriptor(identifier: .isoLatin1)),
            ("latin5.txt", TextEncodingDescriptor(identifier: .isoLatin5)),
            ("macroman.txt", TextEncodingDescriptor(identifier: .macOSRoman)),
            ("ascii.txt", TextEncodingDescriptor(identifier: .ascii))
        ]
        for (name, encoding) in cases {
            let url = directory.appendingPathComponent(name)
            let source: String
            switch encoding.identifier {
            case .windowsCP1251:
                source = (0..<40_000).map { "line-\($0) привет\n" }.joined()
            case .windowsCP1252:
                source = (0..<40_000).map { "line-\($0) Résumé €\n" }.joined()
            case .isoLatin1:
                source = (0..<40_000).map { "line-\($0) café\n" }.joined()
            case .isoLatin5:
                source = (0..<40_000).map { "line-\($0) Türkçe\n" }.joined()
            case .macOSRoman:
                source = (0..<40_000).map { "line-\($0) café\n" }.joined()
            case .ascii:
                source = (0..<40_000).map { "line-\($0) plain\n" }.joined()
            default:
                source = (0..<40_000).map { "line-\($0) привет\n" }.joined()
            }
            try XCTUnwrap(encoding.encodedData(for: source)).write(to: url)
            let selected = try await EditorViewModel.boundedLoadEncodingForTesting(
                from: url,
                preferredEncoding: encoding
            )
            XCTAssertEqual(selected?.identifier, encoding.identifier, name)
        }
    }

    func testDraftRecoveryDeduplicatesExactDuplicateTabs() {
        let duplicate = ContentView.SavedDraftTabSnapshot(
            name: "Untitled 1",
            content: "import os",
            language: "Python",
            fileURLString: nil
        )
        let distinct = ContentView.SavedDraftTabSnapshot(
            name: "Untitled 1",
            content: "print('hello')",
            language: "Python",
            fileURLString: nil
        )

        let restored = deduplicatedDraftSnapshotTabs([duplicate, distinct, duplicate])

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.map(\.content), [duplicate.content, distinct.content])
    }

    func testDraftRecoveryUsesNewestSnapshotAndRestoresItsSelection() throws {
        let olderTab = ContentView.SavedDraftTabSnapshot(
            name: "Draft.md",
            content: "older",
            language: "Markdown",
            fileURLString: "file:///tmp/Draft.md"
        )
        let newestTab = ContentView.SavedDraftTabSnapshot(
            name: "Draft.md",
            content: "newest",
            language: "Markdown",
            fileURLString: "file:///tmp/Draft.md"
        )
        let olderSnapshot = ContentView.SavedDraftSnapshot(
            tabs: [olderTab],
            selectedIndex: 0,
            createdAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        let newestSnapshot = ContentView.SavedDraftSnapshot(
            tabs: [newestTab],
            selectedIndex: 0,
            createdAt: Date(timeIntervalSinceReferenceDate: 2)
        )

        let restored = try XCTUnwrap(
            restoredDraftSnapshotState(from: [olderSnapshot, newestSnapshot])
        )

        XCTAssertEqual(restored.tabs.map(\.content), [newestTab.content])
        XCTAssertEqual(restored.selectedIndex, 0)
    }

    func testSelectTabUpdatesSelectedTabID() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        XCTAssertEqual(tabs.count, 2)

        viewModel.selectTab(id: tabs[0].id)
        XCTAssertEqual(viewModel.selectedTabID, tabs[0].id)

        viewModel.selectTab(id: tabs[1].id)
        XCTAssertEqual(viewModel.selectedTabID, tabs[1].id)
    }

    func testTabSelectionPerformanceWithLargeTabSet() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        for _ in 0..<80 {
            viewModel.addNewTab()
        }
        let tabIDs = viewModel.tabs.map(\.id)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            for tabID in tabIDs {
                viewModel.selectTab(id: tabID)
            }
        }
    }

    func testCloseTabRemovesTargetTabAndKeepsSurvivorSelected() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        XCTAssertEqual(tabs.count, 2)

        viewModel.selectTab(id: tabs[0].id)
        viewModel.closeTab(tabID: tabs[0].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), [tabs[1].id])
        XCTAssertEqual(viewModel.selectedTabID, tabs[1].id)
    }

    func testMoveTabPlacesDraggedTabBeforeDestinationWithoutChangingSelection() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        viewModel.selectTab(id: tabs[2].id)
        viewModel.moveTab(tabID: tabs[2].id, beforeTabID: tabs[0].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), [tabs[2].id, tabs[0].id, tabs[1].id])
        XCTAssertEqual(viewModel.selectedTabID, tabs[2].id)
    }

    func testMoveTabPlacesDraggedTabAfterDestinationInEitherDirection() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        viewModel.selectTab(id: tabs[0].id)
        viewModel.moveTab(tabID: tabs[0].id, afterTabID: tabs[2].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), [tabs[1].id, tabs[2].id, tabs[0].id])
        XCTAssertEqual(viewModel.selectedTabID, tabs[0].id)

        viewModel.moveTab(tabID: tabs[0].id, afterTabID: tabs[1].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), [tabs[1].id, tabs[0].id, tabs[2].id])
    }

    func testAdjacentTabMovesDoNotInvalidateTabState() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        viewModel.addNewTab()
        viewModel.addNewTab()

        let tabs = viewModel.tabs
        let initialOrder = tabs.map(\.id)
        let initialToken = viewModel.tabsObservationToken

        viewModel.moveTab(tabID: tabs[0].id, beforeTabID: tabs[1].id)
        viewModel.moveTab(tabID: tabs[1].id, afterTabID: tabs[0].id)

        XCTAssertEqual(viewModel.tabs.map(\.id), initialOrder)
        XCTAssertEqual(viewModel.tabsObservationToken, initialToken)
    }

    func testTabContentMutationInvalidatesContentObservers() async throws {
        let viewModel = EditorViewModel()
        let tab = try XCTUnwrap(viewModel.selectedTab)
        let invalidated = expectation(description: "Tab content observation token invalidated")

        withObservationTracking {
            _ = viewModel.tabContentObservationToken
        } onChange: {
            invalidated.fulfill()
        }

        viewModel.updateTabContent(tabID: tab.id, content: "Updated content")

        await fulfillment(of: [invalidated], timeout: 1)
    }

    func testTabContentReadInvalidatesWhenDocumentContentChanges() async {
        let tab = TabData(
            name: "Preview.md",
            content: "",
            language: "markdown",
            fileURL: nil
        )
        let invalidated = expectation(description: "Observed tab content invalidated")

        withObservationTracking {
            _ = tab.document.string()
            _ = tab.document.utf16Length
        } onChange: {
            invalidated.fulfill()
        }

        tab.replaceContentStorage(with: "# Loaded\n", compareIfLengthAtMost: nil)

        await fulfillment(of: [invalidated], timeout: 1)
        XCTAssertEqual(tab.document.string(), "# Loaded\n")
        XCTAssertEqual(tab.document.utf16Length, 9)
    }
}
