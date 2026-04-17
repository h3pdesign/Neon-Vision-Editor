import Foundation
import SwiftUI



/// MARK: - Types

enum ReleaseRuntimePolicy {
    static let safeModeFailureThreshold = 2

    static var isUpdaterEnabledForCurrentDistribution: Bool {
#if os(macOS)
        return !isMacAppStoreDistribution
#else
        return false
#endif
    }

#if os(macOS)
    static var isMacAppStoreDistribution: Bool {
#if APP_STORE_BUILD
        return true
#else
        if isForcedAppStoreDistributionForCurrentProcess {
            return true
        }
        let receiptDirectoryURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("_MASReceipt", isDirectory: true)
        let fileManager = FileManager.default
        let receiptURL = receiptDirectoryURL.appendingPathComponent("receipt", isDirectory: false)
        if fileManager.fileExists(atPath: receiptURL.path) {
            return true
        }
        let sandboxReceiptURL = receiptDirectoryURL.appendingPathComponent("sandboxReceipt", isDirectory: false)
        return fileManager.fileExists(atPath: sandboxReceiptURL.path)
#endif
    }

    private static var isForcedAppStoreDistributionForCurrentProcess: Bool {
        let processInfo = ProcessInfo.processInfo
        let environmentValue = processInfo.environment["APP_DISTRIBUTOR_ID_OVERRIDE"]
        let argumentValue = processInfo.arguments
            .first(where: { $0.hasPrefix("APP_DISTRIBUTOR_ID_OVERRIDE=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
        let distributor = (environmentValue ?? argumentValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return distributor == "com.apple.appstore"
    }
#endif

    static func settingsTab(from requested: String?) -> String {
        let trimmed = requested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "general" : trimmed
    }

    static func preferredColorScheme(for appearance: String) -> ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    static func nextFindMatch(
        in source: String,
        query: String,
        useRegex: Bool,
        caseSensitive: Bool,
        cursorLocation: Int
    ) -> (range: NSRange, nextCursorLocation: Int)? {
        guard !query.isEmpty else { return nil }
        let ns = source as NSString
        let clampedStart = min(max(0, cursorLocation), ns.length)
        let forwardRange = NSRange(location: clampedStart, length: max(0, ns.length - clampedStart))
        let wrapRange = NSRange(location: 0, length: max(0, clampedStart))

        let match: NSRange?
        if useRegex {
            guard let regex = try? NSRegularExpression(
                pattern: query,
                options: caseSensitive ? [] : [.caseInsensitive]
            ) else {
                return nil
            }
            match = regex.firstMatch(in: source, options: [], range: forwardRange)?.range
                ?? regex.firstMatch(in: source, options: [], range: wrapRange)?.range
        } else {
            let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            match = ns.range(of: query, options: options, range: forwardRange).toOptional()
                ?? ns.range(of: query, options: options, range: wrapRange).toOptional()
        }

        guard let found = match else { return nil }
        return (range: found, nextCursorLocation: found.upperBound)
    }

    static func subscriptionButtonsEnabled(
        canUseInAppPurchases: Bool,
        isPurchasing: Bool,
        isLoadingProducts: Bool
    ) -> Bool {
        canUseInAppPurchases && !isPurchasing && !isLoadingProducts
    }

    static func shouldEnterSafeMode(
        consecutiveFailedLaunches: Int,
        requestedManually: Bool
    ) -> Bool {
        requestedManually || consecutiveFailedLaunches >= safeModeFailureThreshold
    }

    static func safeModeStartupMessage(
        consecutiveFailedLaunches: Int,
        requestedManually: Bool
    ) -> String? {
        guard shouldEnterSafeMode(
            consecutiveFailedLaunches: consecutiveFailedLaunches,
            requestedManually: requestedManually
        ) else {
            return nil
        }
        if requestedManually {
            return "Safe Mode is active for this launch. Session restore and startup diagnostics are paused."
        }
        return "Safe Mode is active because the last \(consecutiveFailedLaunches) launch attempts did not finish cleanly. Session restore and startup diagnostics are paused."
    }
}
