#if USE_FOUNDATION_MODELS && canImport(FoundationModels)
import Foundation
import FoundationModels

@available(macOS 26.0, iOS 19.0, *)
@Generable(description: "Plain generated text")
public struct GeneratedText { public var text: String }

public enum AppleFM {
    /// Global toggle to enable Apple Foundation Models features at runtime.
    /// Defaults to `false` so code completion/AI features are disabled by default.
    public static var isEnabled: Bool = false

    private static func featureDisabledError() -> NSError {
        NSError(domain: "AppleFM", code: -10, userInfo: [NSLocalizedDescriptionKey: "Foundation Models feature is disabled by default. Enable via AppleFM.isEnabled = true."])
    }

    /// Perform a simple health check by requesting a short completion using the system model.
    /// - Returns: A string indicating the model is responsive ("pong").
    /// - Throws: Any error thrown by the Foundation Models API or availability checks.
    public static func appleFMHealthCheck() async throws -> String {
        if #available(iOS 19.0, macOS 26.0, *) {
            guard isEnabled else {
                AppLogger.shared.warning("AppleFM health check attempted but isEnabled=false", category: "AI")
                throw featureDisabledError()
            }
            // Ensure the system model is available before attempting to respond
            let model = SystemLanguageModel.default
            AppLogger.shared.debug("AppleFM health check: SystemLanguageModel availability = \(model.availability)", category: "AI")
            guard case .available = model.availability else {
                let error = NSError(domain: "AppleFM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence model unavailable: \(String(describing: model.availability))"])
                AppLogger.shared.error("AppleFM health check failed: \(error.localizedDescription)", category: "AI")
                throw error
            }
            AppLogger.shared.debug("AppleFM health check: creating LanguageModelSession", category: "AI")
            let session = LanguageModelSession()
            let start = Date()
            _ = try await session.respond(to: "ping")
            let duration = Date().timeIntervalSince(start)
            AppLogger.shared.debug("AppleFM health check: pong received in \(String(format: "%.3f", duration))s", category: "AI")
            return "pong"
        } else {
            let error = NSError(domain: "AppleFM", code: -3, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence requires iOS 19 / macOS 26 or later."])
            AppLogger.shared.error("AppleFM health check failed: \(error.localizedDescription)", category: "AI")
            throw error
        }
    }

    /// Generate a completion from the given prompt using the system language model.
    /// - Parameter prompt: The prompt string to complete.
    /// - Returns: The completion text from the model.
    /// - Throws: Any error thrown by the Foundation Models API or availability checks.
    public static func appleFMComplete(prompt: String) async throws -> String {
        if #available(iOS 19.0, macOS 26.0, *) {
            guard isEnabled else {
                AppLogger.shared.warning("AppleFM completion attempted but isEnabled=false", category: "AI")
                throw featureDisabledError()
            }
            AppLogger.shared.info("AppleFM completion requested, prompt length: \(prompt.count) chars", category: "AI")
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                let error = NSError(domain: "AppleFM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence model unavailable: \(String(describing: model.availability))"])
                AppLogger.shared.error("AppleFM completion failed: \(error.localizedDescription)", category: "AI")
                throw error
            }
            let session = LanguageModelSession()
            let start = Date()
            let response = try await session.respond(to: prompt)
            let duration = Date().timeIntervalSince(start)
            AppLogger.shared.info("AppleFM completion received: \(response.content.count) chars in \(String(format: "%.2f", duration))s", category: "AI")
            return response.content
        } else {
            let error = NSError(domain: "AppleFM", code: -3, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence requires iOS 19 / macOS 26 or later."])
            AppLogger.shared.error("AppleFM completion failed: \(error.localizedDescription)", category: "AI")
            throw error
        }
    }

    /// Stream a completion from the given prompt, yielding partial updates as the model generates them.
    /// - Parameter prompt: The prompt string to complete.
    /// - Returns: An AsyncStream of incremental text deltas.
    public static func appleFMStream(prompt: String) -> AsyncStream<String> {
        if #available(iOS 19.0, macOS 26.0, *) {
            guard isEnabled else {
                AppLogger.shared.warning("AppleFM stream attempted but isEnabled=false", category: "AI")
                return AsyncStream { $0.finish() }
            }
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                AppLogger.shared.error("AppleFM stream failed: SystemLanguageModel unavailable (\(model.availability))", category: "AI")
                return AsyncStream { $0.finish() }
            }

            AppLogger.shared.info("AppleFM streaming started, prompt length: \(prompt.count) chars", category: "AI")
            
            return AsyncStream { continuation in
                Task {
                    let startTime = Date()
                    var chunkCount = 0
                    var totalChars = 0
                    
                    do {
                        let session = LanguageModelSession()
                        AppLogger.shared.debug("AppleFM stream: session created", category: "AI")

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
                                chunkCount += 1
                                totalChars += delta.count
                                AppLogger.shared.debug("AppleFM stream chunk #\(chunkCount): \(delta.count) chars", category: "AI")
                                continuation.yield(delta)
                            }
                            last = current
                        }
                        
                        let duration = Date().timeIntervalSince(startTime)
                        AppLogger.shared.info("AppleFM streaming completed: \(chunkCount) chunks, \(totalChars) total chars in \(String(format: "%.2f", duration))s", category: "AI")
                    } catch {
                        let duration = Date().timeIntervalSince(startTime)
                        AppLogger.shared.warning("AppleFM streaming failed after \(String(format: "%.2f", duration))s: \(error.localizedDescription), attempting fallback", category: "AI")
                        
                        // Fallback to single-shot completion if streaming fails
                        do {
                            let fallbackStart = Date()
                            let response = try await LanguageModelSession().respond(to: prompt)
                            let fallbackDuration = Date().timeIntervalSince(fallbackStart)
                            AppLogger.shared.info("AppleFM fallback completion succeeded: \(response.content.count) chars in \(String(format: "%.2f", fallbackDuration))s", category: "AI")
                            continuation.yield(response.content)
                        } catch {
                            AppLogger.shared.error("AppleFM fallback completion also failed: \(error.localizedDescription)", category: "AI")
                        }
                    }
                    continuation.finish()
                }
            }
        } else {
            AppLogger.shared.warning("AppleFM stream unavailable: requires iOS 19 / macOS 26 or later", category: "AI")
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
    }
}

#else

import Foundation

public enum AppleFM {
    /// Global toggle to enable Apple Foundation Models features at runtime.
    /// Defaults to `false` so code completion/AI features are disabled by default.
    public static var isEnabled: Bool = false

    /// Stub health check implementation when Foundation Models is not available.
    /// - Throws: Always throws an error indicating the feature is unavailable.
    public static func appleFMHealthCheck() async throws -> String {
        throw NSError(domain: "AppleFM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models feature is not enabled."])
    }

    /// Stub completion implementation when Foundation Models is not available.
    /// - Parameter prompt: The prompt string.
    /// - Returns: Placeholder string indicating unavailable feature.
    public static func appleFMComplete(prompt: String) async throws -> String {
        return "Completion unavailable: Foundation Models feature not enabled."
    }

    /// Stub streaming implementation when Foundation Models is not available.
    public static func appleFMStream(prompt: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }
}

#endif



 

