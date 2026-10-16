import Testing
@testable import Bloomary_Desktop

@MainActor
struct LinkedInSessionStoreTests {
    @Test
    func connectionStateRequiresTokenAndMemberID() {
        let tokenStore = InMemoryTokenStore()
        let store = LinkedInSessionStore(tokenStore: tokenStore)

        #expect(!store.isConnected)

        store.setToken(Self.token(memberID: "member-1"))

        #expect(store.isConnected)
        #expect(tokenStore.savedToken?.profile.memberID == "member-1")
    }

    @Test
    func disconnectClearsToken() {
        let tokenStore = InMemoryTokenStore()
        let store = LinkedInSessionStore(tokenStore: tokenStore)
        store.setToken(Self.token(memberID: "member-1"))

        store.disconnect()

        #expect(!store.isConnected)
        #expect(tokenStore.savedToken == nil)
    }

    private static func token(memberID: String) -> LinkedInToken {
        LinkedInToken(
            accessToken: "access-token",
            idToken: nil,
            tokenType: "Bearer",
            scope: nil,
            expiresIn: nil,
            profile: LinkedInProfile(
                memberID: memberID,
                name: "Katerina Bletsch",
                pictureURL: nil,
                email: nil,
                headline: nil,
                localizedHeadline: nil
            ),
            connectedAt: .now
        )
    }
}

private final class InMemoryTokenStore: LinkedInTokenStore {
    var savedToken: LinkedInToken?

    func load() -> LinkedInToken? {
        savedToken
    }

    func save(_ token: LinkedInToken) {
        savedToken = token
    }

    func clear() {
        savedToken = nil
    }
}
