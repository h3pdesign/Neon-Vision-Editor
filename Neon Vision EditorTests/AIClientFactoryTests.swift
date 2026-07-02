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

    func testCustomProviderRequiresSecureHTTPSBaseURL() {
        let insecureClient = AIClientFactory.makeClient(
            for: .customProvider,
            customBaseURLProvider: { "http://localhost:11434/v1" },
            customModelProvider: { "local-model" }
        )
        let secureClient = AIClientFactory.makeClient(
            for: .customProvider,
            customBaseURLProvider: { "https://example.com/v1" },
            customModelProvider: { "remote-model" }
        )

        XCTAssertFalse(insecureClient is OpenAICompatibleAIClient)
        XCTAssertTrue(secureClient is OpenAICompatibleAIClient)
    }
}
