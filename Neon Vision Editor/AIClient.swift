import Foundation

#if USE_FOUNDATION_MODELS
import FoundationModels
#endif

#if false
// This enum is defined in ContentView.swift; this is here to avoid redefinition errors.
public enum AIModel {
    case appleIntelligence
    case grok
}
#endif

public protocol AIClient {
    func streamSuggestions(prompt: String) -> AsyncStream<String>
}

public struct AppleIntelligenceAIClient: AIClient {
    public init() {}

    public func streamSuggestions(prompt: String) -> AsyncStream<String> {
#if USE_FOUNDATION_MODELS
        if let fmModel = try? FMTextModel(configuration: .init()) {
            return AsyncStream { continuation in
                Task {
                    do {
                        var isFirstChunk = true
                        for try await chunk in fmModel.generate(prompt) {
                            // Simulate streaming: first a prefix, then finish
                            if isFirstChunk {
                                continuation.yield("Here is a suggestion: \(chunk)")
                                isFirstChunk = false
                            } else {
                                continuation.yield(chunk)
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish()
                    }
                }
            }
        } else {
            // Fall back to simulated streamed chunks
            return AsyncStream { continuation in
                Task {
                    continuation.yield("Here is a suggestion:")
                    try? await Task.sleep(nanoseconds: 200 * 1_000_000)
                    continuation.yield(" the quick brown fox")
                    try? await Task.sleep(nanoseconds: 200 * 1_000_000)
                    continuation.yield(" jumps over the lazy dog.")
                    continuation.finish()
                }
            }
        }
#else
        // Simulated streaming for non-FoundationModels environment
        return AsyncStream { continuation in
            Task {
                continuation.yield("Here is a suggestion:")
                try? await Task.sleep(nanoseconds: 200 * 1_000_000)
                continuation.yield(" the quick brown fox")
                try? await Task.sleep(nanoseconds: 200 * 1_000_000)
                continuation.yield(" jumps over the lazy dog.")
                continuation.finish()
            }
        }
#endif
    }
}

public struct GrokAIClient: AIClient {
    private let apiKey: String
    private let model: String

    public init(apiKey: String, model: String = "grok-code-fast-1") {
        self.apiKey = apiKey
        self.model = model
    }

    public func streamSuggestions(prompt: String) -> AsyncStream<String> {
        let client = GrokStreamClient(apiKey: apiKey, model: model)
        return client.streamSuggestions(prompt: prompt)
    }
}

public enum AIClientFactory {
    public static func makeClient(for model: AIModel, grokAPITokenProvider: () -> String?) -> AIClient? {
        switch model {
        case .appleIntelligence:
            return AppleIntelligenceAIClient()
        case .grok:
            if let token = grokAPITokenProvider(), !token.isEmpty {
                return GrokAIClient(apiKey: token)
            } else {
                return nil
            }
        }
    }
}
