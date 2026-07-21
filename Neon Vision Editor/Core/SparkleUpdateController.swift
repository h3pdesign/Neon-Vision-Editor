import Foundation

#if os(macOS)
#if APP_STORE_BUILD
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

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private init() {}

    func checkForUpdates() {
        guard ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution else { return }
        controller.checkForUpdates(nil)
    }
}
#endif
#endif
