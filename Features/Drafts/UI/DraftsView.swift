import SwiftUI

struct DraftsView: View {
    @ObservedObject var viewModel: DraftsViewModel
    let onOpenDraft: () -> Void
    let onShowPurchase: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.syncStatus.message)
                    .font(.caption)
                    .foregroundStyle(AppStyle.muted)

                Text("Drafts")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppStyle.ink)

                if viewModel.drafts.isEmpty {
                    ContentUnavailableView("No drafts", systemImage: "doc.text", description: Text("Saved drafts will appear here."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.drafts) { draft in
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    viewModel.open(draft)
                                    onOpenDraft()
                                } label: {
                                    draftContent(draft)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!viewModel.canEdit(draft))

                                Button {
                                    viewModel.delete(draft)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppStyle.muted)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete draft")
                            }
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if draft.id != viewModel.drafts.last?.id {
                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .background(AppStyle.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppStyle.paper)
        .navigationTitle("")
    }

    private func draftContent(_ draft: Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.title)
                .font(.headline)
                .foregroundStyle(AppStyle.ink)
            Text(draft.body)
                .font(.subheadline)
                .foregroundStyle(AppStyle.muted)
                .lineLimit(3)
            Text(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(AppStyle.muted)
        }
        .padding(.vertical, 6)
    }

}
