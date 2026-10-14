import XCTest
@testable import Neon_Vision_Editor

final class BoundedLRUCacheTests: XCTestCase {
    func testReadsPromoteAndEvictionHonorsCountAndCost() {
        var cache = BoundedLRUCache<String, String>(maximumCount: 2, maximumCost: 10)
        cache.store("A", for: "a", cost: 4)
        cache.store("B", for: "b", cost: 4)
        XCTAssertEqual(cache.value(for: "a"), "A")
        cache.store("C", for: "c", cost: 4)
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertEqual(cache.value(for: "a"), "A")
        cache.store("large", for: "d", cost: 7)
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.totalCost, 7)
        cache.store("too large", for: "d", cost: 11)
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.totalCost, 0)
    }

    func testReplacementInvalidationAndDisabledCacheReleaseCost() {
        var cache = BoundedLRUCache<Int, Int>(maximumCount: 2, maximumCost: 10)
        cache.store(1, for: 1, cost: 8)
        cache.store(2, for: 1, cost: 2)
        XCTAssertEqual(cache.totalCost, 2)
        cache.store(3, for: 2, cost: 0)
        cache.remove { $0 == 1 }
        XCTAssertEqual(cache.totalCost, 0)
        XCTAssertEqual(cache.count, 1)
        var disabled = BoundedLRUCache<Int, Int>(maximumCount: 0, maximumCost: 10)
        disabled.store(1, for: 1, cost: 1)
        XCTAssertEqual(disabled.count, 0)
    }
}
