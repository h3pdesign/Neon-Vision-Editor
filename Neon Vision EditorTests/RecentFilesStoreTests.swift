import XCTest
@testable import Neon_Vision_Editor

final class RecentFilesStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        clearStore()
    }

    override func tearDownWithError() throws {
        clearStore()
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
    }

    func testRememberOrdersMostRecentFirst() throws {
        let first = try makeFile(named: "first.txt")
        let second = try makeFile(named: "second.txt")

        RecentFilesStore.remember(first)
        RecentFilesStore.remember(second)

        XCTAssertEqual(RecentFilesStore.items(limit: 10).map(\.title), ["second.txt", "first.txt"])
    }

    func testPinnedItemsStayAtTop() throws {
        let first = try makeFile(named: "first.txt")
        let second = try makeFile(named: "second.txt")
        let third = try makeFile(named: "third.txt")

        RecentFilesStore.remember(first)
        RecentFilesStore.remember(second)
        RecentFilesStore.remember(third)
        RecentFilesStore.togglePinned(first)

        let items = RecentFilesStore.items(limit: 10)
        XCTAssertEqual(items.map(\.title), ["first.txt", "third.txt", "second.txt"])
        XCTAssertEqual(items.first?.isPinned, true)
    }

    func testClearUnpinnedRetainsPinnedItems() throws {
        let pinned = try makeFile(named: "pinned.txt")
        let unpinned = try makeFile(named: "unpinned.txt")

        RecentFilesStore.remember(pinned)
        RecentFilesStore.remember(unpinned)
        RecentFilesStore.togglePinned(pinned)
        RecentFilesStore.clearUnpinned()

        XCTAssertEqual(RecentFilesStore.items(limit: 10).map(\.title), ["pinned.txt"])
    }

    private func makeFile(named name: String) throws -> URL {
        let url = temporaryDirectoryURL.appendingPathComponent(name)
        try "sample".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func clearStore() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "RecentFilesPathsV1")
        defaults.removeObject(forKey: "PinnedRecentFilesPathsV1")
    }
}
