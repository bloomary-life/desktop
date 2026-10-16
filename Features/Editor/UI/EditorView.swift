import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var formatCommand: EditorFormatCommand?
    @State private var showsEmojiPicker = false
    @State private var showsImagePicker = false
    @State private var scheduleDate = Date().addingTimeInterval(5 * 60)

    let onShowDrafts: () -> Void
    let onPostSucceeded: () -> Void
    let onShowPurchase: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.syncStatus.message)
                    .font(.caption)
                    .foregroundStyle(AppStyle.muted)

                HStack(spacing: 10) {
                    Button {
                        onShowDrafts()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .foregroundStyle(AppStyle.ink)
                    .accessibilityLabel("Back to drafts")

                    Text("Write your post")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppStyle.ink)
                }

                if let warning = viewModel.draftLimitWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(AppStyle.ink)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppStyle.coral.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(spacing: 0) {
                    editorToolbar
                    ZStack(alignment: .topTrailing) {
                        RichTextEditor(text: $viewModel.editorText, command: $formatCommand) {
                            AppTelemetry.track(.editorStarted)
                        }
                            .frame(minHeight: 260)
                            .padding(12)
                            .padding(.trailing, 36)

                        Button {
                            viewModel.clearEditor()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                        }
                        .foregroundStyle(AppStyle.ink)
                        .accessibilityLabel("Clear post text")
                        .disabled(!viewModel.hasEditorText)
                        .opacity(viewModel.hasEditorText ? 1 : 0)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                    }
                }
                    .frame(maxWidth: .infinity)
                    .background(AppStyle.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                preview
                attachedImagePreview
                editorStatusMessage
            }
            .padding()
        }
        .background(AppStyle.paper)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .navigationTitle("")
        .popover(isPresented: $showsEmojiPicker) {
            EmojiPickerView { emoji in
                formatCommand = .insert(emoji)
                showsEmojiPicker = false
            }
        }
        .fileImporter(isPresented: $showsImagePicker, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
            viewModel.setAttachedImage(data: data, filename: url.lastPathComponent, mimeType: mimeType)
        }
        .sheet(isPresented: $viewModel.showsSchedulePicker) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Schedule post").font(.title2.weight(.semibold))
                DatePicker(
                    "Date and time",
                    selection: $scheduleDate,
                    in: Date().addingTimeInterval(60)...viewModel.maximumScheduleDate
                )
                Text(viewModel.scheduleLimitText)
                    .font(.caption)
                    .foregroundStyle(AppStyle.muted)
                if let message = viewModel.scheduleMessage {
                    Text(message).font(.callout).foregroundStyle(AppStyle.coral)
                }
                HStack {
                    Button("Cancel") { viewModel.showsSchedulePicker = false }
                    Spacer()
                    Button(viewModel.isScheduling ? "Scheduling…" : "Schedule") {
                        viewModel.schedule(at: scheduleDate)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isScheduling)
                }
            }
            .padding(24)
            .frame(minWidth: 420)
        }
        .onAppear {
            viewModel.onPostSucceeded = {
                onPostSucceeded()
                openLinkedInProfilePosts()
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button(viewModel.isPro ? "Schedule" : "Schedule · Pro") {
                if viewModel.isPro {
                    scheduleDate = Date().addingTimeInterval(5 * 60)
                    viewModel.scheduleMessage = nil
                    viewModel.showsSchedulePicker = true
                } else {
                    onShowPurchase()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.isPosting || viewModel.isScheduling || (!viewModel.hasEditorText && viewModel.attachedImage == nil))

            Button {
                viewModel.save()
                onShowDrafts()
            } label: {
                Label("Save draft", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.isNewDraftBlockedByLimit)

            Button {
                viewModel.publish()
            } label: {
                Label(viewModel.isPosting ? "Posting..." : "Post to LinkedIn", systemImage: "paperplane.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isPosting || viewModel.isNaturalizing)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppStyle.paper)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppStyle.ink.opacity(0.12))
                .frame(height: 1)
        }
    }

    private var editorToolbar: some View {
        VStack(spacing: 0) {
            HStack {
                formatButton("B", "Bold", .bold).fontWeight(.bold)
                Spacer()
                formatButton("I", "Italic", .italic).italic()
                Spacer()
                formatButton("S", "Strikethrough", .strikethrough).strikethrough()
                Spacer()
                formatButton("U", "Underline", .underline).underline()
                Spacer()
                formatButton("<>", "Code", .code)
                Spacer()
                formatButton("T/", "Clear formatting", .clear)
            }
            HStack {
                toolbarIconButton("wand.and.stars", viewModel.isNaturalizing ? "Naturalizing English" : "Naturalize English") {
                    viewModel.naturalizeEnglish()
                }
                .disabled(!viewModel.hasEditorText || viewModel.isNaturalizing || viewModel.isPosting)
                Spacer()
                toolbarIconButton("face.smiling", "Insert emoji") { showsEmojiPicker = true }
                Spacer()
                toolbarIconButton("photo.on.rectangle.angled", "Attach image") { showsImagePicker = true }
                Spacer()
                formatImageButton("list.bullet", "Bullet list", .bullets)
                Spacer()
                formatImageButton("list.number", "Numbered list", .numbered)
            }
        }
        .padding(.horizontal, 8)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppStyle.ink.opacity(0.12))
                .frame(height: 1)
        }
    }

    private func formatButton(_ title: String, _ label: String, _ command: EditorFormatCommand) -> some View {
        Button(title) {
            formatCommand = command
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(AppStyle.ink.opacity(0.72))
        .frame(width: 44, height: 44)
        .accessibilityLabel(label)
        .help(label)
    }

    private func formatImageButton(_ systemName: String, _ label: String, _ command: EditorFormatCommand) -> some View {
        Button {
            formatCommand = command
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
        }
        .foregroundStyle(AppStyle.ink.opacity(0.72))
        .frame(width: 44, height: 44)
        .accessibilityLabel(label)
        .help(label)
    }

    private func toolbarIconButton(_ systemName: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
        }
        .foregroundStyle(AppStyle.ink.opacity(0.72))
        .frame(width: 44, height: 44)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private var attachedImagePreview: some View {
        if let image = viewModel.attachedImage {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button { viewModel.removeAttachedImage() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewHeader

            Text(viewModel.previewText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppStyle.ink.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var editorStatusMessage: some View {
        if let message = viewModel.statusMessage {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppStyle.muted)
        }
    }

    @ViewBuilder
    private var previewHeader: some View {
        if let profile = viewModel.profile {
            HStack(spacing: 10) {
                LinkedInProfilePhoto(pictureURL: profile.pictureURL, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline)
                    Text(profile.displayHeadline ?? "Now")
                        .font(.subheadline)
                        .foregroundStyle(AppStyle.muted)
                }
            }
        } else {
            Text("Connect LinkedIn to preview your profile.")
                .font(.subheadline)
                .foregroundStyle(AppStyle.muted)
        }
    }

    private func openLinkedInProfilePosts() {
        guard let url = URL(string: "https://www.linkedin.com/in/me/recent-activity/all/") else { return }
        NSWorkspace.shared.open(url)
    }

}

private struct EmojiPickerView: View {
    private let emojis = ["😀", "😄", "😊", "🙂", "😉", "😍", "🥳", "🔥", "✨", "💡", "✅", "🚀", "📌", "📈", "💬", "👏", "🙏", "🤝", "🎯", "⭐", "❤️", "💙", "🧠", "✍️"]
    let onSelect: (String) -> Void
    private let columns = Array(repeating: GridItem(.fixed(38), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(emojis, id: \.self) { emoji in
                Button(emoji) { onSelect(emoji) }
                    .buttonStyle(.plain)
                    .font(.system(size: 26))
                    .frame(width: 38, height: 38)
            }
        }
        .padding()
    }
}
