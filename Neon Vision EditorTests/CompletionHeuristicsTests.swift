import XCTest
@testable import Neon_Vision_Editor

final class CompletionHeuristicsTests: XCTestCase {
    func testLocalSuggestionPrefersNearbyDocumentWord() {
        let text = """
        let recentWorkspacePath = projectURL.path
        recen
        """ as NSString

        let caretLocation = text.length
        let suggestion = CompletionHeuristics.localSuggestion(
            in: text,
            caretLocation: caretLocation,
            language: "swift",
            includeDocumentWords: true,
            includeSyntaxKeywords: false
        )

        XCTAssertEqual(suggestion, "tWorkspacePath")
    }

    func testLocalSuggestionFallsBackToLanguageKeyword() {
        let text = "ret" as NSString
        let suggestion = CompletionHeuristics.localSuggestion(
            in: text,
            caretLocation: text.length,
            language: "swift",
            includeDocumentWords: false,
            includeSyntaxKeywords: true
        )

        XCTAssertEqual(suggestion, "urn")
    }

    func testSanitizeModelSuggestionRemovesRepeatedPrefixAndTrailingOverlap() {
        let sanitized = CompletionHeuristics.sanitizeModelSuggestion(
            "return value)",
            currentTokenPrefix: "ret",
            nextDocumentText: ")"
        )

        XCTAssertEqual(sanitized, "urn value")
    }

    func testWhitespaceTriggerIsSelective() {
        let assignment = "let value = " as NSString
        XCTAssertTrue(
            CompletionHeuristics.shouldTriggerAfterWhitespace(
                in: assignment,
                caretLocation: assignment.length,
                language: "swift"
            )
        )

        let plainSentence = "let value " as NSString
        XCTAssertFalse(
            CompletionHeuristics.shouldTriggerAfterWhitespace(
                in: plainSentence,
                caretLocation: plainSentence.length,
                language: "swift"
            )
        )
    }
}
