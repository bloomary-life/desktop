import Foundation
import Testing
@testable import Bloomary_Desktop

struct DraftSyncPolicyTests {
    @Test
    func enqueueCoalescesByOwnerAndDraft() {
        let draftID = UUID()
        let older = DraftSyncMutation(ownerID: "member-1", operation: .upsert, draftID: draftID, draft: Draft(id: draftID, body: "old"))
        let newer = DraftSyncMutation(ownerID: "member-1", operation: .delete, draftID: draftID)

        let queue = DraftSyncPolicy.enqueue(newer, into: [older])

        #expect(queue == [newer])
    }

    @Test
    func mergeKeepsNewestDraft() {
        let draftID = UUID()
        let local = Draft(id: draftID, body: "local", updatedAt: Date(timeIntervalSince1970: 20))
        let remote = Draft(id: draftID, body: "remote", updatedAt: Date(timeIntervalSince1970: 10))

        let merged = DraftSyncPolicy.merge(local: [local], remote: [remote])

        #expect(merged == [local])
    }

    @Test
    func failedMutationGetsRetryDelay() {
        let mutation = DraftSyncMutation(ownerID: "member-1", operation: .delete, draftID: UUID())
        let failed = DraftSyncPolicy.markFailed(mutation, error: TestError.offline, now: Date(timeIntervalSince1970: 0), jitter: 0)

        #expect(failed.attemptCount == 1)
        #expect(failed.nextAttemptAt == Date(timeIntervalSince1970: 30))
        #expect(failed.lastError == "offline")
    }

    @Test
    func failedMutationBackoffIncludesBoundedJitter() {
        let mutation = DraftSyncMutation(ownerID: "member-1", operation: .delete, draftID: UUID())
        let now = Date(timeIntervalSince1970: 0)

        let noJitter = DraftSyncPolicy.markFailed(mutation, error: TestError.offline, now: now, jitter: 0)
        let withJitter = DraftSyncPolicy.markFailed(mutation, error: TestError.offline, now: now, jitter: 7)

        #expect(noJitter.nextAttemptAt == Date(timeIntervalSince1970: 30))
        #expect(withJitter.nextAttemptAt == Date(timeIntervalSince1970: 37))
    }

    @Test
    func backoffStaysWithinCapEvenWithJitter() {
        var mutation = DraftSyncMutation(ownerID: "member-1", operation: .delete, draftID: UUID())
        mutation.attemptCount = DraftSyncPolicy.maxRetryAttempts - 2
        let now = Date(timeIntervalSince1970: 0)
        let failed = DraftSyncPolicy.markFailed(mutation, error: TestError.offline, now: now, jitter: 15)

        #expect(failed.attemptCount == DraftSyncPolicy.maxRetryAttempts - 1)
        #expect(!DraftSyncPolicy.isParked(failed))
        let delay = failed.nextAttemptAt!.timeIntervalSince(now)
        #expect(delay >= 30)
        #expect(delay <= DraftSyncPolicy.maxBackoffSeconds)
    }

    @Test
    func mutationIsParkedAfterRetryWindow() {
        var mutation = DraftSyncMutation(ownerID: "member-1", operation: .upsert, draftID: UUID())
        mutation.attemptCount = DraftSyncPolicy.maxRetryAttempts - 1

        let failed = DraftSyncPolicy.markFailed(mutation, error: TestError.offline, now: Date(timeIntervalSince1970: 0), jitter: 0)

        #expect(failed.attemptCount == DraftSyncPolicy.maxRetryAttempts)
        #expect(DraftSyncPolicy.isParked(failed))
        #expect(DraftSyncPolicy.dueMutations(from: [failed], now: Date(timeIntervalSince1970: 10_000)).isEmpty)
    }

    @Test
    func resetParkedReArmsMutationForNextLaunch() {
        var mutation = DraftSyncMutation(ownerID: "member-1", operation: .upsert, draftID: UUID())
        mutation.attemptCount = DraftSyncPolicy.maxRetryAttempts - 1
        let parked = DraftSyncPolicy.markFailed(mutation, error: TestError.offline, now: Date(timeIntervalSince1970: 0), jitter: 0)

        let rearmed = DraftSyncPolicy.resetParked(in: [parked])

        #expect(rearmed.count == 1)
        #expect(rearmed[0].attemptCount == 0)
        #expect(rearmed[0].nextAttemptAt == nil)
        #expect(DraftSyncPolicy.dueMutations(from: rearmed).count == 1)
    }

    @Test
    func resetParkedLeavesActiveMutationsUntouched() {
        let active = DraftSyncMutation(ownerID: "member-1", operation: .upsert, draftID: UUID())

        let rearmed = DraftSyncPolicy.resetParked(in: [active])

        #expect(rearmed == [active])
    }

    @Test
    func entitlementErrorIsDetectedAsTerminal() {
        #expect(DraftSyncPolicy.isEntitlementError(SyncedDraftsError.entitlementRequired))
        #expect(!DraftSyncPolicy.isEntitlementError(SyncedDraftsError.server("boom")))
        #expect(!DraftSyncPolicy.isEntitlementError(TestError.offline))
    }
}

private enum TestError: LocalizedError {
    case offline

    var errorDescription: String? { "offline" }
}
