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

        var id: String { path }
    }

    struct RemotePreviewDocument: Equatable {
        let name: String
        let path: String
        let content: String
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
    private(set) var remoteBrowserEntries: [RemoteFileEntry] = []
    private(set) var remoteBrowserPath: String = "~"
    private(set) var remoteBrowserStatusDetail: String = ""
    private(set) var isRemoteBrowserLoading: Bool = false
    private var liveConnection: NWConnection? = nil
#if os(macOS)
    private var liveSSHProcess: Process? = nil
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
        clearRemoteBrowserState()
    }

#if os(macOS)
    func loadRemoteDirectory(path: String? = nil, timeout: TimeInterval = 8) async -> Bool {
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
    }

    func openRemoteFilePreview(path: String, timeout: TimeInterval = 8) async -> RemotePreviewDocument? {
        guard isRemotePreviewConnected, let target = activeTarget else {
            remoteBrowserStatusDetail = "Start a remote session before opening a remote file."
            return nil
        }
        guard target.sshKeyBookmarkData != nil else {
            remoteBrowserStatusDetail = "Remote file preview requires an SSH-key session on macOS."
            return nil
        }

        let requestedPath = normalizedRemoteBrowserPath(path)
        guard EditorViewModel.isSupportedEditorFileURL(URL(fileURLWithPath: requestedPath)) else {
            remoteBrowserStatusDetail = "Only supported text files can be opened as a remote preview."
            return nil
        }

        remoteBrowserStatusDetail = "Opening \(requestedPath)…"

        let result = await runRemoteReadCommandMac(target: target, path: requestedPath, timeout: timeout)
        switch result {
        case .success(let document):
            remoteBrowserStatusDetail = "Opened \(document.name) as a read-only remote preview."
            return document
        case .failure(let detail):
            remoteBrowserStatusDetail = detail
            return nil
        }
    }
#endif

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
#if os(macOS)
        liveSSHProcess?.terminate()
        liveSSHProcess = nil
#endif
    }

    private func clearRemoteBrowserState() {
        remoteBrowserEntries = []
        remoteBrowserPath = "~"
        remoteBrowserStatusDetail = ""
        isRemoteBrowserLoading = false
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
                            self.sessionStatusDetail = detail
                        } else {
                            self.liveSSHProcess = nil
                            self.runtimeState = self.activeTarget == nil ? .idle : state
                            self.sessionStartedAt = nil
                            self.sessionStatusDetail = detail
                        }
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

            connectionQueue.asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                finish(
                    success: true,
                    state: .active,
                    detail: "SSH session active for \(targetSummary) using \(target.sshKeyDisplayName.isEmpty ? "the selected key" : target.sshKeyDisplayName).",
                    shouldTerminate: false
                )
            }
        }
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
                    continuation.resume(returning: .failure("Remote file preview is limited to 1 MB in Phase 7."))
                    return
                }

                let content = String(decoding: payloadData, as: UTF8.self)
                let name = URL(fileURLWithPath: remotePath).lastPathComponent
                continuation.resume(returning: .success(RemotePreviewDocument(name: name, path: remotePath, content: content)))
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

    private nonisolated func normalizedRemoteBrowserPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "~" : trimmed
    }

    private nonisolated func makeRemoteBrowseCommand(for path: String) -> String {
        let pathArgument = path == "~" ? "~" : shellQuoted(path)
        return "cd -- \(pathArgument) && pwd && printf '__NVE_BROWSER__\\n' && LC_ALL=C /bin/ls -1ApA"
    }

    private nonisolated func makeRemoteReadCommand(for path: String) -> String {
        let pathArgument = path == "~" ? "~" : shellQuoted(path)
        return "printf '__NVE_REMOTE_FILE__\\n' && LC_ALL=C /usr/bin/head -c 1048577 -- \(pathArgument)"
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
                return RemoteFileEntry(name: displayName, path: fullPath, isDirectory: isDirectory)
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
}
