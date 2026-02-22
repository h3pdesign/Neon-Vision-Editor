import Foundation

public final class AIModelClient {
    public let apiKey: String
    private let baseURLString = "https://api.x.ai/v1"

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    ///MARK: - Non-streaming text generation
    public func generateText(prompt: String, model: String = "grok-3-beta", maxTokens: Int = 500) async throws -> String {
        guard let baseURL = URL(string: baseURLString) else {
            throw NSError(
                domain: "AIModelClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API base URL"]
            )
        }
        let url = baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "AIModelClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "API request failed (status: \(status))"])
        }

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    ///MARK: - Streaming suggestions (SSE)
    public func streamSuggestions(prompt: String, model: String = "grok-code-fast-1") -> AsyncStream<String> {
        guard let baseURL = URL(string: baseURLString) else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        let url = baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": "You are a helpful code assistant providing concise inline suggestions."],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        struct ChatDeltaChunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta?
                let finish_reason: String?
            }
            let choices: [Choice]?
        }

        return AsyncStream<String> { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        continuation.finish()
                        return
                    }
                    var buffer = ""
                    for try await chunk in bytes.lines {
                        buffer += chunk + "\n"
                        while let range = buffer.range(of: "\n\n") {
                            let event = String(buffer[..<range.lowerBound])
                            buffer = String(buffer[range.upperBound...])

                            let dataLines = event
                                .split(separator: "\n")
                                .filter { $0.hasPrefix("data:") }
                                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }

                            guard !dataLines.isEmpty else { continue }

                            // Handle SSE sentinel
                            if dataLines.count == 1, dataLines[0] == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            let payload = dataLines.joined(separator: "\n")

                            if let data = payload.data(using: .utf8) {
                                if let chunk = try? JSONDecoder().decode(ChatDeltaChunk.self, from: data),
                                   let choice = chunk.choices?.first {
                                    if let content = choice.delta?.content, !content.isEmpty {
                                        continuation.yield(content)
                                    }
                                    if choice.finish_reason != nil {
                                        continuation.finish()
                                        return
                                    }
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    // Fallback: non-streaming request
                    let task = URLSession.shared.dataTask(with: request) { data, _, _ in
                        defer { continuation.finish() }
                        guard let data = data else { return }
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let message = first["message"] as? [String: Any],
                           let content = message["content"] as? String {
                            continuation.yield(content)
                        }
                    }
                    task.resume()
                }
            }
        }
    }
}
