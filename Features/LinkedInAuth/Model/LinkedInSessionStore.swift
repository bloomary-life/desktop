import Foundation

@MainActor
final class LinkedInSessionStore: ObservableObject {
    @Published private(set) var token: LinkedInToken?
    @Published var statusMessage: String?

    private let tokenStore: LinkedInTokenStore

    init(tokenStore: LinkedInTokenStore) {
        self.tokenStore = tokenStore
        self.token = tokenStore.load()
    }

    var isConnected: Bool {
        token?.accessToken.isEmpty == false && token?.profile.memberID.isEmpty == false
    }

    var postCredential: LinkedInPostCredential? {
        guard let token else { return nil }
        return LinkedInPostCredential(accessToken: token.accessToken, memberID: token.profile.memberID)
    }

    func setToken(_ token: LinkedInToken) {
        self.token = token
        statusMessage = nil
        tokenStore.save(token)
    }

    func disconnect() {
        token = nil
        tokenStore.clear()
    }

    func deleteAccountData() {
        token = nil
        tokenStore.clearAccountDeletionData()
    }
}
