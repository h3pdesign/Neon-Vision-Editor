import Foundation
import Observation
import WatchConnectivity
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
@Observable
final class NeonPulseWatchModel: NSObject {
    private(set) var captures: [NeonPulseCapture] = []
    private(set) var status: NeonPulseStatus = .empty
    private(set) var connectionLabel = NSLocalizedString("Waiting for iPhone", comment: "Watch connectivity status")
    private let store = NeonPulseStore()

    override init() {
        super.init()
        reload()
        activateConnectivity()
    }

    var pendingCaptureCount: Int { captures.lazy.filter { $0.deliveredAt == nil }.count }

    @discardableResult
    func capture(_ text: String) -> Bool {
        guard let capture = store.addCapture(text: text) else { return false }
        reload()
        queue(capture)
        return true
    }

    func retryPendingCaptures() {
        captures.filter { $0.deliveredAt == nil }.reversed().forEach(queue)
    }

    private func activateConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func queue(_ capture: NeonPulseCapture) {
        guard WCSession.default.activationState == .activated,
              let data = NeonPulseCodec.encode(capture) else {
            connectionLabel = NSLocalizedString("Saved on Apple Watch", comment: "Watch connectivity status")
            return
        }
        let session = WCSession.default
        let payload = [NeonPulseConstants.capturePayloadKey: data]
        session.transferUserInfo(payload)
        connectionLabel = NSLocalizedString("Queued for iPhone", comment: "Watch connectivity status")
        guard session.isReachable else { return }
        session.sendMessage(payload, replyHandler: { [weak self] receipt in
            guard let id = NeonPulseDeliveryReceipt.captureID(from: receipt), id == capture.id else { return }
            Task { @MainActor in
                self?.markDelivered(id)
            }
        }, errorHandler: nil)
    }

    private func reload() {
        captures = store.captures()
        status = store.status()
        WidgetCenter.shared.reloadTimelines(ofKind: "NeonPulseStatus")
    }
}

extension NeonPulseWatchModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            connectionLabel = error == nil
                ? NSLocalizedString("Ready", comment: "Watch connectivity status")
                : NSLocalizedString("Saved on Apple Watch", comment: "Watch connectivity status")
            if activationState == .activated { retryPendingCaptures() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["neonPulseStatus"] as? Data
        Task { @MainActor in
            guard let data, let status = NeonPulseCodec.decode(NeonPulseStatus.self, from: data) else { return }
            store.saveStatus(status)
            reload()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let id = NeonPulseDeliveryReceipt.captureID(from: userInfo) else { return }
        Task { @MainActor in
            markDelivered(id)
        }
    }

    private func markDelivered(_ id: UUID) {
        store.markDelivered(id: id)
        connectionLabel = NSLocalizedString("Delivered", comment: "Watch connectivity status")
        reload()
    }
}
