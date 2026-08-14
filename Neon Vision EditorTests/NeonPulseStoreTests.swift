import XCTest
@testable import Neon_Vision_Editor

nonisolated final class NeonPulseStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        suiteName = "NeonPulseStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    @MainActor
    func testCaptureIsTrimmedPersistedAndMarkedDelivered() throws {
        let store = NeonPulseStore(defaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let capture = try XCTUnwrap(store.addCapture(text: "  Fix preview handoff  ", now: createdAt))

        XCTAssertEqual(store.captures().first?.text, "Fix preview handoff")
        XCTAssertEqual(store.captures().first?.createdAt, createdAt)
        XCTAssertNil(store.captures().first?.deliveredAt)

        store.markDelivered(id: capture.id, at: createdAt.addingTimeInterval(5))
        XCTAssertEqual(store.captures().first?.deliveredAt, createdAt.addingTimeInterval(5))
    }

    @MainActor
    func testEmptyCaptureIsRejected() {
        let store = NeonPulseStore(defaults: defaults)
        XCTAssertNil(store.addCapture(text: " \n "))
        XCTAssertTrue(store.captures().isEmpty)
    }

    @MainActor
    func testStatusRoundTrips() {
        let store = NeonPulseStore(defaults: defaults)
        let status = NeonPulseStatus(
            projectName: "Sample",
            currentDocument: "README.md",
            pendingChanges: 3,
            hasConflict: true,
            lastSuccessfulSave: Date(timeIntervalSince1970: 42),
            updatedAt: Date(timeIntervalSince1970: 43)
        )
        store.saveStatus(status)
        XCTAssertEqual(store.status(), status)
    }

    @MainActor
    func testDeliveryReceiptRoundTripsCaptureID() {
        let id = UUID()
        XCTAssertEqual(
            NeonPulseDeliveryReceipt.captureID(from: NeonPulseDeliveryReceipt.payload(for: id)),
            id
        )
        XCTAssertNil(NeonPulseDeliveryReceipt.captureID(from: [:]))
    }

    @MainActor
    func testInboxWriterCreatesAndAppendsMarkdownFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeonPulseInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = NeonPulseCapture(text: "First note", createdAt: Date(timeIntervalSince1970: 10))
        let second = NeonPulseCapture(text: "Second\nnote", createdAt: Date(timeIntervalSince1970: 20))

        XCTAssertNotNil(NeonPulseInboxWriter.append(first, to: directory))
        XCTAssertNotNil(NeonPulseInboxWriter.append(second, to: directory))

        let inboxURL = directory.appendingPathComponent(NeonPulseConstants.inboxFilename)
        XCTAssertEqual(inboxURL.lastPathComponent, "Neon Inbox.md")
        let contents = try String(contentsOf: inboxURL, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("# Neon Inbox\n"))
        XCTAssertTrue(contents.contains("- [ ] First note"))
        XCTAssertTrue(contents.contains("- [ ] Second note"))
    }

}
