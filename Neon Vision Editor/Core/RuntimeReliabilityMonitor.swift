import Foundation
import OSLog

@MainActor


/// MARK: - Types

final class RuntimeReliabilityMonitor {
    struct SafeModeLaunchDecision {
        let isEnabled: Bool
        let message: String?
        let consecutiveFailedLaunches: Int
        let requestedManually: Bool
    }

    static let shared = RuntimeReliabilityMonitor()

    private let logger = Logger(subsystem: "h3p.Neon-Vision-Editor", category: "Reliability")
    private let defaults = UserDefaults.standard
    private let activeRunKey = "Reliability.ActiveRunMarkerV1"
    private let crashBucketPrefix = "Reliability.CrashBucketV1."
    private let consecutiveFailedLaunchesKey = "Reliability.ConsecutiveFailedLaunchesV1"
    private let safeModeNextLaunchKey = "Reliability.SafeModeNextLaunchV1"
    private var watchdogTimer: DispatchSourceTimer?
    private var lastMainThreadPingUptime = ProcessInfo.processInfo.systemUptime

    private init() {}

    func markLaunch() {
        if defaults.bool(forKey: activeRunKey) {
            let key = crashBucketPrefix + currentBucketID()
            let current = defaults.integer(forKey: key)
            defaults.set(current + 1, forKey: key)
            defaults.set(defaults.integer(forKey: consecutiveFailedLaunchesKey) + 1, forKey: consecutiveFailedLaunchesKey)
#if DEBUG
            logger.warning("reliability.previous_run_unfinished bucket=\(self.currentBucketID(), privacy: .public) count=\(current + 1, privacy: .public)")
#endif
        }
        defaults.set(true, forKey: activeRunKey)
    }

    func markGracefulTermination() {
        defaults.set(false, forKey: activeRunKey)
        defaults.set(0, forKey: consecutiveFailedLaunchesKey)
    }

    func markLaunchCompleted() {
        defaults.set(false, forKey: activeRunKey)
        defaults.set(0, forKey: consecutiveFailedLaunchesKey)
    }

    func startMainThreadWatchdog() {
#if DEBUG
        guard watchdogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let lagMS = Int(max(0, (now - self.lastMainThreadPingUptime) * 1_000))
            if lagMS > 450 {
                self.logger.warning("reliability.main_thread_lag_ms=\(lagMS, privacy: .public)")
            }
            DispatchQueue.main.async { [weak self] in
                self?.lastMainThreadPingUptime = ProcessInfo.processInfo.systemUptime
            }
        }
        watchdogTimer = timer
        timer.resume()
#endif
    }

    func requestSafeModeOnNextLaunch() {
        defaults.set(true, forKey: safeModeNextLaunchKey)
    }

    func clearSafeModeRecoveryState() {
        defaults.set(0, forKey: consecutiveFailedLaunchesKey)
        defaults.set(false, forKey: safeModeNextLaunchKey)
    }

    func consumeSafeModeLaunchDecision() -> SafeModeLaunchDecision {
        let requestedManually = defaults.bool(forKey: safeModeNextLaunchKey)
        if requestedManually {
            defaults.set(false, forKey: safeModeNextLaunchKey)
        }
        let consecutiveFailedLaunches = defaults.integer(forKey: consecutiveFailedLaunchesKey)
        let message = ReleaseRuntimePolicy.safeModeStartupMessage(
            consecutiveFailedLaunches: consecutiveFailedLaunches,
            requestedManually: requestedManually
        )
        return SafeModeLaunchDecision(
            isEnabled: message != nil,
            message: message,
            consecutiveFailedLaunches: consecutiveFailedLaunches,
            requestedManually: requestedManually
        )
    }

    private func currentBucketID() -> String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
#if os(macOS)
        let platform = "macOS"
#elseif os(iOS)
        let platform = "iOS"
#else
        let platform = "unknown"
#endif
        return "\(platform).build\(build)"
    }
}
