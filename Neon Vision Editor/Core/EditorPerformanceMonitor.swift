import Foundation
import OSLog

@MainActor
final class EditorPerformanceMonitor {
    struct FileOpenEvent: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let elapsedMilliseconds: Int
        let success: Bool
        let byteCount: Int?
    }

    static let shared = EditorPerformanceMonitor()

    private let logger = Logger(subsystem: "h3p.Neon-Vision-Editor", category: "Performance")
    private let launchUptime = ProcessInfo.processInfo.systemUptime
    private var didLogFirstPaint = false
    private var didLogFirstKeystroke = false
    private var fileOpenStartUptimeByTabID: [UUID: TimeInterval] = [:]
    private let defaults = UserDefaults.standard
    private let eventsDefaultsKey = "PerformanceRecentFileOpenEventsV1"
    private let maxEvents = 30

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
        let elapsed = Self.elapsedMilliseconds(since: startedAt)
        storeFileOpenEvent(
            FileOpenEvent(
                id: UUID(),
                timestamp: Date(),
                elapsedMilliseconds: elapsed,
                success: success,
                byteCount: byteCount
            )
        )
#if DEBUG
        if let byteCount {
            logger.debug(
                "perf.file_open_ms=\(elapsed, privacy: .public) success=\(success, privacy: .public) bytes=\(byteCount, privacy: .public)"
            )
        } else {
            logger.debug("perf.file_open_ms=\(elapsed, privacy: .public) success=\(success, privacy: .public)")
        }
#endif
    }

    func recentFileOpenEvents(limit: Int = 10) -> [FileOpenEvent] {
        guard let data = defaults.data(forKey: eventsDefaultsKey),
              let decoded = try? JSONDecoder().decode([FileOpenEvent].self, from: data) else {
            return []
        }
        let clamped = max(1, min(limit, maxEvents))
        return Array(decoded.suffix(clamped))
    }

    private func storeFileOpenEvent(_ event: FileOpenEvent) {
        var existing = recentFileOpenEvents(limit: maxEvents)
        existing.append(event)
        if existing.count > maxEvents {
            existing.removeFirst(existing.count - maxEvents)
        }
        guard let encoded = try? JSONEncoder().encode(existing) else { return }
        defaults.set(encoded, forKey: eventsDefaultsKey)
    }

    private static func elapsedMilliseconds(since startUptime: TimeInterval) -> Int {
        max(0, Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000))
    }
}
