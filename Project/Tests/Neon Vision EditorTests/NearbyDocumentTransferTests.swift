import XCTest
import Combine
import Network
import CryptoKit
@testable import Neon_Vision_Editor

@MainActor
final class NearbyDocumentTransferTests: XCTestCase {
    func testSnapshotPreservesEncodingBOMLineEndingsAndEmptyDocuments() throws {
        for encoding in [TextEncodingDescriptor.utf8,
                         TextEncodingDescriptor(identifier: .utf8WithBOM),
                         TextEncodingDescriptor(identifier: .utf16LittleEndianWithBOM)] {
            for text in ["", "hello\n中文 e\u{301}\n"] {
                let snapshot = try NearbyDocumentSnapshot.make(name: "copy.txt", text: text,
                                                               encoding: encoding, lineEnding: .crlf)
                try snapshot.offer.validate(contents: snapshot.contents)
                XCTAssertEqual(encoding.decode(snapshot.contents), text.replacingOccurrences(of: "\n", with: "\r\n"))
                XCTAssertEqual(snapshot.offer.encoding, encoding.identifier)
            }
        }
    }

    func testMalformedMetadataAndPayloadAreRejectedBeforeImport() throws {
        let valid = try NearbyDocumentSnapshot.make(name: "safe.txt", text: "original", encoding: .utf8, lineEnding: .lf)
        for name in ["", ".", "..", "../safe.txt", "folder/file.txt", "folder\\file.txt", "nul\u{0}.txt", String(repeating: "a", count: 201)] {
            let offer = NearbyDocumentOffer(version: 1, name: name, byteCount: valid.contents.count,
                                            encoding: .utf8, digest: valid.offer.digest)
            XCTAssertThrowsError(try offer.validate())
        }
        for version in [0, 2] {
            for size in [-1, NearbyDocumentOffer.maximumBytes + 1] {
                let offer = NearbyDocumentOffer(version: version, name: "safe.txt", byteCount: size,
                                                encoding: .utf8, digest: valid.offer.digest)
                XCTAssertThrowsError(try offer.validate())
            }
        }
        XCTAssertThrowsError(try valid.offer.validate(contents: Data("changed!".utf8)))
        XCTAssertThrowsError(try valid.offer.validate(contents: Data()))
        XCTAssertThrowsError(try NearbyDocumentSnapshot.make(name: "safe.txt", text: "中文", encoding: TextEncodingDescriptor(identifier: .ascii), lineEnding: .lf))
        let boundary = try NearbyDocumentSnapshot.make(name: "limit.txt", text: String(repeating: "a", count: NearbyDocumentOffer.maximumBytes), encoding: .utf8, lineEnding: .lf)
        XCTAssertEqual(boundary.offer.byteCount, NearbyDocumentOffer.maximumBytes)
        XCTAssertThrowsError(try NearbyDocumentSnapshot.make(name: "limit.txt", text: String(repeating: "a", count: NearbyDocumentOffer.maximumBytes + 1), encoding: .utf8, lineEnding: .lf))
    }

    func testPairingCodeRequiresTheCompleteRandomSecret() throws {
        let first = try NearbyDocumentTransfer.generatePairingCode()
        let second = try NearbyDocumentTransfer.generatePairingCode()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try NearbyDocumentTransfer.pairingKey(first).count, 32)
        XCTAssertEqual(try NearbyDocumentTransfer.pairingKey(first.uppercased()), try NearbyDocumentTransfer.pairingKey(first))
        for code in ["", "123456", String(repeating: "g", count: 64), first + "0"] {
            XCTAssertThrowsError(try NearbyDocumentTransfer.pairingKey(code))
        }
    }

    func testEncryptedLoopbackTransfersIndependentCopyOnlyAfterConsent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nve-transfer-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = NearbyDocumentTransfer(importRoot: root)
        let sender = NearbyDocumentTransfer(importRoot: root)
        defer { receiver.cancel(); sender.cancel() }
        var observations = Set<AnyCancellable>()
        let ready = expectation(description: "TLS listener ready")
        receiver.$listeningPort.compactMap { $0 }.first().sink { _ in ready.fulfill() }.store(in: &observations)
        receiver.receive(advertise: false)
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(receiver.listeningPort)
        let snapshot = try NearbyDocumentSnapshot.make(name: "same ' quoted.txt", text: "unsaved\n中文", encoding: .utf8, lineEnding: .crlf)
        let offered = expectation(description: "metadata received before contents")
        receiver.$pendingOffer.compactMap { $0 }.first().sink { offer in
            XCTAssertEqual(offer, snapshot.offer)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            offered.fulfill()
        }.store(in: &observations)
        let received = expectation(description: "validated independent copy")
        var receivedURL: URL?
        receiver.onReceive = { document in
            receivedURL = document.url
            XCTAssertEqual(try? Data(contentsOf: document.url), snapshot.contents)
            received.fulfill()
        }
        let acknowledged = expectation(description: "sender receives validation acknowledgement")
        sender.$didComplete.filter { $0 }.first().sink { _ in acknowledged.fulfill() }.store(in: &observations)
        sender.send(snapshot, to: .hostPort(host: .ipv4(.loopback), port: port), code: receiver.pairingCode)
        await fulfillment(of: [offered], timeout: 10)
        XCTAssertNil(receivedURL)
        receiver.answerOffer(accept: true)
        await fulfillment(of: [received, acknowledged], timeout: 10)
        XCTAssertTrue(sender.didComplete)
        XCTAssertTrue(receiver.didComplete)
        XCTAssertEqual(receivedURL?.lastPathComponent, snapshot.offer.name)
        XCTAssertEqual(snapshot.contents, try Data(contentsOf: XCTUnwrap(receivedURL)))
    }

    func testDecliningAndCancellingTransfersWriteNoDocument() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nve-transfer-decline-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for cancelInsteadOfDeclining in [false, true] {
            let receiver = NearbyDocumentTransfer(importRoot: root)
            let sender = NearbyDocumentTransfer(importRoot: root)
            defer { receiver.cancel(); sender.cancel() }
            var observations = Set<AnyCancellable>()
            let ready = expectation(description: "listener ready")
            receiver.$listeningPort.compactMap { $0 }.first().sink { _ in ready.fulfill() }.store(in: &observations)
            receiver.receive(advertise: false)
            await fulfillment(of: [ready], timeout: 5)
            let offered = expectation(description: "offer arrives")
            receiver.$pendingOffer.compactMap { $0 }.first().sink { _ in offered.fulfill() }.store(in: &observations)
            let stopped = expectation(description: "sender sees decline or disconnect")
            sender.$status.filter {
                cancelInsteadOfDeclining ? ($0.contains("interrupted") || $0.contains("failed")) : $0.contains("declined")
            }.first().sink { _ in stopped.fulfill() }.store(in: &observations)
            let snapshot = try NearbyDocumentSnapshot.make(name: "safe.txt", text: "private", encoding: .utf8, lineEnding: .lf)
            sender.send(snapshot, to: .hostPort(host: .ipv4(.loopback), port: try XCTUnwrap(receiver.listeningPort)), code: receiver.pairingCode)
            await fulfillment(of: [offered], timeout: 10)
            if cancelInsteadOfDeclining { receiver.cancel() }
            else { receiver.answerOffer(accept: false) }
            await fulfillment(of: [stopped], timeout: 10)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            XCTAssertFalse(sender.didComplete)
            receiver.cancel()
            XCTAssertNil(receiver.listeningPort)
            XCTAssertNil(receiver.pendingOffer)
            XCTAssertTrue(receiver.pairingCode.isEmpty)
        }
    }

    func testWrongPairingKeyNeverReachesConsentOrWritesAFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nve-transfer-auth-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = NearbyDocumentTransfer(importRoot: root)
        let sender = NearbyDocumentTransfer(importRoot: root)
        defer { receiver.cancel(); sender.cancel() }
        var observations = Set<AnyCancellable>()
        let ready = expectation(description: "listener ready")
        receiver.$listeningPort.compactMap { $0 }.first().sink { _ in ready.fulfill() }.store(in: &observations)
        receiver.receive(advertise: false)
        await fulfillment(of: [ready], timeout: 5)
        let rejected = expectation(description: "TLS rejects the wrong pairing secret")
        sender.$status.filter { $0.contains("failed") }.first().sink { _ in rejected.fulfill() }.store(in: &observations)
        let offered = expectation(description: "unauthenticated metadata must not reach consent")
        offered.isInverted = true
        receiver.$pendingOffer.compactMap { $0 }.sink { _ in offered.fulfill() }.store(in: &observations)
        let snapshot = try NearbyDocumentSnapshot.make(name: "private.txt", text: "private", encoding: .utf8, lineEnding: .lf)
        sender.send(snapshot, to: .hostPort(host: .ipv4(.loopback), port: try XCTUnwrap(receiver.listeningPort)),
                    code: try NearbyDocumentTransfer.generatePairingCode())
        await fulfillment(of: [rejected], timeout: 10)
        await fulfillment(of: [offered], timeout: 0.2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertFalse(sender.didComplete)
        XCTAssertFalse(receiver.didComplete)
    }
}
