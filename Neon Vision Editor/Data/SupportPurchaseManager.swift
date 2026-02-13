import Foundation
import Combine
import StoreKit

@MainActor
final class SupportPurchaseManager: ObservableObject {
    static let supportProductID = "h3p.neon-vision-editor.support.optional"

    @Published private(set) var supportProduct: Product?
    @Published private(set) var hasSupported: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var canUseInAppPurchases: Bool = false
    @Published private(set) var allowsTestingBypass: Bool = false
    @Published var statusMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?
    private let bypassDefaultsKey = "SupportPurchaseBypassEnabled"
    
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
        supportProduct?.displayPrice ?? "$4.99"
    }

    var canBypassInCurrentBuild: Bool {
        allowsTestingBypass
    }

    func refreshStoreState() async {
        await refreshBypassEligibility()
        await refreshProducts(showStatusOnFailure: false)
        await refreshSupportEntitlement()
    }

    func bypassForTesting() {
        guard canBypassInCurrentBuild else { return }
        UserDefaults.standard.set(true, forKey: bypassDefaultsKey)
        hasSupported = true
        statusMessage = "Support purchase bypass enabled for TestFlight/Sandbox testing."
    }

    func clearBypassForTesting() {
        UserDefaults.standard.removeObject(forKey: bypassDefaultsKey)
        Task { await refreshSupportEntitlement() }
    }

    func refreshProducts(showStatusOnFailure: Bool = true) async {
        guard canUseInAppPurchases else {
            supportProduct = nil
            isLoadingProducts = false
            return
        }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: [Self.supportProductID])
            supportProduct = products.first
            if supportProduct == nil, showStatusOnFailure {
                statusMessage = "Support purchase is temporarily unavailable. Please try again later."
            }
        } catch {
            if showStatusOnFailure {
                statusMessage = "Failed to load App Store products: \(error.localizedDescription)"
            }
        }
    }

    func purchaseSupport() async {
        guard canUseInAppPurchases else {
            statusMessage = "In-app purchase is only available in App Store/TestFlight builds."
            return
        }
        guard let product = supportProduct else {
            statusMessage = "Support purchase is currently unavailable."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try verify(verificationResult)
                await transaction.finish()
                await refreshSupportEntitlement()
                statusMessage = "Thank you for supporting Neon Vision Editor."
            case .pending:
                statusMessage = "Purchase is pending approval."
            case .userCancelled:
                statusMessage = "Purchase canceled."
            @unknown default:
                statusMessage = "Purchase did not complete."
            }
        } catch {
            statusMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        guard canUseInAppPurchases else {
            statusMessage = "Restore is only available in App Store/TestFlight builds."
            return
        }
        do {
            try await AppStore.sync()
            await refreshBypassEligibility()
            await refreshSupportEntitlement()
            statusMessage = hasSupported ? "Support purchase restored." : "No support purchase found to restore."
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func refreshSupportEntitlement() async {
        if canBypassInCurrentBuild && UserDefaults.standard.bool(forKey: bypassDefaultsKey) {
            hasSupported = true
            return
        }
        var supported = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.supportProductID {
                supported = true
                break
            }
        }
        hasSupported = supported
    }

    private func refreshBypassEligibility() async {
        do {
            let appTransactionResult = try await AppTransaction.shared
            switch appTransactionResult {
            case .verified(let appTransaction):
                canUseInAppPurchases = true
                allowsTestingBypass = shouldAllowTestingBypass(environment: appTransaction.environment)
            case .unverified:
                canUseInAppPurchases = false
                allowsTestingBypass = false
            }
        } catch {
            canUseInAppPurchases = false
            allowsTestingBypass = false
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                do {
                    let transaction = try self.verify(result)
                    await transaction.finish()
                    await self.refreshSupportEntitlement()
                } catch {
                    await MainActor.run {
                        self.statusMessage = "Transaction verification failed."
                    }
                }
            }
        }
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw SupportPurchaseError.failedVerification
        }
    }
}

enum SupportPurchaseError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction could not be verified."
        }
    }
}
