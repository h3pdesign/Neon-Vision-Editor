import Foundation
import os

extension Notification.Name {
    static let neonPulseDocumentDidSave = Notification.Name("NeonPulseDocumentDidSave")
}

#if os(iOS) && canImport(WatchConnectivity)
import WatchConnectivity

@MainActor
final class NeonPulsePhoneBridge {
    static let shared = NeonPulsePhoneBridge()

    private weak var viewModel: EditorViewModel?
    private let processedIDsKey = "NeonPulseProcessedCaptureIDsV1"
    private var lastSuccessfulSave: Date?
    private var saveObserver: NSObjectProtocol?
    private let transport = NeonPulsePhoneTransport()
    private let logger = Logger(subsystem: "h3p.Neon-Vision-Editor", category: "WatchConnectivity")

    func activateConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = transport
        session.activate()
    }

    func start(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        ensureInboxFileExists()
        guard WCSession.isSupported() else { return }
        activateConnectivity()
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

    func receivePayloadData(_ data: Data) {
        guard let capture = NeonPulseCodec.decode(NeonPulseCapture.self, from: data) else { return }
        _ = receive(capture, session: WCSession.default)
    }

    @discardableResult
    @MainActor
    private func receive(_ capture: NeonPulseCapture, session: WCSession) -> Bool {
        var processed = Set(UserDefaults.standard.stringArray(forKey: processedIDsKey) ?? [])
        if processed.contains(capture.id.uuidString) {
            session.transferUserInfo(NeonPulseDeliveryReceipt.payload(for: capture.id))
            return true
        }

        // Acknowledge only after the note is safely written. The watch keeps
        // an unacknowledged capture and can retry it if this write fails.
        guard appendToInbox(capture) else {
            return false
        }
        processed.insert(capture.id.uuidString)
        UserDefaults.standard.set(Array(processed.suffix(500)), forKey: processedIDsKey)
        publishStatus()
        session.transferUserInfo(NeonPulseDeliveryReceipt.payload(for: capture.id))
        return true
    }

    private func appendToInbox(_ capture: NeonPulseCapture) -> Bool {
        guard let directory = ShareImportHandoff.sharedImportDirectory() else {
            logger.error("Watch capture could not access app group container")
            return false
        }
        guard let url = NeonPulseInboxWriter.append(capture, to: directory) else {
            logger.error("Watch capture could not append Neon Inbox.md")
            return false
        }
        SharedImportStore.remember([url])
        SharedImportNotificationBridge.postPendingImport()
        NotificationCenter.default.post(name: .neonPulseInboxDidReceive, object: url)
        return true
    }

    private func ensureInboxFileExists() {
        guard let directory = ShareImportHandoff.sharedImportDirectory() else { return }
        let url = directory.appendingPathComponent(NeonPulseConstants.inboxFilename)
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

/// The Objective-C WatchConnectivity entry point. It deliberately owns no UI
/// state: WatchConnectivity invokes these methods on a background queue while
/// this target defaults Swift declarations to MainActor isolation.
nonisolated final class NeonPulsePhoneTransport: NSObject, WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor in
            NeonPulsePhoneBridge.shared.publishStatus()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[NeonPulseConstants.capturePayloadKey] as? Data else { return }
        deliver(data)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let data = message[NeonPulseConstants.capturePayloadKey] as? Data else {
            replyHandler([:])
            return
        }
        // A durable receipt is transferred only after the main-actor inbox write.
        replyHandler([:])
        deliver(data)
    }

    nonisolated static func deliver(
        _ data: Data,
        handler: @escaping @MainActor @Sendable (Data) -> Void = { data in
            NeonPulsePhoneBridge.shared.receivePayloadData(data)
        }
    ) {
        Task { @MainActor in
            handler(data)
        }
    }

    private nonisolated func deliver(_ data: Data) {
        Self.deliver(data)
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
        let url = directory.appendingPathComponent(NeonPulseConstants.inboxFilename)
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
