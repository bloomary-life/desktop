import Combine
import Foundation
import AppKit

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var isPosting = false
    @Published private(set) var isNaturalizing = false
    @Published var showsSchedulePicker = false
    @Published private(set) var isScheduling = false
    @Published var scheduleMessage: String?

    /// Called after a successful publish; the view wires navigation/side effects.
    var onPostSucceeded: (() -> Void)?

    private let store: DraftStore
    private let sessionStore: LinkedInSessionStore
    private let authService: LinkedInAuthService
    private let postService: LinkedInPostService
    private let naturalizeService: NaturalizeService
    private let aiSettingsStore: AISettingsStore
    private let scheduleMaxAheadDays: Int
    private var cancellables = Set<AnyCancellable>()

    init(
        store: DraftStore,
        sessionStore: LinkedInSessionStore,
        authService: LinkedInAuthService,
        postService: LinkedInPostService,
        naturalizeService: NaturalizeService,
        aiSettingsStore: AISettingsStore,
        scheduleMaxAheadDays: Int = AppConfiguration.Scheduling.default.maxAheadDays
    ) {
        self.store = store
        self.sessionStore = sessionStore
        self.authService = authService
        self.postService = postService
        self.naturalizeService = naturalizeService
        self.aiSettingsStore = aiSettingsStore
        self.scheduleMaxAheadDays = scheduleMaxAheadDays
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sessionStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var editorText: String {
        get { store.editorText }
        set { store.editorText = newValue }
    }

    var syncStatus: DraftSyncStatus {
        store.syncStatus
    }

    var isPro: Bool {
        store.isPro
    }

    var isNewDraftBlockedByLimit: Bool {
        store.isDraftLimitReached && !store.isEditingExistingDraft
    }

    var draftLimitWarning: String? {
        guard isNewDraftBlockedByLimit else { return nil }
        let action = store.isPro ? "Delete a draft to create a new one." : "Delete a draft or upgrade to Pro."
        return "You have \(store.drafts.count) drafts (\(store.isPro ? "Pro" : "free") limit: \(store.maxDrafts)). \(action)"
    }

    var statusMessage: String? {
        store.statusMessage
    }

    var profile: LinkedInProfile? {
        sessionStore.token?.profile
    }

    var hasEditorText: Bool {
        !DraftPolicy.trimmedBody(store.editorText).isEmpty
    }

    var previewText: String {
        DraftPolicy.trimmedBody(store.editorText).isEmpty ? "Preview appears here." : store.editorText
    }

    var attachedImage: NSImage? {
        store.editorImageData.flatMap(NSImage.init(data:))
    }

    var maximumScheduleDate: Date {
        Date().addingTimeInterval(TimeInterval(scheduleMaxAheadDays * 24 * 60 * 60))
    }

    var scheduleLimitText: String {
        "Posts can be scheduled up to \(scheduleMaxAheadDays) days ahead."
    }

    func setAttachedImage(data: Data, filename: String, mimeType: String) {
        guard data.count <= 5 * 1_024 * 1_024 else {
            store.statusMessage = "Image must be 5 MB or smaller."
            return
        }
        guard mimeType.hasPrefix("image/"), NSImage(data: data) != nil else {
            store.statusMessage = "Choose a valid image."
            return
        }
        store.editorImageData = data
        store.editorImageFilename = filename
        store.editorImageMimeType = mimeType
        store.statusMessage = "Image attached."
    }

    func removeAttachedImage() {
        store.editorImageData = nil
        store.editorImageFilename = nil
        store.editorImageMimeType = nil
    }

    func save() {
        store.saveCurrentDraft()
    }

    func clearEditor() {
        store.saveOpenedDraftAndClearEditor()
    }

    func publish() {
        AppTelemetry.track(.postStarted)
        isPosting = true
        Task {
            let signpost = PerformanceSignposts.beginAsyncInterval("PublishAttempt")
            await performPublish()
            PerformanceSignposts.endAsyncInterval("PublishAttempt", signpost)
        }
    }

    func schedule(at date: Date) {
        guard date >= Date().addingTimeInterval(60), date <= maximumScheduleDate else {
            scheduleMessage = "Choose a time between 1 minute and \(scheduleMaxAheadDays) days from now."
            return
        }
        isScheduling = true
        scheduleMessage = nil
        Task {
            do {
                let draft = try await store.syncCurrentDraftForScheduling()
                _ = try await postService.schedule(draftID: draft.id, at: date, credential: sessionStore.postCredential)
                scheduleMessage = "Scheduled for \(date.formatted(date: .abbreviated, time: .shortened))."
                store.statusMessage = scheduleMessage
                showsSchedulePicker = false
            } catch {
                scheduleMessage = error.localizedDescription
            }
            isScheduling = false
        }
    }

    func naturalizeEnglish() {
        isNaturalizing = true
        store.statusMessage = "Naturalizing English..."
        Task {
            await performNaturalize()
        }
    }

    private func performNaturalize() async {
        do {
            let text = try await naturalizeService.naturalize(text: store.editorText, settings: aiSettingsStore.current)
            store.editorText = text
            store.statusMessage = "Naturalized English."
        } catch {
            store.statusMessage = error.localizedDescription
        }
        isNaturalizing = false
    }

    private func performPublish() async {
        do {
            try await connectIfNeeded()
            let attachment = store.editorImageData.map {
                LinkedInPostAttachment(data: $0, filename: store.editorImageFilename ?? "bloomary-linkedin-image.jpg", mimeType: store.editorImageMimeType ?? "image/jpeg")
            }
            try await postService.publish(text: store.editorText, credential: sessionStore.postCredential, attachment: attachment)
            store.deletePostedDraftIfSaved()
            finishPost(message: "Posted to LinkedIn", event: .postSucceeded)
            removeAttachedImage()
            onPostSucceeded?()
        } catch {
            finishPost(message: error.localizedDescription, event: .postFailed)
        }
    }

    private func connectIfNeeded() async throws {
        guard !sessionStore.isConnected else { return }
        AppTelemetry.track(.linkedInConnectStarted)
        let token = try await authService.signIn()
        sessionStore.setToken(token)
        AppTelemetry.track(.linkedInConnected)
    }

    private func finishPost(message: String, event: AppTelemetryEvent) {
        store.statusMessage = message
        isPosting = false
        AppTelemetry.track(event)
    }
}
