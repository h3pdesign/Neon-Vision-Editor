import XCTest
@testable import Neon_Vision_Editor

final class RecentFilesStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        defaultsSuiteName = "RecentFilesStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
    }

    @MainActor
    func testRememberOrdersMostRecentFirst() async throws {
        let first = try makeFile(named: "first.txt")
        let second = try makeFile(named: "second.txt")

        RecentFilesStore.remember(first, defaults: defaults)
        RecentFilesStore.remember(second, defaults: defaults)

        XCTAssertEqual(RecentFilesStore.items(limit: 10, defaults: defaults).map(\.title), ["second.txt", "first.txt"])
        await EditorPreferenceWriter.shared.flush()
    }

    @MainActor
    func testPinnedItemsStayAtTop() async throws {
        let first = try makeFile(named: "first.txt")
        let second = try makeFile(named: "second.txt")
        let third = try makeFile(named: "third.txt")

        RecentFilesStore.remember(first, defaults: defaults)
        RecentFilesStore.remember(second, defaults: defaults)
        RecentFilesStore.remember(third, defaults: defaults)
        RecentFilesStore.togglePinned(first, defaults: defaults)

        let items = RecentFilesStore.items(limit: 10, defaults: defaults)
        XCTAssertEqual(items.map(\.title), ["first.txt", "third.txt", "second.txt"])
        XCTAssertEqual(items.first?.isPinned, true)
        await EditorPreferenceWriter.shared.flush()
    }

    @MainActor
    func testClearUnpinnedRetainsPinnedItems() async throws {
        let pinned = try makeFile(named: "pinned.txt")
        let unpinned = try makeFile(named: "unpinned.txt")

        RecentFilesStore.remember(pinned, defaults: defaults)
        RecentFilesStore.remember(unpinned, defaults: defaults)
        RecentFilesStore.togglePinned(pinned, defaults: defaults)
        RecentFilesStore.clearUnpinned(defaults: defaults)

        XCTAssertEqual(RecentFilesStore.items(limit: 10, defaults: defaults).map(\.title), ["pinned.txt"])
        await EditorPreferenceWriter.shared.flush()
    }

    @MainActor
    func testQueuedPreferencesPreserveMutationOrderAndImmediateReads() async throws {
        let first = try makeFile(named: "first.txt")
        let second = try makeFile(named: "second.txt")
        RecentFilesStore.remember(first, defaults: defaults)
        RecentFilesStore.togglePinned(first, defaults: defaults)
        RecentFilesStore.remember(second, defaults: defaults)
        RecentFilesStore.clearUnpinned(defaults: defaults)
        XCTAssertEqual(RecentFilesStore.items(defaults: defaults).map(\.url), [first])
        EditorPreferenceWriter.shared.flushBeforeTermination()
        XCTAssertNil(defaults.object(forKey: "RecentFilesPathsV1"))
        XCTAssertEqual(defaults.stringArray(forKey: "PinnedRecentFilesPathsV1"), [first.path])
        let bookmarks = defaults.dictionary(forKey: "RecentFilesBookmarksV1") ?? [:]
        XCTAssertNil(bookmarks[second.path])
    }

    @MainActor
    func testPerformanceEventsRemainOrderedWhenClearedDuringPersistence() async {
        let monitor = EditorPerformanceMonitor(defaults: defaults)
        for _ in 0..<35 {
            let id = UUID()
            monitor.beginFileOpen(tabID: id)
            monitor.endFileOpen(tabID: id, success: true, byteCount: 1)
            monitor.beginTabSwitch(tabID: id)
            monitor.markTabSwitchFirstDraw(tabID: id)
        }
        XCTAssertEqual(monitor.recentFileOpenEvents(limit: 100).count, 30)
        XCTAssertEqual(monitor.recentTabSwitchEvents(limit: 100).count, 30)
        monitor.clearRecentFileOpenEvents()
        monitor.clearRecentTabSwitchEvents()
        XCTAssertTrue(monitor.recentFileOpenEvents().isEmpty)
        XCTAssertTrue(monitor.recentTabSwitchEvents().isEmpty)
        let id = UUID()
        monitor.beginFileOpen(tabID: id)
        monitor.endFileOpen(tabID: id, success: false, byteCount: 42)
        await EditorPreferenceWriter.shared.flush()
        let persisted = EditorPerformanceMonitor(defaults: defaults)
        XCTAssertEqual(persisted.recentFileOpenEvents().count, 1)
        XCTAssertEqual(persisted.recentFileOpenEvents().first?.byteCount, 42)
        XCTAssertNil(defaults.data(forKey: "PerformanceRecentTabSwitchEventsV1"))
    }

    @MainActor
    func testTabSwitchPerformanceEventRetainsEndToEndStages() throws {
        let monitor = EditorPerformanceMonitor(defaults: defaults)
        let id = UUID()
        monitor.beginTabSwitch(tabID: id)
        monitor.markLoadedTabStateApplied(tabID: id)
        monitor.markSwiftUIEditorUpdated(tabID: id)
        monitor.markViewportLoaded(tabID: id)
        monitor.markTabSwitchFirstDraw(tabID: id)

        let event = try XCTUnwrap(monitor.recentTabSwitchEvents().last)
        XCTAssertNotNil(event.loadedStateMilliseconds)
        XCTAssertNotNil(event.swiftUIUpdateMilliseconds)
        XCTAssertNotNil(event.viewportMilliseconds)
        XCTAssertLessThanOrEqual(try XCTUnwrap(event.loadedStateMilliseconds), event.elapsedMilliseconds)
        XCTAssertLessThanOrEqual(try XCTUnwrap(event.swiftUIUpdateMilliseconds), event.elapsedMilliseconds)
        XCTAssertLessThanOrEqual(try XCTUnwrap(event.viewportMilliseconds), event.elapsedMilliseconds)
    }

    @MainActor
    func testRapidPreferenceUpdatesCoalesceAndPersistTheLatestValue() async {
        let counter = PreferenceWriteCounter()
        let releaseFirstWrite = DispatchSemaphore(value: 0)
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: nil
        ) { _ in
            counter.increment()
            if counter.count == 1 { _ = releaseFirstWrite.wait(timeout: .now() + 5) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        for index in 0..<100 {
            EditorPreferenceWriter.shared.set(.paths([String(index)]), forKey: "coalesced", defaults: defaults)
        }
        XCTAssertEqual(EditorPreferenceWriter.shared.object(forKey: "coalesced", defaults: defaults) as? [String], ["99"])
        releaseFirstWrite.signal()
        await EditorPreferenceWriter.shared.flush()
        XCTAssertEqual(defaults.stringArray(forKey: "coalesced"), ["99"])
        XCTAssertGreaterThan(counter.count, 0)
        XCTAssertLessThanOrEqual(counter.count, 2)
    }

    private func makeFile(named name: String) throws -> URL {
        let url = temporaryDirectoryURL.appendingPathComponent(name)
        try "sample".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private nonisolated final class PreferenceWriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
