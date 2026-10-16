import Combine
import Foundation

/// Auth surface the account presentation layer depends on. Keeps
/// `AccountViewModel` testable without `ASWebAuthenticationSession`/network.
protocol AccountAuthServicing {
    @MainActor func signIn() async throws -> LinkedInToken
    func disconnect(memberID: String) async throws
    func deleteAccount(memberID: String) async throws
    func requireEphemeralSignInOnce()
}

extension LinkedInAuthService: AccountAuthServicing {}

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var isConnecting = false
    @Published private(set) var isLoggingOut = false
    @Published private(set) var isDeletingAccount = false

    private let authService: AccountAuthServicing
    private let sessionStore: LinkedInSessionStore
    private let draftStore: DraftStore
    private let aiSettingsStore: AISettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(
        authService: AccountAuthServicing,
        sessionStore: LinkedInSessionStore,
        draftStore: DraftStore,
        aiSettingsStore: AISettingsStore
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
        self.draftStore = draftStore
        self.aiSettingsStore = aiSettingsStore
        sessionStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isConnected: Bool {
        sessionStore.isConnected
    }

    var profile: LinkedInProfile? {
        sessionStore.token?.profile
    }

    var connectedAt: Date? {
        sessionStore.token?.connectedAt
    }

    var statusMessage: String? {
        sessionStore.statusMessage
    }

    func connect() {
        AppTelemetry.track(.linkedInConnectStarted)
        isConnecting = true
        Task {
            do {
                let token = try await authService.signIn()
                sessionStore.setToken(token)
                isConnecting = false
                AppTelemetry.track(.linkedInConnected)
            } catch {
                sessionStore.statusMessage = error.localizedDescription
                isConnecting = false
            }
        }
    }

    func logOut() {
        let memberID = sessionStore.token?.profile.memberID
        isLoggingOut = true
        Task {
            do {
                if let memberID {
                    try await authService.disconnect(memberID: memberID)
                }
                sessionStore.disconnect()
                sessionStore.statusMessage = "Logged out."
                isLoggingOut = false
            } catch {
                sessionStore.statusMessage = error.localizedDescription
                isLoggingOut = false
            }
        }
    }

    func deleteAccount(onSuccess: @escaping () -> Void = {}) {
        let memberID = sessionStore.token?.profile.memberID
        isDeletingAccount = true
        Task {
            do {
                if let memberID {
                    try await authService.deleteAccount(memberID: memberID)
                }
                draftStore.deleteAccountData(ownerID: memberID)
                sessionStore.deleteAccountData()
                aiSettingsStore.clearAccountDeletionData()
                authService.requireEphemeralSignInOnce()
                sessionStore.statusMessage = "Account deleted."
                isDeletingAccount = false
                AppTelemetry.track(.accountDeleted)
                onSuccess()
            } catch {
                sessionStore.statusMessage = error.localizedDescription
                isDeletingAccount = false
            }
        }
    }
}
