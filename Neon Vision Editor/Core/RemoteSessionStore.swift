import CryptoKit
import Foundation
import Network
import Observation

private final class RemoteSessionCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var didComplete = false

    nonisolated func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didComplete else { return false }
        didComplete = true
        return true
    }
}

private struct RemoteBrokerAttachEnvelope: Codable {
    let host: String
    let port: Int
    let token: String
}

private struct RemoteBrokerRequest: Codable {
    let token: String
    let method: String
    let path: String?
    let content: String?
    let expectedRevision: String?
}

private struct RemoteBrokerFileEntryPayload: Codable {
    let name: String
    let path: String
    let isDirectory: Bool
}

private struct RemoteBrokerResponse: Codable {
    let success: Bool
    let detail: String
    let path: String?
    let name: String?
    let content: String?
    let revision: String?
    let entries: [RemoteBrokerFileEntryPayload]?
    let broker: RemoteSessionStore.BrokerSessionDescriptor?
}

private struct RemoteBrokerTransportError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private let remoteDocumentByteLimit = 1_048_576
private let brokerMessageByteLimit = 1_310_720

private func makeRemoteSessionFileEntry(name: String, path: String, isDirectory: Bool) -> RemoteSessionStore.RemoteFileEntry {
    let isSupportedTextFile = isDirectory || EditorViewModel.isSupportedEditorFileURL(URL(fileURLWithPath: path))
    return RemoteSessionStore.RemoteFileEntry(
        name: name,
        path: path,
        isDirectory: isDirectory,
        isSupportedTextFile: isSupportedTextFile
    )
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
        var sshKeyBookmarkData: Data?
        var sshKeyDisplayName: String
        var lastPreparedAt: Date

        init(
            id: UUID = UUID(),
            nickname: String,
            host: String,
            username: String,
            port: Int,
            sshKeyBookmarkData: Data? = nil,
            sshKeyDisplayName: String = "",
            lastPreparedAt: Date = Date()
        ) {
            self.id = id
            self.nickname = nickname
            self.host = host
            self.username = username
            self.port = port
            self.sshKeyBookmarkData = sshKeyBookmarkData
            self.sshKeyDisplayName = sshKeyDisplayName
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

    struct RemoteFileEntry: Identifiable, Equatable {
        let name: String
        let path: String
        let isDirectory: Bool
        let isSupportedTextFile: Bool

        var id: String { path }
    }

    struct RemotePreviewDocument: Equatable {
        let name: String
        let path: String
        let content: String
        let isReadOnly: Bool
        let revisionToken: String?
    }

    struct RemoteSaveResult: Equatable {
        let didSave: Bool
        let detail: String
        let revisionToken: String?
        let hasConflict: Bool
    }

    enum BrokerCapability: String, Codable, CaseIterable {
        case readOnlyBrowse
        case readOnlyPreview
        case explicitSavePlanned
        case clientAttachPlanned

        var displayTitle: String {
            switch self {
            case .readOnlyBrowse:
                return "Read-only Browser"
            case .readOnlyPreview:
                return "Read-only Preview"
            case .explicitSavePlanned:
                return "Explicit Save Planned"
            case .clientAttachPlanned:
                return "Client Attach Planned"
            }
        }
    }

    struct BrokerSessionDescriptor: Codable, Equatable {
        let id: UUID
        let hostDisplayName: String
        let ownerPlatform: String
        let targetSummary: String
        let startedAt: Date
        let capabilities: [BrokerCapability]
        let attachHost: String?
        let attachPort: Int?
        let attachToken: String?
    }

    static let shared = RemoteSessionStore()

    private static let savedTargetsKey = "RemoteSessionSavedTargetsV1"
    private static let activeTargetIDKey = "RemoteSessionActiveTargetIDV1"
    private static let activeTargetSummaryKey = "RemoteSessionActiveTargetSummaryV1"
    private static let brokerSessionDescriptorKey = "RemoteSessionBrokerDescriptorV1"

    private(set) var savedTargets: [SavedTarget] = []
    private(set) var activeTargetID: UUID? = nil
    private(set) var activeTargetSummary: String = ""
    private(set) var runtimeState: RuntimeState = .idle
    private(set) var sessionStartedAt: Date? = nil
    private(set) var sessionStatusDetail: String = ""
    private(set) var brokerSessionDescriptor: BrokerSessionDescriptor? = nil
    private(set) var attachedBrokerDescriptor: BrokerSessionDescriptor? = nil
    private(set) var remoteBrowserEntries: [RemoteFileEntry] = []
    private(set) var remoteBrowserPath: String = "~"
    private(set) var remoteBrowserStatusDetail: String = ""
    private(set) var isRemoteBrowserLoading: Bool = false
    private var liveConnection: NWConnection? = nil
#if os(macOS)
    private var liveSSHProcess: Process? = nil
    private var brokerListener: NWListener? = nil
    private var brokerAttachHost: String = "127.0.0.1"
    private var brokerAttachPort: Int? = nil
    private var brokerAttachToken: String? = nil
#endif
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

    var hasBrokerSession: Bool {
        brokerSessionDescriptor != nil
    }

    var canAttachExternalClients: Bool {
        brokerSessionDescriptor?.attachHost != nil &&
        brokerSessionDescriptor?.attachPort != nil &&
        brokerSessionDescriptor?.attachToken != nil
    }

    var isBrokerClientAttached: Bool {
        attachedBrokerDescriptor != nil
    }

    var brokerAttachCode: String {
        guard
            let broker = brokerSessionDescriptor,
            let host = broker.attachHost,
            let port = broker.attachPort,
            let token = broker.attachToken
        else {
            return ""
        }
        let envelope = RemoteBrokerAttachEnvelope(host: host, port: port, token: token)
        guard let data = try? JSONEncoder().encode(envelope) else { return "" }
        return data.base64EncodedString()
    }

    func connectPreview(
        nickname: String,
        host: String,
        username: String,
        port: Int,
        sshKeyBookmarkData: Data? = nil,
        sshKeyDisplayName: String = ""
    ) -> SavedTarget? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        let sanitizedPort = min(max(port, 1), 65535)
        let normalizedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayNickname = normalizedNickname.isEmpty ? trimmedHost : normalizedNickname
        let normalizedSSHKeyDisplayName = sshKeyDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        let target = SavedTarget(
            id: existingTargetID(host: trimmedHost, username: normalizedUsername, port: sanitizedPort) ?? UUID(),
            nickname: displayNickname,
            host: trimmedHost,
            username: normalizedUsername,
            port: sanitizedPort,
            sshKeyBookmarkData: sshKeyBookmarkData,
            sshKeyDisplayName: normalizedSSHKeyDisplayName,
            lastPreparedAt: Date()
        )

        upsert(target)
        activeTargetID = target.id
        activeTargetSummary = target.connectionSummary
        runtimeState = .ready
        sessionStartedAt = nil
        sessionStatusDetail = ""
        brokerSessionDescriptor = nil
        attachedBrokerDescriptor = nil
        clearRemoteBrowserState()
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
        brokerSessionDescriptor = nil
        attachedBrokerDescriptor = nil
        clearRemoteBrowserState()
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
            brokerSessionDescriptor = nil
            attachedBrokerDescriptor = nil
            clearRemoteBrowserState()
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
        brokerSessionDescriptor = nil
        attachedBrokerDescriptor = nil
        clearRemoteBrowserState()
        persist()
        syncLegacyDefaults(with: target)
    }

    func startSession(timeout: TimeInterval = 5) async -> Bool {
        guard let target = activeTarget else { return false }
        let targetSummary = target.connectionSummary

        cancelLiveConnection()
#if os(macOS)
        if target.sshKeyBookmarkData != nil {
            return await startSSHSessionMac(target: target, timeout: timeout)
        }
#endif
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
                            self.brokerSessionDescriptor = nil
                            self.attachedBrokerDescriptor = nil
                        } else {
                            connection.cancel()
                            self.liveConnection = nil
                            self.runtimeState = self.activeTarget == nil ? .idle : state
                            self.sessionStartedAt = nil
                            self.sessionStatusDetail = detail
                            self.brokerSessionDescriptor = nil
                            self.attachedBrokerDescriptor = nil
                        }
                        self.persist()
                    }
                    continuation.resume(returning: success)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(success: true, state: .active, detail: "Connected to \(targetSummary) over the direct TCP fallback. Broker attach, remote browser, and remote editing require an SSH-backed session started on the Mac.")
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
        brokerSessionDescriptor = nil
        attachedBrokerDescriptor = nil
        clearRemoteBrowserState()
        persist()
    }

    func attachToBroker(code: String, timeout: TimeInterval = 5) async -> Bool {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            sessionStatusDetail = "Paste a broker attach code first."
            return false
        }
        guard
            let data = Data(base64Encoded: trimmedCode),
            let envelope = try? JSONDecoder().decode(RemoteBrokerAttachEnvelope.self, from: data)
        else {
            sessionStatusDetail = "The attach code is invalid."
            return false
        }

        runtimeState = .connecting
        sessionStartedAt = nil
        sessionStatusDetail = "Attaching to the remote broker…"
        brokerSessionDescriptor = nil
        attachedBrokerDescriptor = nil
        clearRemoteBrowserState()

        let result = await sendBrokerRequest(
            host: envelope.host,
            port: envelope.port,
            request: RemoteBrokerRequest(token: envelope.token, method: "handshake", path: nil, content: nil, expectedRevision: nil),
            timeout: timeout
        )

        switch result {
        case .success(let response):
            guard let broker = response.broker else {
                runtimeState = .failed
                sessionStatusDetail = "The broker handshake returned no session descriptor."
                persist()
                return false
            }
            attachedBrokerDescriptor = broker
            runtimeState = .active
            sessionStartedAt = Date()
            sessionStatusDetail = response.detail
            persist()
            return true
        case .failure(let error):
            runtimeState = .failed
            sessionStartedAt = nil
            sessionStatusDetail = makeBrokerRecoveryDetail(for: error.localizedDescription)
            persist()
            return false
        }
    }

    func detachBrokerClient() {
        attachedBrokerDescriptor = nil
        if activeTarget == nil {
            runtimeState = .idle
            sessionStartedAt = nil
            sessionStatusDetail = ""
        } else {
            runtimeState = .ready
            sessionStartedAt = nil
            sessionStatusDetail = "Detached from the broker. The local target stays selected."
        }
        clearRemoteBrowserState()
        persist()
    }

    func loadAttachedBrokerDirectory(path: String? = nil, timeout: TimeInterval = 8) async -> Bool {
        guard
            let attachedBrokerDescriptor,
            let host = attachedBrokerDescriptor.attachHost,
            let port = attachedBrokerDescriptor.attachPort,
            let token = attachedBrokerDescriptor.attachToken
        else {
            remoteBrowserStatusDetail = "Attach to a broker before browsing remote files."
            return false
        }

        let requestedPath = {
            let trimmed = (path ?? remoteBrowserPath).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "~" : trimmed
        }()
        isRemoteBrowserLoading = true
        remoteBrowserStatusDetail = "Loading \(requestedPath)…"

        let result = await sendBrokerRequest(
            host: host,
            port: port,
            request: RemoteBrokerRequest(token: token, method: "list", path: requestedPath, content: nil, expectedRevision: nil),
            timeout: timeout
        )

        isRemoteBrowserLoading = false
        switch result {
        case .success(let response):
            remoteBrowserPath = response.path ?? requestedPath
            remoteBrowserEntries = response.entries?.map {
                makeRemoteSessionFileEntry(name: $0.name, path: $0.path, isDirectory: $0.isDirectory)
            } ?? []
            remoteBrowserStatusDetail = response.detail
            return response.success
        case .failure(let error):
            remoteBrowserEntries = []
            noteBrokerRecoveryNeeded(error.localizedDescription)
            return false
        }
    }

    func loadRemoteDirectory(path: String? = nil, timeout: TimeInterval = 8) async -> Bool {
        if let attachedBrokerDescriptor,
           let host = attachedBrokerDescriptor.attachHost,
           let port = attachedBrokerDescriptor.attachPort,
           let token = attachedBrokerDescriptor.attachToken {
            let requestedPath = normalizedRemoteBrowserPath(path ?? remoteBrowserPath)
            isRemoteBrowserLoading = true
            remoteBrowserStatusDetail = "Loading \(requestedPath)…"

            let result = await sendBrokerRequest(
                host: host,
                port: port,
                request: RemoteBrokerRequest(token: token, method: "list", path: requestedPath, content: nil, expectedRevision: nil),
                timeout: timeout
            )

            isRemoteBrowserLoading = false
            switch result {
            case .success(let response):
                remoteBrowserPath = response.path ?? requestedPath
                remoteBrowserEntries = response.entries?.map {
                    makeRemoteSessionFileEntry(name: $0.name, path: $0.path, isDirectory: $0.isDirectory)
                } ?? []
                remoteBrowserStatusDetail = response.detail
                return response.success
            case .failure(let error):
                remoteBrowserEntries = []
                noteBrokerRecoveryNeeded(error.localizedDescription)
                return false
            }
        }

#if os(macOS)
        guard isRemotePreviewConnected, let target = activeTarget else {
            remoteBrowserStatusDetail = "Start a remote session before browsing files."
            return false
        }
        guard target.sshKeyBookmarkData != nil else {
            remoteBrowserStatusDetail = "Remote file browsing requires an SSH-key session on macOS."
            return false
        }

        let requestedPath = normalizedRemoteBrowserPath(path ?? remoteBrowserPath)
        isRemoteBrowserLoading = true
        remoteBrowserStatusDetail = "Loading \(requestedPath)…"

        let result = await runRemoteBrowseCommandMac(target: target, path: requestedPath, timeout: timeout)

        isRemoteBrowserLoading = false
        switch result {
        case .success(let payload):
            remoteBrowserPath = payload.path
            remoteBrowserEntries = payload.entries
            remoteBrowserStatusDetail = payload.entries.isEmpty
                ? "No entries found in \(payload.path)."
                : "Loaded \(payload.entries.count) entr\(payload.entries.count == 1 ? "y" : "ies") from \(payload.path)."
            return true
        case .failure(let detail):
            remoteBrowserEntries = []
            remoteBrowserStatusDetail = detail
            return false
        }
#else
        remoteBrowserEntries = []
        remoteBrowserStatusDetail = "Attach to an active Mac broker session before browsing remote files."
        return false
#endif
    }

    func openRemoteDocument(path: String, timeout: TimeInterval = 8) async -> RemotePreviewDocument? {
        if let attachedBrokerDescriptor,
           let host = attachedBrokerDescriptor.attachHost,
           let port = attachedBrokerDescriptor.attachPort,
           let token = attachedBrokerDescriptor.attachToken {
            let requestedPath = normalizedRemoteBrowserPath(path)
            guard EditorViewModel.isSupportedEditorFileURL(URL(fileURLWithPath: requestedPath)) else {
                remoteBrowserStatusDetail = "Only supported text files can be opened for remote editing."
                return nil
            }

            remoteBrowserStatusDetail = "Opening \(requestedPath)…"
            let result = await sendBrokerRequest(
                host: host,
                port: port,
                request: RemoteBrokerRequest(token: token, method: "open", path: requestedPath, content: nil, expectedRevision: nil),
                timeout: timeout
            )

            switch result {
            case .success(let response):
                guard let resolvedPath = response.path,
                      let name = response.name,
                      let content = response.content else {
                    remoteBrowserStatusDetail = "The broker returned no remote document content."
                    return nil
                }
                remoteBrowserStatusDetail = "Opened \(name) for remote editing."
                return RemotePreviewDocument(
                    name: name,
                    path: resolvedPath,
                    content: content,
                    isReadOnly: false,
                    revisionToken: response.revision
                )
            case .failure(let error):
                noteBrokerRecoveryNeeded(error.localizedDescription)
                return nil
            }
        }

#if os(macOS)
        guard isRemotePreviewConnected, let target = activeTarget else {
            remoteBrowserStatusDetail = "Start a remote session before opening a remote file."
            return nil
        }
        guard target.sshKeyBookmarkData != nil else {
            remoteBrowserStatusDetail = "Remote file editing requires an SSH-key session on macOS."
            return nil
        }

        let requestedPath = normalizedRemoteBrowserPath(path)
        guard EditorViewModel.isSupportedEditorFileURL(URL(fileURLWithPath: requestedPath)) else {
            remoteBrowserStatusDetail = "Only supported text files can be opened for remote editing."
            return nil
        }

        remoteBrowserStatusDetail = "Opening \(requestedPath)…"

        let result = await runRemoteReadCommandMac(target: target, path: requestedPath, timeout: timeout)
        switch result {
        case .success(let document):
            remoteBrowserStatusDetail = "Opened \(document.name) for remote editing."
            return document
        case .failure(let detail):
            remoteBrowserStatusDetail = detail
            return nil
        }
#else
        remoteBrowserStatusDetail = "Attach to an active Mac broker session before opening a remote file."
        return nil
#endif
    }

    func saveRemoteDocument(
        path: String,
        content: String,
        expectedRevision: String?,
        timeout: TimeInterval = 8
    ) async -> RemoteSaveResult {
        let requestedPath = normalizedRemoteBrowserPath(path)
        let trimmedContentSize = content.utf8.count
        guard trimmedContentSize <= remoteDocumentByteLimit else {
            remoteBrowserStatusDetail = "Remote save is limited to 1 MB per document."
            return RemoteSaveResult(
                didSave: false,
                detail: remoteBrowserStatusDetail,
                revisionToken: expectedRevision,
                hasConflict: false
            )
        }

        if let attachedBrokerDescriptor,
           let host = attachedBrokerDescriptor.attachHost,
           let port = attachedBrokerDescriptor.attachPort,
           let token = attachedBrokerDescriptor.attachToken {
            remoteBrowserStatusDetail = "Saving \(requestedPath)…"
            let result = await sendBrokerRequest(
                host: host,
                port: port,
                request: RemoteBrokerRequest(
                    token: token,
                    method: "save",
                    path: requestedPath,
                    content: content,
                    expectedRevision: expectedRevision
                ),
                timeout: timeout
            )

            switch result {
            case .success(let response):
                remoteBrowserStatusDetail = response.detail
                return RemoteSaveResult(
                    didSave: response.success,
                    detail: response.detail,
                    revisionToken: response.revision ?? expectedRevision,
                    hasConflict: !response.success && response.detail.localizedCaseInsensitiveContains("changed remotely")
                )
            case .failure(let error):
                noteBrokerRecoveryNeeded(error.localizedDescription)
                return RemoteSaveResult(
                    didSave: false,
                    detail: remoteBrowserStatusDetail,
                    revisionToken: expectedRevision,
                    hasConflict: false
                )
            }
        }

#if os(macOS)
        guard isRemotePreviewConnected, let target = activeTarget else {
            remoteBrowserStatusDetail = "Start a remote session before saving a remote file."
            return RemoteSaveResult(
                didSave: false,
                detail: remoteBrowserStatusDetail,
                revisionToken: expectedRevision,
                hasConflict: false
            )
        }
        guard target.sshKeyBookmarkData != nil else {
            remoteBrowserStatusDetail = "Remote save requires an SSH-key session on macOS."
            return RemoteSaveResult(
                didSave: false,
                detail: remoteBrowserStatusDetail,
                revisionToken: expectedRevision,
                hasConflict: false
            )
        }

        if let expectedRevision {
            let preflightResult = await runRemoteReadCommandMac(target: target, path: requestedPath, timeout: timeout)
            switch preflightResult {
            case .success(let document):
                if document.revisionToken != expectedRevision {
                    remoteBrowserStatusDetail = "The remote file changed remotely since it was opened. Re-open it before saving again."
                    return RemoteSaveResult(
                        didSave: false,
                        detail: remoteBrowserStatusDetail,
                        revisionToken: document.revisionToken,
                        hasConflict: true
                    )
                }
            case .failure(let detail):
                remoteBrowserStatusDetail = detail
                return RemoteSaveResult(
                    didSave: false,
                    detail: detail,
                    revisionToken: expectedRevision,
                    hasConflict: false
                )
            }
        }

        remoteBrowserStatusDetail = "Saving \(requestedPath)…"
        let result = await runRemoteWriteCommandMac(target: target, path: requestedPath, content: content, timeout: timeout)
        switch result {
        case .success(let detail):
            remoteBrowserStatusDetail = detail
            return RemoteSaveResult(
                didSave: true,
                detail: detail,
                revisionToken: makeRemoteRevisionToken(for: content),
                hasConflict: false
            )
        case .failure(let detail):
            remoteBrowserStatusDetail = detail
            return RemoteSaveResult(
                didSave: false,
                detail: detail,
                revisionToken: expectedRevision,
                hasConflict: false
            )
        }
#else
        remoteBrowserStatusDetail = "Attach to an active Mac broker session before saving a remote file."
        return RemoteSaveResult(
            didSave: false,
            detail: remoteBrowserStatusDetail,
            revisionToken: expectedRevision,
            hasConflict: false
        )
#endif
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
        if let data = defaults.data(forKey: Self.brokerSessionDescriptorKey),
           let decoded = try? JSONDecoder().decode(BrokerSessionDescriptor.self, from: data) {
            brokerSessionDescriptor = decoded
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(savedTargets) {
            defaults.set(data, forKey: Self.savedTargetsKey)
        }
        defaults.set(activeTargetID?.uuidString, forKey: Self.activeTargetIDKey)
        defaults.set(activeTargetSummary, forKey: Self.activeTargetSummaryKey)
        if let brokerSessionDescriptor,
           let data = try? JSONEncoder().encode(brokerSessionDescriptor) {
            defaults.set(data, forKey: Self.brokerSessionDescriptorKey)
        } else {
            defaults.removeObject(forKey: Self.brokerSessionDescriptorKey)
        }
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
#if os(macOS)
        liveSSHProcess?.terminate()
        liveSSHProcess = nil
        brokerListener?.cancel()
        brokerListener = nil
        brokerAttachPort = nil
        brokerAttachToken = nil
#endif
    }

    private func clearRemoteBrowserState() {
        remoteBrowserEntries = []
        remoteBrowserPath = "~"
        remoteBrowserStatusDetail = ""
        isRemoteBrowserLoading = false
    }

    private func noteBrokerRecoveryNeeded(_ detail: String) {
        let recoveryDetail = makeBrokerRecoveryDetail(for: detail)
        runtimeState = .failed
        sessionStartedAt = nil
        sessionStatusDetail = recoveryDetail
        remoteBrowserStatusDetail = recoveryDetail
        isRemoteBrowserLoading = false
        persist()
    }

    private func makeBrokerRecoveryDetail(for detail: String) -> String {
        let normalized = detail.localizedLowercase
        if normalized.contains("changed remotely") {
            return detail
        }
        if attachedBrokerDescriptor != nil {
            return "\(detail) Reattach this device from Settings > Remote using the active Mac attach code."
        }
        if brokerSessionDescriptor != nil {
            return "\(detail) Restart the Mac-hosted SSH session before attaching remote clients again."
        }
        return detail
    }

    private func sendBrokerRequest(
        host: String,
        port: Int,
        request: RemoteBrokerRequest,
        timeout: TimeInterval
    ) async -> Result<RemoteBrokerResponse, RemoteBrokerTransportError> {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(min(max(port, 1), 65535))) else {
            return .failure(RemoteBrokerTransportError(message: "The broker port is invalid."))
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        return await withCheckedContinuation { continuation in
            let completionGate = RemoteSessionCompletionGate()
            let encodedRequest = try? JSONEncoder().encode(request)

            @Sendable func finish(_ result: Result<RemoteBrokerResponse, RemoteBrokerTransportError>) {
                guard completionGate.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let encodedRequest else {
                        finish(.failure(RemoteBrokerTransportError(message: "The broker request could not be encoded.")))
                        return
                    }
                    connection.send(content: encodedRequest, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(RemoteBrokerTransportError(message: "The broker request failed: \(error.localizedDescription)")))
                            return
                        }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: brokerMessageByteLimit) { data, _, _, error in
                            if let error {
                                finish(.failure(RemoteBrokerTransportError(message: "The broker response failed: \(error.localizedDescription)")))
                                return
                            }
                            guard let data, !data.isEmpty else {
                                finish(.failure(RemoteBrokerTransportError(message: "The broker returned no response.")))
                                return
                            }
                            Task { @MainActor in
                                guard let response = try? JSONDecoder().decode(RemoteBrokerResponse.self, from: data) else {
                                    finish(.failure(RemoteBrokerTransportError(message: "The broker returned unreadable data.")))
                                    return
                                }
                                if response.success {
                                    finish(.success(response))
                                } else {
                                    finish(.failure(RemoteBrokerTransportError(message: response.detail)))
                                }
                            }
                        }
                    })
                case .waiting(let error):
                    finish(.failure(RemoteBrokerTransportError(message: "Waiting for broker: \(error.localizedDescription)")))
                case .failed(let error):
                    finish(.failure(RemoteBrokerTransportError(message: "Broker attach failed: \(error.localizedDescription)")))
                case .cancelled:
                    finish(.failure(RemoteBrokerTransportError(message: "Broker connection cancelled.")))
                default:
                    break
                }
            }

            connection.start(queue: connectionQueue)
            connectionQueue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(RemoteBrokerTransportError(message: "Broker request timed out after \(Int(timeout)) seconds.")))
            }
        }
    }

#if os(macOS)
    private struct RemoteBrowsePayload {
        let path: String
        let entries: [RemoteFileEntry]
    }

    private enum RemoteBrowseResult {
        case success(RemoteBrowsePayload)
        case failure(String)
    }

    private enum RemoteReadResult {
        case success(RemotePreviewDocument)
        case failure(String)
    }

    private enum RemoteWriteResult {
        case success(String)
        case failure(String)
    }

    private func startSSHSessionMac(target: SavedTarget, timeout: TimeInterval) async -> Bool {
        guard let bookmarkData = target.sshKeyBookmarkData else {
            runtimeState = .failed
            sessionStartedAt = nil
            sessionStatusDetail = "The selected SSH key is no longer available."
            return false
        }
        guard let keyURL = resolveSecurityScopedBookmarkMac(bookmarkData) else {
            runtimeState = .failed
            sessionStartedAt = nil
            sessionStatusDetail = "The selected SSH key could not be resolved. Re-select the key file."
            return false
        }

        let targetSummary = target.connectionSummary
        let didAccessKey = keyURL.startAccessingSecurityScopedResource()
        let loginTarget = target.username.isEmpty ? target.host : "\(target.username)@\(target.host)"
        let connectTimeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let process = Process()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N",
            "-i", keyURL.path,
            "-o", "BatchMode=yes",
            "-o", "IdentitiesOnly=yes",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "NumberOfPasswordPrompts=0",
            "-o", "PreferredAuthentications=publickey",
            "-o", "PubkeyAuthentication=yes",
            "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
            "-p", "\(target.port)",
            loginTarget
        ]
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        runtimeState = .connecting
        sessionStartedAt = nil
        brokerSessionDescriptor = nil
        attachedBrokerDescriptor = nil
        sessionStatusDetail = "Starting an SSH session to \(targetSummary) with the selected key…"

        return await withCheckedContinuation { continuation in
            let completionGate = RemoteSessionCompletionGate()

            @Sendable func finish(success: Bool, state: RuntimeState, detail: String, shouldTerminate: Bool) {
                guard completionGate.claim() else { return }
                if didAccessKey {
                    keyURL.stopAccessingSecurityScopedResource()
                }
                Task { @MainActor in
                    if self.liveSSHProcess === process {
                        if shouldTerminate {
                            process.terminate()
                        }
                        if success {
                            self.runtimeState = state
                            self.sessionStartedAt = Date()
                            let startedAt = self.sessionStartedAt ?? Date()
                            self.brokerSessionDescriptor = self.makeBrokerDescriptor(
                                targetSummary: targetSummary,
                                startedAt: startedAt
                            )
                            self.sessionStatusDetail = self.makeBrokerActiveDetail(
                                targetSummary: targetSummary,
                                keyDisplayName: target.sshKeyDisplayName
                            )
                        } else {
                            self.liveSSHProcess = nil
                            self.runtimeState = self.activeTarget == nil ? .idle : state
                            self.sessionStartedAt = nil
                            self.sessionStatusDetail = detail
                            self.brokerSessionDescriptor = nil
                            self.attachedBrokerDescriptor = nil
                        }
                        self.persist()
                    }
                    continuation.resume(returning: success)
                }
            }

            process.terminationHandler = { terminatedProcess in
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let detail = stderrText.isEmpty
                    ? "SSH session ended before it became active."
                    : "SSH login failed: \(stderrText)"
                finish(
                    success: false,
                    state: .failed,
                    detail: detail,
                    shouldTerminate: terminatedProcess.isRunning
                )
            }

            do {
                try process.run()
                self.liveSSHProcess = process
            } catch {
                finish(success: false, state: .failed, detail: "SSH could not be started: \(error.localizedDescription)", shouldTerminate: false)
                return
            }

            let successDetail = self.makeBrokerActiveDetail(
                targetSummary: targetSummary,
                keyDisplayName: target.sshKeyDisplayName
            )
            connectionQueue.asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                finish(
                    success: true,
                    state: .active,
                    detail: successDetail,
                    shouldTerminate: false
                )
            }
        }
    }

    private func makeBrokerDescriptor(targetSummary: String, startedAt: Date) -> BrokerSessionDescriptor {
        let token = UUID().uuidString
        let listener = try? NWListener(using: .tcp, on: .any)
        brokerListener?.cancel()
        brokerListener = listener
        brokerAttachHost = preferredBrokerAttachHost()
        brokerAttachPort = nil
        brokerAttachToken = token

        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.connectionQueue)
            self.handleBrokerConnection(connection, expectedToken: token)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let port = listener?.port {
                    Task { @MainActor in
                        self.brokerAttachPort = Int(port.rawValue)
                        if let broker = self.brokerSessionDescriptor {
                            self.brokerSessionDescriptor = BrokerSessionDescriptor(
                                id: broker.id,
                                hostDisplayName: broker.hostDisplayName,
                                ownerPlatform: broker.ownerPlatform,
                                targetSummary: broker.targetSummary,
                                startedAt: broker.startedAt,
                                capabilities: broker.capabilities,
                                attachHost: self.brokerAttachHost,
                                attachPort: Int(port.rawValue),
                                attachToken: token
                            )
                            self.persist()
                        }
                    }
                }
            case .failed, .cancelled:
                Task { @MainActor in
                    self.brokerListener = nil
                    self.brokerAttachPort = nil
                }
            default:
                break
            }
        }
        listener?.start(queue: connectionQueue)

        return BrokerSessionDescriptor(
            id: UUID(),
            hostDisplayName: Host.current().localizedName ?? "This Mac",
            ownerPlatform: "macOS",
            targetSummary: targetSummary,
            startedAt: startedAt,
            capabilities: [.readOnlyBrowse, .readOnlyPreview, .explicitSavePlanned, .clientAttachPlanned],
            attachHost: brokerAttachHost,
            attachPort: nil,
            attachToken: token
        )
    }

    private func makeBrokerActiveDetail(targetSummary: String, keyDisplayName: String) -> String {
        let keyTitle = keyDisplayName.isEmpty ? "the selected key" : keyDisplayName
        return "SSH session active for \(targetSummary) using \(keyTitle). Remote clients can now attach, browse, open, and explicitly save supported text files."
    }

    private func preferredBrokerAttachHost() -> String {
        let candidates = Host.current().addresses
        if let lanAddress = candidates.first(where: { address in
            address.contains(".") &&
            address != "127.0.0.1" &&
            !address.hasPrefix("169.254.")
        }) {
            return lanAddress
        }
        return "127.0.0.1"
    }

    nonisolated private func handleBrokerConnection(_ connection: NWConnection, expectedToken: String) {
        let maximumBrokerMessageLength = 1_310_720
        connection.receive(minimumIncompleteLength: 1, maximumLength: maximumBrokerMessageLength) { [weak self] data, _, _, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.sendBrokerResponse(
                        RemoteBrokerResponse(success: false, detail: "Broker receive failed: \(error.localizedDescription)", path: nil, name: nil, content: nil, revision: nil, entries: nil, broker: nil),
                        on: connection
                    )
                    return
                }

                guard let data, !data.isEmpty else {
                    self.sendBrokerResponse(
                        RemoteBrokerResponse(success: false, detail: "Broker request was invalid.", path: nil, name: nil, content: nil, revision: nil, entries: nil, broker: nil),
                        on: connection
                    )
                    return
                }

                guard let request = try? JSONDecoder().decode(RemoteBrokerRequest.self, from: data) else {
                    self.sendBrokerResponse(
                        RemoteBrokerResponse(success: false, detail: "Broker request was invalid.", path: nil, name: nil, content: nil, revision: nil, entries: nil, broker: nil),
                        on: connection
                    )
                    return
                }

                guard request.token == expectedToken else {
                    self.sendBrokerResponse(
                        RemoteBrokerResponse(success: false, detail: "Broker token mismatch.", path: nil, name: nil, content: nil, revision: nil, entries: nil, broker: nil),
                        on: connection
                    )
                    return
                }

                switch request.method {
                case "handshake":
                    self.sendBrokerResponse(
                        RemoteBrokerResponse(
                            success: self.brokerSessionDescriptor != nil,
                            detail: self.brokerSessionDescriptor == nil
                                ? "The broker is no longer active."
                                : "Broker attach succeeded. Remote browsing, open, and explicit save are now available on this client.",
                            path: nil,
                            name: nil,
                            content: nil,
                            revision: nil,
                            entries: nil,
                            broker: self.brokerSessionDescriptor
                        ),
                        on: connection
                    )
                case "list":
                    guard let target = self.activeTarget else {
                        self.sendBrokerResponse(
                            RemoteBrokerResponse(success: false, detail: "The broker has no active SSH target.", path: nil, name: nil, content: nil, revision: nil, entries: nil, broker: self.brokerSessionDescriptor),
                            on: connection
                        )
                        return
                    }

                    let result = await self.runRemoteBrowseCommandMac(
                        target: target,
                        path: request.path ?? "~",
                        timeout: 8
                    )

                    let response: RemoteBrokerResponse
                    switch result {
                    case .success(let payload):
                        response = RemoteBrokerResponse(
                            success: true,
                            detail: payload.entries.isEmpty
                                ? "No entries found in \(payload.path)."
                                : "Loaded \(payload.entries.count) entr\(payload.entries.count == 1 ? "y" : "ies") from \(payload.path).",
                            path: payload.path,
                            name: nil,
                            content: nil,
                            revision: nil,
                            entries: payload.entries.map {
                                RemoteBrokerFileEntryPayload(name: $0.name, path: $0.path, isDirectory: $0.isDirectory)
                            },
                            broker: self.brokerSessionDescriptor
                        )
                    case .failure(let detail):
                        response = RemoteBrokerResponse(
                            success: false,
                            detail: detail,
                            path: request.path,
                            name: nil,
                            content: nil,
                            revision: nil,
                            entries: [],
                            broker: self.brokerSessionDescriptor
                        )
                    }

                    self.sendBrokerResponse(response, on: connection)
                case "open":
                    guard let target = self.activeTarget else {
                        self.sendBrokerResponse(
                            RemoteBrokerResponse(success: false, detail: "The broker has no active SSH target.", path: request.path, name: nil, content: nil, revision: nil, entries: nil, broker: self.brokerSessionDescriptor),
                            on: connection
                        )
                        return
                    }

                    guard let requestedPath = request.path else {
                        self.sendBrokerResponse(
                            RemoteBrokerResponse(success: false, detail: "Remote open needs a file path.", path: nil, name: nil, content: nil, revision: nil, entries: nil, broker: self.brokerSessionDescriptor),
                            on: connection
                        )
                        return
                    }

                    let result = await self.runRemoteReadCommandMac(target: target, path: requestedPath, timeout: 8)
                    let response: RemoteBrokerResponse
                    switch result {
                    case .success(let document):
                        response = RemoteBrokerResponse(
                            success: true,
                            detail: "Opened \(document.name) for remote editing.",
                            path: document.path,
                            name: document.name,
                            content: document.content,
                            revision: document.revisionToken,
                            entries: nil,
                            broker: self.brokerSessionDescriptor
                        )
                    case .failure(let detail):
                        response = RemoteBrokerResponse(
                            success: false,
                            detail: detail,
                            path: requestedPath,
                            name: nil,
                            content: nil,
                            revision: nil,
                            entries: nil,
                            broker: self.brokerSessionDescriptor
                        )
                    }
                    self.sendBrokerResponse(response, on: connection)
                case "save":
                    guard let target = self.activeTarget else {
                        self.sendBrokerResponse(
                            RemoteBrokerResponse(success: false, detail: "The broker has no active SSH target.", path: request.path, name: nil, content: nil, revision: nil, entries: nil, broker: self.brokerSessionDescriptor),
                            on: connection
                        )
                        return
                    }
                    guard let requestedPath = request.path, let content = request.content else {
                        self.sendBrokerResponse(
                            RemoteBrokerResponse(success: false, detail: "Remote save needs a file path and document content.", path: request.path, name: nil, content: nil, revision: nil, entries: nil, broker: self.brokerSessionDescriptor),
                            on: connection
                        )
                        return
                    }
                    if let expectedRevision = request.expectedRevision {
                        let preflightResult = await self.runRemoteReadCommandMac(target: target, path: requestedPath, timeout: 8)
                        switch preflightResult {
                        case .success(let document):
                            if document.revisionToken != expectedRevision {
                                self.sendBrokerResponse(
                                    RemoteBrokerResponse(
                                        success: false,
                                        detail: "The remote file changed remotely since it was opened. Re-open it before saving again.",
                                        path: requestedPath,
                                        name: document.name,
                                        content: nil,
                                        revision: document.revisionToken,
                                        entries: nil,
                                        broker: self.brokerSessionDescriptor
                                    ),
                                    on: connection
                                )
                                return
                            }
                        case .failure(let detail):
                            self.sendBrokerResponse(
                                RemoteBrokerResponse(
                                    success: false,
                                    detail: detail,
                                    path: requestedPath,
                                    name: nil,
                                    content: nil,
                                    revision: expectedRevision,
                                    entries: nil,
                                    broker: self.brokerSessionDescriptor
                                ),
                                on: connection
                            )
                            return
                        }
                    }
                    let result = await self.runRemoteWriteCommandMac(target: target, path: requestedPath, content: content, timeout: 8)
                    let response: RemoteBrokerResponse
                    switch result {
                    case .success(let detail):
                        response = RemoteBrokerResponse(success: true, detail: detail, path: requestedPath, name: nil, content: nil, revision: self.makeRemoteRevisionToken(for: content), entries: nil, broker: self.brokerSessionDescriptor)
                    case .failure(let detail):
                        response = RemoteBrokerResponse(success: false, detail: detail, path: requestedPath, name: nil, content: nil, revision: request.expectedRevision, entries: nil, broker: self.brokerSessionDescriptor)
                    }
                    self.sendBrokerResponse(response, on: connection)
                default:
                    self.sendBrokerResponse(
                        RemoteBrokerResponse(success: false, detail: "Broker method is unsupported.", path: nil, name: nil, content: nil, revision: nil, entries: nil, broker: nil),
                        on: connection
                    )
                }
            }
        }
    }

    private func sendBrokerResponse(_ response: RemoteBrokerResponse, on connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(response) else {
            connection.cancel()
            return
        }
        sendBrokerResponseData(data, on: connection)
    }

    nonisolated private func sendBrokerResponseData(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func runRemoteBrowseCommandMac(
        target: SavedTarget,
        path: String,
        timeout: TimeInterval
    ) async -> RemoteBrowseResult {
        guard let bookmarkData = target.sshKeyBookmarkData else {
            return .failure("The selected SSH key is no longer available.")
        }
        guard let keyURL = resolveSecurityScopedBookmarkMac(bookmarkData) else {
            return .failure("The selected SSH key could not be resolved. Re-select the key file.")
        }

        let didAccessKey = keyURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessKey {
                keyURL.stopAccessingSecurityScopedResource()
            }
        }

        let loginTarget = target.username.isEmpty ? target.host : "\(target.username)@\(target.host)"
        let connectTimeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let remotePath = normalizedRemoteBrowserPath(path)
        let remoteCommand = makeRemoteBrowseCommand(for: remotePath)

        return await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-i", keyURL.path,
                "-o", "BatchMode=yes",
                "-o", "IdentitiesOnly=yes",
                "-o", "StrictHostKeyChecking=yes",
                "-o", "NumberOfPasswordPrompts=0",
                "-o", "PreferredAuthentications=publickey",
                "-o", "PubkeyAuthentication=yes",
                "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
                "-p", "\(target.port)",
                loginTarget,
                remoteCommand
            ]
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { terminatedProcess in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(data: outputData, encoding: .utf8) ?? ""
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if terminatedProcess.terminationStatus != 0 {
                    continuation.resume(returning: .failure(errorText.isEmpty ? "Remote file browser failed." : "Remote file browser failed: \(errorText)"))
                    return
                }

                guard let payload = self.parseRemoteBrowsePayload(outputText) else {
                    continuation.resume(returning: .failure("Remote file browser returned an unreadable listing."))
                    return
                }

                continuation.resume(returning: .success(payload))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure("SSH browser command could not be started: \(error.localizedDescription)"))
                return
            }

            connectionQueue.asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
            }
        }
    }

    private func runRemoteReadCommandMac(
        target: SavedTarget,
        path: String,
        timeout: TimeInterval
    ) async -> RemoteReadResult {
        guard let bookmarkData = target.sshKeyBookmarkData else {
            return .failure("The selected SSH key is no longer available.")
        }
        guard let keyURL = resolveSecurityScopedBookmarkMac(bookmarkData) else {
            return .failure("The selected SSH key could not be resolved. Re-select the key file.")
        }

        let didAccessKey = keyURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessKey {
                keyURL.stopAccessingSecurityScopedResource()
            }
        }

        let loginTarget = target.username.isEmpty ? target.host : "\(target.username)@\(target.host)"
        let connectTimeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let remotePath = normalizedRemoteBrowserPath(path)
        let remoteCommand = makeRemoteReadCommand(for: remotePath)
        let outputMarker = Data("__NVE_REMOTE_FILE__\n".utf8)

        return await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-i", keyURL.path,
                "-o", "BatchMode=yes",
                "-o", "IdentitiesOnly=yes",
                "-o", "StrictHostKeyChecking=yes",
                "-o", "NumberOfPasswordPrompts=0",
                "-o", "PreferredAuthentications=publickey",
                "-o", "PubkeyAuthentication=yes",
                "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
                "-p", "\(target.port)",
                loginTarget,
                remoteCommand
            ]
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { terminatedProcess in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if terminatedProcess.terminationStatus != 0 {
                    continuation.resume(returning: .failure(errorText.isEmpty ? "Remote file preview failed." : "Remote file preview failed: \(errorText)"))
                    return
                }

                guard outputData.starts(with: outputMarker) else {
                    continuation.resume(returning: .failure("Remote file preview returned unreadable data."))
                    return
                }

                let payloadData = outputData.dropFirst(outputMarker.count)
                let previewByteLimit = 1_048_576
                if payloadData.count > previewByteLimit {
                    continuation.resume(returning: .failure("Remote file open is limited to 1 MB per document."))
                    return
                }

                let content = String(decoding: payloadData, as: UTF8.self)
                let name = URL(fileURLWithPath: remotePath).lastPathComponent
                continuation.resume(
                    returning: .success(
                        RemotePreviewDocument(
                            name: name,
                            path: remotePath,
                            content: content,
                            isReadOnly: false,
                            revisionToken: self.makeRemoteRevisionToken(for: content)
                        )
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure("SSH preview command could not be started: \(error.localizedDescription)"))
                return
            }

            connectionQueue.asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
            }
        }
    }

    private nonisolated func makeRemoteBrowseCommand(for path: String) -> String {
        let pathArgument = path == "~" ? "~" : shellQuoted(path)
        return "cd -- \(pathArgument) && pwd && printf '__NVE_BROWSER__\\n' && LC_ALL=C /bin/ls -1ApA"
    }

    private nonisolated func makeRemoteReadCommand(for path: String) -> String {
        let pathArgument = path == "~" ? "~" : shellQuoted(path)
        return "printf '__NVE_REMOTE_FILE__\\n' && LC_ALL=C /usr/bin/head -c 1048577 -- \(pathArgument)"
    }

    private func runRemoteWriteCommandMac(
        target: SavedTarget,
        path: String,
        content: String,
        timeout: TimeInterval
    ) async -> RemoteWriteResult {
        guard let bookmarkData = target.sshKeyBookmarkData else {
            return .failure("The selected SSH key is no longer available.")
        }
        guard let keyURL = resolveSecurityScopedBookmarkMac(bookmarkData) else {
            return .failure("The selected SSH key could not be resolved. Re-select the key file.")
        }

        let didAccessKey = keyURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessKey {
                keyURL.stopAccessingSecurityScopedResource()
            }
        }

        let loginTarget = target.username.isEmpty ? target.host : "\(target.username)@\(target.host)"
        let connectTimeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let remotePath = normalizedRemoteBrowserPath(path)
        let remoteCommand = makeRemoteWriteCommand(for: remotePath)
        let inputData = Data(content.utf8)

        return await withCheckedContinuation { continuation in
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-i", keyURL.path,
                "-o", "BatchMode=yes",
                "-o", "IdentitiesOnly=yes",
                "-o", "StrictHostKeyChecking=yes",
                "-o", "NumberOfPasswordPrompts=0",
                "-o", "PreferredAuthentications=publickey",
                "-o", "PubkeyAuthentication=yes",
                "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
                "-p", "\(target.port)",
                loginTarget,
                remoteCommand
            ]
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { terminatedProcess in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(data: outputData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if terminatedProcess.terminationStatus != 0 {
                    continuation.resume(returning: .failure(errorText.isEmpty ? "Remote save failed." : "Remote save failed: \(errorText)"))
                    return
                }

                guard outputText.contains("__NVE_REMOTE_SAVE_OK__") else {
                    continuation.resume(returning: .failure("Remote save did not report success."))
                    return
                }

                continuation.resume(returning: .success("Saved \(remotePath) to the remote session."))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure("SSH save command could not be started: \(error.localizedDescription)"))
                return
            }

            self.connectionQueue.async {
                inputPipe.fileHandleForWriting.write(inputData)
                try? inputPipe.fileHandleForWriting.close()
            }

            connectionQueue.asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
            }
        }
    }

    private nonisolated func makeRemoteWriteCommand(for path: String) -> String {
        let pathArgument = path == "~" ? "~" : shellQuoted(path)
        return "target=\(pathArgument); dir=$(/usr/bin/dirname -- \"$target\"); tmp=$(/usr/bin/mktemp \"$dir/.nve-remote-save.XXXXXX\") && /bin/cat > \"$tmp\" && /bin/mv \"$tmp\" \"$target\" && printf '__NVE_REMOTE_SAVE_OK__\\n'"
    }

    private nonisolated func parseRemoteBrowsePayload(_ output: String) -> RemoteBrowsePayload? {
        let separator = "\n__NVE_BROWSER__\n"
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmedOutput.range(of: separator) else { return nil }
        let path = String(trimmedOutput[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let listing = String(trimmedOutput[range.upperBound...])
        let entries = listing
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawEntry -> RemoteFileEntry? in
                let line = String(rawEntry)
                guard line != "." && line != ".." else { return nil }
                let isDirectory = line.hasSuffix("/")
                let displayName = isDirectory ? String(line.dropLast()) : line
                let fullPath = path == "/" ? "/\(displayName)" : "\(path)/\(displayName)"
                let isSupportedTextFile = isDirectory || EditorViewModel.isSupportedEditorFileURL(URL(fileURLWithPath: fullPath))
                return RemoteFileEntry(
                    name: displayName,
                    path: fullPath,
                    isDirectory: isDirectory,
                    isSupportedTextFile: isSupportedTextFile
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        return RemoteBrowsePayload(path: path.isEmpty ? "~" : path, entries: entries)
    }

    private nonisolated func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private nonisolated func makeRemoteRevisionToken(for content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func resolveSecurityScopedBookmarkMac(_ data: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return resolved
    }
#endif

    private nonisolated func normalizedRemoteBrowserPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "~" : trimmed
    }
}
