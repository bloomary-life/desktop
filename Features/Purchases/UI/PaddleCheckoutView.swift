import SwiftUI
import WebKit

struct PaddleCheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: AppConfiguration.Paddle
    let credential: LinkedInPostCredential
    let email: String?
    let service: PaddleCheckoutService
    let onCompleted: () -> Void
    @State private var identity: PaddleCheckoutIdentity?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bloomary Pro").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()
            if let identity {
                PaddleWebView(configuration: configuration, identity: identity, email: email) {
                    onCompleted()
                    dismiss()
                }
            } else if let errorMessage {
                ContentUnavailableView("Checkout unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("Preparing checkout…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, minHeight: 650)
        .task {
            do { identity = try await service.identity(credential: credential) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct PaddleWebView: NSViewRepresentable {
    let configuration: AppConfiguration.Paddle
    let identity: PaddleCheckoutIdentity
    let email: String?
    let onCompleted: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCompleted: onCompleted) }

    func makeNSView(context: Context) -> WKWebView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController.add(context.coordinator, name: "checkoutCompleted")
        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        let checkoutOrigin = configuration.environment == "sandbox"
            ? URL(string: "https://localhost/")
            : URL(string: "https://platform.bloomary.life/")
        webView.loadHTMLString(html, baseURL: checkoutOrigin)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "checkoutCompleted")
    }

    private var html: String {
        let payload: [String: Any] = [
            "environment": configuration.environment,
            "token": configuration.clientToken,
            "priceId": configuration.priceProMonthly,
            "memberId": identity.memberId,
            "signature": identity.signature,
            "email": email ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return "<p>Checkout configuration is invalid.</p>"
        }
        let json = String(decoding: data, as: UTF8.self)
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width">
        <script src="https://cdn.paddle.com/paddle/v2/paddle.js" onerror="document.body.textContent='Checkout could not be loaded.'"></script>
        <style>html,body,.checkout{height:100%;margin:0;background:#fff}</style></head>
        <body><div class="checkout"></div><script>
        const config = \(json);
        if (config.environment === 'sandbox') Paddle.Environment.set('sandbox');
        Paddle.Initialize({token: config.token, eventCallback: event => {
          if (event.name === 'checkout.completed') window.webkit.messageHandlers.checkoutCompleted.postMessage('completed');
          if (event.name === 'checkout.error' || event.name === 'checkout.payment-error') document.querySelector('.checkout').textContent = 'Checkout failed. Please try again.';
        }});
        const options = {
          items: [{priceId: config.priceId, quantity: 1}],
          customData: {member_id: config.memberId, member_signature: config.signature},
          settings: {displayMode: 'inline', frameTarget: 'checkout', frameInitialHeight: 610, frameStyle: 'width:100%;border:none'}
        };
        if (config.email) options.customer = {email: config.email};
        Paddle.Checkout.open(options);
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onCompleted: () -> Void
        init(onCompleted: @escaping () -> Void) { self.onCompleted = onCompleted }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "checkoutCompleted" else { return }
            DispatchQueue.main.async { self.onCompleted() }
        }
    }
}
