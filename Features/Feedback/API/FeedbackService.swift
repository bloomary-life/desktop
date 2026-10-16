import Foundation

enum FeedbackError: LocalizedError {
    case emptyMessage
    case server(String)

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Feedback message is empty."
        case .server(let message):
            return message
        }
    }
}

struct FeedbackImageAttachment: Encodable, Identifiable {
    let id = UUID()
    let filename: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case filename
        case content
    }
}

final class FeedbackService {
    private let apiBaseURL: URL

    init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    func send(title: String, message: String, identity: FeedbackSenderIdentity?, attachments: [FeedbackImageAttachment]) async throws {
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw FeedbackError.emptyMessage }

        var request = URLRequest(url: apiBaseURL.appending(path: "/api/feedback"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.app.encode(FeedbackRequest(
            name: identity?.name ?? "",
            linkedInID: identity?.linkedInID ?? "",
            email: identity?.email ?? "",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            message: body,
            attachments: attachments
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder.app.decode(FeedbackAPIErrorResponse.self, from: data) {
                throw FeedbackError.server(apiError.errorDescription ?? apiError.error)
            }
            throw FeedbackError.server("Feedback send failed.")
        }
    }
}

struct FeedbackSenderIdentity {
    let name: String
    let linkedInID: String
    let email: String?
}

private struct FeedbackRequest: Encodable {
    let name: String
    let linkedInID: String
    let email: String
    let title: String
    let message: String
    let attachments: [FeedbackImageAttachment]

    enum CodingKeys: String, CodingKey {
        case name
        case linkedInID = "linkedInId"
        case email
        case title
        case message
        case attachments
    }
}

private struct FeedbackAPIErrorResponse: Codable {
    let error: String
    let errorDescription: String?
}
