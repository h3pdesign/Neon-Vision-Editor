import Foundation

extension Notification.Name {
    static let neonPulseDocumentDidSave = Notification.Name("NeonPulseDocumentDidSave")
}

#if os(iOS) && canImport(WatchConnectivity)
import WatchConnectivity

@MainActor
final class NeonPulsePhoneBridge: NSObject, WCSessionDelegate {
    static let shared = NeonPulsePhoneBridge()

    private weak var viewModel: EditorViewModel?
    private let processedIDsKey = "NeonPulseProcessedCaptureIDsV1"
    private var lastSuccessfulSave: Date?
    private var saveObserver: NSObjectProtocol?
    private var activationRetryTask: Task<Void, Never>?

    func activateConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func start(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        ensureInboxFileExists()
        guard WCSession.isSupported() else { return }
        activateConnectivity()
        retryPendingWatchDeliveryIfNeeded()
        if saveObserver == nil {
            saveObserver = NotificationCenter.default.addObserver(
                forName: .neonPulseDocumentDidSave,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.lastSuccessfulSave = .now
                    self?.publishStatus()
                }
            }
        }
        publishStatus()
    }

    func publishStatus() {
        guard WCSession.default.activationState == .activated, let viewModel else { return }
        let status = NeonPulseStatus(
            projectName: "Neon Vision Editor",
            currentDocument: viewModel.selectedTab?.name,
            pendingChanges: viewModel.tabs.filter(\.isDirty).count,
            hasConflict: viewModel.pendingExternalFileConflict != nil,
            lastSuccessfulSave: lastSuccessfulSave,
            updatedAt: .now
        )
        guard let data = NeonPulseCodec.encode(status) else { return }
        try? WCSession.default.updateApplicationContext([NeonPulseConstants.statusPayloadKey: data])
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated, error == nil else {
            Task { @MainActor in retryPendingWatchDeliveryIfNeeded() }
            return
        }
        Task { @MainActor in
            publishStatus()
            retryPendingWatchDeliveryIfNeeded()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    @MainActor func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[NeonPulseConstants.capturePayloadKey] as? Data,
              let capture = NeonPulseCodec.decode(NeonPulseCapture.self, from: data) else { return }
        receive(capture, session: session)
    }

    @MainActor func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let data = message[NeonPulseConstants.capturePayloadKey] as? Data,
              let capture = NeonPulseCodec.decode(NeonPulseCapture.self, from: data) else {
            replyHandler([:])
            return
        }
        replyHandler(receive(capture, session: session)
            ? NeonPulseDeliveryReceipt.payload(for: capture.id)
            : [:])
    }

    @discardableResult
    private func receive(_ capture: NeonPulseCapture, session: WCSession) -> Bool {
        var processed = Set(UserDefaults.standard.stringArray(forKey: processedIDsKey) ?? [])
        if processed.contains(capture.id.uuidString) {
            session.transferUserInfo(NeonPulseDeliveryReceipt.payload(for: capture.id))
            return true
        }

        // Acknowledge only after the note is safely written. Leaving the
        // transfer outstanding lets the watch retry when the shared inbox is
        // temporarily unavailable.
        guard appendToInbox(capture) else {
            retryPendingWatchDeliveryIfNeeded()
            return false
        }
        processed.insert(capture.id.uuidString)
        UserDefaults.standard.set(Array(processed.suffix(500)), forKey: processedIDsKey)
        publishStatus()
        session.transferUserInfo(NeonPulseDeliveryReceipt.payload(for: capture.id))
        return true
    }

    private func retryPendingWatchDeliveryIfNeeded() {
        guard activationRetryTask == nil else { return }
        activationRetryTask = Task { @MainActor [weak self] in
            defer { self?.activationRetryTask = nil }
            for _ in 0..<5 {
                guard !Task.isCancelled else { return }
                if WCSession.default.activationState == .activated {
                    self?.drainOutstandingWatchTransfers()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func drainOutstandingWatchTransfers() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for transfer in session.outstandingUserInfoTransfers {
            guard let data = transfer.userInfo[NeonPulseConstants.capturePayloadKey] as? Data,
                  let capture = NeonPulseCodec.decode(NeonPulseCapture.self, from: data) else {
                continue
            }
            receive(capture, session: session)
            transfer.cancel()
        }
    }

    private func appendToInbox(_ capture: NeonPulseCapture) -> Bool {
        guard let directory = ShareImportHandoff.sharedImportDirectory() else { return false }
        guard let url = NeonPulseInboxWriter.append(capture, to: directory) else { return false }
        SharedImportStore.remember([url])
        SharedImportNotificationBridge.postPendingImport()
        NotificationCenter.default.post(name: .neonPulseInboxDidReceive, object: url)
        return true
    }

    private func ensureInboxFileExists() {
        guard let directory = ShareImportHandoff.sharedImportDirectory() else { return }
        let url = directory.appendingPathComponent("Neon Inbox.md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try NeonPulseInboxWriter.createIfNeeded(at: url)
            SharedImportStore.remember([url])
            SharedImportNotificationBridge.postPendingImport()
        } catch {
            // The next capture retries creation through appendToInbox.
        }
    }
}
#endif

enum NeonPulseInboxWriter {
    static func createIfNeeded(at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try "# Neon Inbox\n".write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func append(_ capture: NeonPulseCapture, to directory: URL) -> URL? {
        let url = directory.appendingPathComponent("Neon Inbox.md")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try createIfNeeded(at: url)
            let formatter = ISO8601DateFormatter()
            let text = capture.text.replacingOccurrences(of: "\n", with: " ")
            let entry = "\n- [ ] \(text)\n  - Captured: \(formatter.string(from: capture.createdAt))\n"
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(entry.utf8))
            return url
        } catch {
            return nil
        }
    }
}
