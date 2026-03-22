import SwiftUI

struct ScreenerView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @State private var selectedSector: StockSector?
    @State private var minPrice = ""
    @State private var maxPrice = ""
    @State private var minChange = ""
    @State private var maxChange = ""
    @State private var sortBy: ScreenerSort = .changePercent
    @State private var results: [StockQuote] = []
    @State private var isLoading = false
    @State private var hasSearched = false

    enum ScreenerSort: String, CaseIterable {
        case changePercent = "% Change"
        case price = "Price"
        case volume = "Volume"
        case name = "Name"
    }

    private var sortedResults: [StockQuote] {
        var filtered = results
        if let min = Double(minPrice) { filtered = filtered.filter { $0.price >= min } }
        if let max = Double(maxPrice) { filtered = filtered.filter { $0.price <= max } }
        if let min = Double(minChange) { filtered = filtered.filter { $0.changePercent >= min } }
        if let max = Double(maxChange) { filtered = filtered.filter { $0.changePercent <= max } }

        switch sortBy {
        case .changePercent: return filtered.sorted { $0.changePercent > $1.changePercent }
        case .price: return filtered.sorted { $0.price > $1.price }
        case .volume: return filtered.sorted { $0.volume > $1.volume }
        case .name: return filtered.sorted { $0.symbol < $1.symbol }
        }
    }

    var body: some View {
        List {
            Section("Sector") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StockSector.allCases, id: \.self) { sector in
                            Button {
                                selectedSector = selectedSector == sector ? nil : sector
                            } label: {
                                Text(sector.rawValue)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedSector == sector ? Color.blue : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedSector == sector ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            Section("Filters") {
                HStack {
                    TextField("Min $", text: $minPrice).keyboardType(.decimalPad)
                    Text("—")
                    TextField("Max $", text: $maxPrice).keyboardType(.decimalPad)
                }
                HStack {
                    TextField("Min %", text: $minChange).keyboardType(.decimalPad)
                    Text("—")
                    TextField("Max %", text: $maxChange).keyboardType(.decimalPad)
                }
                Picker("Sort By", selection: $sortBy) {
                    ForEach(ScreenerSort.allCases, id: \.self) { Text($0.rawValue) }
                }
            }

            Section {
                Button {
                    Task { await runScreener() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() }
                        else { Label("Scan Stocks", systemImage: "magnifyingglass") }
                        Spacer()
                    }
                }
            }

            if hasSearched {
                Section("Results (\(sortedResults.count))") {
                    if sortedResults.isEmpty {
                        ContentUnavailableView("No Matches", systemImage: "xmark.circle",
                                               description: Text("Try adjusting your filters or selecting a different sector."))
                    }
                    ForEach(sortedResults) { quote in
                        NavigationLink(destination: StockDetailView(symbol: quote.symbol)) {
                            screenerRow(quote)
                        }
                    }
                }
            }
        }
        .navigationTitle("Stock Screener")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func screenerRow(_ q: StockQuote) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(q.symbol).font(.subheadline.bold())
                Text(q.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(portfolio.formatCurrency(q.price)).font(.subheadline.monospacedDigit())
                Text(String(format: "%+.2f%%", q.changePercent))
                    .font(.caption.bold())
                    .foregroundStyle(q.isPositive ? .green : .red)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatVol(q.volume))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)
        }
    }

    private func runScreener() async {
        isLoading = true
        let symbols: [String]
        if let sector = selectedSector {
            symbols = sector.symbols
        } else {
            // Default: scan all sector ETFs + popular stocks
            symbols = ["SPY", "QQQ", "DIA", "IWM"] + StockSector.technology.symbols.prefix(10) + StockSector.healthcare.symbols.prefix(5) + StockSector.finance.symbols.prefix(5) + StockSector.energy.symbols.prefix(5)
        }
        await stockService.fetchQuotesForHub(.paper, symbols: symbols)
        results = symbols.compactMap { stockService.quotes[$0] }
        hasSearched = true
        isLoading = false
    }

    private func formatVol(_ v: Int64) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1fB", Double(v) / 1e9) }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1e6) }
        if v >= 1_000 { return String(format: "%.0fK", Double(v) / 1e3) }
        return "\(v)"
    }
}
