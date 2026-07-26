import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class NeonPulseStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "NeonPulseStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

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

    func testEmptyCaptureIsRejected() {
        let store = NeonPulseStore(defaults: defaults)
        XCTAssertNil(store.addCapture(text: " \n "))
        XCTAssertTrue(store.captures().isEmpty)
    }

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
}
