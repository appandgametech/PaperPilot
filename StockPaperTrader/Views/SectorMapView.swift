import SwiftUI

struct SectorMapView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @State private var sectorData: [(sector: String, etf: String, change: Double)] = []
    @State private var isLoading = false

    private let sectorETFs: [(String, String)] = [
        ("Technology", "XLK"),
        ("Healthcare", "XLV"),
        ("Finance", "XLF"),
        ("Energy", "XLE"),
        ("Consumer Disc.", "XLY"),
        ("Consumer Staples", "XLP"),
        ("Industrial", "XLI"),
        ("Utilities", "XLU"),
        ("Real Estate", "XLRE"),
        ("Materials", "XLB"),
        ("Communication", "XLC"),
    ]

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView("Loading sectors..."); Spacer() }
                    .listRowBackground(Color.clear)
            }

            if !sectorData.isEmpty {
                Section("Today's Sector Performance") {
                    ForEach(sectorData.sorted { $0.change > $1.change }, id: \.etf) { item in
                        NavigationLink(destination: StockDetailView(symbol: item.etf)) {
                            sectorRow(item)
                        }
                    }
                }

                Section {
                    sectorHeatmap
                } header: {
                    Text("Heatmap")
                }
            }

            Section {
                Label {
                    Text("Sector data comes from SPDR sector ETFs (XLK, XLV, XLF, etc). These track the S&P 500 sectors and give a reliable view of where money is flowing.")
                        .font(.caption).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle").foregroundStyle(.blue)
                }
            }
        }
        .navigationTitle("Sectors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadSectors() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await loadSectors() }
    }

    private func sectorRow(_ item: (sector: String, etf: String, change: Double)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sector).font(.subheadline.bold())
                Text(item.etf).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Bar
            let maxAbs = max(1, sectorData.map { abs($0.change) }.max() ?? 1)
            let barWidth = CGFloat(abs(item.change) / maxAbs) * 80
            HStack(spacing: 4) {
                if item.change < 0 {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.6))
                        .frame(width: barWidth, height: 14)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.6))
                        .frame(width: barWidth, height: 14)
                    Spacer()
                }
            }
            .frame(width: 90)

            Text(String(format: "%+.2f%%", item.change))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(item.change >= 0 ? .green : .red)
                .frame(width: 65, alignment: .trailing)
        }
    }

    private var sectorHeatmap: some View {
        let sorted = sectorData.sorted { $0.change > $1.change }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(sorted, id: \.etf) { item in
                VStack(spacing: 2) {
                    Text(item.sector)
                        .font(.system(size: 9).bold())
                        .lineLimit(1)
                    Text(String(format: "%+.1f%%", item.change))
                        .font(.caption2.bold().monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(heatmapColor(item.change).opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
            }
        }
    }

    private func heatmapColor(_ change: Double) -> Color {
        if change > 1.5 { return .green }
        if change > 0.5 { return Color(red: 0.2, green: 0.7, blue: 0.3) }
        if change > 0 { return Color(red: 0.4, green: 0.6, blue: 0.4) }
        if change > -0.5 { return Color(red: 0.6, green: 0.4, blue: 0.4) }
        if change > -1.5 { return Color(red: 0.7, green: 0.3, blue: 0.2) }
        return .red
    }

    private func loadSectors() async {
        isLoading = true
        let etfSymbols = sectorETFs.map(\.1)
        await stockService.fetchQuotes(for: etfSymbols)
        sectorData = sectorETFs.compactMap { (sector, etf) in
            guard let q = stockService.quotes[etf] else { return nil }
            return (sector: sector, etf: etf, change: q.changePercent)
        }
        isLoading = false
    }
}
