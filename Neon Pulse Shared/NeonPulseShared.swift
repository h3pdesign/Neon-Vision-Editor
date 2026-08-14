import Foundation

enum NeonPulseConstants {
    static let appGroupIdentifier = "group.h3p.Neon-Vision-Editor"
    static let inboxFilename = "Neon Inbox.md"
    static let capturesKey = "NeonPulseCapturesV1"
    static let statusKey = "NeonPulseStatusV1"
    nonisolated static let capturePayloadKey = "neonPulseCapture"
    static let statusPayloadKey = "neonPulseStatus"
    nonisolated static let deliveredCaptureIDKey = "neonPulseDeliveredID"
    static let maximumCaptureCount = 50
}

enum NeonPulseDeliveryReceipt {
    nonisolated static func payload(for captureID: UUID) -> [String: Any] {
        [NeonPulseConstants.deliveredCaptureIDKey: captureID.uuidString]
    }

    nonisolated static func captureID(from payload: [String: Any]) -> UUID? {
        guard let value = payload[NeonPulseConstants.deliveredCaptureIDKey] as? String else { return nil }
        return UUID(uuidString: value)
    }
}

struct NeonPulseCapture: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    var deliveredAt: Date?

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), deliveredAt: Date? = nil) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.deliveredAt = deliveredAt
    }

}

struct NeonPulseStatus: Codable, Equatable, Sendable {
    var projectName: String
    var currentDocument: String?
    var pendingChanges: Int
    var hasConflict: Bool
    var lastSuccessfulSave: Date?
    var updatedAt: Date

    static let empty = NeonPulseStatus(
        projectName: "Neon Vision Editor",
        currentDocument: nil,
        pendingChanges: 0,
        hasConflict: false,
        lastSuccessfulSave: nil,
        updatedAt: .distantPast
    )
}

enum NeonPulseCodec {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(type, from: data)
    }
}

struct NeonPulseStore {
    private static let lock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: NeonPulseConstants.appGroupIdentifier)) {
        self.defaults = defaults ?? .standard
    }

    func captures() -> [NeonPulseCapture] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return loadCaptures()
    }

    private func loadCaptures() -> [NeonPulseCapture] {
        guard let data = defaults.data(forKey: NeonPulseConstants.capturesKey),
              let captures = NeonPulseCodec.decode([NeonPulseCapture].self, from: data) else { return [] }
        return captures.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func addCapture(text: String, now: Date = Date()) -> NeonPulseCapture? {
        let capture = NeonPulseCapture(text: text, createdAt: now)
        guard !capture.text.isEmpty else { return nil }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var items = loadCaptures()
        items.removeAll { $0.id == capture.id }
        items.insert(capture, at: 0)
        saveCaptures(Array(items.prefix(NeonPulseConstants.maximumCaptureCount)))
        return capture
    }

    func markDelivered(id: UUID, at date: Date = Date()) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var items = loadCaptures()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].deliveredAt = date
        saveCaptures(items)
    }

    func status() -> NeonPulseStatus {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let data = defaults.data(forKey: NeonPulseConstants.statusKey),
              let status = NeonPulseCodec.decode(NeonPulseStatus.self, from: data) else { return .empty }
        return status
    }

    func saveStatus(_ status: NeonPulseStatus) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        defaults.set(NeonPulseCodec.encode(status), forKey: NeonPulseConstants.statusKey)
    }

    private func saveCaptures(_ captures: [NeonPulseCapture]) {
        defaults.set(NeonPulseCodec.encode(captures), forKey: NeonPulseConstants.capturesKey)
    }
}
