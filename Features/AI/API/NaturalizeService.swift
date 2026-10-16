import Foundation

enum NaturalizeError: LocalizedError {
    case emptyText
    case missingAPIKey
    case server(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Post is empty."
        case .missingAPIKey:
            return "Add your AI API key in Settings first."
        case .server(let message):
            return message
        }
    }
}

final class NaturalizeService {
    private let chatCompletionURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
    private let model = "gemini-3.8-flash"

    func naturalize(text: String, settings: AISettings) async throws -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw NaturalizeError.emptyText }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NaturalizeError.missingAPIKey
        }

        var request = URLRequest(url: chatCompletionURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.app.encode(ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: naturalizeSystemPrompt),
                ChatMessage(role: "user", content: "Edit this LinkedIn draft:\n\n\(text)")
            ],
            temperature: 0.2
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder.app.decode(GeminiAPIErrorResponse.self, from: data) {
                throw NaturalizeError.server(apiError.error.message)
            }
            throw NaturalizeError.server("AI edit failed.")
        }
        guard let text = try JSONDecoder.app.decode(ChatCompletionResponse.self, from: data).choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw NaturalizeError.server("AI edit failed.")
        }
        return text
    }
}

private let naturalizeSystemPrompt = "You receive a LinkedIn post draft from the user. Draft a LinkedIn post, fix grammar, naturalize English, preserve the user's style, and do not modify meaning. Make the result sound more like the user: preserve their voice, rhythm, directness, emotional logic, and slightly non-native but clear English phrasing when it adds authenticity. Make it hooked in the first 2-3 sentences. Carefully compress the draft: eliminate unnecessary words and replace longer words with shorter ones, ensuring the post retains its original meaning, information, and tone. Wrap any moments you want highlighted — results, numbers, surprising facts, punchy one-liners — in double asterisks like **this**. End the post with exactly three relevant hashtags on one final line. Replace or deduplicate any existing hashtags so the final post contains exactly three hashtags total. Do not explain your edits or wrap the answer in quotes. Return only the edited post."

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct GeminiAPIErrorResponse: Decodable {
    let error: GeminiAPIError

    struct GeminiAPIError: Decodable {
        let message: String
    }
}
