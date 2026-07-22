import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class TextEncodingAndMarkdownConversionTests: XCTestCase {
    func testUTF8BOMRoundTripsWithoutBecomingDocumentText() throws {
        let encoding = TextEncodingDescriptor(identifier: .utf8WithBOM)
        let data = try XCTUnwrap(encoding.encodedData(for: "Résumé"))

        XCTAssertTrue(data.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertEqual(encoding.decode(data), "Résumé")
    }

    func testASCIIRefusesLossySaveData() {
        let encoding = TextEncodingDescriptor(identifier: .ascii)
        XCTAssertNil(encoding.encodedData(for: "Price: €10"))
    }

    func testMarkdownRendererPreservesSourceWhileAddingOnlySyntax() throws {
        let source = "Release notes\nFirst item\nQuoted text"
        let proposal = try XCTUnwrap(
            PlainTextMarkdownRenderer.render(
                source: source,
                styles: [.heading, .unorderedList, .quote]
            )
        )

        XCTAssertEqual(proposal.markdown, "# Release notes\n- First item\n> Quoted text")
        XCTAssertTrue(proposal.preservesSourceText)
    }

    func testProviderCodesRenderAValidatedMarkdownProposal() throws {
        let source = "Release notes\nFirst item\nQuoted text"
        let styles = try XCTUnwrap(
            PlainTextMarkdownRenderer.styles(fromProviderCodes: "\"huq\"", expectedCount: 3)
        )
        let proposal = try XCTUnwrap(PlainTextMarkdownRenderer.render(source: source, styles: styles))

        XCTAssertEqual(proposal.markdown, "# Release notes\n- First item\n> Quoted text")
        XCTAssertTrue(proposal.preservesSourceText)
    }

    func testMarkdownConversionAvailabilityMessagesAreActionable() {
        XCTAssertTrue(
            PlainTextMarkdownConversionError.appleIntelligenceDisabled.localizedDescription.contains("System Settings")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.modelNotReady.localizedDescription.contains("downloading")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.timedOut.localizedDescription.contains("30 seconds")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.providerReturnedNoPlan.localizedDescription.contains("API key")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.providerInvalidPlan.localizedDescription.contains("Apple Intelligence")
        )
    }
}
