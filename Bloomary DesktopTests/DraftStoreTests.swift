import Foundation
import Testing
@testable import Bloomary_Desktop

@MainActor
struct DraftStoreTests {
    @Test
    func savingEmptyDraftDoesNotPersist() {
        let repository = InMemoryDraftRepository()
        var trackedEvents: [AppTelemetryEvent] = []
        let store = DraftStore(draftRepository: repository, telemetry: { event, _ in
            trackedEvents.append(event)
        })

        store.editorText = "   "
        store.saveCurrentDraft()

        #expect(store.drafts.isEmpty)
        #expect(repository.savedDrafts(ownerID: nil).isEmpty)
        #expect(store.statusMessage == "Draft is empty")
        #expect(trackedEvents.isEmpty)
    }

    @Test
    func savingDraftTrimsBodyAndPersists() {
        let repository = InMemoryDraftRepository()
        var trackedEvents: [AppTelemetryEvent] = []
        let store = DraftStore(draftRepository: repository, telemetry: { event, _ in
            trackedEvents.append(event)
        })

        store.editorText = "  Hello LinkedIn  "
        store.saveCurrentDraft()

        #expect(store.drafts.map(\.body) == ["Hello LinkedIn"])
        #expect(repository.savedDrafts(ownerID: nil).map(\.body) == ["Hello LinkedIn"])
        #expect(store.statusMessage == "Draft saved")
        #expect(trackedEvents == [.draftSaved])
    }

    @Test
    func entitlementConfiguresFreemiumDraftAccess() {
        let store = DraftStore(draftRepository: InMemoryDraftRepository())

        store.setEntitlement(
            Entitlement(
                isPro: false,
                subscriptionSource: nil,
                draftLimit: 5,
                postCount: 1,
                accessUntil: nil
            )
        )

        #expect(!store.isPro)
        #expect(store.maxDrafts == 5)
    }

    @Test
    func savingOpenedDraftUpdatesExistingDraft() {
        let draft = Draft(body: "Old body")
        let repository = InMemoryDraftRepository()
        repository.setDrafts([draft], ownerID: nil)
        let store = DraftStore(draftRepository: repository)

        store.openDraft(draft)
        store.editorText = "Updated body"
        store.saveCurrentDraft()

        #expect(store.drafts.count == 1)
        #expect(store.drafts.first?.id == draft.id)
        #expect(store.drafts.first?.body == "Updated body")
        #expect(repository.savedDrafts(ownerID: nil).count == 1)
        #expect(repository.savedDrafts(ownerID: nil).first?.id == draft.id)
    }

    @Test
    func clearingOpenedDraftSavesDraftAndEmptiesEditor() {
        let draft = Draft(body: "Old body")
        let repository = InMemoryDraftRepository()
        repository.setDrafts([draft], ownerID: nil)
        let store = DraftStore(draftRepository: repository)

        store.openDraft(draft)
        store.editorText = "Edited before clear"
        store.saveOpenedDraftAndClearEditor()

        #expect(store.editorText.isEmpty)
        #expect(store.statusMessage == nil)
        #expect(store.drafts.count == 1)
        #expect(store.drafts.first?.id == draft.id)
        #expect(store.drafts.first?.body == "Edited before clear")
        #expect(repository.savedDrafts(ownerID: nil).first?.body == "Edited before clear")
    }

    @Test
    func clearingNewPostDoesNotCreateDraft() {
        let repository = InMemoryDraftRepository()
        let store = DraftStore(draftRepository: repository)

        store.editorText = "New unsaved post"
        store.saveOpenedDraftAndClearEditor()

        #expect(store.editorText.isEmpty)
        #expect(store.statusMessage == nil)
        #expect(store.drafts.isEmpty)
        #expect(repository.savedDrafts(ownerID: nil).isEmpty)
    }

    @Test
    func startingNewPostClearsOpenedDraft() {
        let draft = Draft(body: "Old body")
        let repository = InMemoryDraftRepository()
        repository.setDrafts([draft], ownerID: nil)
        let store = DraftStore(draftRepository: repository)

        store.openDraft(draft)
        store.editorText = "Unsaved edit"
        store.startNewPost()
        store.editorText = "New post"
        store.saveCurrentDraft()

        #expect(store.drafts.count == 2)
        #expect(store.drafts.first?.body == "New post")
        #expect(store.drafts.last?.body == "Old body")
    }

    @Test
    func deletingPostedDraftIfSavedRemovesOpenedDraft() {
        let openedDraft = Draft(body: "Opened body")
        let otherDraft = Draft(body: "Other body")
        let repository = InMemoryDraftRepository()
        repository.setDrafts([openedDraft, otherDraft], ownerID: nil)
        let store = DraftStore(draftRepository: repository)

        store.openDraft(openedDraft)
        store.editorText = "Edited body"
        store.deletePostedDraftIfSaved()

        #expect(store.editorText == "Edited body")
        #expect(store.drafts.map(\.id) == [otherDraft.id])
        #expect(repository.savedDrafts(ownerID: nil).map(\.id) == [otherDraft.id])
    }

    @Test
    func switchingOwnerLoadsOnlyThatOwnersDrafts() {
        let repository = InMemoryDraftRepository()
        repository.setDrafts([Draft(body: "User A draft")], ownerID: "user-a")
        repository.setDrafts([Draft(body: "User B draft")], ownerID: "user-b")
        let store = DraftStore(draftRepository: repository)

        store.setOwnerID("user-a")
        #expect(store.drafts.map(\.body) == ["User A draft"])

        store.setOwnerID("user-b")
        #expect(store.drafts.map(\.body) == ["User B draft"])
    }

    @Test
    func settingSessionPullsNewerRemoteDrafts() async throws {
        let local = Draft(id: UUID(), body: "Local old", updatedAt: Date(timeIntervalSince1970: 10))
        let remote = Draft(id: local.id, body: "Remote newer", updatedAt: Date(timeIntervalSince1970: 20))
        let repository = InMemoryDraftRepository()
        repository.setDrafts([local], ownerID: "user-a")
        let syncService = InMemoryDraftSyncService(remoteDrafts: [remote])
        let store = DraftStore(draftRepository: repository, syncService: syncService)

        store.setSession(linkedInToken(memberID: "user-a"))
        try await waitFor { store.drafts.first?.body == "Remote newer" }

        #expect(repository.savedDrafts(ownerID: "user-a").first?.body == "Remote newer")
    }

    @Test
    func savingDraftPushesRemoteCopy() async throws {
        let repository = InMemoryDraftRepository()
        let syncService = InMemoryDraftSyncService()
        let store = DraftStore(draftRepository: repository, syncService: syncService)

        store.setSession(linkedInToken(memberID: "user-a"))
        store.editorText = "Synced body"
        store.saveCurrentDraft()
        try await waitFor { await syncService.upsertedBodies() == ["Synced body"] }

        #expect(await syncService.upsertedBodies() == ["Synced body"])
        #expect(repository.savedSyncMutations(ownerID: "user-a").isEmpty)
    }

    @Test
    func deletingDraftDeletesRemoteCopy() async throws {
        let draft = Draft(body: "Delete me")
        let repository = InMemoryDraftRepository()
        repository.setDrafts([draft], ownerID: "user-a")
        let syncService = InMemoryDraftSyncService()
        let store = DraftStore(draftRepository: repository, syncService: syncService)

        store.setSession(linkedInToken(memberID: "user-a"))
        store.deleteDraft(draft)
        try await waitFor { await syncService.deletedIDs() == [draft.id] }

        #expect(await syncService.deletedIDs() == [draft.id])
        #expect(repository.savedSyncMutations(ownerID: "user-a").isEmpty)
    }

    @Test
    func failedSyncKeepsMutationForLaterRetry() async throws {
        let repository = InMemoryDraftRepository()
        let syncService = InMemoryDraftSyncService(error: DraftSyncTestError.offline)
        let store = DraftStore(draftRepository: repository, syncService: syncService)

        store.setSession(linkedInToken(memberID: "user-a"))
        store.editorText = "Queued body"
        store.saveCurrentDraft()
        try await waitFor { repository.savedSyncMutations(ownerID: "user-a").first?.lastError != nil }

        #expect(store.syncStatus == .failed)
        #expect(repository.savedSyncMutations(ownerID: "user-a").map(\.operation) == [.upsert])
    }

    @Test
    func entitlementFailureDropsMutationAndKeepsLocalDrafts() async throws {
        let repository = InMemoryDraftRepository()
        let syncService = InMemoryDraftSyncService(error: SyncedDraftsError.entitlementRequired)
        let store = DraftStore(draftRepository: repository, syncService: syncService)

        store.setSession(linkedInToken(memberID: "user-a"))
        store.editorText = "Local only body"
        store.saveCurrentDraft()
        try await waitFor { repository.savedSyncMutations(ownerID: "user-a").isEmpty }

        #expect(store.syncStatus == .localOnly)
        // Local data is never lost on entitlement failure.
        #expect(store.drafts.map(\.body) == ["Local only body"])
        #expect(repository.savedDrafts(ownerID: "user-a").map(\.body) == ["Local only body"])
    }

    @Test
    func parkedMutationIsReArmedOnNextLaunch() async throws {
        let repository = InMemoryDraftRepository()
        let syncService = InMemoryDraftSyncService(error: DraftSyncTestError.offline)
        let store = DraftStore(draftRepository: repository, syncService: syncService)

        // Simulate a mutation parked after the retry window in a previous session.
        var parked = DraftSyncMutation(ownerID: "user-a", operation: .delete, draftID: UUID())
        parked.attemptCount = DraftSyncPolicy.maxRetryAttempts
        parked.nextAttemptAt = .distantFuture
        repository.saveSyncMutations([parked], ownerID: "user-a")

        store.setSession(linkedInToken(memberID: "user-a"))

        try await waitFor {
            guard let mutation = repository.savedSyncMutations(ownerID: "user-a").first else { return false }
            return mutation.attemptCount > 0 && !DraftSyncPolicy.isParked(mutation)
        }
        let mutations = repository.savedSyncMutations(ownerID: "user-a")
        #expect(mutations.count == 1)
        #expect(!DraftSyncPolicy.isParked(mutations[0]))
        #expect(store.syncStatus == .failed)
    }

    @Test
    func deletingAccountDataRemovesSignedInAndSignedOutDrafts() {
        let repository = InMemoryDraftRepository()
        repository.setDrafts([Draft(body: "Signed-in draft")], ownerID: "user-a")
        repository.setDrafts([Draft(body: "Signed-out draft")], ownerID: nil)
        let store = DraftStore(draftRepository: repository)

        store.setOwnerID("user-a")
        store.openDraft(store.drafts[0])
        store.editorText = "Unsaved account text"
        store.deleteAccountData(ownerID: "user-a")

        #expect(store.drafts.isEmpty)
        #expect(store.editorText == "Write a LinkedIn post...")
        #expect(repository.savedDrafts(ownerID: "user-a").isEmpty)
        #expect(repository.savedDrafts(ownerID: nil).isEmpty)
    }

    @Test
    func successfulSyncEmitsAttemptAndQueueLengthTelemetry() async throws {
        let repository = InMemoryDraftRepository()
        let syncService = InMemoryDraftSyncService()
        var tracked: [(AppTelemetryEvent, [String: String])] = []
        let store = DraftStore(draftRepository: repository, syncService: syncService) { event, parameters in
            tracked.append((event, parameters))
        }

        store.setSession(linkedInToken(memberID: "user-a"))
        store.editorText = "Telemetry body"
        store.saveCurrentDraft()

        try await waitFor { tracked.contains { $0.0 == .syncAttemptSucceeded } }
        #expect(tracked.contains { $0.0 == .syncAttemptSucceeded && $0.1["operation"] == "upsert" })
        #expect(tracked.contains { $0.0 == .syncQueueLength })
        #expect(tracked.contains { $0.0 == .draftSaved })
        // Telemetry carries counts and categories only — never draft content.
        #expect(tracked.allSatisfy { !$0.1.values.contains("Telemetry body") })
    }

    @Test
    func failedSyncEmitsAttemptFailedTelemetry() async throws {
        let repository = InMemoryDraftRepository()
        let syncService = InMemoryDraftSyncService(error: DraftSyncTestError.offline)
        var tracked: [(AppTelemetryEvent, [String: String])] = []
        let store = DraftStore(draftRepository: repository, syncService: syncService) { event, parameters in
            tracked.append((event, parameters))
        }

        store.setSession(linkedInToken(memberID: "user-a"))
        store.editorText = "Failing body"
        store.saveCurrentDraft()

        try await waitFor { tracked.contains { $0.0 == .syncAttemptFailed } }
        #expect(store.syncStatus == .failed)
    }

    @Test
    func entitlementFailureEmitsEntitlementBlockedTelemetry() async throws {
        let repository = InMemoryDraftRepository()
        let syncService = InMemoryDraftSyncService(error: SyncedDraftsError.entitlementRequired)
        var tracked: [(AppTelemetryEvent, [String: String])] = []
        let store = DraftStore(draftRepository: repository, syncService: syncService) { event, parameters in
            tracked.append((event, parameters))
        }

        store.setSession(linkedInToken(memberID: "user-a"))
        store.editorText = "Local only body"
        store.saveCurrentDraft()

        try await waitFor { tracked.contains { $0.0 == .syncAttemptEntitlementBlocked } }
        #expect(store.syncStatus == .localOnly)
        #expect(repository.savedDrafts(ownerID: "user-a").map(\.body) == ["Local only body"])
    }
}

private func linkedInToken(memberID: String) -> LinkedInToken {
    LinkedInToken(
        accessToken: "access-token",
        idToken: nil,
        tokenType: nil,
        scope: nil,
        expiresIn: nil,
        profile: LinkedInProfile(
            memberID: memberID,
            name: "Test User",
            pictureURL: nil,
            email: nil,
            headline: nil,
            localizedHeadline: nil
        ),
        connectedAt: Date(timeIntervalSince1970: 0)
    )
}

private func waitFor(
    timeout: Duration = .seconds(1),
    condition: @escaping () async -> Bool
) async throws {
    let start = ContinuousClock.now
    while !Task.isCancelled {
        if await condition() { return }
        if start.duration(to: ContinuousClock.now) > timeout { return }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private final class InMemoryDraftRepository: DraftRepository {
    private var draftsByOwnerID: [String: [Draft]] = [:]
    private var mutationsByOwnerID: [String: [DraftSyncMutation]] = [:]

    func loadDrafts(ownerID: String?) -> [Draft] {
        draftsByOwnerID[key(ownerID)] ?? []
    }

    func saveDrafts(_ drafts: [Draft], ownerID: String?) {
        draftsByOwnerID[key(ownerID)] = drafts
    }

    func deleteDrafts(ownerID: String?) {
        draftsByOwnerID.removeValue(forKey: key(ownerID))
    }

    func loadSyncMutations(ownerID: String) -> [DraftSyncMutation] {
        mutationsByOwnerID[ownerID] ?? []
    }

    func saveSyncMutations(_ mutations: [DraftSyncMutation], ownerID: String) {
        mutationsByOwnerID[ownerID] = mutations
    }

    func deleteSyncMutations(ownerID: String) {
        mutationsByOwnerID.removeValue(forKey: ownerID)
    }

    func setDrafts(_ drafts: [Draft], ownerID: String?) {
        draftsByOwnerID[key(ownerID)] = drafts
    }

    func savedDrafts(ownerID: String?) -> [Draft] {
        draftsByOwnerID[key(ownerID)] ?? []
    }

    func savedSyncMutations(ownerID: String) -> [DraftSyncMutation] {
        mutationsByOwnerID[ownerID] ?? []
    }

    private func key(_ ownerID: String?) -> String {
        ownerID ?? "signed-out"
    }
}

private actor InMemoryDraftSyncService: DraftSyncing {
    private var remoteDrafts: [Draft]
    private var upserts: [Draft] = []
    private var deletes: [Draft.ID] = []
    private let error: Error?

    init(remoteDrafts: [Draft] = [], error: Error? = nil) {
        self.remoteDrafts = remoteDrafts
        self.error = error
    }

    func listDrafts(memberID: String, accessToken: String) async throws -> [Draft] {
        if let error { throw error }
        return remoteDrafts
    }

    func upsertDraft(_ draft: Draft, memberID: String, accessToken: String) async throws -> Draft {
        if let error { throw error }
        upserts.append(draft)
        remoteDrafts.removeAll { $0.id == draft.id }
        remoteDrafts.append(draft)
        return draft
    }

    func deleteDraft(id: Draft.ID, memberID: String, accessToken: String) async throws {
        if let error { throw error }
        deletes.append(id)
        remoteDrafts.removeAll { $0.id == id }
    }

    func upsertedBodies() -> [String] {
        upserts.map(\.body)
    }

    func deletedIDs() -> [Draft.ID] {
        deletes
    }
}

private enum DraftSyncTestError: LocalizedError {
    case offline

    var errorDescription: String? { "offline" }
}
