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
}
