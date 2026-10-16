import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var viewModel: AccountViewModel
    @State private var showsFeedback = false

    let feedbackService: FeedbackService?
    @ObservedObject var aiSettingsStore: AISettingsStore
    let showsUpgrade: Bool
    let subscriptionSource: String?
    let onShowPurchase: () -> Void
    let onManageSubscription: () -> Void
    private var hasFeedback: Bool { feedbackService != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppStyle.ink)

                aiSection

                if viewModel.isConnected {
                    if showsUpgrade {
                        Button("Upgrade to Pro") { onShowPurchase() }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button(subscriptionSource == "apple" ? "Manage in App Store" : "Manage subscription") {
                            onManageSubscription()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    accountSection
                    logoutButton
                    communitySection
                    feedbackSection
                } else {
                    connectButton
                }
                accountStatusMessage
            }
            .padding()
        }
        .background(AppStyle.paper)
        .navigationTitle("")
        .sheet(isPresented: $showsFeedback) {
            if let feedbackService {
                NavigationStack {
                    FeedbackView(feedbackService: feedbackService)
                }
            }
        }
    }

    private var accountSection: some View {
        section {
            NavigationLink {
                AccountDetailView(viewModel: viewModel)
            } label: {
                rowLabel("Account", systemImage: "person.crop.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private var communitySection: some View {
        section {
            communityLink
        }
    }

    private var aiSection: some View {
        section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gemini API key")
                    .font(.headline)
                    .foregroundStyle(AppStyle.ink)

                SecureField("Gemini API key", text: $aiSettingsStore.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .privacySensitive()

                Button("Save AI settings") {
                    aiSettingsStore.save()
                }
                .buttonStyle(SecondaryButtonStyle())

                Text("Use a Gemini key that Google accepts for Gemini API. Free quota, billing, region, and key restrictions are handled by Google.")
                    .font(.caption)
                    .foregroundStyle(AppStyle.muted)

                if let message = aiSettingsStore.statusMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppStyle.muted)
                }
            }
            .padding()
            .background(AppStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if hasFeedback {
            section {
                feedbackButton
            }
        }
    }

    private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
    }

    private var connectButton: some View {
        Button(viewModel.isConnecting ? "Connecting..." : "Connect LinkedIn") {
            viewModel.connect()
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(viewModel.isConnecting)
    }

    private var logoutButton: some View {
        Button(viewModel.isLoggingOut ? "Logging out..." : "Log out") {
            viewModel.logOut()
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(viewModel.isLoggingOut)
    }

    private var communityLink: some View {
        Link(destination: URL(string: "https://t.me/+NDQcpuABme9iYTU0")!) {
            rowLabel("Community", systemImage: "person.2")
        }
    }

    private func rowLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(AppStyle.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppStyle.ink.opacity(0.16), lineWidth: 1)
            }
    }

    private var feedbackButton: some View {
        Button {
            showsFeedback = true
            AppTelemetry.track(.feedbackOpened)
        } label: {
            Label("Send feedback", systemImage: "ladybug")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppStyle.coral)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var accountStatusMessage: some View {
        if let message = viewModel.statusMessage {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppStyle.muted)
        }
    }
}

private struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AccountViewModel
    @State private var showsDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Account")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppStyle.ink)

                accountCard
                accountStatusMessage
            }
            .padding()
        }
        .background(AppStyle.paper)
        .safeAreaInset(edge: .bottom) {
            if viewModel.isConnected {
                Button(viewModel.isDeletingAccount ? "Deleting..." : "Delete account", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.isDeletingAccount)
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
        }
        .navigationTitle("")
        .overlay {
            if showsDeleteConfirmation {
                deleteConfirmationModal
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let profile = viewModel.profile {
                HStack(alignment: .top, spacing: 12) {
                    LinkedInProfilePhoto(pictureURL: profile.pictureURL, size: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        if let headline = profile.displayHeadline {
                            Text(headline)
                                .font(.subheadline)
                                .foregroundStyle(AppStyle.muted)
                        }
                        Text("Registered \(viewModel.connectedAt?.formatted(date: .numeric, time: .omitted) ?? "")")
                            .font(.caption)
                            .foregroundStyle(AppStyle.muted)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppStyle.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Not connected.")
                    .foregroundStyle(AppStyle.muted)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppStyle.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var accountStatusMessage: some View {
        if let message = viewModel.statusMessage {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppStyle.muted)
        }
    }

    private var deleteConfirmationModal: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Delete account?")
                        .font(.headline)
                        .foregroundStyle(AppStyle.ink)
                    Text("This deletes your LinkedIn connection, drafts, local authorization token, and AI API key. Support, legal, and security records may be retained where required.")
                        .font(.subheadline)
                        .foregroundStyle(AppStyle.muted)

                    VStack(spacing: 10) {
                        Button("Cancel") {
                            showsDeleteConfirmation = false
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: .infinity)

                        Button("Delete account", role: .destructive) {
                            showsDeleteConfirmation = false
                            viewModel.deleteAccount {
                                dismiss()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .frame(width: proxy.size.width * 0.7)
                .background(AppStyle.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: AppStyle.ink.opacity(0.18), radius: 18, x: 0, y: 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
