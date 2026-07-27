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

    func start(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
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
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor in publishStatus() }
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

    private func receive(_ capture: NeonPulseCapture, session: WCSession) {
        var processed = Set(UserDefaults.standard.stringArray(forKey: processedIDsKey) ?? [])
        if processed.contains(capture.id.uuidString) {
            session.transferUserInfo(["neonPulseDeliveredID": capture.id.uuidString])
            return
        }

        // Acknowledge only after the note is safely written. Leaving the
        // transfer outstanding lets the watch retry when the shared inbox is
        // temporarily unavailable.
        guard appendToInbox(capture) else { return }
        processed.insert(capture.id.uuidString)
        UserDefaults.standard.set(Array(processed.suffix(500)), forKey: processedIDsKey)
        publishStatus()
        session.transferUserInfo(["neonPulseDeliveredID": capture.id.uuidString])
    }

    private func appendToInbox(_ capture: NeonPulseCapture) -> Bool {
        guard let directory = ShareImportHandoff.sharedImportDirectory() else { return false }
        let url = directory.appendingPathComponent("Neon Inbox.md")
        let formatter = ISO8601DateFormatter()
        let entry = "\n- [ ] \(capture.text.replacingOccurrences(of: "\n", with: " "))\n  - Captured: \(formatter.string(from: capture.createdAt))\n"
        do {
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? "# Neon Inbox\n"
            try (existing + entry).write(to: url, atomically: true, encoding: .utf8)
            SharedImportStore.remember([url])
            SharedImportNotificationBridge.postPendingImport()
            return true
        } catch {
            return false
        }
    }
}
#endif
