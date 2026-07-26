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
    private(set) var connectionLabel = "Waiting for iPhone"
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
            connectionLabel = "Saved on Apple Watch"
            return
        }
        WCSession.default.transferUserInfo([NeonPulseConstants.capturePayloadKey: data])
        connectionLabel = "Queued for iPhone"
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
            connectionLabel = error == nil ? "Ready" : "Saved on Apple Watch"
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
        guard let idText = userInfo["neonPulseDeliveredID"] as? String,
              let id = UUID(uuidString: idText) else { return }
        Task { @MainActor in
            store.markDelivered(id: id)
            connectionLabel = "Delivered"
            reload()
        }
    }
}
