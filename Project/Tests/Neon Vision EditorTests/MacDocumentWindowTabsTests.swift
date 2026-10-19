#if os(macOS)
import AppKit
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class MacDocumentWindowTabsTests: XCTestCase {
    private func window(_ title: String = "Native document tabs QA") -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title
        window.contentView = NSTextField(labelWithString: title)
        return window
    }

    func testNativeModeIsExplicitAndLegacyModelsAreNotRegistered() {
        let store = MacDocumentWindowTabs()
        let model = EditorViewModel()
        let window = window()
        defer { window.close() }
        window.tabbingMode = .disallowed
        store.register(model, window: window) { _ in XCTFail("Legacy mode must not create native windows") }
        XCTAssertFalse(model.usesNativeDocumentTabs)
        XCTAssertNil(model.nativeDocumentDestination)
        XCTAssertTrue(store.models.isEmpty)
        XCTAssertEqual(window.tabbingMode, .disallowed)
    }

    func testNewNativeTabGetsItsOwnModelWithoutMovingDirtyBuffer() throws {
        let store = MacDocumentWindowTabs()
        let source = EditorViewModel(usesNativeDocumentTabs: true)
        let window = window()
        defer { store.unregister(source); window.close() }
        var requests: [UUID] = []
        store.register(source, window: window) { requests.append($0) }
        let original = try XCTUnwrap(source.selectedTab)
        source.updateTabContent(tabID: original.id, content: "unsaved 中文 😀")
        source.addNewTab()
        XCTAssertEqual(requests.count, 1)
        let destination = try XCTUnwrap(store.takePendingModel(for: requests[0]))
        XCTAssertFalse(source === destination)
        XCTAssertTrue(source.selectedTab === original)
        XCTAssertEqual(original.document.string(), "unsaved 中文 😀")
        XCTAssertTrue(original.isDirty)
        XCTAssertEqual(source.tabs.count, 1)
        XCTAssertEqual(destination.tabs.count, 1)
        XCTAssertFalse(destination.selectedTab?.isDirty ?? true)
        XCTAssertEqual(store.models.count, 2, "Pending scenes participate in persistence before attachment")
        XCTAssertTrue(store.takePendingModel(for: requests[0]) === destination)
    }

    func testAttachingChildUsesRealAppKitWindowTabsAndUnregistersOnlyItsOwner() throws {
        let store = MacDocumentWindowTabs()
        let source = EditorViewModel(usesNativeDocumentTabs: true)
        let first = window("First document")
        let second = window("Second document")
        defer { first.close(); second.close() }
        var request: UUID?
        store.register(source, window: first) { request = $0 }
        source.addNewTab()
        let child = try XCTUnwrap(store.takePendingModel(for: XCTUnwrap(request)))
        store.register(child, window: second) { _ in }
        XCTAssertEqual(first.tabbingIdentifier, MacDocumentTabPolicy.tabbingIdentifier)
        XCTAssertEqual(second.tabbingMode, .preferred)
        XCTAssertEqual(first.tabbedWindows?.count, 2)
        XCTAssertTrue(first.tabbedWindows?.contains(where: { $0 === second }) == true)
        first.addTabbedWindow(second, ordered: .below)
        XCTAssertEqual(store.models.count, 2)
        XCTAssertTrue(source.selectedTab !== child.selectedTab)
        store.unregister(child)
        XCTAssertNil(child.nativeDocumentDestination)
        XCTAssertEqual(store.models.count, 1)
        XCTAssertTrue(store.models.first === source)
        store.unregister(source)
        XCTAssertTrue(store.models.isEmpty)
    }

    func testNativeTabBarSceneGetsAnOwnerAndJoinsTheActiveWindowGroup() throws {
        let store = MacDocumentWindowTabs()
        let source = EditorViewModel(usesNativeDocumentTabs: true)
        let first = window("Active native document")
        let second = window("AppKit plus scene")
        defer { store.unregister(source); first.close(); second.close() }
        store.register(source, window: first) { _ in }
        store.noteBecameKey(source)

        let sceneID = try XCTUnwrap(store.prepareNativeTabScene())
        let destination = try XCTUnwrap(store.takePendingModel(for: sceneID))
        store.register(destination, window: second) { _ in }

        XCTAssertTrue(first.tabbedWindows?.contains(where: { $0 === second }) == true)
        XCTAssertTrue(store.models.contains(where: { $0 === destination }))
        XCTAssertTrue(store.selectedModel === destination)
    }

    func testNativeFileOpenReusesOnlyBlankOwnerAndDeduplicatesPendingScenes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.txt")
        let secondURL = directory.appendingPathComponent("second.unknown")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second 中文".write(to: secondURL, atomically: true, encoding: .utf8)
        let store = MacDocumentWindowTabs()
        let source = EditorViewModel(usesNativeDocumentTabs: true)
        let window = window()
        defer { store.unregister(source); window.close() }
        var requests: [UUID] = []
        store.register(source, window: window) { requests.append($0) }
        XCTAssertTrue(source.openFile(url: firstURL))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(source.openFile(url: secondURL))
        XCTAssertEqual(requests.count, 1)
        let child = try XCTUnwrap(store.takePendingModel(for: requests[0]))
        XCTAssertTrue(source.openFile(url: secondURL))
        XCTAssertEqual(requests.count, 1)
        for _ in 0..<200 where source.selectedTab?.isLoadingContent == true || child.selectedTab?.isLoadingContent == true {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(source.tabs.count, 1)
        XCTAssertEqual(child.tabs.count, 1)
        XCTAssertEqual(source.selectedTab?.document.string(), "first")
        XCTAssertEqual(child.selectedTab?.document.string(), "second 中文")
    }

    func testNativeDraftRestoreKeepsEveryUnsavedDocumentInSeparateOwners() throws {
        let store = MacDocumentWindowTabs()
        let source = EditorViewModel(usesNativeDocumentTabs: true)
        let window = window()
        defer { store.unregister(source); window.close() }
        var requests: [UUID] = []
        store.register(source, window: window) { requests.append($0) }
        let snapshots = ["one 😀", "two 中文", "three"].map { text in
            EditorViewModel.RestoredTabSnapshot(name: text, content: text, language: "plain", fileURL: nil,
                languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
                lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)
        }
        source.restoreTabsFromSnapshot(snapshots, selectedIndex: 1)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(store.models.count, 3)
        XCTAssertEqual(store.models.map { $0.tabs.count }, [1, 1, 1])
        XCTAssertEqual(store.models.compactMap { $0.selectedTab?.document.string() }, ["one 😀", "two 中文", "three"])
        XCTAssertTrue(store.models.allSatisfy { $0.selectedTab?.isDirty == true })
        XCTAssertEqual(store.selectedModel?.selectedTab?.document.string(), "two 中文")
        let lastWindow = self.window("Last restored draft")
        let selectedWindow = self.window("Selected restored draft")
        defer { lastWindow.close(); selectedWindow.close() }
        let last = try XCTUnwrap(store.takePendingModel(for: requests[1]))
        let selected = try XCTUnwrap(store.takePendingModel(for: requests[0]))
        store.register(last, window: lastWindow) { _ in }
        store.register(selected, window: selectedWindow) { _ in }
        XCTAssertTrue(window.tabGroup?.selectedWindow === selectedWindow)
        store.unregister(last)
        store.unregister(selected)
    }

    func testNativeRemoteOpenDoesNotLeaveAnExtraBlankDocument() {
        let model = EditorViewModel(usesNativeDocumentTabs: true)
        model.openRemoteDocument(name: "remote.txt", remotePath: "/remote.txt", content: "remote",
                                 isReadOnly: false)
        XCTAssertEqual(model.tabs.count, 1)
        model.openRemoteDocument(name: "remote.txt", remotePath: "/remote.txt", content: "updated",
                                 isReadOnly: false)
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.selectedTab?.document.string(), "updated")
    }

    func testSaveBeforeNativeWindowCloseAwaitsWritesAndPreservesModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("saved.txt")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        let model = EditorViewModel(usesNativeDocumentTabs: true)
        XCTAssertTrue(model.openFile(url: url))
        for _ in 0..<200 where model.selectedTab?.isLoadingContent == true {
            try await Task.sleep(for: .milliseconds(10))
        }
        let tab = try XCTUnwrap(model.selectedTab)
        model.updateTabContent(tabID: tab.id, content: "new 😀")
        let saved = await model.saveDirtyDocumentsBeforeWindowClose()
        XCTAssertTrue(saved)
        XCTAssertFalse(tab.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new 😀")
        XCTAssertTrue(model.selectedTab === tab, "The window delegate, not saving, owns closing")
    }

    func testNativeWindowSelectionAndDetachDoNotChangeBufferOwners() throws {
        let store = MacDocumentWindowTabs()
        let model = EditorViewModel(usesNativeDocumentTabs: true)
        let first = window("First editable document")
        let second = window("Second editable document")
        defer { first.close(); second.close() }
        var request: UUID?
        store.register(model, window: first) { request = $0 }
        let firstTab = try XCTUnwrap(model.selectedTab)
        model.updateTabContent(tabID: firstTab.id, content: "First unsaved")
        model.addNewTab()
        let child = try XCTUnwrap(store.takePendingModel(for: XCTUnwrap(request)))
        let secondTab = try XCTUnwrap(child.selectedTab)
        child.updateTabContent(tabID: secondTab.id, content: "Second unsaved")
        store.register(child, window: second) { _ in }
        let start = ContinuousClock.now
        for _ in 0..<100 {
            first.tabGroup?.selectedWindow = first
            first.selectNextTab(nil)
            second.selectPreviousTab(nil)
        }
        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed, .seconds(5), "Native selection must not load or copy document buffers")
        XCTAssertTrue(model.selectedTab === firstTab)
        XCTAssertTrue(child.selectedTab === secondTab)
        XCTAssertEqual(firstTab.document.string(), "First unsaved")
        XCTAssertEqual(secondTab.document.string(), "Second unsaved")
        XCTAssertTrue(firstTab.isDirty)
        XCTAssertTrue(secondTab.isDirty)
        second.moveTabToNewWindow(nil)
        XCTAssertTrue(model.selectedTab === firstTab)
        XCTAssertTrue(child.selectedTab === secondTab)
        first.addTabbedWindow(second, ordered: .above)
        XCTAssertEqual(first.tabbedWindows?.count, 2)
        let image = try XCTUnwrap(first.contentView?.bitmapImageRepForCachingDisplay(in: first.contentView!.bounds))
        first.contentView?.cacheDisplay(in: first.contentView!.bounds, to: image)
        let attachment = XCTAttachment(data: try XCTUnwrap(image.representation(using: .png, properties: [:])),
                                      uniformTypeIdentifier: "public.png")
        attachment.name = "Native document group content"
        attachment.lifetime = .keepAlways
        add(attachment)
        store.unregister(child)
        store.unregister(model)
    }

    func testTerminationPersistsCompleteDraftSetBeforeFreezingWindowTeardown() {
        let store = MacDocumentWindowTabs()
        let model = EditorViewModel(usesNativeDocumentTabs: true)
        let window = window()
        defer { window.close() }
        var persisted = 0
        store.register(model, window: window, persistDrafts: {
            XCTAssertFalse(store.isTerminating)
            XCTAssertEqual(store.models.count, 1)
            persisted += 1
        }) { _ in }
        store.beginTermination()
        store.unregister(model)
        store.beginTermination()
        XCTAssertTrue(store.isTerminating)
        XCTAssertEqual(persisted, 1)
        XCTAssertEqual(store.models.count, 1, "Window teardown must not replace recovery with a partial session")
    }

    func testFailedNativeWindowSaveKeepsDirtyDocumentOpen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = EditorViewModel(usesNativeDocumentTabs: true)
        model.restoreTabsFromSnapshot([.init(name: "invalid target", content: "Keep this unsaved text", language: "plain",
            fileURL: directory, languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
            lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)], selectedIndex: 0)
        let tab = try XCTUnwrap(model.selectedTab)
        let saved = await model.saveDirtyDocumentsBeforeWindowClose()
        XCTAssertFalse(saved)
        XCTAssertTrue(model.selectedTab === tab)
        XCTAssertTrue(tab.isDirty)
        XCTAssertEqual(tab.document.string(), "Keep this unsaved text")
    }

    func testPDFAndAttachedNoteRemainACompositeWindowWithoutLosingTheSource() throws {
        let model = EditorViewModel(usesNativeDocumentTabs: true)
        let source = try XCTUnwrap(model.selectedTab)
        let noteID = model.addPDFNoteTab(name: "source.pdf.notes.md", content: "Note content")
        XCTAssertTrue(model.tabs.contains { $0 === source })
        XCTAssertEqual(model.selectedTabID, noteID)
        model.selectTab(id: source.id)
        XCTAssertEqual(model.tabs.first { $0.id == noteID }?.document.string(), "Note content")
    }

    func testFocusingAnEmptyDirtyDraftDoesNotReloadItsOldDiskContents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("emptied.txt")
        try "Previous disk contents".write(to: url, atomically: true, encoding: .utf8)
        let model = EditorViewModel(usesNativeDocumentTabs: true)
        model.restoreTabsFromSnapshot([.init(name: url.lastPathComponent, content: "", language: "plain",
            fileURL: url, languageLocked: false, isDirty: true, lastSavedFingerprint: nil,
            lastKnownFileModificationDate: nil, fileEncodingRawValue: String.Encoding.utf8.rawValue)], selectedIndex: 0)
        XCTAssertTrue(model.openFile(url: url))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.selectedTab?.isLoadingContent ?? true)
        XCTAssertTrue(model.selectedTab?.isDirty ?? false)
        XCTAssertEqual(model.selectedTab?.document.string(), "")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Previous disk contents")
    }
}
#endif
