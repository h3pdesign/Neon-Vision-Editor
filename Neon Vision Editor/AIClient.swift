import Foundation

#if USE_FOUNDATION_MODELS
import FoundationModels
#endif

#if false
// This enum is defined in ContentView.swift; this is here to avoid redefinition errors.
public enum AIModel {
    case appleIntelligence
    case grok
    // New cases (non-compiling stub for reference)
    case openAI
    case gemini
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
                        let response = try await fmModel.generate(prompt)
                        continuation.yield(response)
                    } catch { }
                    continuation.finish()
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

final class OpenAIAIClient: AIClient {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    func streamSuggestions(prompt: String) -> AsyncStream<String> {
        // For simplicity, use non-streaming completion and yield once. You can upgrade to SSE later.
        return AsyncStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": model,
                        "messages": [["role": "user", "content": prompt]],
                        "max_tokens": 200
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continuation.finish()
                        return
                    }
                    if let text = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = text["choices"] as? [[String: Any]],
                       let first = choices.first,
                       let msg = first["message"] as? [String: Any],
                       let content = msg["content"] as? String {
                        continuation.yield(content)
                    }
                } catch { }
                continuation.finish()
            }
        }
    }
}

final class GeminiAIClient: AIClient {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gemini-1.5-pro") {
        self.apiKey = apiKey
        self.model = model
    }

    func streamSuggestions(prompt: String) -> AsyncStream<String> {
        // Use text generation via non-streaming and yield once.
        return AsyncStream { continuation in
            Task {
                do {
                    var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
                    comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
                    var request = URLRequest(url: comps.url!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "contents": [[
                            "parts": [["text": prompt]]
                        ]]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continuation.finish()
                        return
                    }
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let candidates = json["candidates"] as? [[String: Any]],
                       let first = candidates.first,
                       let content = first["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let text = parts.first?["text"] as? String {
                        continuation.yield(text)
                    }
                } catch { }
                continuation.finish()
            }
        }
    }
}

// Streaming Grok AIClient using xAI API Server-Sent Events
final class GrokAIClientStreaming: AIClient {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "grok-3-beta") {
        self.apiKey = apiKey
        self.model = model
    }

    func streamSuggestions(prompt: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            // Build streaming request
            var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": prompt]],
                "stream": true,
                "max_tokens": 200
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                // Non-streaming fallback: yield once if server doesn't stream
                if let data, let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    if let text = String(data: data, encoding: .utf8) {
                        // Attempt to parse content quickly
                        if let content = GrokAIClientStreaming.extractContent(from: data) {
                            continuation.yield(content)
                        } else {
                            continuation.yield(text)
                        }
                    }
                }
                continuation.finish()
            }

            // Prefer streaming via bytes task when available
            if #available(macOS 12.0, *) {
                let session = URLSession(configuration: .default)
                Task {
                    do {
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                            continuation.finish(); return
                        }
                        for try await line in bytes.lines {
                            // xAI SSE format: lines starting with "data: {json}"
                            guard line.hasPrefix("data:") else { continue }
                            let jsonPart = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if jsonPart == "[DONE]" { break }
                            if let data = jsonPart.data(using: .utf8),
                               let chunk = GrokAIClientStreaming.extractDelta(from: data), !chunk.isEmpty {
                                continuation.yield(chunk)
                            }
                        }
                    } catch {
                        // Fall back to non-streaming task
                        task.resume()
                    }
                    continuation.finish()
                }
            } else {
                // Fallback for older macOS
                task.resume()
            }
        }
    }

    private static func extractContent(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }

    private static func extractDelta(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let choices = obj["choices"] as? [[String: Any]],
           let first = choices.first,
           let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        // some providers may stream as { "choices": [{"message": {"content": "..."}}] }
        if let choices = obj["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return nil
    }
}

enum AIProviderTokenKey { case grok, openAI, gemini }

struct AIClientFactory {
    static func makeClient(for model: AIModel,
                           grokAPITokenProvider: () -> String? = { nil },
                           openAIKeyProvider: () -> String? = { nil },
                           geminiKeyProvider: () -> String? = { nil }) -> AIClient? {
        switch model {
        case .appleIntelligence:
            return AppleIntelligenceAIClient()
        case .grok:
            if let token = grokAPITokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
                // Use streaming GrokAIClient
                return GrokAIClientStreaming(apiKey: token)
            }
            return nil
        case .openAI:
            if let key = openAIKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return OpenAIAIClient(apiKey: key)
            }
            return nil
        case .gemini:
            if let key = geminiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return GeminiAIClient(apiKey: key)
            }
            return nil
        }
    }
}
