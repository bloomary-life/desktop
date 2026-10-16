import Foundation

enum DraftSyncStatus: Equatable {
    case localOnly
    case pending
    case synced
    case failed

    var message: String {
        switch self {
        case .localOnly:
            return "Saved locally"
        case .pending:
            return "Sync pending"
        case .synced:
            return "Synced"
        case .failed:
            return "Sync failed, will retry"
        }
    }
}

@MainActor
final class DraftStore: ObservableObject {
    @Published var editorText: String
    @Published private(set) var drafts: [Draft]
    @Published var statusMessage: String?
    @Published private(set) var syncStatus: DraftSyncStatus = .localOnly
    @Published private(set) var isPro = false
    @Published private(set) var maxDrafts = 5
    @Published var editorImageData: Data?
    @Published var editorImageFilename: String?
    @Published var editorImageMimeType: String?
    private var editingDraftID: Draft.ID?
    private var ownerID: String?
    private var isDrainingSyncQueue = false
    private var localRevision = 0
    private var lastSuccessfulSyncAt: Date?
    var isDraftLimitReached: Bool { drafts.count >= maxDrafts }
    var isEditingExistingDraft: Bool { editingDraftID != nil }

    private let draftRepository: DraftRepository
    private let syncService: DraftSyncing?
    private let telemetry: (AppTelemetryEvent, [String: String]) -> Void
    private var accessToken: String?

    init(
        draftRepository: DraftRepository,
        syncService: DraftSyncing? = nil,
        telemetry: @escaping (AppTelemetryEvent, [String: String]) -> Void = { _, _ in }
    ) {
        self.draftRepository = draftRepository
        self.syncService = syncService
        self.telemetry = telemetry
        self.editorText = "Write a LinkedIn post..."
        let snapshot = PerformanceSignposts.draftCacheLoad { draftRepository.loadSnapshot(ownerID: nil) }
        self.drafts = snapshot.drafts
        self.lastSuccessfulSyncAt = snapshot.lastSuccessfulSyncAt
    }

    func setSession(_ token: LinkedInToken?) {
        guard ownerID != token?.profile.memberID || accessToken != token?.accessToken else { return }
        ownerID = token?.profile.memberID
        accessToken = token?.accessToken
        localRevision += 1
        let snapshot = PerformanceSignposts.draftCacheLoad { draftRepository.loadSnapshot(ownerID: ownerID) }
        drafts = snapshot.drafts
        lastSuccessfulSyncAt = snapshot.lastSuccessfulSyncAt
        startNewPost()
        rearmParkedSyncMutations()
        drainSyncQueue(thenFetchRemote: true)
    }

    func setOwnerID(_ ownerID: String?) {
        guard self.ownerID != ownerID else { return }
        self.ownerID = ownerID
        accessToken = nil
        localRevision += 1
        let snapshot = PerformanceSignposts.draftCacheLoad { draftRepository.loadSnapshot(ownerID: ownerID) }
        drafts = snapshot.drafts
        lastSuccessfulSyncAt = snapshot.lastSuccessfulSyncAt
        startNewPost()
        rearmParkedSyncMutations()
        syncStatus = ownerID == nil ? .localOnly : .pending
    }

    private func rearmParkedSyncMutations() {
        guard let ownerID else { return }
        let queue = draftRepository.loadSyncMutations(ownerID: ownerID)
        let rearmed = DraftSyncPolicy.resetParked(in: queue)
        if rearmed != queue {
            draftRepository.saveSyncMutations(rearmed, ownerID: ownerID)
        }
    }

    func startNewPost() {
        editorText = "Write a LinkedIn post..."
        editorImageData = nil
        editorImageFilename = nil
        editorImageMimeType = nil
        editingDraftID = nil
        statusMessage = nil
    }

    func saveCurrentDraft() {
        let body = DraftPolicy.trimmedBody(editorText)
        guard !body.isEmpty || editorImageData != nil else {
            statusMessage = "Draft is empty"
            return
        }

        let result = PerformanceSignposts.measure("DraftSave") {
            DraftPolicy.save(drafts: drafts, editingDraftID: editingDraftID, body: body, maxDrafts: maxDrafts, imageData: editorImageData, imageFilename: editorImageFilename, imageMimeType: editorImageMimeType)
        }
        if result.limitReached {
            statusMessage = "Draft limit reached. Delete a draft or upgrade to Pro."
            return
        }
        drafts = result.drafts
        editingDraftID = result.editingDraftID
        guard result.changedDraft != nil else {
            statusMessage = "Draft saved"
            return
        }
        persistDrafts(ownerID: ownerID)
        localRevision += 1
        if let editingDraftID,
           let draft = drafts.first(where: { $0.id == editingDraftID }) {
            enqueueSync(.upsert, draftID: draft.id, draft: draft)
        }
        telemetry(.draftSaved, [:])
        statusMessage = "Draft saved"
    }

    func syncCurrentDraftForScheduling() async throws -> Draft {
        saveCurrentDraft()
        guard let ownerID, let accessToken, let syncService,
              let editingDraftID, let draft = drafts.first(where: { $0.id == editingDraftID }) else {
            throw SyncedDraftsError.server("Save and sync this draft before scheduling.")
        }
        let synced = try await syncService.upsertDraft(draft, memberID: ownerID, accessToken: accessToken)
        if let index = drafts.firstIndex(where: { $0.id == synced.id }) {
            drafts[index] = synced
            persistDrafts(ownerID: ownerID)
        }
        return synced
    }

    func saveOpenedDraftAndClearEditor() {
        if editingDraftID != nil {
            saveCurrentDraft()
        }
        editorText = ""
        editorImageData = nil
        editorImageFilename = nil
        editorImageMimeType = nil
        editingDraftID = nil
        statusMessage = nil
    }

    func openDraft(_ draft: Draft) {
        editorText = draft.body
        editorImageData = draft.imageData
        editorImageFilename = draft.imageFilename
        editorImageMimeType = draft.imageMimeType
        editingDraftID = draft.id
    }

    func deleteDraft(_ draft: Draft) {
        drafts = DraftPolicy.delete(drafts, id: draft.id)
        if editingDraftID == draft.id {
            editingDraftID = nil
        }
        persistDrafts(ownerID: ownerID)
        localRevision += 1
        syncDelete(id: draft.id)
    }

    func deletePostedDraftIfSaved() {
        guard let editingDraftID else { return }
        self.editingDraftID = nil
        let remaining = DraftPolicy.delete(drafts, id: editingDraftID)
        if remaining.count != drafts.count {
            drafts = remaining
            persistDrafts(ownerID: ownerID)
            localRevision += 1
            syncDelete(id: editingDraftID)
        }
    }

    func deleteAccountData(ownerID: String?) {
        if let ownerID {
            draftRepository.deleteDrafts(ownerID: ownerID)
            draftRepository.deleteSyncMutations(ownerID: ownerID)
        }
        draftRepository.deleteDrafts(ownerID: nil)
        self.ownerID = nil
        drafts = []
        syncStatus = .localOnly
        localRevision += 1
        startNewPost()
    }

    func setEntitlement(_ entitlement: Entitlement?) {
        isPro = entitlement?.isPro ?? false
        maxDrafts = max(1, entitlement?.draftLimit ?? 5)
    }

    func canEdit(_ draft: Draft) -> Bool {
        guard !isPro else { return true }
        let editableIDs = Set(drafts
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxDrafts)
            .map(\.id))
        return editableIDs.contains(draft.id)
    }

    private func syncFromRemote() {
        guard let syncService, let accessToken, let ownerID else { return }
        guard draftRepository.loadSyncMutations(ownerID: ownerID).isEmpty else { return }
        let localDrafts = drafts
        let startedRevision = localRevision
        Task {
            guard let remoteDrafts = try? await syncService.listDrafts(memberID: ownerID, accessToken: accessToken) else { return }
            let merged = await MainActor.run {
                guard self.ownerID == ownerID, self.accessToken == accessToken, self.localRevision == startedRevision else { return [Draft]() }
                let merged = DraftSyncPolicy.merge(local: localDrafts, remote: remoteDrafts)
                drafts = merged
                lastSuccessfulSyncAt = Date()
                persistDrafts(ownerID: ownerID)
                return merged
            }
            for draft in merged {
                await MainActor.run {
                    enqueueSync(.upsert, draftID: draft.id, draft: draft)
                }
            }
            await MainActor.run {
                drainSyncQueue()
            }
        }
    }

    private func enqueueSync(_ operation: DraftSyncOperation, draftID: Draft.ID, draft: Draft? = nil) {
        guard let ownerID else {
            syncStatus = .localOnly
            return
        }
        let mutation = DraftSyncMutation(ownerID: ownerID, operation: operation, draftID: draftID, draft: draft)
        let queue = draftRepository.loadSyncMutations(ownerID: ownerID)
        let updatedQueue = DraftSyncPolicy.enqueue(mutation, into: queue)
        draftRepository.saveSyncMutations(updatedQueue, ownerID: ownerID)
        telemetry(.syncQueueLength, ["count": "\(updatedQueue.count)"])
        syncStatus = .pending
        drainSyncQueue()
    }

    private func syncDelete(id: Draft.ID) {
        enqueueSync(.delete, draftID: id)
    }

    private func persistDrafts(ownerID: String?) {
        draftRepository.saveSnapshot(
            DraftSnapshot(drafts: drafts, ownerID: ownerID, lastSuccessfulSyncAt: lastSuccessfulSyncAt),
            ownerID: ownerID
        )
    }

    private func drainSyncQueue(thenFetchRemote: Bool = false) {
        guard !isDrainingSyncQueue else { return }
        guard let syncService, let accessToken, let ownerID else {
            syncStatus = ownerID == nil ? .localOnly : .pending
            return
        }
        var queue = draftRepository.loadSyncMutations(ownerID: ownerID)
        guard !queue.isEmpty else {
            syncStatus = .synced
            if thenFetchRemote { syncFromRemote() }
            return
        }
        let due = DraftSyncPolicy.dueMutations(from: queue)
        guard !due.isEmpty else {
            syncStatus = .pending
            return
        }
        isDrainingSyncQueue = true
        Task {
            var didHitEntitlement = false
            for mutation in due {
                guard self.ownerID == ownerID, self.accessToken == accessToken else { break }
                do {
                    switch mutation.operation {
                    case .upsert:
                        guard let draft = mutation.draft else { continue }
                        let remoteDraft = try await syncService.upsertDraft(draft, memberID: ownerID, accessToken: accessToken)
                        guard self.ownerID == ownerID, self.accessToken == accessToken else { break }
                        drafts = DraftSyncPolicy.merge(local: drafts, remote: [remoteDraft])
                        persistDrafts(ownerID: ownerID)
                        queue = draftRepository.loadSyncMutations(ownerID: ownerID)
                        queue.removeAll { $0.id == mutation.id }
                    case .delete:
                        try await syncService.deleteDraft(id: mutation.draftID, memberID: ownerID, accessToken: accessToken)
                        queue = draftRepository.loadSyncMutations(ownerID: ownerID)
                        queue.removeAll { $0.id == mutation.id }
                    }
                    telemetry(.syncAttemptSucceeded, ["operation": mutation.operation.rawValue])
                } catch {
                    queue = draftRepository.loadSyncMutations(ownerID: ownerID)
                    if DraftSyncPolicy.isEntitlementError(error) {
                        // Graceful degradation: the account cannot sync drafts.
                        // Drop the mutation without retrying; local drafts stay untouched.
                        queue.removeAll { $0.id == mutation.id }
                        didHitEntitlement = true
                        syncStatus = .localOnly
                        telemetry(.syncAttemptEntitlementBlocked, ["operation": mutation.operation.rawValue])
                    } else if let index = queue.firstIndex(where: { $0.id == mutation.id }) {
                        queue[index] = DraftSyncPolicy.markFailed(mutation, error: error)
                        telemetry(.syncAttemptFailed, ["operation": mutation.operation.rawValue])
                    }
                }
            }
            guard self.ownerID == ownerID, self.accessToken == accessToken else {
                isDrainingSyncQueue = false
                return
            }
            draftRepository.saveSyncMutations(queue, ownerID: ownerID)
            telemetry(.syncQueueLength, ["count": "\(queue.count)"])
            if didHitEntitlement {
                syncStatus = .localOnly
            } else {
                if queue.isEmpty {
                    lastSuccessfulSyncAt = Date()
                    persistDrafts(ownerID: ownerID)
                }
                syncStatus = queue.isEmpty ? .synced : (queue.contains { $0.lastError != nil } ? .failed : .pending)
            }
            isDrainingSyncQueue = false
            if queue.isEmpty, !didHitEntitlement, thenFetchRemote {
                syncFromRemote()
            } else if !DraftSyncPolicy.dueMutations(from: queue).isEmpty {
                drainSyncQueue()
            }
        }
    }
}
