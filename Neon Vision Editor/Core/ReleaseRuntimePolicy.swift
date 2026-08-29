import Foundation
import SwiftUI



// MARK: - Types

enum ReleaseRuntimePolicy {
    static let safeModeFailureThreshold = 2

    struct FindSearchResult: Equatable, Sendable {
        let ranges: [NSRange]
        let errorMessage: String?

        var isValid: Bool { errorMessage == nil }
    }

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
        cursorLocation: Int,
        wholeWord: Bool = false
    ) -> (range: NSRange, nextCursorLocation: Int)? {
        let result = findMatches(
            in: source,
            query: query,
            useRegex: useRegex,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord
        )
        guard result.isValid,
              let index = initialFindMatchIndex(in: result.ranges, caretLocation: cursorLocation) else {
            return nil
        }
        let found = result.ranges[index]
        let sourceLength = (source as NSString).length
        let nextLocation = found.length > 0
            ? found.upperBound
            : min(sourceLength, found.location + 1)
        return (range: found, nextCursorLocation: nextLocation)
    }

    nonisolated static func findMatches(
        in source: String,
        query: String,
        useRegex: Bool,
        caseSensitive: Bool,
        wholeWord: Bool = false
    ) -> FindSearchResult {
        guard !query.isEmpty else { return FindSearchResult(ranges: [], errorMessage: nil) }
        let sourceRange = NSRange(location: 0, length: (source as NSString).length)
        let pattern: String
        if useRegex {
            pattern = query
        } else if wholeWord {
            pattern = "(?<![\\p{L}\\p{N}_])\(NSRegularExpression.escapedPattern(for: query))(?![\\p{L}\\p{N}_])"
        } else {
            let nsSource = source as NSString
            let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            var ranges: [NSRange] = []
            var searchRange = sourceRange
            while searchRange.length > 0 {
                let found = nsSource.range(of: query, options: options, range: searchRange)
                guard found.location != NSNotFound else { break }
                ranges.append(found)
                let nextLocation = found.location + max(found.length, 1)
                guard nextLocation < nsSource.length else { break }
                searchRange = NSRange(location: nextLocation, length: nsSource.length - nextLocation)
            }
            return FindSearchResult(ranges: ranges, errorMessage: nil)
        }

        do {
            let expression = try NSRegularExpression(
                pattern: pattern,
                options: caseSensitive ? [] : [.caseInsensitive]
            )
            return FindSearchResult(
                ranges: expression.matches(in: source, options: [], range: sourceRange).map(\.range),
                errorMessage: nil
            )
        } catch {
            return FindSearchResult(ranges: [], errorMessage: "Invalid regular expression")
        }
    }

    static func initialFindMatchIndex(in ranges: [NSRange], caretLocation: Int) -> Int? {
        guard !ranges.isEmpty else { return nil }
        let caret = max(0, caretLocation)
        return ranges.firstIndex(where: { range in
            NSLocationInRange(caret, range) || range.location >= caret
        }) ?? 0
    }

    static func movedFindMatchIndex(currentIndex: Int?, matchCount: Int, delta: Int) -> Int? {
        guard matchCount > 0 else { return nil }
        guard let currentIndex else { return delta < 0 ? matchCount - 1 : 0 }
        let current = min(max(0, currentIndex), matchCount - 1)
        return (current + delta + matchCount) % matchCount
    }

    static func replacementForFindMatch(
        in source: String,
        range: NSRange,
        query: String,
        replacement: String,
        useRegex: Bool,
        caseSensitive: Bool,
        wholeWord: Bool = false
    ) -> String? {
        let nsSource = source as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= nsSource.length else { return nil }
        let selectedText = nsSource.substring(with: range)
        if useRegex {
            guard let expression = try? NSRegularExpression(
                pattern: query,
                options: caseSensitive ? [] : [.caseInsensitive]
            ) else { return nil }
            let selectedRange = NSRange(location: 0, length: (selectedText as NSString).length)
            guard let match = expression.firstMatch(in: selectedText, options: [], range: selectedRange),
                  match.range == selectedRange else { return nil }
            return expression.stringByReplacingMatches(
                in: selectedText,
                options: [],
                range: selectedRange,
                withTemplate: replacement
            )
        }
        let result = findMatches(
            in: selectedText,
            query: query,
            useRegex: false,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord
        )
        guard result.ranges == [NSRange(location: 0, length: range.length)] else { return nil }
        return replacement
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
            return "Safe Mode is active for this launch. Session restore, startup diagnostics, Markdown preview, and code minimap are paused."
        }
        return "Safe Mode is active because the last \(consecutiveFailedLaunches) launch attempts did not finish cleanly. Session restore, startup diagnostics, Markdown preview, and code minimap are paused."
    }
}
