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
            if showStatusOnFailure {
                statusMessage = NSLocalizedString("App Store pricing is currently unavailable.", comment: "")
            }
            return
        }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: [Self.supportProductID])
            supportProduct = products.first
            if supportProduct != nil {
                lastSuccessfulPriceRefreshAt = Date()
                statusMessage = nil
            }
            if supportProduct == nil, showStatusOnFailure {
                let format = NSLocalizedString(
                    "App Store did not return product %@. Check App Store Connect and TestFlight availability.",
                    comment: ""
                )
                statusMessage = String(format: format, Self.supportProductID)
            }
        } catch {
            if showStatusOnFailure {
                let format = NSLocalizedString("Failed to load App Store products: %@", comment: "")
                statusMessage = String(format: format, error.localizedDescription)
            }
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

    // Detects whether this device can use in-app purchases.
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
