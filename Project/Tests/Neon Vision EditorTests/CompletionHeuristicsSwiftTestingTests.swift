import Testing
import XCTest
@testable import Neon_Vision_Editor

@MainActor
@Suite("Completion heuristics — Swift Testing pilot")
struct CompletionHeuristicsSwiftTestingTests {
    @Test("Natural-language completion stays limited to prose formats")
    func naturalLanguageCompletionClassification() {
        #expect(CompletionHeuristics.usesNaturalLanguageCompletion(for: "markdown"))
        #expect(CompletionHeuristics.usesNaturalLanguageCompletion(for: "plain"))
        #expect(!CompletionHeuristics.usesNaturalLanguageCompletion(for: "swift"))
    }

    @Test("Model suggestions preserve prose whitespace and Unicode")
    func proseSuggestionSanitization() {
        let suggestion = CompletionHeuristics.sanitizeModelSuggestion(
            " schön — danke",
            currentTokenPrefix: "",
            nextDocumentText: "",
            maxLength: 80,
            allowsNaturalLanguage: true
        )

        #expect(suggestion == " schön — danke")
    }

    @Test("XCTest assertions report through Swift Testing")
    func xctestAssertionInteroperability() {
        XCTAssertEqual(
            CompletionHeuristics.sanitizeModelSuggestion(
                "return value)",
                currentTokenPrefix: "ret",
                nextDocumentText: ")"
            ),
            "urn value"
        )
    }
}

@MainActor
final class SwiftTestingExpectationInteropTests: XCTestCase {
    func testSwiftTestingExpectationReportsThroughXCTest() {
        #expect(CompletionHeuristics.usesNaturalLanguageCompletion(for: "markdown"))
    }
}
