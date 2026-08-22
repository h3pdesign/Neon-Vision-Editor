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
        XCTAssertTrue(prompt.contains("## Recommendation"))
        XCTAssertTrue(prompt.contains("Never return a single long paragraph"))
        XCTAssertTrue(prompt.contains("Every response must be valid Markdown"))
        XCTAssertTrue(prompt.contains("leave a blank line between sections"))
        XCTAssertTrue(prompt.contains("actual syntax-correct implementation in a fenced Markdown code block"))
        XCTAssertTrue(prompt.contains("The final USER request is authoritative"))
        XCTAssertTrue(prompt.contains("A follow-up such as “now in code” means return the actual syntax-correct implementation"))
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

    func testOnDevicePromptBoundsCombinedEditorContext() {
        let prompt = AIChatConversation.requestPrompt(
            userPrompt: "Summarize the document",
            context: AIChatContext(
                selection: String(repeating: "selection\n", count: 1_000),
                documentName: "Large.md",
                documentLanguage: "markdown",
                documentText: String(repeating: "document\n", count: 10_000),
                projectStructure: String(repeating: "path/to/file\n", count: 1_000)
            ),
            history: [
                .init(role: .user, content: String(repeating: "history\n", count: 1_000))
            ],
            contextCharacterBudget: 5_000
        )

        XCTAssertLessThanOrEqual(prompt.count, 12_000)
        XCTAssertTrue(prompt.contains("USER:\nSummarize the document"))
    }

    func testQuickActionsAreLanguageAwareAndAdvisory() {
        XCTAssertTrue(AIChatQuickAction.tests.prompt.contains("appropriate testing framework"))
        XCTAssertTrue(AIChatQuickAction.explain.prompt.contains("## Key responsibilities"))
        XCTAssertTrue(AIChatQuickAction.explain.prompt.contains("each heading on its own line"))
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
