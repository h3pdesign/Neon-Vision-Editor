import XCTest
@testable import Neon_Vision_Editor

@MainActor
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

    func testProseSuggestionPreservesLeadingSpaceAndUnicode() {
        let sanitized = CompletionHeuristics.sanitizeModelSuggestion(
            " schön — danke",
            currentTokenPrefix: "",
            nextDocumentText: "",
            maxLength: 80,
            allowsNaturalLanguage: true
        )

        XCTAssertEqual(sanitized, " schön — danke")
    }

    func testMarkdownAndPlainTextUseNaturalLanguageCompletion() {
        XCTAssertTrue(CompletionHeuristics.usesNaturalLanguageCompletion(for: "markdown"))
        XCTAssertTrue(CompletionHeuristics.usesNaturalLanguageCompletion(for: "plain"))
        XCTAssertFalse(CompletionHeuristics.usesNaturalLanguageCompletion(for: "swift"))
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

    func testCommentContextSkipsSwiftLineComments() {
        let text = "let value = 1 // explain val" as NSString

        XCTAssertTrue(
            CompletionHeuristics.isLikelyInCommentOrString(
                in: text,
                caretLocation: text.length,
                language: "swift"
            )
        )
    }

    func testCommentMarkerInsideStringDoesNotSkipCompletion() {
        let source = #"let url = "https://example.com"; val"#
        let text = source as NSString

        XCTAssertFalse(
            CompletionHeuristics.isLikelyInCommentOrString(
                in: text,
                caretLocation: text.length,
                language: "swift"
            )
        )
    }

    func testStringContextSkipsCompletion() {
        let text = #"let title = "hel"# as NSString

        XCTAssertTrue(
            CompletionHeuristics.isLikelyInCommentOrString(
                in: text,
                caretLocation: text.length,
                language: "swift"
            )
        )
    }

    func testCaretLineColumnUsesUTF16Offsets() {
        let text = "one\ntwo\nthree" as NSString

        let caret = editorCaretLineColumn(in: text, location: 6)

        XCTAssertEqual(caret.line, 2)
        XCTAssertEqual(caret.column, 3)
    }
}
