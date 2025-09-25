import Foundation

class GrokAPIClient {
    private let apiKey: String
    private let baseURL = "https://api.x.ai/v1"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func generateText(prompt: String, model: String = "grok-3-beta", maxTokens: Int = 500) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
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
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "GrokAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }

        let json = try JSONDecoder().decode(GrokResponse.self, from: data)
        return json.choices.first?.message.content ?? ""
    }
}

struct GrokResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}