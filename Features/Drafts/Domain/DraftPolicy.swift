import Foundation

/// Pure draft list policies: save (create/update), pruning to the max draft
/// count, and deletion. No SwiftUI, URLSession, UserDefaults, Keychain, or
/// MainActor — unit-testable in isolation.
enum DraftPolicy {
    struct SaveResult: Equatable {
        let drafts: [Draft]
        let editingDraftID: Draft.ID?
        /// Non-nil when a draft was created or its content changed.
        let changedDraft: Draft?
        let limitReached: Bool
    }

    static func trimmedBody(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies an editor save: updates the edited draft in place when the body
    /// changed, or creates a new draft at the top of the list. Creating a new
    /// draft is blocked when at the limit.
    static func save(drafts: [Draft], editingDraftID: Draft.ID?, body: String, maxDrafts: Int, imageData: Data? = nil, imageFilename: String? = nil, imageMimeType: String? = nil, now: Date = Date()) -> SaveResult {
        if let editingDraftID, let index = drafts.firstIndex(where: { $0.id == editingDraftID }) {
            var drafts = drafts
            guard drafts[index].body != body ||
                    drafts[index].imageData != imageData ||
                    drafts[index].imageFilename != imageFilename ||
                    drafts[index].imageMimeType != imageMimeType else {
                return SaveResult(drafts: drafts, editingDraftID: editingDraftID, changedDraft: nil, limitReached: false)
            }
            drafts[index].body = body
            drafts[index].imageData = imageData
            drafts[index].imageFilename = imageFilename
            drafts[index].imageMimeType = imageMimeType
            drafts[index].updatedAt = now
            return SaveResult(drafts: drafts, editingDraftID: editingDraftID, changedDraft: drafts[index], limitReached: false)
        }
        if drafts.count >= maxDrafts {
            return SaveResult(drafts: drafts, editingDraftID: editingDraftID, changedDraft: nil, limitReached: true)
        }
        let draft = Draft(body: body, imageData: imageData, imageFilename: imageFilename, imageMimeType: imageMimeType, createdAt: now, updatedAt: now)
        return SaveResult(drafts: [draft] + drafts, editingDraftID: draft.id, changedDraft: draft, limitReached: false)
    }

    static func delete(_ drafts: [Draft], id: Draft.ID) -> [Draft] {
        drafts.filter { $0.id != id }
    }
}
