import XCTest
@testable import Neon_Vision_Editor

// Each session owns its fixture in a header; no global mutable handler or live API.
private final class JevFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.value(forHTTPHeaderField: "Fixture-Error") != nil {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let status = Int(request.value(forHTTPHeaderField: "Fixture-Status") ?? "200") ?? 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = Data(base64Encoded: request.value(forHTTPHeaderField: "Fixture-Body") ?? "") ?? Data()
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class JevContextRankingTests: XCTestCase {
    private var context: AIChatContext {
        .init(selection: "    let π = 3\n", documentName: "App.swift", documentLanguage: "swift",
              documentText: "let unrelated = true", projectStructure: "Sources/App.swift")
    }

    private func fixtureRanker(answers: [String: Any], status: Int = 200, error: Bool = false, model: String = "jev-1.13.0") throws -> JevContextRanker {
        let data = try JSONSerialization.data(withJSONObject: [
            "model": model, "answers": answers, "usage": ["input_tokens": 350]
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JevFixtureProtocol.self]
        configuration.httpAdditionalHeaders = [
            "Fixture-Body": data.base64EncodedString(), "Fixture-Status": String(status)
        ]
        if error { configuration.httpAdditionalHeaders?["Fixture-Error"] = "timeout" }
        return JevContextRanker(apiKey: "test-key", session: URLSession(configuration: configuration))
    }

    private func answer(_ choice: String, confidence: Double = 1, probability: Double = 1) -> [String: Any] {
        var probabilities = ["relevant": 0.0, "irrelevant": 0.0, "uncertain": 0.0]
        probabilities[choice] = probability
        if probability < 1 { probabilities[choice == "uncertain" ? "relevant" : "uncertain"] = 1 - probability }
        return ["type": "choice", "choice": choice, "confidence": confidence, "probabilities": probabilities]
    }

    func testEligibilityRequiresOptInExternalChatAndOptionalContext() {
        XCTAssertTrue(JevContextRankingConfig.isEligible(enabled: true, isOnDevice: false, isAgent: false, hasOptionalContext: true))
        XCTAssertFalse(JevContextRankingConfig.isEligible(enabled: false, isOnDevice: false, isAgent: false, hasOptionalContext: true))
        XCTAssertFalse(JevContextRankingConfig.isEligible(enabled: true, isOnDevice: true, isAgent: false, hasOptionalContext: true))
        XCTAssertFalse(JevContextRankingConfig.isEligible(enabled: true, isOnDevice: false, isAgent: true, hasOptionalContext: true))
        XCTAssertFalse(JevContextRankingConfig.isEligible(enabled: true, isOnDevice: false, isAgent: false, hasOptionalContext: false))
    }

    func testRequestBoundsOptionalContextAndExcludesSelection() throws {
        let context = AIChatContext(selection: "SELECTION_ONLY", documentName: "Test", documentLanguage: "swift",
                                    documentText: String(repeating: "é", count: 9_000), projectStructure: String(repeating: "p", count: 4_000))
        let request = try XCTUnwrap(JevContextRanker.request(prompt: "  Complete request\nTAIL\n", context: context, apiKey: "fixture"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(request.timeoutInterval, 3)
        XCTAssertFalse(request.httpShouldHandleCookies)
        let data = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SELECTION_ONLY"))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "jev-1.13.0")
        let state = try XCTUnwrap(payload["state"] as? [String: Any])
        XCTAssertEqual(state["request"] as? String, "  Complete request\nTAIL\n")
        let optional = try XCTUnwrap(state["optional_context"] as? [String: String])
        XCTAssertEqual(optional["document"]?.count, 6_000)
        XCTAssertEqual(optional["project"]?.count, 2_000)
    }

    func testUnsafeEmptyAndOversizedInputsSkipTransmission() {
        XCTAssertNil(JevContextRanker.request(prompt: String(repeating: "x", count: 16_001), context: context, apiKey: "test"))
        XCTAssertNil(JevContextRanker.request(prompt: "", context: context, apiKey: "test"))
        let empty = AIChatContext(selection: "selection", documentName: nil, documentLanguage: nil, documentText: nil, projectStructure: nil)
        XCTAssertNil(JevContextRanker.request(prompt: "Explain", context: empty, apiKey: "test"))
        let secret = "api_key = sk-test-1234567890"
        XCTAssertNil(JevContextRanker.request(prompt: secret, context: context, apiKey: "test"))
        for field in 0..<3 {
            let unsafe = AIChatContext(selection: field == 0 ? secret : nil, documentName: nil, documentLanguage: nil,
                                       documentText: field == 1 ? String(repeating: "x", count: 6_001) + "\n" + secret : "safe",
                                       projectStructure: field == 2 ? secret : nil)
            XCTAssertNil(JevContextRanker.request(prompt: "Explain", context: unsafe, apiKey: "test"))
        }
    }

    func testOnlyConfidentlyIrrelevantOptionalContextIsRemoved() async throws {
        let context = AIChatContext(selection: String(repeating: "s", count: 5_000), documentName: "App.swift",
                                    documentLanguage: "swift", documentText: String(repeating: "d", count: 9_000),
                                    projectStructure: "Sources/App.swift")
        let ranker = try fixtureRanker(answers: ["document": answer("irrelevant"), "project": answer("relevant")])
        let result = await ranker.rank(prompt: "Write a poem", context: context)
        XCTAssertNil(result.context.documentText)
        XCTAssertEqual(result.context.projectStructure, context.projectStructure)
        XCTAssertEqual(result.context.selection, context.selection)
        XCTAssertEqual(result.context.documentName, context.documentName)
        XCTAssertTrue(result.summary.contains("350 input tokens"))
        let baseline = AIChatConversation.requestPrompt(userPrompt: "Write a poem", context: context, history: [])
        let filtered = AIChatConversation.requestPrompt(userPrompt: "Write a poem", context: result.context, history: [])
        XCTAssertLessThan(filtered.count, baseline.count)
        XCTAssertTrue(filtered.contains("<selection>\n" + String(repeating: "s", count: 4_000) + "\n</selection>"))
        XCTAssertTrue(result.summary.contains("17/6017 optional characters retained"))
    }

    func testUncertainAndThresholdBoundaryRetainContext() async throws {
        for value in [answer("uncertain"), answer("irrelevant", confidence: 0.899), answer("irrelevant", probability: 0.949)] {
            let ranker = try fixtureRanker(answers: ["document": value, "project": answer("relevant")])
            let result = await ranker.rank(prompt: "Explain", context: context)
            XCTAssertEqual(result.context.documentText, context.documentText)
        }
        let ranker = try fixtureRanker(answers: ["document": answer("irrelevant", confidence: 0.9, probability: 0.95), "project": answer("relevant")])
        let result = await ranker.rank(prompt: "Explain", context: context)
        XCTAssertNil(result.context.documentText)
    }

    func testMalformedMismatchedAndFailedResponsesRetainAllContext() async throws {
        var invalid = answer("irrelevant")
        invalid["confidence"] = 2
        var badDistribution = answer("irrelevant")
        badDistribution["probabilities"] = ["relevant": 0, "irrelevant": 0.9, "uncertain": 0]
        var wrongType = answer("irrelevant")
        wrongType["type"] = "score"
        var inconsistent = answer("irrelevant")
        inconsistent["probabilities"] = ["relevant": 1, "irrelevant": 0, "uncertain": 0]
        let cases: [[String: Any]] = [
            [:], ["document": answer("irrelevant")],
            ["document": invalid, "project": answer("irrelevant")],
            ["document": badDistribution, "project": answer("irrelevant")],
            ["document": wrongType, "project": answer("irrelevant")],
            ["document": inconsistent, "project": answer("irrelevant")],
            ["document": ["type": "choice"], "project": answer("irrelevant")]
        ]
        for answers in cases {
            let result = await (try fixtureRanker(answers: answers)).rank(prompt: "Explain", context: context)
            XCTAssertEqual(result.context.documentText, context.documentText)
            XCTAssertEqual(result.context.projectStructure, context.projectStructure)
        }
        let answers = ["document": answer("irrelevant"), "project": answer("irrelevant")]
        for ranker in [try fixtureRanker(answers: answers, status: 429), try fixtureRanker(answers: answers, error: true),
                       try fixtureRanker(answers: answers, model: "different-model"), JevContextRanker(apiKey: "")] {
            let result = await ranker.rank(prompt: "Explain", context: context)
            XCTAssertEqual(result.context.documentText, context.documentText)
            XCTAssertEqual(result.context.projectStructure, context.projectStructure)
        }
    }

    private final class CapturingClient: AIClient {
        var requests: [String] = []
        func streamSuggestions(prompt: String) -> AsyncStream<String> {
            requests.append(prompt)
            return AsyncStream { $0.yield("Fixture response"); $0.finish() }
        }
    }

    private final class DelayedRanker: AIChatContextRanking {
        var calls = 0
        var resume: CheckedContinuation<AIChatContextRankingResult, Never>?
        func rank(prompt: String, context: AIChatContext) async -> AIChatContextRankingResult {
            calls += 1
            return await withCheckedContinuation { resume = $0 }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for fixture state")
    }

    func testUnavailableRankingPreservesExistingPromptAndSelectionLimits() async throws {
        let conversation = AIChatConversation()
        let client = CapturingClient()
        let selection = "    " + String(repeating: "π", count: 40_000) + "\nTAIL\n"
        let context = AIChatContext(selection: selection, documentName: "Test", documentLanguage: "swift",
                                    documentText: "optional document", projectStructure: nil)
        let prompt = "  Complete request\n"
        let baseline = AIChatConversation.requestPrompt(
            userPrompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), context: context, history: []
        )
        conversation.start(prompt: prompt, context: context, providerName: "Test", client: client,
                           contextRanker: JevContextRanker(apiKey: ""))
        try await waitUntil { !conversation.isSending }
        XCTAssertEqual(client.requests.first?.count, baseline.count)
        XCTAssertEqual(client.requests.first, baseline)
        conversation.clear()
    }

    func testConversationPreservesBoundedSelectionAndRetryWithoutReranking() async throws {
        let conversation = AIChatConversation()
        let client = CapturingClient()
        let ranker = DelayedRanker()
        let selection = "    " + String(repeating: "π", count: 5_000) + "\nTAIL\n"
        let context = AIChatContext(selection: selection, documentName: "Test", documentLanguage: "swift", documentText: "optional document", projectStructure: nil)
        conversation.start(prompt: "  Complete request\n", context: context, providerName: "Test", client: client, contextRanker: ranker)
        try await waitUntil { ranker.calls == 1 }
        XCTAssertTrue(client.requests.isEmpty)
        ranker.resume?.resume(returning: .init(context: .init(selection: selection, documentName: "Test", documentLanguage: "swift", documentText: nil, projectStructure: nil), summary: "Fixture ranking"))
        ranker.resume = nil
        try await waitUntil { !conversation.isSending }
        XCTAssertTrue(client.requests[0].contains("<selection>\n" + String(selection.prefix(4_000)) + "\n</selection>"))
        XCTAssertFalse(client.requests[0].contains("TAIL"))
        XCTAssertTrue(client.requests[0].hasSuffix("USER:\nComplete request"))
        XCTAssertFalse(client.requests[0].contains("optional document"))
        conversation.retryLast()
        try await waitUntil { !conversation.isSending }
        XCTAssertEqual(ranker.calls, 1)
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests[0], client.requests[1])
        conversation.clear()
    }

    func testCancelledRankingCannotStartProviderOrOverwriteNewRequest() async throws {
        let conversation = AIChatConversation()
        let oldClient = CapturingClient()
        let newClient = CapturingClient()
        let ranker = DelayedRanker()
        conversation.start(prompt: "Old", context: context, providerName: "Test", client: oldClient, contextRanker: ranker)
        try await waitUntil { ranker.calls == 1 }
        conversation.clear()
        conversation.start(prompt: "New", context: context, providerName: "Test", client: newClient)
        ranker.resume?.resume(returning: .init(context: context, summary: "Stale ranking"))
        ranker.resume = nil
        try await waitUntil { !conversation.isSending }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(oldClient.requests.isEmpty)
        XCTAssertEqual(newClient.requests.count, 1)
        XCTAssertNil(conversation.contextRankingSummary)
        conversation.clear()
    }

    func testFollowUpAndDisabledRankingKeepOriginalContext() async throws {
        let conversation = AIChatConversation()
        let client = CapturingClient()
        conversation.start(prompt: "First", context: context, providerName: "Test", client: client)
        try await waitUntil { !conversation.isSending }
        let followUpContext = AIChatContext(selection: String(repeating: "s", count: 5_000), documentName: "Test",
                                           documentLanguage: "swift", documentText: context.documentText,
                                           projectStructure: context.projectStructure)
        let baseline = AIChatConversation.requestPrompt(userPrompt: "Now fix that", context: followUpContext,
                                                         history: conversation.messages[...])
        let ranker = DelayedRanker()
        conversation.start(prompt: "Now fix that", context: followUpContext, providerName: "Test", client: client, contextRanker: ranker)
        try await waitUntil { !conversation.isSending }
        XCTAssertEqual(ranker.calls, 0)
        XCTAssertTrue(client.requests.last?.contains(context.documentText!) == true)
        XCTAssertEqual(client.requests.last, baseline)
        XCTAssertTrue(conversation.contextRankingSummary?.contains("follow-up") == true)
        conversation.clear()
    }
}
