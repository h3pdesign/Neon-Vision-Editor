import Foundation

struct GrokAPIClient {
    let apiKey: String
    private let baseURL = URL(string: "https://api.x.ai/v1")!
    
    func generateText(prompt: String, maxTokens: Int = 100) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("generate"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "grok-4",
            "prompt": prompt,
            "max_tokens": maxTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let json = try JSONDecoder().decode([String: String].self, from: data)
        return json["text"] ?? ""
    }
}
