import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class TextEncodingAndMarkdownConversionTests: XCTestCase {
    private struct ParagraphPlanClient: AIClient {
        func streamSuggestions(prompt: String) -> AsyncStream<String> {
            let count = prompt
                .range(of: #"exactly ([0-9]+) characters"#, options: .regularExpression)
                .map { match in
                    Int(prompt[match].filter(\.isNumber)) ?? 0
                } ?? 0
            return AsyncStream { continuation in
                continuation.yield(String(repeating: "p", count: count))
                continuation.finish()
            }
        }
    }

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

    func testEncodingDescriptorsPreserveBOMAndEndianVariants() throws {
        let samples: [(TextEncodingDescriptor.Identifier, [UInt8])] = [
            (.utf8WithBOM, [0xEF, 0xBB, 0xBF]),
            (.utf16LittleEndianWithBOM, [0xFF, 0xFE]),
            (.utf16BigEndianWithBOM, [0xFE, 0xFF])
        ]
        for (identifier, bom) in samples {
            let descriptor = TextEncodingDescriptor(identifier: identifier)
            let data = try XCTUnwrap(descriptor.encodedData(for: "Türkçe Русский"))
            XCTAssertTrue(data.starts(with: bom))
            XCTAssertEqual(descriptor.decode(data), "Türkçe Русский")
            XCTAssertEqual(TextEncodingDescriptor.detected(in: data)?.identifier, identifier)
        }
    }

    func testLegacyEncodingsRoundTripRepresentativeLanguages() throws {
        let samples: [(TextEncodingDescriptor.Identifier, String)] = [
            (.windowsCP1251, "Привет"),
            (.windowsCP1252, "Résumé €"),
            (.isoLatin1, "Crème brûlée"),
            (.isoLatin5, "İstanbul şeker")
        ]
        for (identifier, text) in samples {
            let descriptor = TextEncodingDescriptor(identifier: identifier)
            let data = try XCTUnwrap(descriptor.encodedData(for: text), "\(identifier)")
            XCTAssertEqual(descriptor.decode(data), text, "\(identifier)")
        }
    }

    func testLineEndingDetectionAndSaveRepresentation() {
        XCTAssertEqual(TextLineEnding.detect(in: "one\r\ntwo\r\n"), .crlf)
        XCTAssertEqual(TextLineEnding.detect(in: "one\ntwo\n"), .lf)
        XCTAssertEqual(TextLineEnding.crlf.applying(to: "one\ntwo\n"), "one\r\ntwo\r\n")
        XCTAssertEqual(TextLineEnding.lf.applying(to: "one\ntwo\n"), "one\ntwo\n")
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

    func testMarkdownRendererSupportsEmphasisLinksAutolinksAndTables() throws {
        let source = "Important\nDocumentation | https://example.com/docs\nVisit https://example.com\nName | Value\nOne | 1"
        let proposal = try XCTUnwrap(
            PlainTextMarkdownRenderer.render(
                source: source,
                styles: [.strong, .link, .autolink, .table, .table]
            )
        )

        XCTAssertTrue(proposal.markdown.contains("**Important**"))
        XCTAssertTrue(proposal.markdown.contains("[Documentation](https://example.com/docs)"))
        XCTAssertTrue(proposal.markdown.contains("<https://example.com>"))
        XCTAssertTrue(proposal.markdown.contains("| --- | --- |"))
        XCTAssertTrue(proposal.preservesSourceText)
    }

    func testMalformedProviderPlanIsRejected() {
        XCTAssertNil(
            PlainTextMarkdownRenderer.styles(
                fromProviderCodes: "\"h?\"",
                expectedCount: 2
            )
        )
        XCTAssertNil(
            PlainTextMarkdownRenderer.styles(
                fromProviderCodes: "\"hpp\"",
                expectedCount: 2
            )
        )
    }

    func testLargeMultilingualProviderConversionUsesCancelableChunks() async throws {
        let lines = (0..<450).map { index in
            index.isMultiple(of: 2) ? "Résumé \(index)" : "日本語 \(index)"
        }
        let source = lines.joined(separator: "\n")
        let proposal = try await PlainTextMarkdownConverter.convertWithConfiguredProvider(
            source,
            client: ParagraphPlanClient()
        )

        XCTAssertEqual(proposal.markdown, source)
        XCTAssertTrue(proposal.preservesSourceText)
    }

    func testProviderConversionHonorsCancellationBeforeGeneration() async {
        let task = Task {
            try await PlainTextMarkdownConverter.convertWithConfiguredProvider(
                "One\nTwo",
                client: ParagraphPlanClient()
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRestoredTabKeepsExplicitBOMAndAutomaticMode() {
        let viewModel = EditorViewModel()
        viewModel.resetTabsForSessionRestore()
        let descriptor = TextEncodingDescriptor(identifier: .utf8WithBOM)
        let automaticDescriptor = TextEncodingDescriptor(identifier: .utf16BigEndianWithBOM)
        viewModel.restoreTabsFromSnapshot(
            [
                .init(
                    name: "bom.txt",
                    content: "Hello",
                    language: "plain",
                    fileURL: nil,
                    languageLocked: true,
                    isDirty: true,
                    lastSavedFingerprint: nil,
                    lastKnownFileModificationDate: nil,
                    fileEncodingRawValue: descriptor.encodingRawValue,
                    fileEncoding: descriptor,
                    usesAutomaticFileEncoding: false
                ),
                .init(
                    name: "automatic.txt",
                    content: "World",
                    language: "plain",
                    fileURL: nil,
                    languageLocked: true,
                    isDirty: true,
                    lastSavedFingerprint: nil,
                    lastKnownFileModificationDate: nil,
                    fileEncodingRawValue: automaticDescriptor.encodingRawValue,
                    fileEncoding: automaticDescriptor,
                    usesAutomaticFileEncoding: true
                )
            ],
            selectedIndex: 0
        )

        XCTAssertEqual(viewModel.selectedTab?.fileEncoding.identifier, .utf8WithBOM)
        XCTAssertEqual(viewModel.selectedTab?.usesAutomaticFileEncoding, false)
        viewModel.selectTab(id: viewModel.tabs[1].id)
        XCTAssertEqual(viewModel.selectedTab?.fileEncoding.identifier, .utf16BigEndianWithBOM)
        XCTAssertEqual(viewModel.selectedTab?.usesAutomaticFileEncoding, true)
    }

    func testSelectionReplacementLeavesSurroundingDocumentUntouched() {
        let viewModel = EditorViewModel()
        let tabID = try! XCTUnwrap(viewModel.selectedTab?.id)
        viewModel.updateTabContent(tabID: tabID, content: "Before\nSelected\nAfter")
        let range = ("Before\nSelected\nAfter" as NSString).range(of: "Selected")

        viewModel.applyTabContentEdit(tabID: tabID, range: range, replacement: "**Selected**")

        XCTAssertEqual(viewModel.selectedTab?.document.string(), "Before\n**Selected**\nAfter")
    }

    func testMarkdownConversionAvailabilityMessagesAreActionable() {
        XCTAssertTrue(
            PlainTextMarkdownConversionError.appleIntelligenceDisabled.localizedDescription.contains("System Settings")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.modelNotReady.localizedDescription.contains("downloading")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.incompletePlan.localizedDescription.contains("fewer classifications")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.timedOut(seconds: 60).localizedDescription.contains("60 seconds")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.providerReturnedNoPlan.localizedDescription.contains("API key")
        )
        XCTAssertTrue(
            PlainTextMarkdownConversionError.providerInvalidPlan.localizedDescription.contains("Apple Intelligence")
        )
    }
}
