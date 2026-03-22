import SwiftUI

struct NewsView: View {
    @EnvironmentObject var stockService: StockService
    @State private var newsItems: [YahooNewsItem] = []
    @State private var isLoading = false
    @State private var selectedSymbol: String = "all"

    private var symbols: [String] { ["all"] + stockService.watchlistForHub(.paper) }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(symbols, id: \.self) { sym in
                            Button {
                                selectedSymbol = sym
                                Task { await loadNews() }
                            } label: {
                                Text(sym == "all" ? "All" : sym)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedSymbol == sym ? Color.blue : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedSymbol == sym ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if isLoading {
                HStack { Spacer(); ProgressView("Loading news..."); Spacer() }
                    .listRowBackground(Color.clear)
            }

            if !isLoading && newsItems.isEmpty {
                ContentUnavailableView("No News", systemImage: "newspaper",
                                       description: Text("No headlines found. Try a different stock."))
            }

            Section {
                ForEach(newsItems) { item in
                    if let url = URL(string: item.link) {
                        Link(destination: url) {
                            newsRow(item)
                        }
                    } else {
                        newsRow(item)
                    }
                }
            }
        }
        .navigationTitle("Market News")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadNews() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await loadNews() }
    }

    private func newsRow(_ item: YahooNewsItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline.bold())
                .lineLimit(3)
            HStack {
                if let publisher = item.publisher {
                    Text(publisher)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                Spacer()
                if let date = item.providerPublishTime {
                    Text(Date(timeIntervalSince1970: TimeInterval(date)), style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func loadNews() async {
        isLoading = true
        let query = selectedSymbol == "all" ? stockService.watchlistForHub(.paper).prefix(3).joined(separator: ",") : selectedSymbol
        newsItems = await fetchYahooNews(query: query)
        isLoading = false
    }

    private func fetchYahooNews(query: String) async -> [YahooNewsItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=0&newsCount=20"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(YahooNewsResponse.self, from: data)
            return decoded.news ?? []
        } catch {
            return []
        }
    }
}

// MARK: - Yahoo News Models
struct YahooNewsResponse: Codable {
    let news: [YahooNewsItem]?
}

struct YahooNewsItem: Codable, Identifiable {
    let uuid: String
    let title: String
    let link: String
    let publisher: String?
    let providerPublishTime: Int?

    var id: String { uuid }
}
