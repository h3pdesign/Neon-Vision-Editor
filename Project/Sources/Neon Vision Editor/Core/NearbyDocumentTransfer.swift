import Foundation
import Combine
import CryptoKit
import Network
import Security

nonisolated struct NearbyDocumentOffer: Codable, Equatable, Sendable {
    static let maximumBytes = 4 * 1_024 * 1_024
    let version: Int
    let name: String
    let byteCount: Int
    let encoding: TextEncodingDescriptor.Identifier
    let digest: Data

    func validate() throws {
        guard version == 1, byteCount >= 0, byteCount <= Self.maximumBytes,
              digest.count == 32, !name.isEmpty, name.utf8.count <= 200,
              name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw NearbyDocumentTransferError.invalidDocument
        }
    }

    func validate(contents: Data) throws {
        try validate()
        guard contents.count == byteCount, Data(SHA256.hash(data: contents)) == digest,
              TextEncodingDescriptor(identifier: encoding).decode(contents) != nil else {
            throw NearbyDocumentTransferError.invalidDocument
        }
    }
}

nonisolated struct NearbyDocumentSnapshot: Sendable {
    let offer: NearbyDocumentOffer
    let contents: Data

    static func make(name: String, text: String, encoding: TextEncodingDescriptor,
                     lineEnding: TextLineEnding) throws -> Self {
        guard let data = encoding.encodedData(for: lineEnding.applying(to: text)),
              data.count <= NearbyDocumentOffer.maximumBytes else {
            throw NearbyDocumentTransferError.invalidDocument
        }
        let offer = NearbyDocumentOffer(version: 1, name: name, byteCount: data.count,
                                        encoding: encoding.identifier, digest: Data(SHA256.hash(data: data)))
        try offer.validate()
        return Self(offer: offer, contents: data)
    }
}

nonisolated enum NearbyDocumentTransferError: LocalizedError {
    case invalidDocument, invalidPairingCode, interrupted, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidDocument: return "The document is unsupported, incomplete, or exceeds the 4 MB transfer limit."
        case .invalidPairingCode: return "Enter the full pairing code displayed on the receiving device."
        case .interrupted: return "The transfer was cancelled or the connection was interrupted."
        case .invalidResponse: return "The other device returned an unsupported transfer response."
        }
    }
}

/// One explicit foreground transfer. The receiver supplies a random 256-bit pairing secret,
/// used by TLS-PSK to authenticate both endpoints before any document metadata is exchanged.
@MainActor
final class NearbyDocumentTransfer: ObservableObject {
    nonisolated struct Peer: Identifiable, Sendable {
        let endpoint: NWEndpoint
        let name: String
        var id: String { endpoint.debugDescription }
    }
    struct ReceivedDocument {
        let url: URL
        let encoding: TextEncodingDescriptor
    }

    @Published private(set) var peers: [Peer] = []
    @Published private(set) var pairingCode = ""
    @Published private(set) var status = ""
    @Published private(set) var pendingOffer: NearbyDocumentOffer?
    @Published private(set) var isBusy = false
    @Published private(set) var didComplete = false
    @Published private(set) var listeningPort: NWEndpoint.Port?
    @Published private(set) var advertisedName = ""
    var onReceive: ((ReceivedDocument) -> Void)?

    nonisolated static let serviceType = "_nve-transfer._tcp"
    private let queue = DispatchQueue(label: "Neon.NearbyDocumentTransfer", qos: .utility)
    private let importRoot: URL
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var connection: NWConnection?
    private var operation: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var consentContinuation: CheckedContinuation<Bool, Never>?
    private var attempt = UUID()

    init(importRoot: URL? = nil) {
        self.importRoot = importRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NeonVisionEditor/NearbyImports", isDirectory: true)
    }

    deinit {
        browser?.cancel()
        listener?.cancel()
        connection?.cancel()
        operation?.cancel()
        timeout?.cancel()
        consentContinuation?.resume(returning: false)
    }

    func browse() {
        cancel()
        status = "Choose the receiving device, then enter its pairing code."
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        self.browser = browser
        let current = attempt
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let discovered = results.compactMap { result -> Peer? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Peer(endpoint: result.endpoint, name: String(name.prefix(80)))
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            Task { @MainActor [weak self] in
                guard let self, self.attempt == current else { return }
                self.peers = discovered
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor [weak self] in
                    guard let self, self.attempt == current else { return }
                    self.fail("Nearby discovery is unavailable. Check Local Network access and Wi-Fi.")
                }
            }
        }
        browser.start(queue: queue)
    }

    func receive(advertise: Bool = true) {
        cancel()
        do {
            let code = try Self.generatePairingCode()
            let listener = try NWListener(using: Self.parameters(code: code))
            pairingCode = code
            self.listener = listener
            if advertise {
                advertisedName = "Neon " + String(UUID().uuidString.prefix(6))
                listener.service = NWListener.Service(name: advertisedName, type: Self.serviceType)
            }
            let current = attempt
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.attempt == current else { return }
                    switch state {
                    case .ready:
                        self.listeningPort = self.listener?.port
                        self.status = "Enter this pairing code on the sending device. You will be asked to accept the document."
                    case .failed:
                        self.fail("Receiving is unavailable. Check Local Network access and Wi-Fi.")
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    guard let self, self.attempt == current, self.connection == nil else {
                        connection.cancel()
                        return
                    }
                    self.attach(connection, attempt: current) { [weak self] in
                        await self?.receiveDocument(over: connection, attempt: current)
                    }
                }
            }
            listener.start(queue: queue)
            armTimeout(seconds: 300, attempt: current)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func send(_ snapshot: NearbyDocumentSnapshot, to endpoint: NWEndpoint, code: String) {
        do {
            try snapshot.offer.validate(contents: snapshot.contents)
            let parameters = try Self.parameters(code: code)
            cancel()
            let current = attempt
            let connection = NWConnection(to: endpoint, using: parameters)
            attach(connection, attempt: current) { [weak self] in
                guard let self else { return }
                do {
                    try await Self.sendFrame(JSONEncoder().encode(snapshot.offer), over: connection)
                    let response = try await Self.receiveFrame(over: connection, limit: 1)
                    guard response == Data([1]) else {
                        if response == Data([0]) { self.fail("The receiving device declined the document.") }
                        else { self.fail(NearbyDocumentTransferError.invalidResponse.localizedDescription) }
                        return
                    }
                    guard self.attempt == current else { return }
                    self.status = "Sending document…"
                    try await Self.sendFrame(snapshot.contents, over: connection)
                    let acknowledgement = try await Self.receiveFrame(over: connection, limit: 1)
                    guard acknowledgement == Data([2]), self.attempt == current else {
                        throw NearbyDocumentTransferError.invalidResponse
                    }
                    self.complete("The receiving device validated the complete document.")
                } catch {
                    guard self.attempt == current else { return }
                    self.fail(error.localizedDescription)
                }
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func answerOffer(accept: Bool) {
        pendingOffer = nil
        consentContinuation?.resume(returning: accept)
        consentContinuation = nil
    }

    func cancel() {
        attempt = UUID()
        consentContinuation?.resume(returning: false)
        consentContinuation = nil
        operation?.cancel()
        operation = nil
        timeout?.cancel()
        timeout = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        pendingOffer = nil
        pairingCode = ""
        listeningPort = nil
        advertisedName = ""
        peers = []
        isBusy = false
        didComplete = false
    }

    private func attach(_ connection: NWConnection, attempt current: UUID,
                        ready: @escaping @MainActor () async -> Void) {
        self.connection = connection
        isBusy = true
        status = "Verifying the pairing code…"
        browser?.cancel()
        browser = nil
        armTimeout(seconds: 90, attempt: current)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.attempt == current else { return }
                switch state {
                case .ready:
                    guard self.operation == nil else { return }
                    self.listener?.cancel()
                    self.listener = nil
                    self.operation = Task { await ready() }
                case .failed:
                    self.fail("Connection failed. Confirm the pairing code and Local Network access on both devices.")
                case .waiting(let error):
                    if case .tls = error {
                        self.fail("Pairing code verification failed. Start a new session and confirm the complete code.")
                    } else {
                        self.status = "Waiting for a local connection…"
                    }
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func receiveDocument(over connection: NWConnection, attempt current: UUID) async {
        do {
            let metadata = try await Self.receiveFrame(over: connection, limit: 8_192)
            let offer = try JSONDecoder().decode(NearbyDocumentOffer.self, from: metadata)
            try offer.validate()
            guard attempt == current else { return }
            status = "Review the incoming document. No contents have been received."
            let accepted = await withCheckedContinuation { continuation in
                consentContinuation = continuation
                pendingOffer = offer
            }
            guard attempt == current else { return }
            try await Self.sendFrame(Data([accepted ? 1 : 0]), over: connection)
            guard accepted else { fail("Document declined."); return }
            status = "Receiving document…"
            let contents = try await Self.receiveFrame(over: connection, limit: offer.byteCount)
            let root = importRoot
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let document = try await Task.detached(priority: .userInitiated) {
                try offer.validate(contents: contents)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    let url = directory.appendingPathComponent(offer.name, isDirectory: false)
                    try contents.write(to: url, options: .atomic)
                    return url
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    throw error
                }
            }.value
            guard attempt == current else {
                try? FileManager.default.removeItem(at: directory)
                return
            }
            onReceive?(ReceivedDocument(url: document, encoding: TextEncodingDescriptor(identifier: offer.encoding)))
            try await Self.sendFrame(Data([2]), over: connection)
            complete("Received an independent copy. Save it where you want to keep it.")
        } catch {
            guard attempt == current else { return }
            fail(error.localizedDescription)
        }
    }

    private func complete(_ message: String) {
        cancel()
        didComplete = true
        status = message
    }
    private func fail(_ message: String) {
        cancel()
        status = message
    }
    private func armTimeout(seconds: Int, attempt current: UUID) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.attempt == current else { return }
            self.fail("The transfer timed out. Start a new send or receive session.")
        }
    }

    nonisolated static func generatePairingCode() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NearbyDocumentTransferError.invalidPairingCode
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func pairingKey(_ code: String) throws -> Data {
        let normalized = code.filter { $0 != "-" && !$0.isWhitespace }.lowercased()
        guard normalized.count == 64, normalized.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw NearbyDocumentTransferError.invalidPairingCode
        }
        let characters = Array(normalized)
        return Data(stride(from: 0, to: 64, by: 2).map {
            UInt8(String(characters[$0...($0 + 1)]), radix: 16)!
        })
    }
    nonisolated static func parameters(code: String) throws -> NWParameters {
        let key = try pairingKey(code)
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        // Network.framework's supported TLS-PSK mode is TLS 1.2, not TLS 1.3.
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        // The TLS-PSK suite is supported by Network but omitted from the Swift enum.
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: 0x00A8)!)
        key.withUnsafeBytes { keyBytes in
            Data("nve-transfer-v1".utf8).withUnsafeBytes { identityBytes in
                sec_protocol_options_add_pre_shared_key(options,
                    DispatchData(bytes: keyBytes) as __DispatchData,
                    DispatchData(bytes: identityBytes) as __DispatchData)
            }
        }
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        return parameters
    }

    nonisolated static func sendFrame(_ data: Data, over connection: NWConnection) async throws {
        guard data.count <= NearbyDocumentOffer.maximumBytes else { throw NearbyDocumentTransferError.invalidDocument }
        var length = UInt32(data.count).bigEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }
    nonisolated static func receiveFrame(over connection: NWConnection, limit: Int) async throws -> Data {
        let header = try await receiveExactly(4, over: connection)
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length <= limit, length <= NearbyDocumentOffer.maximumBytes else {
            throw NearbyDocumentTransferError.invalidDocument
        }
        return try await receiveExactly(length, over: connection)
    }
    nonisolated private static func receiveExactly(_ count: Int, over connection: NWConnection) async throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: NearbyDocumentTransferError.interrupted) }
                }
            }
            result.append(chunk)
        }
        return result
    }
}
