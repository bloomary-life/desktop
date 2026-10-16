import Combine
import Foundation

@MainActor
final class DraftsViewModel: ObservableObject {
    private let store: DraftStore
    private var cancellables = Set<AnyCancellable>()

    init(store: DraftStore) {
        self.store = store
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var drafts: [Draft] {
        store.drafts
    }

    var syncStatus: DraftSyncStatus {
        store.syncStatus
    }

    var isPro: Bool {
        store.isPro
    }

    func open(_ draft: Draft) {
        guard store.canEdit(draft) else { return }
        store.openDraft(draft)
    }

    func canEdit(_ draft: Draft) -> Bool {
        store.canEdit(draft)
    }

    func delete(_ draft: Draft) {
        store.deleteDraft(draft)
    }
}
