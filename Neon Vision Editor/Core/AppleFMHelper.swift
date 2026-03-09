#if USE_FOUNDATION_MODELS && canImport(FoundationModels) && canImport(FoundationModelsMacros)
import Foundation
import FoundationModels

@Generable(description: "Plain generated text")


/// MARK: - Types

public struct GeneratedText { public var text: String }

public enum AppleFM {
    public static var isEnabled: Bool = false

    private static func featureDisabledError() -> NSError {
        NSError(domain: "AppleFM", code: -10, userInfo: [NSLocalizedDescriptionKey: "Foundation Models feature is disabled by default. Enable via AppleFM.isEnabled = true."])
    }

    public static func appleFMHealthCheck() async throws -> String {
        if #available(iOS 18.0, macOS 15.0, *) {
            guard isEnabled else {
                throw featureDisabledError()
            }
            // Ensure the system model is available before attempting to respond
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw NSError(domain: "AppleFM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence model unavailable: \(String(describing: model.availability))"]) 
            }
            let session = LanguageModelSession()
            _ = try await session.respond(to: "ping")
            return "pong"
        } else {
            throw NSError(domain: "AppleFM", code: -3, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence requires iOS 18 / macOS 15 or later."])
        }
    }

    public static func appleFMComplete(prompt: String) async throws -> String {
        if #available(iOS 18.0, macOS 15.0, *) {
            guard isEnabled else {
                throw featureDisabledError()
            }
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw NSError(domain: "AppleFM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence model unavailable: \(String(describing: model.availability))"]) 
            }
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return response.content
        } else {
            throw NSError(domain: "AppleFM", code: -3, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence requires iOS 18 / macOS 15 or later."])
        }
    }

    public static func appleFMStream(prompt: String) -> AsyncStream<String> {
        if #available(iOS 18.0, macOS 15.0, *) {
            guard isEnabled else {
                return AsyncStream { $0.finish() }
            }
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                return AsyncStream { $0.finish() }
            }

            return AsyncStream { continuation in
                Task {
                    do {
                        let session = LanguageModelSession()

                        var last = ""
                        for try await partial in session.streamResponse(to: prompt, generating: GeneratedText.self) {
                            // Extract the full current text from the partially generated content
                            let currentOptional = partial.content.text

                            // If the model hasn't produced any text yet, skip this iteration
                            guard let current = currentOptional else { continue }

                            // Compute the delta from the last full content we saw using String indices
                            let lastCount = last.count
                            let currentCount = current.count
                            let prefixCount = min(lastCount, currentCount)

                            let startIdx = current.index(current.startIndex, offsetBy: prefixCount)
                            let delta = String(current[startIdx...])

                            if !delta.isEmpty {
                                continuation.yield(delta)
                            }
                            last = current
                        }
                    } catch {
                        // Fallback to single-shot completion if streaming fails
                        do {
                            let response = try await LanguageModelSession().respond(to: prompt)
                            continuation.yield(response.content)
                        } catch {
                            // Swallow secondary errors
                        }
                    }
                    continuation.finish()
                }
            }
        } else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
    }
}

#else

import Foundation

public enum AppleFM {
    public static var isEnabled: Bool = false

    public static func appleFMHealthCheck() async throws -> String {
        throw NSError(domain: "AppleFM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models feature is not enabled."])
    }

    public static func appleFMComplete(prompt: String) async throws -> String {
        return "Completion unavailable: Foundation Models feature not enabled."
    }

    public static func appleFMStream(prompt: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }
}

#endif



 

