import Foundation
import Observation
import WatchConnectivity
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Owns WatchConnectivity's Objective-C callbacks. WatchConnectivity invokes
/// delegate and message-handler blocks on its own queues, so this type must
/// never capture the main-actor observable model in those entry points.
nonisolated final class NeonPulseWatchTransport: NSObject, WCSessionDelegate {
    private let session = WCSession.default
    private let onActivation: @MainActor @Sendable (Bool) -> Void
    private let onStatus: @MainActor @Sendable (Data) -> Void
    private let onReceipt: @MainActor @Sendable (UUID) -> Void
    private let onDeliveryFailure: @MainActor @Sendable () -> Void

    @MainActor
    init(
        onActivation: @escaping @MainActor @Sendable (Bool) -> Void,
        onStatus: @escaping @MainActor @Sendable (Data) -> Void,
        onReceipt: @escaping @MainActor @Sendable (UUID) -> Void,
        onDeliveryFailure: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onActivation = onActivation
        self.onStatus = onStatus
        self.onReceipt = onReceipt
        self.onDeliveryFailure = onDeliveryFailure
        super.init()
    }

    @MainActor
    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    @MainActor
    var activationState: WCSessionActivationState { session.activationState }

    @MainActor
    var isReachable: Bool { session.isReachable }

    @MainActor
    func queueUserInfoIfNeeded(_ payload: [String: Any], captureID: UUID) {
        let alreadyQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let queuedData = transfer.userInfo[NeonPulseConstants.capturePayloadKey] as? Data,
                  let queuedCapture = NeonPulseCodec.decode(NeonPulseCapture.self, from: queuedData) else {
                return false
            }
            return queuedCapture.id == captureID
        }
        if !alreadyQueued {
            session.transferUserInfo(payload)
        }
    }

    @MainActor
    func sendMessage(_ payload: [String: Any], captureID: UUID) {
        let replyHandler: @Sendable ([String: Any]) -> Void = { [onReceipt] receipt in
            guard let id = NeonPulseDeliveryReceipt.captureID(from: receipt), id == captureID else { return }
            Task { @MainActor in
                onReceipt(id)
            }
        }
        let errorHandler: @Sendable (Error) -> Void = { [onDeliveryFailure] _ in
            Task { @MainActor in
                onDeliveryFailure()
            }
        }
        session.sendMessage(payload, replyHandler: replyHandler, errorHandler: errorHandler)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let activated = activationState == .activated && error == nil
        Task { @MainActor [onActivation] in
            onActivation(activated)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["neonPulseStatus"] as? Data else { return }
        Task { @MainActor [onStatus] in
            onStatus(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let id = NeonPulseDeliveryReceipt.captureID(from: userInfo) else { return }
        Task { @MainActor [onReceipt] in
            onReceipt(id)
        }
    }
}

@MainActor
@Observable
final class NeonPulseWatchModel: NSObject {
    private(set) var captures: [NeonPulseCapture] = []
    private(set) var status: NeonPulseStatus = .empty
    private(set) var connectionLabel = NSLocalizedString("Waiting for iPhone", comment: "Watch connectivity status")
    private let store = NeonPulseStore()
    @ObservationIgnored private lazy var transport = NeonPulseWatchTransport(
        onActivation: { [weak self] activated in self?.handleActivation(activated) },
        onStatus: { [weak self] data in self?.receiveStatusData(data) },
        onReceipt: { [weak self] id in self?.markDelivered(id) },
        onDeliveryFailure: { [weak self] in self?.markDeliveryQueued() }
    )

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
        let pendingCaptures = captures.filter { $0.deliveredAt == nil }
        guard !pendingCaptures.isEmpty else {
            connectionLabel = NSLocalizedString("Ready", comment: "Watch connectivity status")
            return
        }

        activateConnectivity()
        guard transport.activationState == .activated else {
            connectionLabel = NSLocalizedString("Connecting to iPhone", comment: "Watch connectivity status")
            return
        }
        pendingCaptures.reversed().forEach(queue)
    }

    private func activateConnectivity() {
        transport.activate()
    }

    private func queue(_ capture: NeonPulseCapture) {
        guard transport.activationState == .activated,
              let data = NeonPulseCodec.encode(capture) else {
            connectionLabel = NSLocalizedString("Saved on Apple Watch", comment: "Watch connectivity status")
            return
        }
        let payload = [NeonPulseConstants.capturePayloadKey: data]
        transport.queueUserInfoIfNeeded(payload, captureID: capture.id)
        guard transport.isReachable else {
            connectionLabel = NSLocalizedString("Queued for iPhone", comment: "Watch connectivity status")
            return
        }
        connectionLabel = NSLocalizedString("Delivering to iPhone", comment: "Watch connectivity status")
        transport.sendMessage(payload, captureID: capture.id)
    }

    private func reload() {
        captures = store.captures()
        status = store.status()
        WidgetCenter.shared.reloadTimelines(ofKind: "NeonPulseStatus")
    }
    private func handleActivation(_ activated: Bool) {
        connectionLabel = activated
            ? NSLocalizedString("Ready", comment: "Watch connectivity status")
            : NSLocalizedString("Saved on Apple Watch", comment: "Watch connectivity status")
        if activated { retryPendingCaptures() }
    }

    private func receiveStatusData(_ data: Data) {
        guard let status = NeonPulseCodec.decode(NeonPulseStatus.self, from: data) else { return }
        store.saveStatus(status)
        reload()
    }

    private func markDeliveryQueued() {
        connectionLabel = NSLocalizedString("Queued for iPhone", comment: "Watch connectivity status")
    }

    private func markDelivered(_ id: UUID) {
        store.markDelivered(id: id)
        connectionLabel = NSLocalizedString("Delivered", comment: "Watch connectivity status")
        reload()
    }
}
