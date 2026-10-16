import Foundation

enum DraftSyncOperation: String, Codable, Equatable {
    case upsert
    case delete
}

struct DraftSyncMutation: Identifiable, Codable, Equatable {
    let id: UUID
    let ownerID: String
    let operation: DraftSyncOperation
    let draftID: Draft.ID
    let draft: Draft?
    let queuedAt: Date
    var attemptCount: Int
    var lastError: String?
    var nextAttemptAt: Date?

    init(
        id: UUID = UUID(),
        ownerID: String,
        operation: DraftSyncOperation,
        draftID: Draft.ID,
        draft: Draft? = nil,
        queuedAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String? = nil,
        nextAttemptAt: Date? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.operation = operation
        self.draftID = draftID
        self.draft = draft
        self.queuedAt = queuedAt
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.nextAttemptAt = nextAttemptAt
    }
}

enum DraftSyncPolicy {
    /// After this many failed attempts a mutation is parked (not retried again
    /// this session) and re-armed on the next app launch via `resetParked`.
    static let maxRetryAttempts = 5
    static let maxBackoffSeconds: TimeInterval = 300
    /// Bounded jitter added to the backoff so retries do not thunder-herd.
    static let jitterRange: ClosedRange<TimeInterval> = 0...15

    static func enqueue(_ mutation: DraftSyncMutation, into queue: [DraftSyncMutation]) -> [DraftSyncMutation] {
        let remaining = queue.filter {
            !($0.ownerID == mutation.ownerID && $0.draftID == mutation.draftID)
        }
        return remaining + [mutation]
    }

    static func dueMutations(from queue: [DraftSyncMutation], now: Date = Date()) -> [DraftSyncMutation] {
        queue.filter { !isParked($0) && ($0.nextAttemptAt ?? .distantPast) <= now }
    }

    static func markFailed(
        _ mutation: DraftSyncMutation,
        error: Error,
        now: Date = Date(),
        jitter: TimeInterval = TimeInterval.random(in: jitterRange)
    ) -> DraftSyncMutation {
        var failed = mutation
        failed.attemptCount += 1
        failed.lastError = error.localizedDescription
        if failed.attemptCount >= maxRetryAttempts {
            failed.nextAttemptAt = .distantFuture
        } else {
            failed.nextAttemptAt = now.addingTimeInterval(backoffSeconds(attemptCount: failed.attemptCount, jitter: jitter))
        }
        return failed
    }

    static func isParked(_ mutation: DraftSyncMutation) -> Bool {
        mutation.nextAttemptAt == .distantFuture
    }

    /// Re-arms parked mutations so the queue is retried after an app relaunch.
    static func resetParked(in queue: [DraftSyncMutation]) -> [DraftSyncMutation] {
        queue.map { mutation in
            guard isParked(mutation) else { return mutation }
            var reset = mutation
            reset.attemptCount = 0
            reset.nextAttemptAt = nil
            return reset
        }
    }

    static func isEntitlementError(_ error: Error) -> Bool {
        guard case .entitlementRequired = error as? SyncedDraftsError else { return false }
        return true
    }

    static func merge(local: [Draft], remote: [Draft]) -> [Draft] {
        var byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for draft in remote {
            if let existing = byID[draft.id], existing.updatedAt >= draft.updatedAt {
                continue
            }
            byID[draft.id] = draft
        }
        // Soft enforcement: keep all drafts regardless of limit.
        // Limit is enforced on new draft creation, not on sync/merge.
        return Array(byID.values)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func backoffSeconds(attemptCount: Int, jitter: TimeInterval) -> TimeInterval {
        let clampedJitter = min(max(jitter, jitterRange.lowerBound), jitterRange.upperBound)
        let base = pow(2, Double(attemptCount - 1)) * 30
        return min(maxBackoffSeconds, max(30, base) + clampedJitter)
    }
}
