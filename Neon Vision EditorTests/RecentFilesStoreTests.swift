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
    func testRememberOrdersMostRecentFirst() throws {
        let first = try makeFile(named: "first.txt")
        let second = try makeFile(named: "second.txt")

        RecentFilesStore.remember(first, defaults: defaults)
        RecentFilesStore.remember(second, defaults: defaults)

        XCTAssertEqual(RecentFilesStore.items(limit: 10, defaults: defaults).map(\.title), ["second.txt", "first.txt"])
    }

    @MainActor
    func testPinnedItemsStayAtTop() throws {
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
    }

    @MainActor
    func testClearUnpinnedRetainsPinnedItems() throws {
        let pinned = try makeFile(named: "pinned.txt")
        let unpinned = try makeFile(named: "unpinned.txt")

        RecentFilesStore.remember(pinned, defaults: defaults)
        RecentFilesStore.remember(unpinned, defaults: defaults)
        RecentFilesStore.togglePinned(pinned, defaults: defaults)
        RecentFilesStore.clearUnpinned(defaults: defaults)

        XCTAssertEqual(RecentFilesStore.items(limit: 10, defaults: defaults).map(\.title), ["pinned.txt"])
    }

    private func makeFile(named name: String) throws -> URL {
        let url = temporaryDirectoryURL.appendingPathComponent(name)
        try "sample".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
