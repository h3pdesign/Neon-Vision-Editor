import XCTest
import StoreKit
import StoreKitTest
@testable import Neon_Vision_Editor

@MainActor
final class SupportPurchaseManagerTests: XCTestCase {
    private func makeSession() throws -> SKTestSession {
        let configuration = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Neon Vision Editor/SupportOptional.storekit")
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    func testLocalStoreKitLoadsPriceAndCompletesConsumablePurchase() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let manager = SupportPurchaseManager(canMakePayments: { true })
        await manager.refreshStoreState()
        let product = try XCTUnwrap(manager.supportProduct)
        XCTAssertEqual(product.id, SupportPurchaseManager.supportProductID)
        XCTAssertEqual(manager.availableSupportPriceLabel, product.displayPrice)
        XCTAssertFalse(manager.shouldShowPriceRetry)
        await manager.purchaseSupport { try await $0.purchase() }
        XCTAssertTrue(manager.hasSupported)
        XCTAssertFalse(manager.isPurchasing)
    }

    func testFailedLookupDoesNotSuppressNextSupportVisit() async {
        var attempts = 0
        let manager = SupportPurchaseManager(loadProducts: {
            attempts += 1
            return []
        }, canMakePayments: { true })
        await manager.refreshStoreStateIfStale()
        let initialAttempts = attempts
        XCTAssertGreaterThan(initialAttempts, 0)
        XCTAssertTrue(manager.shouldShowPriceRetry)
        XCTAssertNil(manager.lastSuccessfulPriceRefreshAt)
        await manager.refreshStoreStateIfStale()
        XCTAssertGreaterThan(attempts, initialAttempts)
        XCTAssertFalse(manager.isLoadingProducts)
    }

    func testRestrictedPaymentsStillLoadMetadataAndNeverPurchase() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let manager = SupportPurchaseManager(canMakePayments: { false })
        await manager.refreshStoreState()
        XCTAssertNotNil(manager.supportProduct)
        XCTAssertTrue(manager.shouldShowStoreUnavailableMessage)
        await manager.purchaseSupport { _ in
            XCTFail("A restricted account must not enter the payment sheet")
            return .pending
        }
        XCTAssertFalse(manager.isPurchasing)
    }

    func testPurchaseWaitsForSharedLookupAndRejectsOverlappingPurchase() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [SupportPurchaseManager.supportProductID])
        XCTAssertFalse(products.isEmpty)
        var resumeLookup: CheckedContinuation<Void, Never>?
        var lookups = 0
        var purchases = 0
        let started = expectation(description: "Product request started")
        let manager = SupportPurchaseManager(loadProducts: {
            lookups += 1
            await withCheckedContinuation { continuation in
                resumeLookup = continuation
                started.fulfill()
            }
            return products
        }, canMakePayments: { true })
        let refresh = Task { await manager.refreshStoreState() }
        await fulfillment(of: [started], timeout: 2)
        let purchase = Task {
            await manager.purchaseSupport { _ in
                purchases += 1
                return .pending
            }
        }
        // Yield until the purchase owns its guard, while lookup remains suspended.
        for _ in 0..<100 where !manager.isPurchasing { await Task.yield() }
        XCTAssertTrue(manager.isPurchasing)
        XCTAssertEqual(purchases, 0)
        await manager.purchaseSupport { _ in
            XCTFail("Overlapping purchase must not enter StoreKit")
            return .pending
        }
        resumeLookup?.resume()
        await refresh.value
        await purchase.value
        XCTAssertEqual(lookups, 1)
        XCTAssertEqual(purchases, 1)
        XCTAssertFalse(manager.isLoadingProducts)
        XCTAssertFalse(manager.isPurchasing)
    }

    func testSuccessfulPriceSurvivesFailedRefreshAndFreshCacheSkipsLookup() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [SupportPurchaseManager.supportProductID])
        var lookups = 0
        let manager = SupportPurchaseManager(loadProducts: {
            lookups += 1
            return lookups == 1 ? products : []
        }, canMakePayments: { true })
        await manager.refreshStoreState()
        let price = try XCTUnwrap(manager.availableSupportPriceLabel)
        await manager.refreshStoreStateIfStale()
        XCTAssertEqual(lookups, 1)
        await manager.refreshPrice()
        XCTAssertEqual(manager.availableSupportPriceLabel, price)
        XCTAssertNil(manager.statusMessage)
    }

    func testCancelledLookupResetsLoadingAndCanBeRetried() async {
        var lookups = 0
        let manager = SupportPurchaseManager(loadProducts: {
            lookups += 1
            throw CancellationError()
        }, canMakePayments: { true })
        await manager.refreshStoreState()
        XCTAssertFalse(manager.isLoadingProducts)
        XCTAssertNil(manager.statusMessage)
        await manager.refreshStoreStateIfStale()
        XCTAssertEqual(lookups, 2)
    }

    func testTransactionObserverDoesNotRetainManager() async {
        weak var releasedManager: SupportPurchaseManager?
        do {
            let manager = SupportPurchaseManager(loadProducts: { [] }, canMakePayments: { true })
            releasedManager = manager
            await Task.yield()
        }
        XCTAssertNil(releasedManager)
    }
}
