import Foundation
import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class GrokAIClientStreamingTests: XCTestCase {
    func testStreamFailureUsesNonStreamingFallbackRequest() async {
        GrokFallbackURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GrokFallbackURLProtocol.self]
        let client = GrokAIClientStreaming(
            apiKey: "test-token",
            session: URLSession(configuration: configuration)
        )

        for await _ in client.streamSuggestions(prompt: "Test fallback") {}
        XCTAssertEqual(GrokFallbackURLProtocol.streamFlags(), [false])
    }

    func testFallbackResponseContentPrefersChatCompletionText() {
        let data = Data("{\"choices\":[{\"message\":{\"content\":\"Fallback response\"}}]}".utf8)

        XCTAssertEqual(GrokAIClientStreaming.fallbackContent(from: data), "Fallback response")
    }
}

private final class GrokFallbackURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recordedStreamFlags: [Bool] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.x.ai"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let payload = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
        let isStreaming = payload?["stream"] as? Bool ?? false
        Self.lock.lock()
        Self.recordedStreamFlags.append(isStreaming)
        Self.lock.unlock()

        if isStreaming {
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }

        DispatchQueue.global().async { [weak self] in
            guard let self, let url = self.request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else { return }
            let responseData = Data("{\"choices\":[{\"message\":{\"content\":\"Fallback response\"}}]}".utf8)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: responseData)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    static func reset() {
        lock.lock()
        recordedStreamFlags = []
        lock.unlock()
    }

    static func streamFlags() -> [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStreamFlags
    }
}
