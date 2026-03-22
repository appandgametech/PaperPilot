import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingSearch = false
    @State private var sortBy: WatchlistSort? = nil
    @State private var viewMode: WatchlistMode = .list
    @State private var showInfo = false
    @State private var isEditing = false

    private var isWide: Bool { sizeClass == .regular }

    // Hub-specific watchlist
    private var hubWatchlist: [String] {
        stockService.watchlistForHub(portfolio.activeHub)
    }

    enum WatchlistMode: String, CaseIterable {
        case list = "List"
        case heatmap = "Heatmap"
    }

    private var displaySymbols: [String] {
        guard let sortBy else {
            return hubWatchlist
        }
        return hubWatchlist.sorted { a, b in
            let qa = stockService.quotes[a]
            let qb = stockService.quotes[b]
            switch sortBy {
            case .name: return a < b
            case .price: return (qa?.price ?? 0) > (qb?.price ?? 0)
            case .changePercent: return (qa?.changePercent ?? 0) > (qb?.changePercent ?? 0)
            case .volume: return (qa?.volume ?? 0) > (qb?.volume ?? 0)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode + sort controls
                HStack {
                    Picker("View", selection: $viewMode) {
                        ForEach(WatchlistMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)

                    Spacer()

                    Menu {
                        Button {
                            sortBy = nil
                        } label: {
                            Label("Custom Order", systemImage: sortBy == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(WatchlistSort.allCases, id: \.self) { sort in
                            Button {
                                sortBy = sort
                            } label: {
                                Label(sort.rawValue, systemImage: sortBy == sort ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if viewMode == .list {
                    listView
                } else {
                    heatmapView
                }
            }
            .navigationTitle("\(portfolio.activeHub.rawValue) Markets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if sortBy == nil {
                        Button {
                            withAnimation { isEditing.toggle() }
                        } label: {
                            Text(isEditing ? "Done" : "Edit")
                                .font(.subheadline)
                        }
                    }
                    Button { showingSearch = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    Button {
                        Task { await stockService.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                SearchStockSheet()
            }
            .sheet(isPresented: $showInfo) {
                MarketsInfoSheet()
            }
        }
    }

    private var listView: some View {
        List {
            if !stockService.isConnected {
                Label("Offline — showing cached data", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .listRowBackground(Color.orange.opacity(0.1))
            }

            if stockService.isLoading && stockService.quotes.isEmpty {
                ProgressView("Loading quotes...")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            if let error = stockService.errorMessage, stockService.isConnected {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(displaySymbols, id: \.self) { symbol in
                if let quote = stockService.quotes[symbol] {
                    NavigationLink(destination: StockDetailView(symbol: symbol)) {
                        QuoteRow(quote: quote, sparkline: stockService.sparklines[symbol])
                    }
                } else {
                    HStack {
                        Text(symbol).font(.headline)
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .onDelete { offsets in
                let symbols = offsets.map { displaySymbols[$0] }
                symbols.forEach { stockService.removeFromWatchlist($0, hub: portfolio.activeHub) }
            }
            .onMove { from, to in
                stockService.moveWatchlistItem(from: from, to: to, hub: portfolio.activeHub)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .refreshable {
            await stockService.refreshAll()
        }
    }

    // MARK: - Heatmap
    private var heatmapView: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: isWide ? 140 : 90, maximum: isWide ? 220 : 150))]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(displaySymbols, id: \.self) { symbol in
                    if let quote = stockService.quotes[symbol] {
                        NavigationLink(destination: StockDetailView(symbol: symbol)) {
                            heatmapCell(quote)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    private func heatmapCell(_ quote: StockQuote) -> some View {
        VStack(spacing: 2) {
            Text(quote.symbol)
                .font(.caption.bold())
                .foregroundStyle(.white)
            Text(String(format: "$%.2f", quote.price))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            Text(String(format: "%+.1f%%", quote.changePercent))
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: isWide ? 90 : 70)
        .background(heatmapColor(quote.changePercent), in: RoundedRectangle(cornerRadius: 8))
    }

    private func heatmapColor(_ pct: Double) -> Color {
        if pct > 3 { return .green }
        if pct > 1 { return .green.opacity(0.7) }
        if pct > 0 { return .green.opacity(0.4) }
        if pct > -1 { return .red.opacity(0.4) }
        if pct > -3 { return .red.opacity(0.7) }
        return .red
    }
}


// MARK: - Markets Info Sheet
struct MarketsInfoSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    infoSection(icon: "list.bullet.rectangle", color: .blue,
                                title: "Your Watchlist",
                                detail: "Add stocks you're interested in. Tap any stock to see detailed charts, stats, and trade directly. Swipe left to remove.")

                    infoSection(icon: "arrow.up.arrow.down", color: .purple,
                                title: "Sort & Reorder",
                                detail: "Use the Sort menu to order by name, price, change %, or volume. Choose 'Custom Order' and tap Edit to drag stocks into your preferred order.")

                    infoSection(icon: "square.grid.2x2", color: .orange,
                                title: "Heatmap View",
                                detail: "Switch to Heatmap to see all your stocks at a glance. Green = up, red = down. The intensity shows how much the stock has moved.")

                    infoSection(icon: "chart.line.uptrend.xyaxis", color: .green,
                                title: "Sparklines",
                                detail: "The mini charts next to each stock show the 5-day price trend. A quick visual to spot momentum without opening the detail view.")

                    infoSection(icon: "magnifyingglass", color: .cyan,
                                title: "Search & Add",
                                detail: "Tap + to search for any stock by symbol or company name. Results come from Yahoo Finance and include stocks and ETFs.")

                    infoSection(icon: "arrow.clockwise", color: .secondary,
                                title: "Live Data",
                                detail: "Prices refresh automatically based on your interval in Settings (default 30s). Pull down to refresh manually. Data comes from Yahoo Finance or Alpaca depending on your settings.")
                }
                .padding()
            }
            .navigationTitle("About Markets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoSection(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


struct QuoteRow: View {
    let quote: StockQuote
    var sparkline: [Double]? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.symbol).font(.headline)
                Text(quote.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            // Sparkline mini chart
            if let data = sparkline, data.count >= 2 {
                SparklineView(data: data, isPositive: quote.isPositive)
                    .frame(width: 50, height: 24)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", quote.price))
                    .font(.subheadline.bold().monospacedDigit())
                HStack(spacing: 4) {
                    Image(systemName: quote.isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(String(format: "%+.2f%%", quote.changePercent))
                        .font(.caption.bold().monospacedDigit())
                }
                .foregroundStyle(quote.isPositive ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    (quote.isPositive ? Color.green : Color.red).opacity(0.15),
                    in: Capsule()
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sparkline
struct SparklineView: View {
    let data: [Double]
    let isPositive: Bool

    var body: some View {
        Canvas { context, size in
            guard data.count >= 2 else { return }
            let minV = data.min() ?? 0
            let maxV = data.max() ?? 1
            let range = maxV - minV
            let color: Color = isPositive ? .green : .red

            if range == 0 {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: 1.5)
                return
            }

            let stepX = size.width / CGFloat(data.count - 1)
            var path = Path()
            for (i, val) in data.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - ((val - minV) / range) * size.height
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }
}

struct SearchStockSheet: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var results: [StockQuote] = []

    private var currentWatchlist: [String] {
        stockService.watchlistForHub(portfolio.activeHub)
    }

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !query.isEmpty {
                    Text("No results for \"\(query)\"")
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { result in
                    Button {
                        stockService.addToWatchlist(result.symbol, hub: portfolio.activeHub)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(result.symbol).font(.headline)
                                Text(result.name).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if currentWatchlist.contains(result.symbol) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Add Stock")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search by symbol or name")
            .onChange(of: query) { _, newValue in
                Task {
                    results = await stockService.searchStocks(query: newValue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
