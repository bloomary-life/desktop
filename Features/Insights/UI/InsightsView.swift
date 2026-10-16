import SwiftUI
import AppKit

struct InsightsView: View {
    private let insights = [
        Insight(topline: "$2M revenue", title: "Christian Krause / Quota League", summary: "Daily LinkedIn posts helped build $2M revenue and a coaching business.", url: "https://www.linkedin.com/feed/update/urn%3Ali%3Aactivity%3A7340347428467843072/"),
        Insight(topline: "$100K+ MRR pipeline", title: "Alyona Mysko", summary: "Founder-led LinkedIn posts created $100K+ in measurable MRR pipeline.", url: "https://www.linkedin.com/feed/update/urn%3Ali%3Aactivity%3A7379153226815795200/"),
        Insight(topline: "600+ leads", title: "Jim Taylor", summary: "Consistent LinkedIn content produced 600+ leads without ads or cold outreach.", url: "https://www.linkedin.com/feed/update/urn%3Ali%3Aactivity%3A7465096268839628800/"),
        Insight(topline: "2x in 60 days", title: "Lauren Tickner", summary: "Buyer-focused LinkedIn content helped a client double revenue in 60 days.", url: "https://www.linkedin.com/feed/update/urn%3Ali%3Aactivity%3A7479866952899956736/"),
        Insight(topline: "3x client income", title: "Trisha Paul", summary: "Profile and post clarity helped turn LinkedIn into 3x client income.", url: "https://www.linkedin.com/feed/update/urn%3Ali%3Aactivity%3A7343299040001851394/"),
        Insight(topline: "7 inbound leads/week", title: "Rita Kerola", summary: "Clear positioning helped turn LinkedIn into 7 inbound leads per week.", url: "https://www.linkedin.com/feed/update/urn%3Ali%3Aactivity%3A7465280725379039232/")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Public LinkedIn signals")
                    .font(.caption)
                    .foregroundStyle(AppStyle.muted)

                Text("People turn their lived work into visible opportunity.")
                    .font(.title2)
                    .fontWeight(.semibold)

                ForEach(insights) { insight in
                    insightCard(insight)
                }
            }
            .padding()
        }
        .background(AppStyle.paper)
        .navigationTitle("")
    }

    private func insightCard(_ insight: Insight) -> some View {
        Button {
            if let url = URL(string: insight.url) {
                if NSWorkspace.shared.open(url) {
                    AppTelemetry.track(.insightOpened)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.topline)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppStyle.coral)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(insight.title)
                        .font(.headline)
                        .foregroundStyle(AppStyle.ink)
                    Spacer()
                }
                Text(insight.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppStyle.muted)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct Insight: Identifiable {
    var id: String { url }
    let topline: String
    let title: String
    let summary: String
    let url: String
}
