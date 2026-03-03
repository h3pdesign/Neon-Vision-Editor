import Foundation
import OSLog

@MainActor
final class EditorPerformanceMonitor {
    static let shared = EditorPerformanceMonitor()

    private let logger = Logger(subsystem: "h3p.Neon-Vision-Editor", category: "Performance")
    private let launchUptime = ProcessInfo.processInfo.systemUptime
    private var didLogFirstPaint = false
    private var didLogFirstKeystroke = false
    private var fileOpenStartUptimeByTabID: [UUID: TimeInterval] = [:]

    private init() {}

    func markLaunchConfigured() {
#if DEBUG
        logger.debug("perf.launch.configured")
#endif
    }

    func markFirstPaint() {
        guard !didLogFirstPaint else { return }
        didLogFirstPaint = true
#if DEBUG
        logger.debug("perf.first_paint_ms=\(Self.elapsedMilliseconds(since: launchUptime), privacy: .public)")
#endif
    }

    func markFirstKeystroke() {
        guard !didLogFirstKeystroke else { return }
        didLogFirstKeystroke = true
#if DEBUG
        logger.debug("perf.first_keystroke_ms=\(Self.elapsedMilliseconds(since: launchUptime), privacy: .public)")
#endif
    }

    func beginFileOpen(tabID: UUID) {
        fileOpenStartUptimeByTabID[tabID] = ProcessInfo.processInfo.systemUptime
    }

    func endFileOpen(tabID: UUID, success: Bool, byteCount: Int?) {
        guard let startedAt = fileOpenStartUptimeByTabID.removeValue(forKey: tabID) else { return }
#if DEBUG
        let elapsed = Self.elapsedMilliseconds(since: startedAt)
        if let byteCount {
            logger.debug(
                "perf.file_open_ms=\(elapsed, privacy: .public) success=\(success, privacy: .public) bytes=\(byteCount, privacy: .public)"
            )
        } else {
            logger.debug("perf.file_open_ms=\(elapsed, privacy: .public) success=\(success, privacy: .public)")
        }
#endif
    }

    private static func elapsedMilliseconds(since startUptime: TimeInterval) -> Int {
        max(0, Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000))
    }
}
