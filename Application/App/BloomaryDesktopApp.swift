import SwiftUI

@main
struct BloomaryDesktopApp: App {
    private let container: AppContainer
    @StateObject private var draftStore: DraftStore
    @StateObject private var linkedInSessionStore: LinkedInSessionStore
    @StateObject private var aiSettingsStore: AISettingsStore

    init() {
        CrashReporter.start()
        let configuration = AppConfiguration.load()
        AppTelemetry.start(configuration: configuration.observability)
        AppTelemetry.track(.appOpened)
        let container = AppContainer(configuration: configuration)
        self.container = container
        _draftStore = StateObject(wrappedValue: container.draftStore)
        _linkedInSessionStore = StateObject(wrappedValue: container.linkedInSessionStore)
        _aiSettingsStore = StateObject(wrappedValue: container.aiSettingsStore)
    }

    var body: some Scene {
        WindowGroup {
            MainSplitView(
                editorViewModel: container.editorViewModel,
                draftsViewModel: container.draftsViewModel,
                accountViewModel: container.accountViewModel,
                aiSettingsStore: aiSettingsStore,
                feedbackService: container.feedbackService,
                entitlementService: container.entitlementService,
                paddleCheckoutService: container.paddleCheckoutService,
                paddleConfiguration: container.configuration.paddle
            )
                .environmentObject(draftStore)
                .environmentObject(linkedInSessionStore)
                .frame(minWidth: 720, minHeight: 500)
                .tint(AppStyle.lime)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 900, height: 650)
    }
}
