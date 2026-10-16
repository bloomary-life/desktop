import Foundation

protocol DraftRepository {
    func loadDrafts(ownerID: String?) -> [Draft]
    func saveDrafts(_ drafts: [Draft], ownerID: String?)
    func deleteDrafts(ownerID: String?)
    func loadSnapshot(ownerID: String?) -> DraftSnapshot
    func saveSnapshot(_ snapshot: DraftSnapshot, ownerID: String?)
    func loadSyncMutations(ownerID: String) -> [DraftSyncMutation]
    func saveSyncMutations(_ mutations: [DraftSyncMutation], ownerID: String)
    func deleteSyncMutations(ownerID: String)
}

/// Default snapshot bridge so existing repositories (and test doubles) keep
/// working; the durable store overrides these with the versioned envelope.
extension DraftRepository {
    func loadSnapshot(ownerID: String?) -> DraftSnapshot {
        DraftSnapshot(drafts: loadDrafts(ownerID: ownerID), ownerID: ownerID)
    }

    func saveSnapshot(_ snapshot: DraftSnapshot, ownerID: String?) {
        saveDrafts(snapshot.drafts, ownerID: ownerID)
    }
}

final class UserDefaultsDraftRepository: DraftRepository {
    private let key: String
    private let defaults: UserDefaults

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func loadDrafts(ownerID: String?) -> [Draft] {
        loadSnapshot(ownerID: ownerID).drafts
    }

    func saveDrafts(_ drafts: [Draft], ownerID: String?) {
        var snapshot = loadSnapshot(ownerID: ownerID)
        snapshot.drafts = drafts
        saveSnapshot(snapshot, ownerID: ownerID)
    }

    func loadSnapshot(ownerID: String?) -> DraftSnapshot {
        guard let data = defaults.data(forKey: scopedKey(ownerID: ownerID)) else {
            return .empty(ownerID: ownerID)
        }
        // Current format: versioned snapshot envelope.
        if let snapshot = try? JSONDecoder.app.decode(DraftSnapshot.self, from: data),
           snapshot.schemaVersion <= DraftSnapshot.currentSchemaVersion {
            return snapshot
        }
        // Migration point: pre-snapshot payloads were a bare [Draft] array.
        if let drafts = try? JSONDecoder.app.decode([Draft].self, from: data) {
            return DraftSnapshot(drafts: drafts, ownerID: ownerID)
        }
        // Corrupt cache falls back to empty drafts.
        return .empty(ownerID: ownerID)
    }

    func saveSnapshot(_ snapshot: DraftSnapshot, ownerID: String?) {
        guard let data = try? JSONEncoder.app.encode(snapshot) else { return }
        defaults.set(data, forKey: scopedKey(ownerID: ownerID))
    }

    func deleteDrafts(ownerID: String?) {
        defaults.removeObject(forKey: scopedKey(ownerID: ownerID))
    }

    func loadSyncMutations(ownerID: String) -> [DraftSyncMutation] {
        guard let data = defaults.data(forKey: syncQueueKey(ownerID: ownerID)) else { return [] }
        return (try? JSONDecoder.app.decode([DraftSyncMutation].self, from: data)) ?? []
    }

    func saveSyncMutations(_ mutations: [DraftSyncMutation], ownerID: String) {
        guard let data = try? JSONEncoder.app.encode(mutations) else { return }
        defaults.set(data, forKey: syncQueueKey(ownerID: ownerID))
    }

    func deleteSyncMutations(ownerID: String) {
        defaults.removeObject(forKey: syncQueueKey(ownerID: ownerID))
    }

    private func scopedKey(ownerID: String?) -> String {
        "\(key).\(ownerID ?? "signed-out")"
    }

    private func syncQueueKey(ownerID: String) -> String {
        "\(key).syncQueue.\(ownerID)"
    }
}
