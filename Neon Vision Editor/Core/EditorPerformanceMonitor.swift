import Foundation
import OSLog

@MainActor


// MARK: - Types

final class EditorPerformanceMonitor {
    struct PreviewReloadSnapshot: Equatable {
        let requested: Int
        let coalesced: Int
        let executed: Int
    }
    struct FileOpenEvent: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let elapsedMilliseconds: Int
        let success: Bool
        let byteCount: Int?
    }

    struct TabSwitchEvent: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let elapsedMilliseconds: Int
    }

    static let shared = EditorPerformanceMonitor()

    private let logger = Logger(subsystem: "h3p.Neon-Vision-Editor", category: "Performance")
    private let signposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "TabSwitch")
    private let launchUptime = ProcessInfo.processInfo.systemUptime
    private var didLogFirstPaint = false
    private var didLogFirstKeystroke = false
    private var fileOpenStartUptimeByTabID: [UUID: TimeInterval] = [:]
    private var minimapViewportStartUptimeByTabID: [UUID: TimeInterval] = [:]
    private var tabSwitchStartUptimeByTabID: [UUID: TimeInterval] = [:]
    private var previewReloadRequestedCount = 0
    private var previewReloadCoalescedCount = 0
    private var previewReloadExecutedCount = 0
    private(set) var lastMinimapViewportLatencyMilliseconds: Int?
    private(set) var lastTabSwitchLatencyMilliseconds: Int?
    private let defaults: UserDefaults
    private let eventsDefaultsKey = "PerformanceRecentFileOpenEventsV1"
    private let tabSwitchEventsDefaultsKey = "PerformanceRecentTabSwitchEventsV1"
    private let maxEvents = 30

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

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

    func beginTabSwitch(tabID: UUID) {
        tabSwitchStartUptimeByTabID[tabID] = ProcessInfo.processInfo.systemUptime
        signposter.emitEvent("selection")
    }

    func markLoadedTabStateApplied(tabID: UUID) {
        guard tabSwitchStartUptimeByTabID[tabID] != nil else { return }
        signposter.emitEvent("loaded_state")
    }

    func markSwiftUIEditorUpdated(tabID: UUID) {
        guard tabSwitchStartUptimeByTabID[tabID] != nil else { return }
        signposter.emitEvent("swiftui_update")
    }

    func markViewportLoaded(tabID: UUID) {
        guard tabSwitchStartUptimeByTabID[tabID] != nil else { return }
        signposter.emitEvent("viewport")
    }

    func markDocumentProjection(tabID: UUID) {
        signposter.emitEvent("document_string")
    }

    func markTOCUpdated(tabID: UUID) {
        signposter.emitEvent("toc")
    }

    func markPreviewUpdated(tabID: UUID) {
        signposter.emitEvent("preview")
    }

    func markPreviewReloadScheduled(coalesced: Bool) {
        previewReloadRequestedCount &+= 1
        if coalesced {
            previewReloadCoalescedCount &+= 1
        }
    }

    func markPreviewReloadExecuted() {
        previewReloadExecutedCount &+= 1
#if DEBUG
        if previewReloadExecutedCount.isMultiple(of: 10) {
            logger.debug(
                "perf.preview_reload requested=\(self.previewReloadRequestedCount, privacy: .public) coalesced=\(self.previewReloadCoalescedCount, privacy: .public) executed=\(self.previewReloadExecutedCount, privacy: .public)"
            )
        }
#endif
    }

    func previewReloadSnapshot() -> PreviewReloadSnapshot {
        PreviewReloadSnapshot(
            requested: previewReloadRequestedCount,
            coalesced: previewReloadCoalescedCount,
            executed: previewReloadExecutedCount
        )
    }

    func resetPreviewReloadMetrics() {
        previewReloadRequestedCount = 0
        previewReloadCoalescedCount = 0
        previewReloadExecutedCount = 0
    }

    func measureVirtualEditorLayout<T>(_ work: () -> T) -> T {
        let state = signposter.beginInterval("virtual_editor_layout")
        defer { signposter.endInterval("virtual_editor_layout", state) }
        return work()
    }

    func markTabSwitchFirstDraw(tabID: UUID) {
        guard let startedAt = tabSwitchStartUptimeByTabID.removeValue(forKey: tabID) else { return }
        let elapsed = Self.elapsedMilliseconds(since: startedAt)
        lastTabSwitchLatencyMilliseconds = elapsed
        storeTabSwitchEvent(
            TabSwitchEvent(
                id: UUID(),
                timestamp: Date(),
                elapsedMilliseconds: elapsed
            )
        )
        signposter.emitEvent("first_draw")
#if DEBUG
        logger.debug("perf.tab_switch_first_draw_ms=\(elapsed, privacy: .public)")
#endif
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

    func beginMinimapViewportUpdate(tabID: UUID) {
        minimapViewportStartUptimeByTabID[tabID] = ProcessInfo.processInfo.systemUptime
    }

    func endMinimapViewportUpdate(tabID: UUID) {
        guard let startedAt = minimapViewportStartUptimeByTabID.removeValue(forKey: tabID) else { return }
        lastMinimapViewportLatencyMilliseconds = Self.elapsedMilliseconds(since: startedAt)
    }

    func recentFileOpenEvents(limit: Int = 10) -> [FileOpenEvent] {
        guard let data = EditorPreferenceWriter.shared.object(forKey: eventsDefaultsKey, defaults: defaults) as? Data,
              let decoded = try? JSONDecoder().decode([FileOpenEvent].self, from: data) else {
            return []
        }
        let clamped = max(1, min(limit, maxEvents))
        return Array(decoded.suffix(clamped))
    }

    func clearRecentFileOpenEvents() {
        EditorPreferenceWriter.shared.set(.removed, forKey: eventsDefaultsKey, defaults: defaults)
    }

    func recentTabSwitchEvents(limit: Int = 10) -> [TabSwitchEvent] {
        guard let data = EditorPreferenceWriter.shared.object(forKey: tabSwitchEventsDefaultsKey, defaults: defaults) as? Data,
              let decoded = try? JSONDecoder().decode([TabSwitchEvent].self, from: data) else {
            return []
        }
        let clamped = max(1, min(limit, maxEvents))
        return Array(decoded.suffix(clamped))
    }

    func clearRecentTabSwitchEvents() {
        EditorPreferenceWriter.shared.set(.removed, forKey: tabSwitchEventsDefaultsKey, defaults: defaults)
    }

    private func storeFileOpenEvent(_ event: FileOpenEvent) {
        var existing = recentFileOpenEvents(limit: maxEvents)
        existing.append(event)
        if existing.count > maxEvents {
            existing.removeFirst(existing.count - maxEvents)
        }
        guard let encoded = try? JSONEncoder().encode(existing) else { return }
        EditorPreferenceWriter.shared.set(.data(encoded), forKey: eventsDefaultsKey, defaults: defaults)
    }

    private func storeTabSwitchEvent(_ event: TabSwitchEvent) {
        var existing = recentTabSwitchEvents(limit: maxEvents)
        existing.append(event)
        if existing.count > maxEvents {
            existing.removeFirst(existing.count - maxEvents)
        }
        guard let encoded = try? JSONEncoder().encode(existing) else { return }
        EditorPreferenceWriter.shared.set(.data(encoded), forKey: tabSwitchEventsDefaultsKey, defaults: defaults)
    }

    private static func elapsedMilliseconds(since startUptime: TimeInterval) -> Int {
        max(0, Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000))
    }
}
