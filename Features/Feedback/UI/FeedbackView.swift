import PhotosUI
import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var linkedInSessionStore: LinkedInSessionStore
    @State private var title = ""
    @State private var message = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var attachments: [FeedbackImageAttachment] = []
    @State private var isSending = false
    @State private var statusMessage = ""

    let feedbackService: FeedbackService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                intro
                form
                links
            }
            .padding()
        }
        .background(AppStyle.paper)
        .onChange(of: selectedItems) { _, newItems in
            loadAttachments(from: newItems)
        }
    }

    private var header: some View {
        HStack {
            Text("Feedback")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("Close") {
                dismiss()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome")
                .font(.title2)
                .fontWeight(.semibold)
            Text("We're open to your thoughts to make this app bring you more, so don't hesitate to share your ideas, feedback on app work, or whatever you may find insightful.")
                .foregroundStyle(AppStyle.muted)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppStyle.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $message)
                .frame(minHeight: 180)
                .padding(8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppStyle.ink.opacity(0.12), lineWidth: 1)
                )

            PhotosPicker(selection: $selectedItems, maxSelectionCount: 5, matching: .images) {
                Label("Attach images", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(SecondaryButtonStyle())

            if !attachments.isEmpty {
                Text("\(attachments.count) image\(attachments.count == 1 ? "" : "s") attached")
                    .font(.caption)
                    .foregroundStyle(AppStyle.muted)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppStyle.muted)
            }

            Button(isSending ? "Sending..." : "Send feedback") {
                sendFeedback()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSending)
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 10) {
            Link("Talk instead", destination: URL(string: "https://calendly.com/dailymind/20min")!)
            Link("Privacy policy", destination: URL(string: "https://bloomary.life/privacy/")!)
        }
        .font(.subheadline)
        .foregroundStyle(Color.black)
    }

    private func loadAttachments(from items: [PhotosPickerItem]) {
        Task {
            var loaded: [FeedbackImageAttachment] = []
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded.append(FeedbackImageAttachment(
                        filename: "feedback-\(index + 1).jpg",
                        content: data.base64EncodedString()
                    ))
                }
            }
            await MainActor.run {
                attachments = loaded
            }
        }
    }

    private func sendFeedback() {
        isSending = true
        statusMessage = ""
        Task {
            do {
                try await feedbackService.send(
                    title: title,
                    message: message,
                    identity: senderIdentity,
                    attachments: attachments
                )
                await MainActor.run {
                    statusMessage = "Sent. Confirmation was emailed to you."
                    isSending = false
                    AppTelemetry.track(.feedbackSent)
                    title = ""
                    message = ""
                    selectedItems = []
                    attachments = []
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private var senderIdentity: FeedbackSenderIdentity? {
        guard let profile = linkedInSessionStore.token?.profile else { return nil }
        return FeedbackSenderIdentity(name: profile.name, linkedInID: profile.memberID, email: profile.email)
    }
}
