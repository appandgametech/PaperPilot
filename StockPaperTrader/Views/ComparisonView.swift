import SwiftUI

struct ComparisonView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @State private var symbols: [String] = ["AAPL", "MSFT"]
    @State private var newSymbol = ""
    @State private var chartDataMap: [String: [ChartDataPoint]] = [:]
    @State private var timeframe: ChartTimeframe = .oneMonth
    @State private var isLoading = false

    private let colors: [Color] = [.blue, .orange, .green, .purple, .red, .cyan, .pink, .yellow]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Symbol chips
                symbolBar

                // Add symbol
                HStack {
                    TextField("Add symbol", text: $newSymbol)
                        .textInputAutocapitalization(.characters)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let sym = newSymbol.uppercased()
                        guard !sym.isEmpty, !symbols.contains(sym), symbols.count < 8 else { return }
                        symbols.append(sym)
                        newSymbol = ""
                        Task { await loadCharts() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newSymbol.isEmpty || symbols.count >= 8)
                }
                .padding(.horizontal)

                // Timeframe
                HStack {
                    ForEach(ChartTimeframe.allCases, id: \.self) { tf in
                        Button {
                            timeframe = tf
                            Task { await loadCharts() }
                        } label: {
                            Text(tf.rawValue)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(timeframe == tf ? Color.blue : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(timeframe == tf ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Comparison chart (normalized to %)
                if isLoading {
                    ProgressView().frame(height: 220)
                } else {
                    comparisonChart.frame(height: 220)
                }

                // Legend
                HStack(spacing: 12) {
                    ForEach(Array(symbols.enumerated()), id: \.element) { idx, sym in
                        HStack(spacing: 4) {
                            Circle().fill(colors[idx % colors.count]).frame(width: 8, height: 8)
                            Text(sym).font(.caption.bold())
                            if let q = stockService.quotes[sym] {
                                Text(String(format: "%+.1f%%", q.changePercent))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(q.isPositive ? .green : .red)
                            }
                        }
                    }
                }

                // Stats comparison table
                statsTable
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCharts() }
    }

    private var symbolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(symbols.enumerated()), id: \.element) { idx, sym in
                    HStack(spacing: 4) {
                        Circle().fill(colors[idx % colors.count]).frame(width: 8, height: 8)
                        Text(sym).font(.caption.bold())
                        if symbols.count > 1 {
                            Button {
                                symbols.removeAll { $0 == sym }
                                chartDataMap.removeValue(forKey: sym)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Normalized Comparison Chart
    private var comparisonChart: some View {
        Canvas { context, size in
            guard !chartDataMap.isEmpty else { return }

            // Normalize all series to percentage change from first point
            var allNormalized: [(symbol: String, values: [Double], color: Color)] = []
            for (idx, sym) in symbols.enumerated() {
                guard let data = chartDataMap[sym], !data.isEmpty else { continue }
                let closes = data.map(\.close)
                let base = closes.first ?? 1
                let normalized = closes.map { (($0 - base) / base) * 100 }
                allNormalized.append((sym, normalized, colors[idx % colors.count]))
            }
            guard !allNormalized.isEmpty else { return }

            let allValues = allNormalized.flatMap(\.values)
            let minY = (allValues.min() ?? -5) - 1
            let maxY = (allValues.max() ?? 5) + 1
            let range = maxY - minY
            guard range > 0 else { return }
            let maxCount = allNormalized.map(\.values.count).max() ?? 1

            // Zero line
            let zeroY = size.height - ((0 - minY) / range) * size.height
            var zeroPath = Path()
            zeroPath.move(to: CGPoint(x: 0, y: zeroY))
            zeroPath.addLine(to: CGPoint(x: size.width, y: zeroY))
            context.stroke(zeroPath, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

            // Gridlines
            for i in 0...4 {
                let y = size.height * CGFloat(i) / 4
                var gp = Path()
                gp.move(to: CGPoint(x: 0, y: y))
                gp.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(gp, with: .color(.secondary.opacity(0.08)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                let val = maxY - (maxY - minY) * Double(i) / 4
                let label = Text(String(format: "%+.1f%%", val)).font(.system(size: 8).monospacedDigit()).foregroundColor(.secondary)
                context.draw(context.resolve(label), at: CGPoint(x: size.width - 2, y: y), anchor: .topTrailing)
            }

            // Draw each series
            for series in allNormalized {
                let stepX = size.width / CGFloat(max(1, maxCount - 1))
                var path = Path()
                for (i, val) in series.values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = size.height - ((val - minY) / range) * size.height
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(series.color), lineWidth: 2)

                // End label
                if let last = series.values.last {
                    let x = CGFloat(series.values.count - 1) * stepX
                    let y = size.height - ((last - minY) / range) * size.height
                    let dot = Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
                    context.fill(dot, with: .color(series.color))
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Stats Table
    private var statsTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Metric").font(.caption2.bold()).frame(width: 70, alignment: .leading)
                ForEach(symbols, id: \.self) { sym in
                    Text(sym).font(.caption2.bold()).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))

            Divider()

            statRow("Price") { sym in
                if let q = stockService.quotes[sym] { return portfolio.formatCurrency(q.price) }
                return "—"
            }
            statRow("Change") { sym in
                if let q = stockService.quotes[sym] { return String(format: "%+.2f%%", q.changePercent) }
                return "—"
            }
            statRow("Volume") { sym in
                if let q = stockService.quotes[sym] { return formatVol(q.volume) }
                return "—"
            }
            statRow("Day High") { sym in
                if let q = stockService.quotes[sym] { return portfolio.formatCurrency(q.dayHigh) }
                return "—"
            }
            statRow("Day Low") { sym in
                if let q = stockService.quotes[sym] { return portfolio.formatCurrency(q.dayLow) }
                return "—"
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func statRow(_ label: String, value: @escaping (String) -> String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            ForEach(symbols, id: \.self) { sym in
                Text(value(sym))
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal).padding(.vertical, 4)
    }

    private func loadCharts() async {
        isLoading = true
        await stockService.fetchQuotesForHub(.paper, symbols: symbols)
        await withTaskGroup(of: (String, [ChartDataPoint]).self) { group in
            for sym in symbols {
                group.addTask { [stockService, timeframe] in
                    let data = await stockService.fetchChartDataForHub(.paper, symbol: sym, timeframe: timeframe)
                    return (sym, data)
                }
            }
            for await (sym, data) in group {
                chartDataMap[sym] = data
            }
        }
        isLoading = false
    }

    private func formatVol(_ v: Int64) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1fB", Double(v) / 1e9) }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1e6) }
        if v >= 1_000 { return String(format: "%.0fK", Double(v) / 1e3) }
        return "\(v)"
    }
}
