import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class AIClientFactoryTests: XCTestCase {
    func testOpenCodeGoProviderUsesConfiguredTokenAndModel() {
        let client = AIClientFactory.makeClient(
            for: .openCodeGo,
            openCodeGoKeyProvider: { "test-token" },
            openCodeGoModelProvider: { "kimi-k2.7-code" }
        )

        XCTAssertTrue(client is OpenAICompatibleAIClient)
    }

    func testCustomProviderAllowsHTTPSAndLoopbackHTTPBaseURLs() {
        let localClient = AIClientFactory.makeClient(
            for: .customProvider,
            customBaseURLProvider: { "http://127.0.0.1:11434/v1" },
            customModelProvider: { "local-model" }
        )
        let localhostClient = AIClientFactory.makeClient(
            for: .customProvider,
            customBaseURLProvider: { "http://localhost:11434/v1" },
            customModelProvider: { "local-model" }
        )
        let secureClient = AIClientFactory.makeClient(
            for: .customProvider,
            customBaseURLProvider: { "https://example.com/v1" },
            customModelProvider: { "remote-model" }
        )

        XCTAssertTrue(localClient is OpenAICompatibleAIClient)
        XCTAssertTrue(localhostClient is OpenAICompatibleAIClient)
        XCTAssertTrue(secureClient is OpenAICompatibleAIClient)
    }

    func testCustomProviderRejectsExternalHTTPBaseURL() {
        let externalHTTPClient = AIClientFactory.makeClient(
            for: .customProvider,
            customBaseURLProvider: { "http://example.com/v1" },
            customModelProvider: { "remote-model" }
        )

        XCTAssertFalse(externalHTTPClient is OpenAICompatibleAIClient)
    }
}
