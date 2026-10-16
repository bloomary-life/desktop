import Foundation

@MainActor
final class AppContainer {
    static let shared = AppContainer(configuration: .load())

    let draftStore: DraftStore
    let linkedInSessionStore: LinkedInSessionStore
    let authService: LinkedInAuthService
    let postService: LinkedInPostService
    let naturalizeService: NaturalizeService
    let entitlementService: EntitlementService
    let paddleCheckoutService: PaddleCheckoutService
    let feedbackService: FeedbackService
    let draftRepository: DraftRepository
    let tokenStore: LinkedInTokenStore
    let aiSettingsStore: AISettingsStore
    let configuration: AppConfiguration
    let editorViewModel: EditorViewModel
    let draftsViewModel: DraftsViewModel
    let accountViewModel: AccountViewModel

    init(configuration: AppConfiguration) {
        let draftRepository = UserDefaultsDraftRepository(key: configuration.storage.draftsKey)
        let tokenStore = AuthTokenStore(key: configuration.storage.linkedInTokenKey)

        self.configuration = configuration
        self.draftRepository = draftRepository
        self.tokenStore = tokenStore
        self.authService = LinkedInAuthService(
            apiBaseURL: configuration.api.baseURL,
            callbackURLScheme: configuration.linkedIn.callbackURLScheme,
            tokenStore: tokenStore
        )
        self.postService = LinkedInPostService(apiBaseURL: configuration.api.baseURL)
        self.naturalizeService = NaturalizeService()
        self.entitlementService = EntitlementService(apiBaseURL: configuration.api.baseURL)
        self.paddleCheckoutService = PaddleCheckoutService(apiBaseURL: configuration.api.baseURL)
        self.feedbackService = FeedbackService(apiBaseURL: configuration.api.baseURL)
        self.draftStore = DraftStore(
            draftRepository: draftRepository,
            syncService: SyncedDraftsService(apiBaseURL: configuration.api.baseURL),
            telemetry: AppTelemetry.track
        )
        self.linkedInSessionStore = LinkedInSessionStore(tokenStore: tokenStore)
        self.aiSettingsStore = AISettingsStore()
        self.draftsViewModel = DraftsViewModel(store: draftStore)
        self.editorViewModel = EditorViewModel(
            store: draftStore,
            sessionStore: linkedInSessionStore,
            authService: authService,
            postService: postService,
            naturalizeService: naturalizeService,
            aiSettingsStore: aiSettingsStore,
            scheduleMaxAheadDays: configuration.scheduling.maxAheadDays
        )
        self.accountViewModel = AccountViewModel(
            authService: authService,
            sessionStore: linkedInSessionStore,
            draftStore: draftStore,
            aiSettingsStore: aiSettingsStore
        )
    }
}
