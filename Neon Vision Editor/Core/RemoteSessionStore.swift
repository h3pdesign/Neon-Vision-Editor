import Foundation
import Network
import Observation

private final class RemoteSessionCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didComplete else { return false }
        didComplete = true
        return true
    }
}

@MainActor
@Observable
final class RemoteSessionStore {
    enum RuntimeState: String {
        case idle
        case ready
        case connecting
        case active
        case failed
    }

    struct SavedTarget: Identifiable, Codable, Equatable {
        let id: UUID
        var nickname: String
        var host: String
        var username: String
        var port: Int
        var lastPreparedAt: Date

        init(
            id: UUID = UUID(),
            nickname: String,
            host: String,
            username: String,
            port: Int,
            lastPreparedAt: Date = Date()
        ) {
            self.id = id
            self.nickname = nickname
            self.host = host
            self.username = username
            self.port = port
            self.lastPreparedAt = lastPreparedAt
        }

        var displayTitle: String {
            let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedNickname.isEmpty ? connectionSummary : trimmedNickname
        }

        var connectionSummary: String {
            let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let userPrefix = trimmedUser.isEmpty ? "" : "\(trimmedUser)@"
            return "\(userPrefix)\(host):\(port)"
        }
    }

    static let shared = RemoteSessionStore()

    private static let savedTargetsKey = "RemoteSessionSavedTargetsV1"
    private static let activeTargetIDKey = "RemoteSessionActiveTargetIDV1"
    private static let activeTargetSummaryKey = "RemoteSessionActiveTargetSummaryV1"

    private(set) var savedTargets: [SavedTarget] = []
    private(set) var activeTargetID: UUID? = nil
    private(set) var activeTargetSummary: String = ""
    private(set) var runtimeState: RuntimeState = .idle
    private(set) var sessionStartedAt: Date? = nil
    private(set) var sessionStatusDetail: String = ""
    private var liveConnection: NWConnection? = nil
    private let connectionQueue = DispatchQueue(label: "RemoteSessionStore.Connection")

    private init() {
        load()
    }

    var activeTarget: SavedTarget? {
        guard let activeTargetID else { return nil }
        return savedTargets.first(where: { $0.id == activeTargetID })
    }

    var isRemotePreviewReady: Bool {
        activeTarget != nil
    }

    var isRemotePreviewConnected: Bool {
        runtimeState == .active && activeTarget != nil
    }

    var isRemotePreviewConnecting: Bool {
        runtimeState == .connecting
    }

    func connectPreview(nickname: String, host: String, username: String, port: Int) -> SavedTarget? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        let sanitizedPort = min(max(port, 1), 65535)
        let normalizedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayNickname = normalizedNickname.isEmpty ? trimmedHost : normalizedNickname

        let target = SavedTarget(
            id: existingTargetID(host: trimmedHost, username: normalizedUsername, port: sanitizedPort) ?? UUID(),
            nickname: displayNickname,
            host: trimmedHost,
            username: normalizedUsername,
            port: sanitizedPort,
            lastPreparedAt: Date()
        )

        upsert(target)
        activeTargetID = target.id
        activeTargetSummary = target.connectionSummary
        runtimeState = .ready
        sessionStartedAt = nil
        sessionStatusDetail = ""
        persist()
        syncLegacyDefaults(with: target)
        return target
    }

    func disconnectPreview() {
        cancelLiveConnection()
        activeTargetID = nil
        activeTargetSummary = ""
        runtimeState = .idle
        sessionStartedAt = nil
        sessionStatusDetail = ""
        persist()
        syncLegacyDefaultsForDisconnect()
    }

    func removeSavedTarget(id: UUID) {
        savedTargets.removeAll { $0.id == id }
        if activeTargetID == id {
            cancelLiveConnection()
            activeTargetID = nil
            activeTargetSummary = ""
            runtimeState = .idle
            sessionStartedAt = nil
            sessionStatusDetail = ""
            syncLegacyDefaultsForDisconnect()
        }
        persist()
    }

    func activateSavedTarget(id: UUID) {
        guard let target = savedTargets.first(where: { $0.id == id }) else { return }
        activeTargetID = id
        activeTargetSummary = target.connectionSummary
        runtimeState = .ready
        sessionStartedAt = nil
        sessionStatusDetail = ""
        persist()
        syncLegacyDefaults(with: target)
    }

    func startSession(timeout: TimeInterval = 5) async -> Bool {
        guard let target = activeTarget else { return false }
        let targetSummary = target.connectionSummary

        cancelLiveConnection()
        runtimeState = .connecting
        sessionStartedAt = nil
        sessionStatusDetail = "Opening a TCP connection to \(targetSummary)…"

        guard let port = NWEndpoint.Port(rawValue: UInt16(target.port)) else {
            runtimeState = .failed
            sessionStatusDetail = "The selected port is invalid."
            return false
        }

        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: .tcp)
        liveConnection = connection

        return await withCheckedContinuation { continuation in
            let completionGate = RemoteSessionCompletionGate()

            @Sendable func finish(success: Bool, state: RuntimeState, detail: String) {
                guard completionGate.claim() else { return }
                Task { @MainActor in
                    if self.liveConnection === connection {
                        if success {
                            self.runtimeState = state
                            self.sessionStartedAt = Date()
                            self.sessionStatusDetail = detail
                        } else {
                            connection.cancel()
                            self.liveConnection = nil
                            self.runtimeState = self.activeTarget == nil ? .idle : state
                            self.sessionStartedAt = nil
                            self.sessionStatusDetail = detail
                        }
                    }
                    continuation.resume(returning: success)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(success: true, state: .active, detail: "Connected to \(targetSummary). Remote transport is limited to this session socket in Phase 4.")
                case .waiting(let error):
                    finish(success: false, state: .failed, detail: "Connection is waiting: \(error.localizedDescription)")
                case .failed(let error):
                    finish(success: false, state: .failed, detail: "Connection failed: \(error.localizedDescription)")
                case .cancelled:
                    finish(success: false, state: .ready, detail: "Connection cancelled.")
                default:
                    break
                }
            }

            connection.start(queue: connectionQueue)

            connectionQueue.asyncAfter(deadline: .now() + timeout) {
                finish(success: false, state: .failed, detail: "Connection timed out after \(Int(timeout)) seconds.")
            }
        }
    }

    func stopSession() {
        cancelLiveConnection()
        runtimeState = activeTarget == nil ? .idle : .ready
        sessionStartedAt = nil
        sessionStatusDetail = activeTarget == nil ? "" : "Connection closed. The target stays selected for later."
    }

    private func upsert(_ target: SavedTarget) {
        if let existingIndex = savedTargets.firstIndex(where: { $0.id == target.id }) {
            savedTargets[existingIndex] = target
        } else {
            savedTargets.insert(target, at: 0)
        }
        savedTargets.sort { $0.lastPreparedAt > $1.lastPreparedAt }
    }

    private func existingTargetID(host: String, username: String, port: Int) -> UUID? {
        savedTargets.first {
            $0.host.caseInsensitiveCompare(host) == .orderedSame &&
            $0.username == username &&
            $0.port == port
        }?.id
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.savedTargetsKey),
           let decoded = try? JSONDecoder().decode([SavedTarget].self, from: data) {
            savedTargets = decoded
        }
        if let raw = defaults.string(forKey: Self.activeTargetIDKey),
           let parsed = UUID(uuidString: raw),
           savedTargets.contains(where: { $0.id == parsed }) {
            activeTargetID = parsed
        }
        activeTargetSummary = defaults.string(forKey: Self.activeTargetSummaryKey) ?? ""
        if activeTargetSummary.isEmpty, let activeTarget {
            activeTargetSummary = activeTarget.connectionSummary
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(savedTargets) {
            defaults.set(data, forKey: Self.savedTargetsKey)
        }
        defaults.set(activeTargetID?.uuidString, forKey: Self.activeTargetIDKey)
        defaults.set(activeTargetSummary, forKey: Self.activeTargetSummaryKey)
    }

    private func syncLegacyDefaults(with target: SavedTarget) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "SettingsRemoteSessionsEnabled")
        defaults.set(target.host, forKey: "SettingsRemoteHost")
        defaults.set(target.username, forKey: "SettingsRemoteUsername")
        defaults.set(target.port, forKey: "SettingsRemotePort")
        defaults.set(target.connectionSummary, forKey: "SettingsRemotePreparedTarget")
    }

    private func syncLegacyDefaultsForDisconnect() {
        let defaults = UserDefaults.standard
        defaults.set("", forKey: "SettingsRemotePreparedTarget")
    }

    private func cancelLiveConnection() {
        liveConnection?.cancel()
        liveConnection = nil
    }
}
