import Foundation
import SwiftUI

enum ReleaseRuntimePolicy {
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
}
