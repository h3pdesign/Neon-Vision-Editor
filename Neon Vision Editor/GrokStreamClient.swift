import Foundation

public struct GrokStreamClient {
    public let apiKey: String
    /// Update to the latest code-focused Grok model as per xAI docs
    public var model: String = "grok-code-fast-1"
    private let endpoint = URL(string: "https://api.x.ai/v1/chat/completions")!

    private struct ChatDeltaChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta?
            let finish_reason: String?
        }
        let choices: [Choice]?
    }

    public func streamSuggestions(prompt: String) -> AsyncStream<String> {
        var request = URLRequest(url: endpoint)
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

                            let payload = event
                                .split(separator: "\n")
                                .filter { $0.hasPrefix("data:") }
                                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                                .joined()

                            guard !payload.isEmpty else { continue }
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
                    let task = URLSession.shared.dataTask(with: request) { data, _, error in
                        defer { continuation.finish() }
                        guard error == nil, let data = data else { return }
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
