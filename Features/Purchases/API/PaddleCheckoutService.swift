import Foundation

struct PaddleCheckoutIdentity: Decodable {
    let memberId: String
    let signature: String
}

private struct PaddlePortalSession: Decodable {
    let url: URL
}

final class PaddleCheckoutService {
    private let apiBaseURL: URL

    init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    func identity(credential: LinkedInPostCredential) async throws -> PaddleCheckoutIdentity {
        guard var components = URLComponents(url: apiBaseURL.appending(path: "/api/paddle/checkout-identity"), resolvingAgainstBaseURL: false) else {
            throw EntitlementError.server("Could not prepare Paddle checkout.")
        }
        components.queryItems = [URLQueryItem(name: "memberId", value: credential.memberID)]
        guard let url = components.url else { throw EntitlementError.server("Could not prepare Paddle checkout.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw EntitlementError.server("Could not prepare Paddle checkout.")
        }
        return try JSONDecoder.app.decode(PaddleCheckoutIdentity.self, from: data)
    }

    func portalURL(credential: LinkedInPostCredential) async throws -> URL {
        guard var components = URLComponents(url: apiBaseURL.appending(path: "/api/paddle/portal"), resolvingAgainstBaseURL: false) else {
            throw EntitlementError.server("Could not open subscription settings.")
        }
        components.queryItems = [URLQueryItem(name: "memberId", value: credential.memberID)]
        guard let url = components.url else { throw EntitlementError.server("Could not open subscription settings.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EntitlementError.server("Could not open subscription settings.")
        }
        if http.statusCode == 404 {
            throw EntitlementError.server("Manage this subscription where you originally subscribed.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw EntitlementError.server("Could not open subscription settings.")
        }
        return try JSONDecoder.app.decode(PaddlePortalSession.self, from: data).url
    }
}
