import Foundation

#if os(macOS)
#if APP_STORE_BUILD || !canImport(Sparkle)
/// The Mac App Store distributes updates itself, so its build does not link Sparkle.
@MainActor
final class SparkleUpdateController {
    static let shared = SparkleUpdateController()

    private init() {}

    func checkForUpdates() {}
}
#else
import Sparkle

/// Owns the supported sandbox-aware updater for direct macOS distribution.
@MainActor
final class SparkleUpdateController {
    static let shared = SparkleUpdateController()

    private let updaterDelegate: SparkleUpdateDelegate
    private let controller: SPUStandardUpdaterController

    private init() {
        updaterDelegate = SparkleUpdateDelegate()
        updaterDelegate.removeStaleTemporaryUpdates()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution else { return }
        controller.checkForUpdates(nil)
    }
}

@MainActor
private final class SparkleUpdateDelegate: NSObject, SPUUpdaterDelegate {
    private let temporaryUpdatePrefix = "nve-update-"
    private let staleUpdateAge: TimeInterval = 60 * 60

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        removeTemporaryUpdates()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        removeTemporaryUpdates()
    }

    func removeStaleTemporaryUpdates() {
        removeTemporaryUpdates(olderThan: staleUpdateAge)
    }

    private func removeTemporaryUpdates(olderThan age: TimeInterval = 0) {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        guard let entries = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-age)
        for entry in entries where entry.lastPathComponent.hasPrefix(temporaryUpdatePrefix) {
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  values.isDirectory == true,
                  age == 0 || (values.contentModificationDate ?? .distantPast) < cutoff else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }
}
#endif
#endif
