import Foundation
import OSLog

@MainActor
final class RuntimeReliabilityMonitor {
    static let shared = RuntimeReliabilityMonitor()

    private let logger = Logger(subsystem: "h3p.Neon-Vision-Editor", category: "Reliability")
    private let defaults = UserDefaults.standard
    private let activeRunKey = "Reliability.ActiveRunMarkerV1"
    private let crashBucketPrefix = "Reliability.CrashBucketV1."
    private var watchdogTimer: DispatchSourceTimer?
    private var lastMainThreadPingUptime = ProcessInfo.processInfo.systemUptime

    private init() {}

    func markLaunch() {
        if defaults.bool(forKey: activeRunKey) {
            let key = crashBucketPrefix + currentBucketID()
            let current = defaults.integer(forKey: key)
            defaults.set(current + 1, forKey: key)
#if DEBUG
            logger.warning("reliability.previous_run_unfinished bucket=\(self.currentBucketID(), privacy: .public) count=\(current + 1, privacy: .public)")
#endif
        }
        defaults.set(true, forKey: activeRunKey)
    }

    func markGracefulTermination() {
        defaults.set(false, forKey: activeRunKey)
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
