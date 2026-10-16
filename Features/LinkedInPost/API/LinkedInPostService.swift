import Foundation

enum LinkedInPostError: LocalizedError {
    case emptyPost
    case missingAuth
    case server(String)

    var errorDescription: String? {
        switch self {
        case .emptyPost:
            return "Post is empty."
        case .missingAuth:
            return "Connect LinkedIn first."
        case .server(let message):
            return message
        }
    }
}

final class LinkedInPostService {
    private let apiBaseURL: URL

    init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    func publish(text: String, credential: LinkedInPostCredential?, attachment: LinkedInPostAttachment? = nil) async throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || attachment != nil else { throw LinkedInPostError.emptyPost }
        guard let credential, !credential.accessToken.isEmpty, !credential.memberID.isEmpty else {
            throw LinkedInPostError.missingAuth
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let builder = MultipartFormDataBuilder(boundary: boundary)
        var request = URLRequest(url: apiBaseURL.appending(path: "/api/linkedin/post"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = builder.body(
            fields: [
                "memberId": credential.memberID,
                "commentary": body,
                "timezone": TimeZone.current.identifier
            ],
            file: attachment.map { MultipartFormFile(fieldName: "attachment", filename: $0.filename, mimeType: $0.mimeType, data: $0.data) }
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder.app.decode(PostAPIErrorResponse.self, from: data) {
                throw LinkedInPostError.server(apiError.errorDescription ?? apiError.error)
            }
            throw LinkedInPostError.server("LinkedIn post failed.")
        }
    }

    func schedule(draftID: UUID, at date: Date, credential: LinkedInPostCredential?) async throws -> ScheduledPostResult {
        guard let credential, !credential.accessToken.isEmpty, !credential.memberID.isEmpty else {
            throw LinkedInPostError.missingAuth
        }
        var components = URLComponents(url: apiBaseURL.appending(path: "/api/linkedin/schedule"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "memberId", value: credential.memberID)]
        guard let url = components?.url else { throw LinkedInPostError.server("LinkedIn scheduling failed.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        request.httpBody = try JSONEncoder.app.encode(
            ScheduleRequest(draftId: draftID.uuidString, scheduledAt: formatter.string(from: date))
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let apiError = try? JSONDecoder.app.decode(PostAPIErrorResponse.self, from: data)
            throw LinkedInPostError.server(apiError?.errorDescription ?? apiError?.error ?? "LinkedIn scheduling failed.")
        }
        return try JSONDecoder.app.decode(ScheduledPostResult.self, from: data)
    }
}

struct LinkedInPostAttachment: Equatable {
    let data: Data
    let filename: String
    let mimeType: String
}

struct LinkedInPostCredential {
    let accessToken: String
    let memberID: String
}

struct ScheduledPostResult: Decodable, Equatable {
    let scheduleId: String
    let draftId: String?
    let status: String
    let scheduledAt: String
    let message: String?
}

private struct ScheduleRequest: Encodable {
    let draftId: String
    let scheduledAt: String
}

private struct PostAPIErrorResponse: Codable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription
    }
}
