import Foundation
import TelemetryDeck

enum AppTelemetryEvent: String {
    case appOpened = "app_opened"
    case insightOpened = "insight_opened"
    case editorStarted = "editor_started"
    case draftSaved = "draft_saved"
    case linkedInConnectStarted = "linkedin_connect_started"
    case linkedInConnected = "linkedin_connected"
    case accountDeleted = "account_deleted"
    case postStarted = "post_started"
    case postSucceeded = "post_succeeded"
    case postFailed = "post_failed"
    case syncQueueLength = "sync_queue_length"
    case syncAttemptSucceeded = "sync_attempt_succeeded"
    case syncAttemptFailed = "sync_attempt_failed"
    case syncAttemptEntitlementBlocked = "sync_attempt_entitlement_blocked"
    case feedbackOpened = "feedback_opened"
    case feedbackSent = "feedback_sent"
}

enum AppTelemetry {
    private static var isConfigured = false

    static func start(configuration: AppConfiguration.Observability) {
        let appID = configuration.telemetryDeckAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty, !CrashReporter.isRunningTests else { return }

        let namespace = configuration.telemetryDeckNamespace.trimmingCharacters(in: .whitespacesAndNewlines)
        let telemetryConfig = TelemetryDeck.Config(appID: appID, namespace: namespace.isEmpty ? nil : namespace)
        telemetryConfig.defaultUser = UUID().uuidString
        telemetryConfig.sendNewSessionBeganSignal = false
        telemetryConfig.sessionStatsEnabled = false
        TelemetryDeck.initialize(config: telemetryConfig)
        isConfigured = true
    }

    static func track(_ event: AppTelemetryEvent, parameters: [String: String] = [:]) {
        guard isConfigured else { return }
        // Only numeric counters and fixed category labels may be passed here —
        // never post bodies, tokens, feedback text, or attachment content.
        TelemetryDeck.signal(event.rawValue, parameters: parameters)
    }
}
