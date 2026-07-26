import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class AIChatPromptTests: XCTestCase {
    func testContextPromptCarriesLanguageAndContextualGuidance() {
        let prompt = AIChatConversation.requestPrompt(
            userPrompt: "Find the bug",
            context: AIChatContext(
                selection: "let count: Int = \"three\"",
                documentName: "Content.swift",
                documentLanguage: "swift",
                documentText: nil,
                projectStructure: nil
            ),
            history: []
        )

        XCTAssertTrue(prompt.contains("Content.swift (swift"))
        XCTAssertTrue(prompt.contains("Editor context is the primary reference"))
        XCTAssertTrue(prompt.contains("never mix syntax from another language"))
    }

    func testNoContextPromptTellsUserHowToRequestContextualHelp() {
        let prompt = AIChatConversation.requestPrompt(
            userPrompt: "Review this code",
            context: AIChatContext(
                selection: nil,
                documentName: nil,
                documentLanguage: nil,
                documentText: nil,
                projectStructure: nil
            ),
            history: []
        )

        XCTAssertTrue(prompt.contains("No editor context was supplied"))
        XCTAssertTrue(prompt.contains("enable Selection or Current File"))
    }

    func testQuickActionsAreLanguageAwareAndAdvisory() {
        XCTAssertTrue(AIChatQuickAction.tests.prompt.contains("appropriate testing framework"))
        XCTAssertTrue(AIChatQuickAction.validateSyntax.prompt.contains("advisory review"))
        XCTAssertEqual(AIChatQuickAction.validateSyntax.title, "Syntax Review")
        XCTAssertTrue(AIChatQuickAction.story.prompt.contains("polished story"))
        XCTAssertTrue(AIChatQuickAction.markdown.prompt.contains("valid Markdown syntax"))
        XCTAssertTrue(AIChatQuickAction.readme.preferredScopes.contains(.projectStructure))
        XCTAssertTrue(AIChatQuickAction.requirements.prompt.contains("requirements.txt"))
    }

    func testSensitiveContentDetectorFlagsCommonSecretsButNotOrdinaryCode() {
        XCTAssertTrue(AIChatSensitiveContentDetector.containsPotentialSecret("api_key = \"sk-test-1234567890\""))
        XCTAssertTrue(AIChatSensitiveContentDetector.containsPotentialSecret("-----BEGIN PRIVATE KEY-----"))
        XCTAssertFalse(AIChatSensitiveContentDetector.containsPotentialSecret("let tokenCount = 12"))
    }
}
