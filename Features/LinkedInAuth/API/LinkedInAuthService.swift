import AuthenticationServices
import Foundation
import AppKit

enum LinkedInAuthError: LocalizedError {
    case invalidStartURL
    case missingWindow
    case cancelled
    case timedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidStartURL:
            return "LinkedIn authorization URL is invalid."
        case .missingWindow:
            return "Cannot open LinkedIn authorization."
        case .cancelled:
            return "LinkedIn authorization was cancelled."
        case .timedOut:
            return "LinkedIn authorization timed out."
        case .server(let message):
            return message
        }
    }
}

final class LinkedInAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let apiBaseURL: URL
    private let callbackURLScheme: String
    private let tokenStore: LinkedInTokenStore
    private var session: ASWebAuthenticationSession?
    private var requiresEphemeralSignIn = false

    init(apiBaseURL: URL, callbackURLScheme: String, tokenStore: LinkedInTokenStore) {
        self.apiBaseURL = apiBaseURL
        self.callbackURLScheme = callbackURLScheme
        self.tokenStore = tokenStore
    }

    @MainActor
    func signIn() async throws -> LinkedInToken {
        let start = try await startFlow()
        if let callbackURL = try await openAuthorization(start.authURL) {
            try await completeInterceptedCallback(callbackURL)
        }
        let token = try await pollResult(state: start.state)
        tokenStore.save(token)
        return token
    }

    func disconnect(memberID: String) async throws {
        let body = DisconnectRequest(linkedInID: memberID)
        var request = URLRequest(url: apiBaseURL.appending(path: "/api/linkedin/disconnect"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.app.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func deleteAccount(memberID: String) async throws {
        let body = DisconnectRequest(linkedInID: memberID)
        var request = URLRequest(url: apiBaseURL.appending(path: "/api/account/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.app.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func requireEphemeralSignInOnce() {
        requiresEphemeralSignIn = true
    }

    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }

    private func startFlow() async throws -> StartResponse {
        let url = apiBaseURL.appending(path: "/api/linkedin/cli/start")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder.app.decode(StartResponse.self, from: data)
    }

    @MainActor
    private func openAuthorization(_ url: URL) async throws -> URL? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL?, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: self.callbackURLScheme) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: LinkedInAuthError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            let prefersEphemeral = self.requiresEphemeralSignIn
            self.requiresEphemeralSignIn = false
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = prefersEphemeral
            self.session = session
            if !session.start() {
                continuation.resume(throwing: LinkedInAuthError.missingWindow)
            }
        }
    }

    private func completeInterceptedCallback(_ url: URL) async throws {
        guard url.host == apiBaseURL.host,
              url.path == "/api/linkedin/callback" else {
            return
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
    }

    private func pollResult(state: String) async throws -> LinkedInToken {
        for _ in 0..<45 {
            var components = URLComponents(url: apiBaseURL.appending(path: "/api/linkedin/cli/result"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "wait", value: "2")
            ]
            guard let url = components?.url else { throw LinkedInAuthError.invalidStartURL }
            let (data, response) = try await URLSession.shared.data(from: url)
            try validate(response: response, data: data)

            let envelope = try JSONDecoder.app.decode(ResultEnvelope.self, from: data)
            switch envelope.status {
            case "done":
                if let token = envelope.token {
                    return token
                }
                throw LinkedInAuthError.server("LinkedIn token is missing.")
            case "pending":
                continue
            case "error":
                throw LinkedInAuthError.server(envelope.errorDescription ?? envelope.error ?? "LinkedIn authorization failed.")
            default:
                throw LinkedInAuthError.server("Unexpected LinkedIn authorization status.")
            }
        }
        throw LinkedInAuthError.timedOut
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder.app.decode(APIErrorResponse.self, from: data) {
                throw LinkedInAuthError.server(apiError.errorDescription ?? apiError.error)
            }
            throw LinkedInAuthError.server("Request failed with status \(http.statusCode).")
        }
    }
}

struct StartResponse: Codable {
    let authURL: URL
    let state: String
    let redirectURI: URL
    let pollURL: String

    enum CodingKeys: String, CodingKey {
        case authURL = "authUrl"
        case state
        case redirectURI = "redirectUri"
        case pollURL = "pollUrl"
    }
}

struct ResultEnvelope: Codable {
    let status: String
    let token: LinkedInToken?
    let error: String?
    let errorDescription: String?
    let httpStatus: Int?
    let upstreamBody: String?

    enum CodingKeys: String, CodingKey {
        case status
        case token
        case error
        case errorDescription
        case httpStatus
        case upstreamBody
    }
}

struct APIErrorResponse: Codable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription
    }
}

private struct DisconnectRequest: Encodable {
    let linkedInID: String

    enum CodingKeys: String, CodingKey {
        case linkedInID = "linkedInId"
    }
}
