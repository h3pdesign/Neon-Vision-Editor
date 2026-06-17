import Foundation

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

// MARK: - Types

public protocol AIClient {
    func streamSuggestions(prompt: String) -> AsyncStream<String>
}

public struct AppleIntelligenceAIClient: AIClient {
    public init() {}

    public func streamSuggestions(prompt: String) -> AsyncStream<String> {
        // Delegate to the centralized Apple Foundation Models helper. When
        // Foundation Models are unavailable, AppleFM returns an empty stream
        // instead of simulating a completion.
        return AppleFM.appleFMStream(prompt: prompt)
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
            let apiKey = self.apiKey
            let model = self.model
            Task {
                do {
                    guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                        continuation.finish()
                        return
                    }
                    var request = URLRequest(url: url)
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

    init(apiKey: String, model: String = "gemini-2.5-flash-lite") {
        self.apiKey = apiKey
        self.model = model
    }

    func streamSuggestions(prompt: String) -> AsyncStream<String> {
        // Use text generation via non-streaming and yield once.
        return AsyncStream { continuation in
            let apiKey = self.apiKey
            let model = self.model
            Task {
                do {
                    guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
                        continuation.finish()
                        return
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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

final class AnthropicAIClient: AIClient {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "claude-3-5-haiku-latest") {
        self.apiKey = apiKey
        self.model = model
    }

    func streamSuggestions(prompt: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            let apiKey = self.apiKey
            let model = self.model
            Task {
                do {
                    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                        continuation.finish()
                        return
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 256,
                        "messages": [
                            ["role": "user", "content": prompt]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continuation.finish()
                        return
                    }
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let content = json["content"] as? [[String: Any]],
                       let first = content.first,
                       let text = first["text"] as? String {
                        continuation.yield(text)
                    } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? [String: Any],
                              let content = message["content"] as? [[String: Any]],
                              let first = content.first,
                              let text = first["text"] as? String {
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
            let apiKey = self.apiKey
            let model = self.model
            // Build streaming request
            guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
                continuation.finish()
                return
            }
            var request = URLRequest(url: url)
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

    nonisolated private static func extractContent(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }

    nonisolated private static func extractDelta(from data: Data) -> String? {
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

// OpenAI-compatible client for endpoints that speak the v1 chat-completions
// API (POST /v1/chat/completions, Bearer auth, choices[].message.content).
// Used for OpenCode Go and user-configured custom providers. The base URL and
// model are supplied per provider; an empty key sends no Authorization header
// so local/keyless servers work.
final class OpenAICompatibleAIClient: AIClient {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    init(apiKey: String, baseURL: String, model: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    func streamSuggestions(prompt: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            let apiKey = self.apiKey
            let model = self.model
            let endpoint = OpenAICompatibleAIClient.chatCompletionsURL(from: self.baseURL)
            Task {
                do {
                    guard let url = endpoint else {
                        AIActivityLog.record("OpenAI-compatible: invalid base URL", level: .error, source: "Completion")
                        continuation.finish()
                        return
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    if !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    // OpenCode Zen models are reasoning models: they spend tokens
                    // on reasoning_content before writing the answer to content.
                    // The budget must cover reasoning AND the completion, or content
                    // comes back empty with finish_reason "length".
                    let body: [String: Any] = [
                        "model": model,
                        "messages": [["role": "user", "content": prompt]],
                        "max_tokens": 1024
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        let bodyText = String(data: data, encoding: .utf8) ?? ""
                        AIActivityLog.record("OpenAI-compatible request failed: HTTP \(status) (model \(model)) \(bodyText.prefix(300))", level: .error, source: "Completion")
                        continuation.finish()
                        return
                    }
                    if let text = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = text["choices"] as? [[String: Any]],
                       let first = choices.first,
                       let msg = first["message"] as? [String: Any],
                       let content = msg["content"] as? String, !content.isEmpty {
                        continuation.yield(content)
                    } else {
                        // Empty content usually means the token budget was consumed by
                        // reasoning before any answer was produced (finish_reason "length").
                        let finishReason = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String ?? "unknown"
                        AIActivityLog.record("OpenAI-compatible: empty content (model \(model), finish_reason \(finishReason)); raise max_tokens or use a non-reasoning model", level: .warning, source: "Completion")
                    }
                } catch {
                    AIActivityLog.record("OpenAI-compatible request error: \(error.localizedDescription)", level: .error, source: "Completion")
                }
                continuation.finish()
            }
        }
    }

    // Accepts either a full chat-completions URL or a base URL and normalizes to
    // the v1 chat-completions endpoint.
    static func chatCompletionsURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: base + "/chat/completions")
    }
}

// Fixed configuration for the hosted OpenCode Go (OpenCode Zen) endpoint. Like
// the other providers, the model is fixed in code rather than user-selectable.
// deepseek-v4-flash is chosen for the highest rate limits among the supported
// models. Note: only the OpenAI-compatible models (GLM, DeepSeek, Kimi) work via
// this /chat/completions client; MiniMax and Qwen use OpenCode's Anthropic-style
// /v1/messages endpoint, so the default must stay an OpenAI-compatible model.
// These are reasoning models (they spend a large token budget on reasoning before
// the answer), so completion latency is high — best used on demand, not inline.
// Available models: https://opencode.ai/zen/go/v1/models
enum OpenCodeGoConfig {
    static let baseURL = "https://opencode.ai/zen/go/v1"
    static let defaultModel = "deepseek-v4-flash"
}

// UserDefaults keys for the user-configured custom OpenAI-compatible provider.
enum CustomProviderConfig {
    static let baseURLDefaultsKey = "CustomProviderBaseURL"
    static let modelDefaultsKey = "CustomProviderModel"
}

struct AIClientFactory {
    static func makeClient(for model: AIModel,
                           grokAPITokenProvider: () -> String? = { nil },
                           openAIKeyProvider: () -> String? = { nil },
                           geminiKeyProvider: () -> String? = { nil },
                           anthropicKeyProvider: () -> String? = { nil },
                           openCodeGoKeyProvider: () -> String? = { nil },
                           openCodeGoModelProvider: () -> String? = { nil },
                           customKeyProvider: () -> String? = { nil },
                           customBaseURLProvider: () -> String? = { nil },
                           customModelProvider: () -> String? = { nil }) -> AIClient? {
        switch model {
        case .appleIntelligence:
            // Default to Apple Intelligence client
            return AppleIntelligenceAIClient()
        case .grok:
            if let token = grokAPITokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
                return GrokAIClientStreaming(apiKey: token)
            }
            // Fallback to Apple Intelligence when no Grok key
            return AppleIntelligenceAIClient()
        case .openAI:
            if let key = openAIKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return OpenAIAIClient(apiKey: key)
            }
            // Fallback to Apple Intelligence when no OpenAI key
            return AppleIntelligenceAIClient()
        case .gemini:
            if let key = geminiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return GeminiAIClient(apiKey: key)
            }
            // Fallback to Apple Intelligence when no Gemini key
            return AppleIntelligenceAIClient()
        case .anthropic:
            if let key = anthropicKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return AnthropicAIClient(apiKey: key)
            }
            return AppleIntelligenceAIClient()
        case .openCodeGo:
            if let key = openCodeGoKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                let configuredModel = openCodeGoModelProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let model = configuredModel.isEmpty ? OpenCodeGoConfig.defaultModel : configuredModel
                return OpenAICompatibleAIClient(apiKey: key, baseURL: OpenCodeGoConfig.baseURL, model: model)
            }
            // Fallback to Apple Intelligence when no OpenCode Go key.
            return AppleIntelligenceAIClient()
        case .customProvider:
            let key = customKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let baseURL = customBaseURLProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let model = customModelProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !baseURL.isEmpty, !model.isEmpty {
                return OpenAICompatibleAIClient(apiKey: key, baseURL: baseURL, model: model)
            }
            // Fallback to Apple Intelligence until a base URL and model are configured.
            return AppleIntelligenceAIClient()
        }
    }
}
