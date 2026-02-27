import Foundation
import Combine
import StoreKit

///MARK: - Support Purchase Manager
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
    @Published private(set) var allowsTestingBypass: Bool = false
    @Published private(set) var lastSuccessfulPriceRefreshAt: Date?
    @Published private(set) var lastProductFetchAttemptAt: Date?
    @Published private(set) var lastProductFetchErrorDescription: String?
    @Published var statusMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?
    private let bypassDefaultsKey = "SupportPurchaseBypassEnabled"
    
    // Allows bypass in simulator/debug environments for testing purchase-gated UI.
    private func shouldAllowTestingBypass(environment: AppStore.Environment) -> Bool {
#if targetEnvironment(simulator)
        return true
#elseif DEBUG
        return true
#else
        _ = environment
        return false
#endif
    }

    init() {
        transactionUpdatesTask = observeTransactionUpdates()
        Task {
            await refreshStoreState()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var supportPriceLabel: String {
        supportProduct?.displayPrice ?? NSLocalizedString("Unavailable", comment: "")
    }

    var canBypassInCurrentBuild: Bool {
        allowsTestingBypass
    }

    var hasExternalSupportFallback: Bool {
        Self.externalSupportURL != nil
    }

    var supportProductLoaded: Bool {
        supportProduct != nil
    }

    // Refreshes StoreKit capability and product metadata.
    func refreshStoreState() async {
        await refreshBypassEligibility()
        await refreshProducts(showStatusOnFailure: false)
    }

    // Enables testing bypass where allowed.
    func bypassForTesting() {
        guard canBypassInCurrentBuild else { return }
        UserDefaults.standard.set(true, forKey: bypassDefaultsKey)
        hasSupported = true
        statusMessage = NSLocalizedString("Support purchase bypass enabled for TestFlight/Sandbox testing.", comment: "")
    }

    // Clears testing bypass.
    func clearBypassForTesting() {
        UserDefaults.standard.removeObject(forKey: bypassDefaultsKey)
        hasSupported = false
    }

    // Loads support product metadata from App Store.
    func refreshProducts(showStatusOnFailure: Bool = true) async {
        guard canUseInAppPurchases else {
            supportProduct = nil
            isLoadingProducts = false
            lastProductFetchErrorDescription = nil
            if showStatusOnFailure {
#if os(iOS)
                if !AppStore.canMakePayments {
                    statusMessage = NSLocalizedString("In-App Purchases are disabled on this device. Check App Store login and Screen Time restrictions.", comment: "")
                } else {
                    statusMessage = NSLocalizedString("App Store pricing is only available in App Store/TestFlight builds.", comment: "")
                }
#else
                statusMessage = NSLocalizedString("App Store pricing is only available in App Store/TestFlight builds.", comment: "")
#endif
            }
            return
        }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        lastProductFetchAttemptAt = Date()
        let maxAttempts = 3
        var latestError: Error?
        var productMissing = false

        for attempt in 1...maxAttempts {
            do {
                let products = try await Product.products(for: [Self.supportProductID])
                supportProduct = products.first
                if supportProduct != nil {
                    lastSuccessfulPriceRefreshAt = Date()
                    lastProductFetchErrorDescription = nil
                    statusMessage = nil
                    return
                }
                productMissing = true
            } catch {
                latestError = error
                lastProductFetchErrorDescription = error.localizedDescription
            }

            if attempt < maxAttempts {
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                } catch {
                    break
                }
            }
        }

        supportProduct = nil
        if showStatusOnFailure {
            statusMessage = productLoadFailureMessage(fetchError: latestError, productWasMissing: productMissing)
        }
    }

    // Refreshes in-app purchase availability and product pricing for settings UI.
    func refreshPrice() async {
        statusMessage = nil
        await refreshBypassEligibility()
        await refreshProducts(showStatusOnFailure: true)
    }

    // Starts purchase flow for the optional support product.
    func purchaseSupport() async {
        // Prevent overlapping StoreKit purchase flows that can race and surface misleading cancel states.
        guard !isPurchasing else { return }
        guard canUseInAppPurchases else {
#if os(iOS)
            if !AppStore.canMakePayments {
                statusMessage = NSLocalizedString("In-App Purchases are disabled on this device. Check App Store login and Screen Time restrictions.", comment: "")
            } else {
                statusMessage = NSLocalizedString("In-app purchase is only available in App Store/TestFlight builds. Use external support in direct distribution.", comment: "")
            }
#else
            statusMessage = NSLocalizedString("In-app purchase is only available in App Store/TestFlight builds. Use external support in direct distribution.", comment: "")
#endif
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
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
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

    // Detects whether this build/environment can use in-app purchases.
    private func refreshBypassEligibility() async {
        #if os(iOS) || os(macOS)
        canUseInAppPurchases = AppStore.canMakePayments
        #else
        canUseInAppPurchases = false
        #endif
        do {
            let appTransactionResult = try await AppTransaction.shared
            switch appTransactionResult {
            case .verified(let appTransaction):
#if os(iOS) || os(macOS)
                switch appTransaction.environment {
                case .production, .sandbox:
                    canUseInAppPurchases = AppStore.canMakePayments
                case .xcode:
#if targetEnvironment(simulator) || DEBUG
                    canUseInAppPurchases = AppStore.canMakePayments
#else
                    canUseInAppPurchases = false
#endif
                default:
                    canUseInAppPurchases = AppStore.canMakePayments
                }
#else
                canUseInAppPurchases = false
#endif
                allowsTestingBypass = shouldAllowTestingBypass(environment: appTransaction.environment)
            case .unverified:
                canUseInAppPurchases = AppStore.canMakePayments
                allowsTestingBypass = false
            }
        } catch {
            #if os(iOS) || os(macOS)
            canUseInAppPurchases = AppStore.canMakePayments
            #else
            canUseInAppPurchases = false
            #endif
            allowsTestingBypass = false
        }

#if targetEnvironment(simulator) || DEBUG
        if !allowsTestingBypass {
            allowsTestingBypass = true
        }
#endif
    }

    // Listens for transaction updates and applies verified changes.
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
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

    private func productLoadFailureMessage(fetchError: Error?, productWasMissing: Bool) -> String {
        if productWasMissing {
            let format = NSLocalizedString(
                "App Store did not return product %@. Check App Store Connect and TestFlight availability.",
                comment: ""
            )
            return String(format: format, Self.supportProductID)
        }

        if let urlError = fetchError as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return NSLocalizedString("Could not reach the App Store. Check network connection and try Retry App Store.", comment: "")
            default:
                break
            }
        }

        if let fetchError {
            let format = NSLocalizedString("Failed to load App Store products: %@", comment: "")
            return String(format: format, fetchError.localizedDescription)
        }

        return NSLocalizedString("Support purchase is currently unavailable.", comment: "")
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

///MARK: - StoreKit Errors
enum SupportPurchaseError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction could not be verified."
        }
    }
}
