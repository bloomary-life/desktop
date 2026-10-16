import AppKit
import SwiftUI

struct MainSplitView: View {
    private enum Section: Hashable {
        case insights
        case drafts
        case editor
        case settings
    }

    @EnvironmentObject private var draftStore: DraftStore
    @EnvironmentObject private var linkedInSessionStore: LinkedInSessionStore
    @State private var selection: Section? = .editor
    @State private var opensDraftInEditor = false
    @State private var showsFeedback = false
    @State private var showsPostToast = false
    @State private var showsPurchase = false
    @State private var isPro = false
    @State private var subscriptionSource: String?
    @State private var subscriptionAlertMessage = ""
    @State private var showsSubscriptionAlert = false
    @State private var feedbackButtonPosition: CGPoint?
    @State private var feedbackButtonDragStart: CGPoint?
    let editorViewModel: EditorViewModel
    let draftsViewModel: DraftsViewModel
    let accountViewModel: AccountViewModel
    let aiSettingsStore: AISettingsStore
    let feedbackService: FeedbackService
    let entitlementService: EntitlementService
    let paddleCheckoutService: PaddleCheckoutService
    let paddleConfiguration: AppConfiguration.Paddle

    var body: some View {
        NavigationSplitView {
            List(selection: sectionSelection) {
                Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(Section.insights)
                Label("Drafts", systemImage: "doc.text")
                    .tag(Section.drafts)
                Label("Editor", systemImage: "square.and.pencil")
                    .tag(Section.editor)
                Label("Settings", systemImage: "gearshape")
                    .tag(Section.settings)
            }
        } detail: {
            detailView
        }
        .overlay {
            GeometryReader { proxy in
                let defaultPosition = defaultFeedbackButtonPosition(in: proxy.size)
                Image(systemName: "ladybug")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 52, height: 52)
                    .background(AppStyle.coral)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .accessibilityLabel("Send feedback")
                    .accessibilityAddTraits(.isButton)
                .position(feedbackButtonPosition ?? defaultPosition)
                .onTapGesture {
                    openFeedback()
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let start = feedbackButtonDragStart ?? feedbackButtonPosition ?? defaultPosition
                            feedbackButtonDragStart = start
                            feedbackButtonPosition = clampedFeedbackButtonPosition(
                                CGPoint(
                                    x: start.x + value.translation.width,
                                    y: start.y + value.translation.height
                                ),
                                in: proxy.size
                            )
                        }
                        .onEnded { _ in
                            feedbackButtonDragStart = nil
                        }
                )
            }
        }
        .overlay(alignment: .top) {
            if showsPostToast {
                Text("Posted to LinkedIn")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppStyle.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppStyle.panel.opacity(0.96))
                    .clipShape(Capsule())
                    .shadow(color: AppStyle.ink.opacity(0.12), radius: 18, x: 0, y: 8)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showsFeedback) {
            NavigationStack {
                FeedbackView(feedbackService: feedbackService)
            }
        }
        .sheet(isPresented: $showsPurchase) {
            if let credential = linkedInSessionStore.postCredential {
                PaddleCheckoutView(
                    configuration: paddleConfiguration,
                    credential: credential,
                    email: linkedInSessionStore.token?.profile.email,
                    service: paddleCheckoutService
                ) {
                    refreshEntitlementAfterPurchase()
                }
            }
        }
        .onAppear {
            PerformanceSignposts.appLaunchComplete()
            draftStore.setSession(linkedInSessionStore.token)
            refreshEntitlement()
        }
        .onChange(of: linkedInSessionStore.token) { _, token in
            draftStore.setSession(token)
            refreshEntitlement()
        }
        .alert("Subscription", isPresented: $showsSubscriptionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subscriptionAlertMessage)
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .editor {
        case .insights:
            NavigationStack {
                InsightsView()
            }
        case .drafts:
            NavigationStack {
                DraftsView(viewModel: draftsViewModel) {
                    openDraftInEditor()
                } onShowPurchase: {
                    showsPurchase = true
                }
            }
        case .editor:
            NavigationStack {
                EditorView(viewModel: editorViewModel) {
                    selection = .drafts
                } onPostSucceeded: {
                    showPostedToast()
                } onShowPurchase: {
                    showsPurchase = true
                }
            }
        case .settings:
            NavigationStack {
                AccountSettingsView(
                    viewModel: accountViewModel,
                    feedbackService: feedbackService,
                    aiSettingsStore: aiSettingsStore,
                    showsUpgrade: !isPro,
                    subscriptionSource: subscriptionSource,
                    onShowPurchase: { showsPurchase = true },
                    onManageSubscription: manageSubscription
                )
            }
        }
    }

    private var sectionSelection: Binding<Section?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let section = newValue else { return }
                selectSection(section)
            }
        )
    }

    private func selectSection(_ section: Section) {
        if section == .editor, !opensDraftInEditor {
            draftStore.startNewPost()
        }
        opensDraftInEditor = false
        selection = section
    }

    private func openDraftInEditor() {
        opensDraftInEditor = true
        selection = .editor
    }

    private func defaultFeedbackButtonPosition(in size: CGSize) -> CGPoint {
        CGPoint(x: 44, y: max(92, size.height * 0.82))
    }

    private func clampedFeedbackButtonPosition(_ position: CGPoint, in size: CGSize) -> CGPoint {
        let radius: CGFloat = 34
        return CGPoint(
            x: min(max(position.x, radius), size.width - radius),
            y: min(max(position.y, radius), size.height - radius)
        )
    }

    private func openFeedback() {
        showsFeedback = true
        AppTelemetry.track(.feedbackOpened)
    }

    private func showPostedToast() {
        selection = .insights
        withAnimation(.easeInOut(duration: 0.2)) {
            showsPostToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeInOut(duration: 0.4)) {
                showsPostToast = false
            }
        }
    }

    private func refreshEntitlement() {
        guard let credential = linkedInSessionStore.postCredential else {
            isPro = false
            subscriptionSource = nil
            draftStore.setEntitlement(nil)
            return
        }

        isPro = false
        subscriptionSource = nil
        draftStore.setEntitlement(nil)

        Task {
            guard let entitlement = try? await entitlementService.entitlement(credential: credential) else { return }
            guard linkedInSessionStore.postCredential?.memberID == credential.memberID else { return }
            await MainActor.run {
                isPro = entitlement.isPro
                subscriptionSource = entitlement.subscriptionSource
                draftStore.setEntitlement(entitlement)
            }
        }
    }

    private func refreshEntitlementAfterPurchase() {
        guard let credential = linkedInSessionStore.postCredential else { return }
        Task {
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(2))
                guard let entitlement = try? await entitlementService.entitlement(credential: credential) else { continue }
                guard linkedInSessionStore.postCredential?.memberID == credential.memberID else { return }
                await MainActor.run {
                    isPro = entitlement.isPro
                    subscriptionSource = entitlement.subscriptionSource
                    draftStore.setEntitlement(entitlement)
                }
                if entitlement.isPro { return }
            }
        }
    }

    private func manageSubscription() {
        if subscriptionSource == "apple" {
            NSWorkspace.shared.open(URL(string: "https://apps.apple.com/account/subscriptions")!)
            return
        }
        guard let credential = linkedInSessionStore.postCredential else { return }
        Task {
            do {
                let url = try await paddleCheckoutService.portalURL(credential: credential)
                await MainActor.run { NSWorkspace.shared.open(url) }
            } catch {
                await MainActor.run {
                    subscriptionAlertMessage = error.localizedDescription
                    showsSubscriptionAlert = true
                }
            }
        }
    }
}
