import SwiftUI

struct StockDetailView: View {
    let symbol: String
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @State private var showTradeSheet = false
    @State private var tradeType: TradeType = .buy
    @State private var chartData: [ChartDataPoint] = []
    @State private var selectedTimeframe: ChartTimeframe = .oneDay
    @State private var showInfo = false

    private var quote: StockQuote? {
        stockService.quotes[symbol]
    }

    private var position: Position? {
        portfolio.positions.first { $0.symbol == symbol }
    }

    var body: some View {
        Group {
            if let quote {
                ScrollView {
                    VStack(spacing: 20) {
                        priceHeader(quote)
                        miniChart
                        signalSummary(quote)
                        statsGrid(quote)
                        if let pos = position {
                            positionCard(pos)
                        }
                        tradeButtons
                    }
                    .padding()
                }
            } else {
                ProgressView("Loading \(symbol)...")
            }
        }
        .navigationTitle(symbol)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                    }
                    if !stockService.watchlist.contains(symbol) {
                        Button {
                            stockService.addToWatchlist(symbol)
                            HapticManager.selectionFeedback()
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .refreshable {
            await stockService.fetchQuotes(for: [symbol])
        }
        .task {
            chartData = await stockService.fetchChartData(symbol: symbol, timeframe: selectedTimeframe)
        }
        .onChange(of: selectedTimeframe) { _, _ in
            Task { chartData = await stockService.fetchChartData(symbol: symbol, timeframe: selectedTimeframe) }
        }
        .sheet(isPresented: $showTradeSheet) {
            if let quote {
                QuickTradeSheet(symbol: symbol, price: quote.price, tradeType: tradeType)
            }
        }
        .sheet(isPresented: $showInfo) {
            StockDetailInfoSheet()
        }
    }

    // MARK: - Signal Summary (decision helper)
    private func signalSummary(_ quote: StockQuote) -> some View {
        let closes = chartData.map(\.close)
        let signals = computeSignals(quote: quote, closes: closes)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick Signals")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(signals.overall)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(signals.overallColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(signals.overallColor)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                signalRow(label: "Day Trend", value: quote.change >= 0 ? "Bullish" : "Bearish",
                          color: quote.change >= 0 ? .green : .red)
                signalRow(label: "Volume", value: signals.volumeSignal, color: signals.volumeColor)
                signalRow(label: "Price vs Range", value: signals.rangePosition, color: signals.rangeColor)
                signalRow(label: "Momentum", value: signals.momentum, color: signals.momentumColor)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func signalRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.bold())
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
    }

    private struct SignalData {
        var overall: String
        var overallColor: Color
        var volumeSignal: String
        var volumeColor: Color
        var rangePosition: String
        var rangeColor: Color
        var momentum: String
        var momentumColor: Color
    }

    private func computeSignals(quote: StockQuote, closes: [Double]) -> SignalData {
        var bullish = 0
        var bearish = 0

        // Volume signal
        let volumeSignal: String
        let volumeColor: Color
        if quote.volume > 0 {
            // Simple heuristic: high volume = strong signal
            volumeSignal = quote.volume > 50_000_000 ? "High" : quote.volume > 10_000_000 ? "Normal" : "Low"
            volumeColor = quote.volume > 50_000_000 ? .green : quote.volume > 10_000_000 ? .primary : .orange
        } else {
            volumeSignal = "—"
            volumeColor = .secondary
        }

        // Range position
        let range = quote.dayHigh - quote.dayLow
        let rangePosition: String
        let rangeColor: Color
        if range > 0 {
            let pct = (quote.price - quote.dayLow) / range
            if pct > 0.75 {
                rangePosition = "Near High"
                rangeColor = .green
                bullish += 1
            } else if pct < 0.25 {
                rangePosition = "Near Low"
                rangeColor = .red
                bearish += 1
            } else {
                rangePosition = "Mid Range"
                rangeColor = .primary
            }
        } else {
            rangePosition = "—"
            rangeColor = .secondary
        }

        // Momentum from closes
        let momentum: String
        let momentumColor: Color
        if closes.count >= 5 {
            let recent = Array(closes.suffix(5))
            let older = Array(closes.prefix(max(1, closes.count - 5)).suffix(5))
            let recentAvg = recent.reduce(0, +) / Double(recent.count)
            let olderAvg = older.isEmpty ? recentAvg : older.reduce(0, +) / Double(older.count)
            if recentAvg > olderAvg * 1.01 {
                momentum = "Rising"
                momentumColor = .green
                bullish += 1
            } else if recentAvg < olderAvg * 0.99 {
                momentum = "Falling"
                momentumColor = .red
                bearish += 1
            } else {
                momentum = "Flat"
                momentumColor = .primary
            }
        } else {
            momentum = "—"
            momentumColor = .secondary
        }

        // Day trend
        if quote.change >= 0 { bullish += 1 } else { bearish += 1 }

        let overall: String
        let overallColor: Color
        if bullish > bearish + 1 {
            overall = "Bullish"
            overallColor = .green
        } else if bearish > bullish + 1 {
            overall = "Bearish"
            overallColor = .red
        } else if bullish > bearish {
            overall = "Slightly Bullish"
            overallColor = .green
        } else if bearish > bullish {
            overall = "Slightly Bearish"
            overallColor = .red
        } else {
            overall = "Neutral"
            overallColor = .secondary
        }

        return SignalData(overall: overall, overallColor: overallColor,
                          volumeSignal: volumeSignal, volumeColor: volumeColor,
                          rangePosition: rangePosition, rangeColor: rangeColor,
                          momentum: momentum, momentumColor: momentumColor)
    }

    private var miniChart: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(ChartTimeframe.allCases, id: \.self) { tf in
                    Button {
                        selectedTimeframe = tf
                    } label: {
                        Text(tf.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTimeframe == tf ? Color.blue : Color.clear, in: Capsule())
                            .foregroundStyle(selectedTimeframe == tf ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if chartData.count >= 2 {
                Canvas { context, size in
                    let closes = chartData.map(\.close)
                    let minY = closes.min() ?? 0
                    let maxY = closes.max() ?? 1
                    let range = maxY - minY
                    guard range > 0 else { return }
                    let stepX = size.width / CGFloat(closes.count - 1)
                    let isUp = (closes.last ?? 0) >= (closes.first ?? 0)
                    let color: Color = isUp ? .green : .red

                    var fill = Path()
                    for (i, val) in closes.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = size.height - ((val - minY) / range) * size.height
                        if i == 0 { fill.move(to: CGPoint(x: x, y: y)) }
                        else { fill.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.addLine(to: CGPoint(x: 0, y: size.height))
                    fill.closeSubpath()
                    context.fill(fill, with: .linearGradient(
                        Gradient(colors: [color.opacity(0.3), color.opacity(0)]),
                        startPoint: .init(x: 0, y: 0), endPoint: .init(x: 0, y: size.height)
                    ))

                    var line = Path()
                    for (i, val) in closes.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = size.height - ((val - minY) / range) * size.height
                        if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                        else { line.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(line, with: .color(color), lineWidth: 2)
                }
                .frame(height: 150)
            } else {
                ProgressView("Loading chart...")
                    .frame(height: 150)
            }
        }
    }

    private func priceHeader(_ quote: StockQuote) -> some View {
        VStack(spacing: 8) {
            Text(quote.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String(format: "$%.2f", quote.price))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                Image(systemName: quote.isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                Text(String(format: "%+.2f (%+.2f%%)", quote.change, quote.changePercent))
                    .font(.headline)
            }
            .foregroundStyle(quote.isPositive ? .green : .red)

            Text("Last updated \(quote.lastUpdated, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top)
    }

    private func statsGrid(_ quote: StockQuote) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Day High", value: String(format: "$%.2f", quote.dayHigh))
            StatCard(title: "Day Low", value: String(format: "$%.2f", quote.dayLow))
            StatCard(title: "Prev Close", value: String(format: "$%.2f", quote.previousClose))
            StatCard(title: "Volume", value: formatVolume(quote.volume))
        }
    }

    private func positionCard(_ pos: Position) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Position")
                .font(.headline)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(portfolio.formatShares(pos.shares)) shares")
                    Text("Avg cost: \(portfolio.formatCurrency(pos.averageCost))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(portfolio.formatCurrency(pos.marketValue))
                        .font(.headline)
                    Text(String(format: "%+.2f%%", pos.profitLossPercent))
                        .font(.subheadline.bold())
                        .foregroundStyle(pos.isPositive ? .green : .red)
                    Text(portfolio.formatCurrency(pos.profitLoss))
                        .font(.caption)
                        .foregroundStyle(pos.isPositive ? .green : .red)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var tradeButtons: some View {
        HStack(spacing: 16) {
            Button {
                tradeType = .buy
                showTradeSheet = true
            } label: {
                Label("Buy", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .font(.headline)
            }

            Button {
                tradeType = .sell
                showTradeSheet = true
            } label: {
                Label("Sell", systemImage: "minus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(position != nil ? .red : .gray, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .disabled(position == nil)
        }
    }

    private func formatVolume(_ vol: Int64) -> String {
        if vol >= 1_000_000_000 { return String(format: "%.1fB", Double(vol) / 1_000_000_000) }
        if vol >= 1_000_000 { return String(format: "%.1fM", Double(vol) / 1_000_000) }
        if vol >= 1_000 { return String(format: "%.1fK", Double(vol) / 1_000) }
        return "\(vol)"
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Stock Detail Info Sheet
struct StockDetailInfoSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    infoSection(icon: "chart.xyaxis.line", color: .blue,
                                title: "Price Chart",
                                detail: "Shows the stock's price movement over time. Switch between 1D, 5D, 1M, 3M, 6M, and 1Y timeframes. The gradient fill shows the trend direction — green for up, red for down.")

                    infoSection(icon: "lightbulb", color: .yellow,
                                title: "Quick Signals",
                                detail: "A snapshot of key indicators to help you decide. Day Trend shows today's direction. Volume indicates trading activity. Price vs Range shows where the price sits between today's high and low. Momentum compares recent prices to earlier ones.")

                    infoSection(icon: "exclamationmark.triangle", color: .orange,
                                title: "Not Financial Advice",
                                detail: "Signals are simple heuristics based on price data. They are not buy/sell recommendations. Always do your own research. This is a paper trading app for learning — no real money is at risk.")

                    infoSection(icon: "chart.bar", color: .purple,
                                title: "Key Stats",
                                detail: "Day High/Low: The highest and lowest prices today. Prev Close: Yesterday's closing price. Volume: How many shares traded today — higher volume often means stronger price moves.")

                    infoSection(icon: "briefcase", color: .green,
                                title: "Your Position",
                                detail: "If you own shares, you'll see your average cost, current value, and profit/loss. Tap Buy or Sell to trade directly from this screen.")

                    infoSection(icon: "plus.circle", color: .cyan,
                                title: "Watchlist",
                                detail: "Tap the + icon in the top right to add this stock to your watchlist for easy tracking on the Markets tab.")
                }
                .padding()
            }
            .navigationTitle("Understanding This Screen")
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
