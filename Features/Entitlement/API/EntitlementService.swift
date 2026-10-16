import Foundation

enum EntitlementError: LocalizedError {
    case missingAuth
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAuth:
            return "LinkedIn connection is required."
        case .server(let message):
            return message
        }
    }
}

struct Entitlement: Codable, Equatable {
    let isPro: Bool
    let subscriptionSource: String?
    let draftLimit: Int
    let postCount: Int
    let accessUntil: Date?
}

final class EntitlementService {
    private let apiBaseURL: URL

    init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    func entitlement(credential: LinkedInPostCredential) async throws -> Entitlement {
        guard !credential.accessToken.isEmpty, !credential.memberID.isEmpty else {
            throw EntitlementError.missingAuth
        }

        var components = URLComponents(url: apiBaseURL.appending(path: "/api/entitlement"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "memberId", value: credential.memberID)]
        guard let url = components?.url else {
            throw EntitlementError.server("Entitlement load failed.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder.app.decode(EntitlementAPIError.self, from: data) {
                throw EntitlementError.server(apiError.errorDescription ?? apiError.error)
            }
            throw EntitlementError.server("Entitlement load failed.")
        }

        return try JSONDecoder.app.decode(Entitlement.self, from: data)
    }
}

private struct EntitlementAPIError: Decodable {
    let error: String
    let errorDescription: String?
}
