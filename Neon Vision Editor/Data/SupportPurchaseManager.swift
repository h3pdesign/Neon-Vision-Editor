import Foundation
import Combine
import StoreKit

// MARK: - Support Purchase Manager
// Handles optional consumable support purchase state via StoreKit.
@MainActor
final class SupportPurchaseManager: ObservableObject {
    static let supportProductID = "002420160"
    static let externalSupportURL = URL(string: "https://www.patreon.com/h3p")

    @Published private(set) var supportProduct: Product?
    @Published private(set) var hasSupported: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var canUseInAppPurchases: Bool = false
    @Published private(set) var hasCheckedStoreAvailability: Bool = false
    @Published private(set) var lastSuccessfulPriceRefreshAt: Date?
    @Published var statusMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?
    private var productLoadTask: Task<Void, Never>?
    private let loadProducts: @MainActor () async throws -> [Product]
    private let canMakePayments: @MainActor () -> Bool
    private let storeStateFreshnessInterval: TimeInterval = 300
    private let productLookupAttempts = 3

    init(
        loadProducts: @escaping @MainActor () async throws -> [Product] = {
            try await Product.products(for: [SupportPurchaseManager.supportProductID])
        },
        canMakePayments: @escaping @MainActor () -> Bool = { AppStore.canMakePayments }
    ) {
        self.loadProducts = loadProducts
        self.canMakePayments = canMakePayments
        transactionUpdatesTask = observeTransactionUpdates()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var availableSupportPriceLabel: String? {
        supportProduct?.displayPrice
    }

    var supportPurchaseButtonTitle: String {
        guard let price = availableSupportPriceLabel else {
            return NSLocalizedString("Send Support Tip", comment: "")
        }
        let format = NSLocalizedString("Send Support Tip — %@", comment: "")
        return String(format: format, price)
    }

    var supportTipDialogButtonTitle: String {
        guard let price = availableSupportPriceLabel else {
            return NSLocalizedString("Send Support Tip", comment: "")
        }
        let format = NSLocalizedString("Send Tip %@", comment: "")
        return String(format: format, price)
    }

    var shouldShowStoreUnavailableMessage: Bool {
        hasCheckedStoreAvailability && !canUseInAppPurchases
    }

    /// Shows a manual recovery action only after StoreKit is available but did
    /// not return the support product. Loading and capability failures are
    /// represented by their own status in the price card instead.
    var shouldShowPriceRetry: Bool {
        hasCheckedStoreAvailability
            && canUseInAppPurchases
            && supportProduct == nil
            && !isLoadingProducts
    }

    // Refreshes StoreKit capability and product metadata.
    func refreshStoreState() async {
        refreshPurchaseAvailability()
        await refreshProducts(showStatusOnFailure: false)
    }

    // Refreshes only when the cached StoreKit state is stale or unavailable.
    func refreshStoreStateIfStale() async {
        refreshPurchaseAvailability()
        if supportProduct != nil, let lastSuccessfulPriceRefreshAt,
           Date().timeIntervalSince(lastSuccessfulPriceRefreshAt) < storeStateFreshnessInterval {
            return
        }
        await refreshStoreState()
    }

    // Loads support product metadata from App Store.
    func refreshProducts(showStatusOnFailure: Bool = true) async {
        if let productLoadTask {
            await productLoadTask.value
            return
        }
        isLoadingProducts = true
        // Keep a shared lookup alive when a settings view disappears. All
        // callers, including purchases, await the same metadata request.
        let task = Task {
            await loadSupportProduct(showStatusOnFailure: showStatusOnFailure)
        }
        productLoadTask = task
        await task.value
        productLoadTask = nil
    }

    private func loadSupportProduct(showStatusOnFailure: Bool) async {
        defer { isLoadingProducts = false }

        // Product metadata can be available even when purchases are disabled by
        // Screen Time or account restrictions. Do not gate the lookup on
        // AppStore.canMakePayments, and do not discard a previously validated
        // product while StoreKit is recovering from a transient response.
        var lastLookupError: Error?
        for attempt in 0..<productLookupAttempts {
            if Task.isCancelled { return }
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 250_000_000)
            }

            do {
                let products = try await loadProducts()
                if let product = products.first(where: { $0.id == Self.supportProductID }) {
                    supportProduct = product
                    lastSuccessfulPriceRefreshAt = Date()
                    statusMessage = nil
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                lastLookupError = error
                continue
            }
        }

        // A missing response is not a reason to erase a price that was already
        // validated in this session. It may be a temporary App Store/sandbox
        // propagation failure; a later refresh can replace the cached value.
        if supportProduct == nil, showStatusOnFailure, let lastLookupError {
            let format = NSLocalizedString("Failed to load App Store products: %@", comment: "")
            statusMessage = String(format: format, lastLookupError.localizedDescription)
        } else if supportProduct == nil, showStatusOnFailure {
            let format = NSLocalizedString(
                "App Store did not return product %@. Check App Store Connect and TestFlight availability.",
                comment: ""
            )
            statusMessage = String(format: format, Self.supportProductID)
        }
    }

    // Refreshes in-app purchase availability and product pricing for settings UI.
    func refreshPrice() async {
        statusMessage = nil
        refreshPurchaseAvailability()
        await refreshProducts(showStatusOnFailure: true)
    }

    // Starts purchase flow for the optional support product.
    func purchaseSupport(using purchase: @MainActor (Product) async throws -> Product.PurchaseResult) async {
        // Prevent overlapping StoreKit purchase flows that can race and surface misleading cancel states.
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        if !hasCheckedStoreAvailability {
            await refreshStoreState()
        }
        guard canUseInAppPurchases else {
            statusMessage = NSLocalizedString("In-App Purchases are currently unavailable on this device. Check App Store login and Screen Time restrictions.", comment: "")
            return
        }
        if supportProduct == nil {
            await refreshProducts(showStatusOnFailure: true)
        }
        guard let product = supportProduct else {
            statusMessage = NSLocalizedString("Support purchase is currently unavailable.", comment: "")
            return
        }

        statusMessage = nil
        let hadSupportedBeforeAttempt = hasSupported
        do {
            let result = try await purchase(product)
            switch result {
            case .success(let verificationResult):
                let transaction = try verify(verificationResult)
                await transaction.finish()
                hasSupported = true
                statusMessage = NSLocalizedString("Thank you for supporting Neon Vision Editor.", comment: "")
            case .pending:
                statusMessage = NSLocalizedString("Purchase is pending approval.", comment: "")
            case .userCancelled:
                // On some devices a verified transaction update may arrive shortly after a cancel-like result.
                // Wait briefly to avoid surfacing a false cancellation state.
                do {
                    try await Task.sleep(nanoseconds: 700_000_000)
                } catch {
                    // Ignore cancellation of the delay; state check below remains safe.
                }
                if !hasSupported && !hadSupportedBeforeAttempt {
                    statusMessage = NSLocalizedString("Purchase canceled.", comment: "")
                }
            @unknown default:
                statusMessage = NSLocalizedString("Purchase did not complete.", comment: "")
            }
        } catch {
            let details = String(describing: error)
            if details == error.localizedDescription {
                let format = NSLocalizedString("Purchase failed: %@", comment: "")
                statusMessage = String(format: format, error.localizedDescription)
            } else {
                let format = NSLocalizedString("Purchase failed: %@ (%@)", comment: "")
                statusMessage = String(format: format, error.localizedDescription, details)
            }
        }
    }

    // Detects whether this device can use in-app purchases.
    private func refreshPurchaseAvailability() {
        // Optional consumable tips have no app-receipt entitlement prerequisite.
        // Product lookup must not wait for AppTransaction.shared to resolve.
        canUseInAppPurchases = canMakePayments()
        hasCheckedStoreAvailability = true
    }

    // Listens for transaction updates and applies verified changes.
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.verify(result)
                    await transaction.finish()
                    await MainActor.run {
                        self.hasSupported = true
                    }
                } catch {
                    await MainActor.run {
                        self.statusMessage = NSLocalizedString("Transaction verification failed.", comment: "")
                    }
                }
            }
        }
    }

    // Enforces StoreKit verification before using transaction payloads.
    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw SupportPurchaseError.failedVerification
        }
    }
}

// MARK: - StoreKit Errors
enum SupportPurchaseError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction could not be verified."
        }
    }
}
