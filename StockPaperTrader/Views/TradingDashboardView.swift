import SwiftUI

struct TradingDashboardView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedSymbol: String = "AAPL"
    @State private var chartData: [ChartDataPoint] = []
    @State private var timeframe: ChartTimeframe = .oneDay
    @State private var isLoadingChart = false
    @State private var showWidgetPicker = false
    @State private var chartStyle: ChartStyle = .line
    @State private var showChartInfo = false
    @State private var fullscreenWidget: DashboardWidget? = nil
    @State private var enabledWidgets: Set<DashboardWidget> = [
        .priceChart, .volumeBars, .dayRange, .stats, .rsi
    ]

    private var isWide: Bool { sizeClass == .regular }

    enum ChartStyle: String, CaseIterable {
        case line = "Line"
        case candle = "Candle"
    }

    private var quote: StockQuote? { stockService.quotes[selectedSymbol] }

    var body: some View {
        NavigationStack {
            Group {
                if !hubIsConnected {
                    notConnectedView
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Symbol picker
                            symbolBar

                            // Price header
                            if let q = quote {
                                priceHeader(q)
                            }

                            // Timeframe + chart style
                            controlBar

                            // Widgets — adaptive layout
                            let activeWidgets = DashboardWidget.allCases.filter { enabledWidgets.contains($0) }
                            if isWide {
                                // iPad: price chart full width, then 2-col grid for the rest
                                if activeWidgets.contains(.priceChart) {
                                    widgetView(.priceChart)
                                }
                                let remaining = activeWidgets.filter { $0 != .priceChart }
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(remaining) { widget in
                                        widgetView(widget)
                                    }
                                }
                            } else {
                                ForEach(activeWidgets) { widget in
                                    widgetView(widget)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("\(portfolio.activeHub.rawValue) Charts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showChartInfo = true } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showWidgetPicker = true } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadChart() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showWidgetPicker) {
                WidgetPickerSheet(enabledWidgets: $enabledWidgets)
            }
            .sheet(isPresented: $showChartInfo) {
                ChartInfoSheet()
            }
            #if !targetEnvironment(macCatalyst)
            .fullScreenCover(item: $fullscreenWidget) { widget in
                FullScreenChartSheet(
                    widget: widget,
                    chartData: chartData,
                    chartStyle: chartStyle,
                    timeframe: timeframe,
                    quote: quote,
                    symbol: selectedSymbol,
                    smaCompute: { data, period in sma(data, period: period) },
                    emaCompute: { data, period in ema(data, period: period) },
                    bbCompute: { data, period, mult in bollingerBands(data, period: period, multiplier: mult) },
                    rsiCompute: { data, period in computeRSI(data, period: period) },
                    macdCompute: { data in computeMACD(data) }
                )
            }
            #endif
            .task {
                // Set default symbol based on hub
                if portfolio.activeHub == .futures && !stockService.futuresSymbols.contains(selectedSymbol) {
                    selectedSymbol = stockService.futuresSymbols.first ?? "ES=F"
                }
                await loadChart()
            }
            .onChange(of: timeframe) { _, _ in Task { @MainActor in await loadChart() } }
            .onChange(of: selectedSymbol) { _, _ in Task { @MainActor in await loadChart() } }
        }
    }

    // Hub-specific default symbols — no commingling
    private var hubSymbols: [String] {
        stockService.watchlistForHub(portfolio.activeHub)
    }

    // Whether the current hub has valid credentials
    private var hubIsConnected: Bool {
        switch portfolio.activeHub {
        case .paper: return true
        case .equities: return !stockService.alpacaApiKey.isEmpty && !stockService.alpacaSecretKey.isEmpty
        case .futures: return !stockService.ntUsername.isEmpty && !stockService.ntPassword.isEmpty
        }
    }

    // MARK: - Symbol Bar
    private var symbolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(hubSymbols, id: \.self) { sym in
                    Button {
                        selectedSymbol = sym
                    } label: {
                        VStack(spacing: 2) {
                            Text(sym)
                                .font(.caption.bold())
                            if let q = stockService.quotes[sym] {
                                Text(String(format: "%+.1f%%", q.changePercent))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(q.isPositive ? .green : .red)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedSymbol == sym ? portfolio.activeHub.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedSymbol == sym ? portfolio.activeHub.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func priceHeader(_ q: StockQuote) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(q.name).font(.caption).foregroundStyle(.secondary)
                Text(String(format: "$%.2f", q.price))
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: q.isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(String(format: "%+.2f", q.change))
                        .font(.subheadline.bold().monospacedDigit())
                }
                .foregroundStyle(q.isPositive ? .green : .red)
                Text(String(format: "%+.2f%%", q.changePercent))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(q.isPositive ? .green : .red)
            }
        }
    }

    private var controlBar: some View {
        HStack {
            // Timeframe
            ForEach(ChartTimeframe.allCases, id: \.self) { tf in
                Button {
                    timeframe = tf
                } label: {
                    Text(tf.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(timeframe == tf ? portfolio.activeHub.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(timeframe == tf ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            // Chart style toggle
            Picker("", selection: $chartStyle) {
                Image(systemName: "chart.xyaxis.line").tag(ChartStyle.line)
                Image(systemName: "chart.bar.doc.horizontal").tag(ChartStyle.candle)
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
        }
    }

    private func loadChart() async {
        // Each hub uses ONLY its own data source — zero commingling
        guard hubIsConnected else {
            chartData = []
            isLoadingChart = false
            return
        }
        isLoadingChart = true
        chartData = await stockService.fetchChartDataForHub(portfolio.activeHub, symbol: selectedSymbol, timeframe: timeframe)
        isLoadingChart = false
    }

    // MARK: - Widget Router
    @ViewBuilder
    private func widgetView(_ widget: DashboardWidget) -> some View {
        switch widget {
        case .priceChart:
            chartWidget
        case .volumeBars:
            volumeWidget
        case .movingAverages:
            movingAveragesWidget
        case .bollingerBands:
            bollingerWidget
        case .rsi:
            rsiWidget
        case .macd:
            macdWidget
        case .dayRange:
            if let q = quote { dayRangeWidget(q) }
        case .stats:
            if let q = quote { statsWidget(q) }
        case .position:
            positionWidget
        case .tradeHistory:
            tradeHistoryWidget
        }
    }

    // MARK: - Price Chart
    private var chartWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Price").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                expandButton(.priceChart)
            }
            if isLoadingChart {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else if chartData.isEmpty {
                Text("No chart data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                if chartStyle == .line {
                    InteractiveLineChartView(data: chartData, timeframe: timeframe)
                        .frame(height: 280)
                } else {
                    InteractiveCandlestickChartView(data: chartData, timeframe: timeframe)
                        .frame(height: 280)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Volume
    private var volumeWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Volume").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                expandButton(.volumeBars)
            }
            if chartData.isEmpty {
                Text("—").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VolumeBarView(data: chartData).frame(height: 60)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Moving Averages
    private var movingAveragesWidget: some View {
        let closes = chartData.map(\.close)
        let sma20 = sma(closes, period: 20)
        let sma50 = sma(closes, period: 50)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Moving Averages").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                expandButton(.movingAverages)
            }
            if chartData.count >= 20 {
                MAChartView(data: chartData, sma20: sma20, sma50: sma50).frame(height: 150)
                HStack(spacing: 16) {
                    Label("SMA 20: \(String(format: "%.2f", sma20.last ?? 0))", systemImage: "circle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                    Label("SMA 50: \(String(format: "%.2f", sma50.last ?? 0))", systemImage: "circle.fill")
                        .font(.caption2).foregroundStyle(.purple)
                }
            } else {
                Text("Need 20+ data points").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bollinger Bands
    private var bollingerWidget: some View {
        let closes = chartData.map(\.close)
        let bb = bollingerBands(closes, period: 20)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bollinger Bands (20, 2)").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                expandButton(.bollingerBands)
            }
            if bb.upper.count >= 2 {
                BollingerChartView(data: chartData, upper: bb.upper, middle: bb.middle, lower: bb.lower)
                    .frame(height: 150)
                HStack(spacing: 12) {
                    miniLabel("Upper", value: bb.upper.last ?? 0, color: .red)
                    miniLabel("Mid", value: bb.middle.last ?? 0, color: .blue)
                    miniLabel("Lower", value: bb.lower.last ?? 0, color: .green)
                }
            } else {
                Text("Need 20+ data points").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - RSI
    private var rsiWidget: some View {
        let closes = chartData.map(\.close)
        let rsiValues = computeRSI(closes, period: 14)
        let currentRSI = rsiValues.last ?? 50
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RSI (14)").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", currentRSI))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(currentRSI > 70 ? .red : currentRSI < 30 ? .green : .primary)
                expandButton(.rsi)
            }
            if rsiValues.count >= 2 {
                RSIChartView(values: rsiValues).frame(height: 80)
                HStack {
                    Text("Oversold < 30").font(.caption2).foregroundStyle(.green)
                    Spacer()
                    Text(currentRSI > 70 ? "Overbought" : currentRSI < 30 ? "Oversold" : "Neutral")
                        .font(.caption2.bold())
                        .foregroundStyle(currentRSI > 70 ? .red : currentRSI < 30 ? .green : .secondary)
                    Spacer()
                    Text("Overbought > 70").font(.caption2).foregroundStyle(.red)
                }
            } else {
                Text("Need 14+ data points").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - MACD
    private var macdWidget: some View {
        let closes = chartData.map(\.close)
        let macdResult = computeMACD(closes)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MACD (12, 26, 9)").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if let last = macdResult.histogram.last {
                    Text(String(format: "%.2f", last))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(last >= 0 ? .green : .red)
                }
                expandButton(.macd)
            }
            if macdResult.macdLine.count >= 2 {
                MACDChartView(macd: macdResult).frame(height: 100)
                HStack(spacing: 16) {
                    Label("MACD", systemImage: "circle.fill").font(.caption2).foregroundStyle(.blue)
                    Label("Signal", systemImage: "circle.fill").font(.caption2).foregroundStyle(.orange)
                    Label("Histogram", systemImage: "square.fill").font(.caption2).foregroundStyle(.gray)
                }
            } else {
                Text("Need 26+ data points").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Day Range
    private func dayRangeWidget(_ q: StockQuote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day Range").font(.caption.bold()).foregroundStyle(.secondary)
            GeometryReader { geo in
                let range = q.dayHigh - q.dayLow
                let pct = range > 0 ? (q.price - q.dayLow) / range : 0.5
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 8)
                    Capsule().fill(
                        LinearGradient(colors: [.red, .yellow, .green], startPoint: .leading, endPoint: .trailing)
                    ).frame(width: geo.size.width, height: 8)
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .shadow(radius: 2)
                        .offset(x: max(0, min(geo.size.width - 14, geo.size.width * pct - 7)))
                }
            }
            .frame(height: 14)
            HStack {
                Text(String(format: "$%.2f", q.dayLow)).font(.caption2.monospacedDigit()).foregroundStyle(.red)
                Spacer()
                Text(String(format: "$%.2f", q.price)).font(.caption2.bold().monospacedDigit())
                Spacer()
                Text(String(format: "$%.2f", q.dayHigh)).font(.caption2.monospacedDigit()).foregroundStyle(.green)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats
    private func statsWidget(_ q: StockQuote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Stats").font(.caption.bold()).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                statCell("Open", String(format: "$%.2f", chartData.first?.open ?? q.previousClose))
                statCell("High", String(format: "$%.2f", q.dayHigh))
                statCell("Low", String(format: "$%.2f", q.dayLow))
                statCell("Prev Close", String(format: "$%.2f", q.previousClose))
                statCell("Volume", formatVol(q.volume))
                statCell("Mkt Cap", formatVol(q.marketCap > 0 ? Int64(q.marketCap) : 0))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Position
    private var positionWidget: some View {
        Group {
            if let pos = portfolio.positions.first(where: { $0.symbol == selectedSymbol }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Position").font(.caption.bold()).foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(portfolio.formatShares(pos.shares)) shares")
                                .font(.subheadline.bold())
                            Text("Avg: \(portfolio.formatCurrency(pos.averageCost))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(portfolio.formatCurrency(pos.marketValue)).font(.subheadline.bold())
                            Text(String(format: "%+.2f%%", pos.profitLossPercent))
                                .font(.caption.bold())
                                .foregroundStyle(pos.isPositive ? .green : .red)
                        }
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack {
                    Image(systemName: "briefcase").foregroundStyle(.secondary)
                    Text("No position in \(selectedSymbol)").font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Trade History
    private var tradeHistoryWidget: some View {
        let trades = portfolio.tradeHistory.filter { $0.symbol == selectedSymbol }.prefix(5)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent Trades").font(.caption.bold()).foregroundStyle(.secondary)
            if trades.isEmpty {
                Text("No trades for \(selectedSymbol)").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(trades)) { trade in
                    HStack {
                        Image(systemName: trade.type == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .foregroundStyle(trade.type == .buy ? .green : .red)
                            .font(.caption)
                        Text("\(trade.type.rawValue) \(portfolio.formatShares(trade.shares))")
                            .font(.caption)
                        Spacer()
                        Text(portfolio.formatCurrency(trade.price)).font(.caption.monospacedDigit())
                        Text(trade.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers
    private func miniLabel(_ title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(color)
            Text(String(format: "%.2f", value)).font(.caption2.monospacedDigit())
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold().monospacedDigit())
        }
    }

    private func formatVol(_ v: Int64) -> String {
        if v >= 1_000_000_000_000 { return String(format: "%.1fT", Double(v) / 1e12) }
        if v >= 1_000_000_000 { return String(format: "%.1fB", Double(v) / 1e9) }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1e6) }
        if v >= 1_000 { return String(format: "%.0fK", Double(v) / 1e3) }
        return "\(v)"
    }

    // MARK: - Not Connected View
    private var notConnectedView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: portfolio.activeHub == .equities ? "key.fill" : "bolt.horizontal.fill")
                .font(.system(size: 48))
                .foregroundStyle(portfolio.activeHub.accentColor.opacity(0.5))
            Text(portfolio.activeHub == .equities ? "Connect Alpaca" : "Connect NinjaTrader")
                .font(.title2.bold())
            Text(portfolio.activeHub == .equities
                 ? "Enter your Alpaca API keys in Settings to view charts and trade."
                 : "Enter your NinjaTrader credentials in Settings to start trading futures.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text("Go to Settings")
            }
            .font(.subheadline.bold())
            .foregroundStyle(portfolio.activeHub.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Expand Button
    private func expandButton(_ widget: DashboardWidget) -> some View {
        Button {
            #if targetEnvironment(macCatalyst)
            let config = ChartWindowConfig(
                id: UUID(),
                widget: widget,
                chartData: chartData,
                chartStyle: chartStyle.rawValue,
                timeframe: timeframe,
                quote: quote,
                symbol: selectedSymbol
            )
            ChartWindowManager.shared.openChartWindow(config: config)
            #else
            fullscreenWidget = widget
            #endif
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
                .background(Color.secondary.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Technical Indicators
    private func sma(_ data: [Double], period: Int) -> [Double] {
        guard data.count >= period else { return [] }
        var result: [Double] = []
        for i in (period - 1)..<data.count {
            let slice = data[(i - period + 1)...i]
            result.append(slice.reduce(0, +) / Double(period))
        }
        return result
    }

    private func ema(_ data: [Double], period: Int) -> [Double] {
        guard !data.isEmpty else { return [] }
        let k = 2.0 / Double(period + 1)
        var result: [Double] = [data[0]]
        for i in 1..<data.count {
            result.append(data[i] * k + result[i - 1] * (1 - k))
        }
        return result
    }

    private func bollingerBands(_ data: [Double], period: Int, multiplier: Double = 2.0) -> (upper: [Double], middle: [Double], lower: [Double]) {
        let mid = sma(data, period: period)
        guard mid.count > 0 else { return ([], [], []) }
        var upper: [Double] = []
        var lower: [Double] = []
        let offset = data.count - mid.count
        for i in 0..<mid.count {
            let slice = Array(data[(i + offset - period + 1)...(i + offset)])
            let mean = mid[i]
            let variance = slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(period)
            let std = sqrt(variance)
            upper.append(mean + multiplier * std)
            lower.append(mean - multiplier * std)
        }
        return (upper, mid, lower)
    }

    private func computeRSI(_ data: [Double], period: Int) -> [Double] {
        guard data.count > period else { return [] }
        var gains: [Double] = []
        var losses: [Double] = []
        for i in 1..<data.count {
            let diff = data[i] - data[i - 1]
            gains.append(max(0, diff))
            losses.append(max(0, -diff))
        }
        guard gains.count >= period else { return [] }
        var avgGain = gains[0..<period].reduce(0, +) / Double(period)
        var avgLoss = losses[0..<period].reduce(0, +) / Double(period)
        var rsi: [Double] = []
        let rs = avgLoss > 0 ? avgGain / avgLoss : 100
        rsi.append(100 - 100 / (1 + rs))
        for i in period..<gains.count {
            avgGain = (avgGain * Double(period - 1) + gains[i]) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + losses[i]) / Double(period)
            let rs = avgLoss > 0 ? avgGain / avgLoss : 100
            rsi.append(100 - 100 / (1 + rs))
        }
        return rsi
    }

    struct MACDResult {
        let macdLine: [Double]
        let signalLine: [Double]
        let histogram: [Double]
    }

    private func computeMACD(_ data: [Double]) -> MACDResult {
        let ema12 = ema(data, period: 12)
        let ema26 = ema(data, period: 26)
        guard ema12.count == ema26.count else { return MACDResult(macdLine: [], signalLine: [], histogram: []) }
        let macdLine = zip(ema12, ema26).map { $0 - $1 }
        let signal = ema(macdLine, period: 9)
        let minLen = min(macdLine.count, signal.count)
        let offset = macdLine.count - minLen
        let histogram = (0..<minLen).map { macdLine[$0 + offset] - signal[$0 + (signal.count - minLen)] }
        return MACDResult(macdLine: macdLine, signalLine: signal, histogram: histogram)
    }
}


// MARK: - Full Screen Chart Sheet
struct FullScreenChartSheet: View {
    let widget: DashboardWidget
    let chartData: [ChartDataPoint]
    let chartStyle: TradingDashboardView.ChartStyle
    let timeframe: ChartTimeframe
    let quote: StockQuote?
    let symbol: String
    let smaCompute: ([Double], Int) -> [Double]
    let emaCompute: ([Double], Int) -> [Double]
    let bbCompute: ([Double], Int, Double) -> (upper: [Double], middle: [Double], lower: [Double])
    let rsiCompute: ([Double], Int) -> [Double]
    let macdCompute: ([Double]) -> TradingDashboardView.MACDResult

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if let q = quote {
                        HStack {
                            Text(q.name).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", q.price))
                                .font(.headline.bold().monospacedDigit())
                            Text(String(format: "%+.2f%%", q.changePercent))
                                .font(.caption.bold())
                                .foregroundStyle(q.isPositive ? .green : .red)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    fullscreenContent(height: geo.size.height - 100)
                        .padding(.horizontal, 8)
                }
            }
            .navigationTitle("\(symbol) — \(widget.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func fullscreenContent(height: CGFloat) -> some View {
        let closes = chartData.map(\.close)

        switch widget {
        case .priceChart:
            if chartStyle == .line {
                InteractiveLineChartView(data: chartData, timeframe: timeframe)
                    .frame(height: max(300, height))
            } else {
                InteractiveCandlestickChartView(data: chartData, timeframe: timeframe)
                    .frame(height: max(300, height))
            }

        case .volumeBars:
            VolumeBarView(data: chartData)
                .frame(height: max(200, height))

        case .movingAverages:
            let sma20 = smaCompute(closes, 20)
            let sma50 = smaCompute(closes, 50)
            VStack(spacing: 8) {
                MAChartView(data: chartData, sma20: sma20, sma50: sma50)
                    .frame(height: max(250, height - 40))
                HStack(spacing: 16) {
                    Label("SMA 20: \(String(format: "%.2f", sma20.last ?? 0))", systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                    Label("SMA 50: \(String(format: "%.2f", sma50.last ?? 0))", systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(.purple)
                }
            }

        case .bollingerBands:
            let bb = bbCompute(closes, 20, 2.0)
            VStack(spacing: 8) {
                BollingerChartView(data: chartData, upper: bb.upper, middle: bb.middle, lower: bb.lower)
                    .frame(height: max(250, height - 40))
                HStack(spacing: 12) {
                    VStack(spacing: 1) {
                        Text("Upper").font(.caption2).foregroundStyle(.red)
                        Text(String(format: "%.2f", bb.upper.last ?? 0)).font(.caption2.monospacedDigit())
                    }
                    VStack(spacing: 1) {
                        Text("Mid").font(.caption2).foregroundStyle(.blue)
                        Text(String(format: "%.2f", bb.middle.last ?? 0)).font(.caption2.monospacedDigit())
                    }
                    VStack(spacing: 1) {
                        Text("Lower").font(.caption2).foregroundStyle(.green)
                        Text(String(format: "%.2f", bb.lower.last ?? 0)).font(.caption2.monospacedDigit())
                    }
                }
            }

        case .rsi:
            let rsiValues = rsiCompute(closes, 14)
            let currentRSI = rsiValues.last ?? 50
            VStack(spacing: 8) {
                RSIChartView(values: rsiValues)
                    .frame(height: max(200, height - 50))
                HStack {
                    Text("Oversold < 30").font(.caption).foregroundStyle(.green)
                    Spacer()
                    Text(String(format: "RSI: %.1f", currentRSI))
                        .font(.headline.bold().monospacedDigit())
                        .foregroundStyle(currentRSI > 70 ? .red : currentRSI < 30 ? .green : .primary)
                    Spacer()
                    Text("Overbought > 70").font(.caption).foregroundStyle(.red)
                }
            }

        case .macd:
            let macdResult = macdCompute(closes)
            VStack(spacing: 8) {
                MACDChartView(macd: macdResult)
                    .frame(height: max(200, height - 50))
                HStack(spacing: 16) {
                    Label("MACD", systemImage: "circle.fill").font(.caption).foregroundStyle(.blue)
                    Label("Signal", systemImage: "circle.fill").font(.caption).foregroundStyle(.orange)
                    Label("Histogram", systemImage: "square.fill").font(.caption).foregroundStyle(.gray)
                    Spacer()
                    if let last = macdResult.histogram.last {
                        Text(String(format: "%.2f", last))
                            .font(.headline.bold().monospacedDigit())
                            .foregroundStyle(last >= 0 ? .green : .red)
                    }
                }
            }

        default:
            Text("This widget doesn't have a fullscreen view.")
                .foregroundStyle(.secondary)
        }
    }
}


// MARK: - Widget Picker
struct WidgetPickerSheet: View {
    @Binding var enabledWidgets: Set<DashboardWidget>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Customize your dashboard. Toggle widgets on/off.") {
                    ForEach(DashboardWidget.allCases) { widget in
                        Toggle(isOn: Binding(
                            get: { enabledWidgets.contains(widget) },
                            set: { enabled in
                                if enabled { enabledWidgets.insert(widget) }
                                else { enabledWidgets.remove(widget) }
                            }
                        )) {
                            Label(widget.rawValue, systemImage: widget.icon)
                        }
                    }
                }
            }
            .navigationTitle("Dashboard Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Chart Helpers
struct ChartLayout {
    static let yAxisWidth: CGFloat = 52
    static let xAxisHeight: CGFloat = 20
    static let gridLineCount = 5

    static func priceFormat(_ value: Double) -> String {
        if value >= 1000 { return String(format: "$%.0f", value) }
        if value >= 100 { return String(format: "$%.1f", value) }
        return String(format: "$%.2f", value)
    }

    static func timeLabel(for date: Date, timeframe: ChartTimeframe) -> String {
        let f = DateFormatter()
        switch timeframe {
        case .oneDay:
            f.dateFormat = "h:mma"
        case .fiveDay:
            f.dateFormat = "E ha"
        case .oneMonth:
            f.dateFormat = "MMM d"
        case .threeMonth, .sixMonth:
            f.dateFormat = "MMM d"
        case .oneYear:
            f.dateFormat = "MMM yy"
        }
        return f.string(from: date).lowercased()
    }

    static func crosshairTime(for date: Date, timeframe: ChartTimeframe) -> String {
        let f = DateFormatter()
        switch timeframe {
        case .oneDay:
            f.dateFormat = "h:mm:ss a"
        case .fiveDay:
            f.dateFormat = "E, MMM d h:mm a"
        default:
            f.dateFormat = "MMM d, yyyy"
        }
        return f.string(from: date)
    }
}

// MARK: - Interactive Line Chart
struct InteractiveLineChartView: View {
    let data: [ChartDataPoint]
    let timeframe: ChartTimeframe

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var crosshairIndex: Int? = nil
    @State private var isDragging = false

    private var visibleData: [ChartDataPoint] {
        let count = data.count
        let visibleCount = max(10, Int(CGFloat(count) / scale))
        let startIdx = max(0, count - visibleCount)
        return Array(data[startIdx..<count])
    }

    var body: some View {
        VStack(spacing: 0) {
            crosshairBar.frame(height: 20)

            HStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack {
                        Canvas { context, size in
                            drawLineChart(context: context, size: size)
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(dragGesture(in: geo.size))
                        .simultaneousGesture(magnificationGesture)

                        if let idx = crosshairIndex, idx >= 0, idx < visibleData.count {
                            crosshairOverlay(at: idx, size: geo.size)
                        }
                    }
                }
                yAxisLabels.frame(width: ChartLayout.yAxisWidth)
            }

            xAxisLabels
                .frame(height: ChartLayout.xAxisHeight)
                .padding(.trailing, ChartLayout.yAxisWidth)
        }
    }

    private var crosshairBar: some View {
        Group {
            if let idx = crosshairIndex, idx >= 0, idx < visibleData.count {
                let pt = visibleData[idx]
                HStack(spacing: 8) {
                    Text(ChartLayout.crosshairTime(for: pt.date, timeframe: timeframe))
                        .font(.caption2.bold())
                    Spacer()
                    Text("O:\(ChartLayout.priceFormat(pt.open))")
                        .font(.caption2.monospacedDigit())
                    Text("H:\(ChartLayout.priceFormat(pt.high))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.green)
                    Text("L:\(ChartLayout.priceFormat(pt.low))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.red)
                    Text("C:\(ChartLayout.priceFormat(pt.close))")
                        .font(.caption2.monospacedDigit().bold())
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            } else {
                HStack {
                    #if targetEnvironment(macCatalyst)
                    Text("Click & drag for crosshair · Scroll to zoom")
                    #else
                    Text("Long press for crosshair · Pinch to zoom")
                    #endif
                }
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
            }
        }
    }

    private func drawLineChart(context: GraphicsContext, size: CGSize) {
        let vd = visibleData
        guard vd.count >= 2 else { return }
        let closes = vd.map(\.close)
        let padding: CGFloat = 8
        let minY = (closes.min() ?? 0) * 0.999
        let maxY = (closes.max() ?? 1) * 1.001
        let range = maxY - minY
        guard range > 0 else { return }
        let chartH = size.height - padding * 2

        // Gridlines
        for i in 0...ChartLayout.gridLineCount {
            let y = padding + chartH * CGFloat(i) / CGFloat(ChartLayout.gridLineCount)
            var gp = Path()
            gp.move(to: CGPoint(x: 0, y: y))
            gp.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(gp, with: .color(.secondary.opacity(0.1)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        }

        let stepX = size.width / CGFloat(vd.count - 1)
        let isPositive = (closes.last ?? 0) >= (closes.first ?? 0)
        let lineColor: Color = isPositive ? .green : .red

        // Fill
        var fillPath = Path()
        for (i, val) in closes.enumerated() {
            let x = CGFloat(i) * stepX
            let y = padding + chartH - ((val - minY) / range) * chartH
            if i == 0 { fillPath.move(to: CGPoint(x: x, y: y)) }
            else { fillPath.addLine(to: CGPoint(x: x, y: y)) }
        }
        fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
        fillPath.addLine(to: CGPoint(x: 0, y: size.height))
        fillPath.closeSubpath()
        context.fill(fillPath, with: .linearGradient(
            Gradient(colors: [lineColor.opacity(0.25), lineColor.opacity(0.0)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)
        ))

        // Line
        var linePath = Path()
        for (i, val) in closes.enumerated() {
            let x = CGFloat(i) * stepX
            let y = padding + chartH - ((val - minY) / range) * chartH
            if i == 0 { linePath.move(to: CGPoint(x: x, y: y)) }
            else { linePath.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(linePath, with: .color(lineColor), lineWidth: 2)

        // High/Low markers
        if let maxVal = closes.max(), let maxIdx = closes.firstIndex(of: maxVal) {
            let x = CGFloat(maxIdx) * stepX
            let y = padding + chartH - ((maxVal - minY) / range) * chartH
            context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(.green))
            let label = Text("H:\(ChartLayout.priceFormat(maxVal))").font(.system(size: 8).monospacedDigit()).foregroundColor(.green)
            context.draw(context.resolve(label), at: CGPoint(x: x, y: y - 10), anchor: .bottom)
        }
        if let minVal = closes.min(), let minIdx = closes.firstIndex(of: minVal) {
            let x = CGFloat(minIdx) * stepX
            let y = padding + chartH - ((minVal - minY) / range) * chartH
            context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(.red))
            let label = Text("L:\(ChartLayout.priceFormat(minVal))").font(.system(size: 8).monospacedDigit()).foregroundColor(.red)
            context.draw(context.resolve(label), at: CGPoint(x: x, y: y + 10), anchor: .top)
        }
    }

    private func crosshairOverlay(at idx: Int, size: CGSize) -> some View {
        let vd = visibleData
        let closes = vd.map(\.close)
        let padding: CGFloat = 8
        let minY = (closes.min() ?? 0) * 0.999
        let maxY = (closes.max() ?? 1) * 1.001
        let range = maxY - minY
        let chartH = size.height - padding * 2
        let stepX = size.width / CGFloat(max(1, vd.count - 1))
        let x = CGFloat(idx) * stepX
        let y = range > 0 ? padding + chartH - ((closes[idx] - minY) / range) * chartH : size.height / 2

        return ZStack {
            Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                .stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                .stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            Circle().fill(.white).frame(width: 8, height: 8).shadow(color: .blue, radius: 3).position(x: x, y: y)
            Text(ChartLayout.priceFormat(closes[idx]))
                .font(.caption2.bold().monospacedDigit())
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(.blue, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .position(x: min(max(30, x), size.width - 30), y: max(16, y - 16))
        }
        .allowsHitTesting(false)
    }

    private var yAxisLabels: some View {
        let closes = visibleData.map(\.close)
        let minY = (closes.min() ?? 0) * 0.999
        let maxY = (closes.max() ?? 1) * 1.001
        return GeometryReader { geo in
            let padding: CGFloat = 8
            let chartH = geo.size.height - padding * 2
            ForEach(0...ChartLayout.gridLineCount, id: \.self) { i in
                let frac = CGFloat(i) / CGFloat(ChartLayout.gridLineCount)
                let value = maxY - (maxY - minY) * Double(frac)
                let y = padding + chartH * frac
                Text(ChartLayout.priceFormat(value))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .position(x: ChartLayout.yAxisWidth / 2, y: y)
            }
        }
    }

    private var xAxisLabels: some View {
        GeometryReader { geo in
            let vd = visibleData
            let count = vd.count
            if count >= 2 {
                let labelCount = min(5, count)
                let step = max(1, count / labelCount)
                ForEach(0..<labelCount, id: \.self) { i in
                    let idx = min(i * step, count - 1)
                    let x = geo.size.width * CGFloat(idx) / CGFloat(count - 1)
                    Text(ChartLayout.timeLabel(for: vd[idx].date, timeframe: timeframe))
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .position(x: x, y: ChartLayout.xAxisHeight / 2)
                }
            }
        }
    }

    private func crosshairGestureIndex(location: CGPoint, size: CGSize) -> Int {
        let vd = visibleData
        guard vd.count >= 2 else { return 0 }
        let stepX = size.width / CGFloat(vd.count - 1)
        return max(0, min(vd.count - 1, Int(round(location.x / stepX))))
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        #if targetEnvironment(macCatalyst)
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                crosshairIndex = crosshairGestureIndex(location: drag.location, size: size)
                isDragging = true
            }
            .onEnded { _ in
                isDragging = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !isDragging { crosshairIndex = nil }
                }
            }
        #else
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    guard let drag else { return }
                    crosshairIndex = crosshairGestureIndex(location: drag.location, size: size)
                    isDragging = true
                default: break
                }
            }
            .onEnded { _ in
                isDragging = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !isDragging { crosshairIndex = nil }
                }
            }
        #endif
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = min(10, max(1, lastScale * value)) }
            .onEnded { _ in lastScale = scale }
    }
}

// MARK: - Interactive Candlestick Chart
struct InteractiveCandlestickChartView: View {
    let data: [ChartDataPoint]
    let timeframe: ChartTimeframe

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var crosshairIndex: Int? = nil
    @State private var isDragging = false

    private var visibleData: [ChartDataPoint] {
        let count = data.count
        let visibleCount = max(10, Int(CGFloat(count) / scale))
        let startIdx = max(0, count - visibleCount)
        return Array(data[startIdx..<count])
    }

    var body: some View {
        VStack(spacing: 0) {
            crosshairBar.frame(height: 20)

            HStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack {
                        Canvas { context, size in
                            drawCandlestickChart(context: context, size: size)
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(dragGesture(in: geo.size))
                        .simultaneousGesture(magnificationGesture)

                        if let idx = crosshairIndex, idx >= 0, idx < visibleData.count {
                            candleCrosshairOverlay(at: idx, size: geo.size)
                        }
                    }
                }
                yAxisLabels.frame(width: ChartLayout.yAxisWidth)
            }

            xAxisLabels
                .frame(height: ChartLayout.xAxisHeight)
                .padding(.trailing, ChartLayout.yAxisWidth)
        }
    }

    private var crosshairBar: some View {
        Group {
            if let idx = crosshairIndex, idx >= 0, idx < visibleData.count {
                let pt = visibleData[idx]
                HStack(spacing: 8) {
                    Text(ChartLayout.crosshairTime(for: pt.date, timeframe: timeframe))
                        .font(.caption2.bold())
                    Spacer()
                    Text("O:\(ChartLayout.priceFormat(pt.open))")
                        .font(.caption2.monospacedDigit())
                    Text("H:\(ChartLayout.priceFormat(pt.high))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.green)
                    Text("L:\(ChartLayout.priceFormat(pt.low))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.red)
                    Text("C:\(ChartLayout.priceFormat(pt.close))")
                        .font(.caption2.monospacedDigit().bold())
                    Text("V:\(formatVolShort(pt.volume))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            } else {
                HStack {
                    #if targetEnvironment(macCatalyst)
                    Text("Click & drag for crosshair · Scroll to zoom")
                    #else
                    Text("Long press for crosshair · Pinch to zoom")
                    #endif
                }
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
            }
        }
    }

    private func drawCandlestickChart(context: GraphicsContext, size: CGSize) {
        let vd = visibleData
        guard vd.count >= 2 else { return }
        let allPrices = vd.flatMap { [$0.high, $0.low] }
        let padding: CGFloat = 8
        let minY = (allPrices.min() ?? 0) * 0.999
        let maxY = (allPrices.max() ?? 1) * 1.001
        let range = maxY - minY
        guard range > 0 else { return }
        let chartH = size.height - padding * 2

        // Gridlines
        for i in 0...ChartLayout.gridLineCount {
            let y = padding + chartH * CGFloat(i) / CGFloat(ChartLayout.gridLineCount)
            var gp = Path()
            gp.move(to: CGPoint(x: 0, y: y))
            gp.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(gp, with: .color(.secondary.opacity(0.1)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        }

        let candleWidth = max(2, (size.width / CGFloat(vd.count)) * 0.6)
        let stepX = size.width / CGFloat(vd.count)

        for (i, point) in vd.enumerated() {
            let x = CGFloat(i) * stepX + stepX / 2
            let isGreen = point.close >= point.open
            let color: Color = isGreen ? .green : .red

            let highY = padding + chartH - ((point.high - minY) / range) * chartH
            let lowY = padding + chartH - ((point.low - minY) / range) * chartH
            var wick = Path()
            wick.move(to: CGPoint(x: x, y: highY))
            wick.addLine(to: CGPoint(x: x, y: lowY))
            context.stroke(wick, with: .color(color), lineWidth: 1)

            let openY = padding + chartH - ((point.open - minY) / range) * chartH
            let closeY = padding + chartH - ((point.close - minY) / range) * chartH
            let bodyTop = min(openY, closeY)
            let bodyHeight = max(1, abs(closeY - openY))
            let bodyRect = CGRect(x: x - candleWidth / 2, y: bodyTop, width: candleWidth, height: bodyHeight)
            context.fill(Path(bodyRect), with: .color(color))
        }
    }

    private func candleCrosshairOverlay(at idx: Int, size: CGSize) -> some View {
        let vd = visibleData
        let allPrices = vd.flatMap { [$0.high, $0.low] }
        let padding: CGFloat = 8
        let minY = (allPrices.min() ?? 0) * 0.999
        let maxY = (allPrices.max() ?? 1) * 1.001
        let range = maxY - minY
        let chartH = size.height - padding * 2
        let stepX = size.width / CGFloat(vd.count)
        let x = CGFloat(idx) * stepX + stepX / 2
        let y = range > 0 ? padding + chartH - ((vd[idx].close - minY) / range) * chartH : size.height / 2

        return ZStack {
            Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                .stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                .stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            Circle().fill(.white).frame(width: 8, height: 8).shadow(color: .blue, radius: 3).position(x: x, y: y)
            Text(ChartLayout.priceFormat(vd[idx].close))
                .font(.caption2.bold().monospacedDigit())
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(.blue, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .position(x: min(max(30, x), size.width - 30), y: max(16, y - 16))
        }
        .allowsHitTesting(false)
    }

    private var yAxisLabels: some View {
        let allPrices = visibleData.flatMap { [$0.high, $0.low] }
        let minY = (allPrices.min() ?? 0) * 0.999
        let maxY = (allPrices.max() ?? 1) * 1.001
        return GeometryReader { geo in
            let padding: CGFloat = 8
            let chartH = geo.size.height - padding * 2
            ForEach(0...ChartLayout.gridLineCount, id: \.self) { i in
                let frac = CGFloat(i) / CGFloat(ChartLayout.gridLineCount)
                let value = maxY - (maxY - minY) * Double(frac)
                let y = padding + chartH * frac
                Text(ChartLayout.priceFormat(value))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .position(x: ChartLayout.yAxisWidth / 2, y: y)
            }
        }
    }

    private var xAxisLabels: some View {
        GeometryReader { geo in
            let vd = visibleData
            let count = vd.count
            if count >= 2 {
                let labelCount = min(5, count)
                let step = max(1, count / labelCount)
                ForEach(0..<labelCount, id: \.self) { i in
                    let idx = min(i * step, count - 1)
                    let x = geo.size.width * CGFloat(idx) / CGFloat(count - 1)
                    Text(ChartLayout.timeLabel(for: vd[idx].date, timeframe: timeframe))
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .position(x: x, y: ChartLayout.xAxisHeight / 2)
                }
            }
        }
    }

    private func crosshairGestureIndex(location: CGPoint, size: CGSize) -> Int {
        let vd = visibleData
        guard vd.count >= 2 else { return 0 }
        let stepX = size.width / CGFloat(vd.count)
        return max(0, min(vd.count - 1, Int(location.x / stepX)))
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        #if targetEnvironment(macCatalyst)
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                crosshairIndex = crosshairGestureIndex(location: drag.location, size: size)
                isDragging = true
            }
            .onEnded { _ in
                isDragging = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !isDragging { crosshairIndex = nil }
                }
            }
        #else
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    guard let drag else { return }
                    crosshairIndex = crosshairGestureIndex(location: drag.location, size: size)
                    isDragging = true
                default: break
                }
            }
            .onEnded { _ in
                isDragging = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !isDragging { crosshairIndex = nil }
                }
            }
        #endif
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = min(10, max(1, lastScale * value)) }
            .onEnded { _ in lastScale = scale }
    }

    private func formatVolShort(_ v: Int64) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1e6) }
        if v >= 1_000 { return String(format: "%.0fK", Double(v) / 1e3) }
        return "\(v)"
    }
}

// MARK: - Volume Bars
struct VolumeBarView: View {
    let data: [ChartDataPoint]

    var body: some View {
        Canvas { context, size in
            guard !data.isEmpty else { return }
            let maxVol = Double(data.map(\.volume).max() ?? 1)
            guard maxVol > 0 else { return }
            let barWidth = max(1, (size.width / CGFloat(data.count)) * 0.7)
            let stepX = size.width / CGFloat(data.count)

            for (i, point) in data.enumerated() {
                let x = CGFloat(i) * stepX + stepX / 2
                let h = (Double(point.volume) / maxVol) * size.height
                let isGreen = point.close >= point.open
                let rect = CGRect(x: x - barWidth / 2, y: size.height - h, width: barWidth, height: h)
                context.fill(Path(rect), with: .color(isGreen ? .green.opacity(0.5) : .red.opacity(0.5)))
            }
        }
    }
}

// MARK: - Moving Averages Chart
struct MAChartView: View {
    let data: [ChartDataPoint]
    let sma20: [Double]
    let sma50: [Double]

    var body: some View {
        Canvas { context, size in
            let closes = data.map(\.close)
            let all = closes + sma20 + sma50
            let minY = all.min() ?? 0
            let maxY = all.max() ?? 1
            let range = maxY - minY
            guard range > 0 else { return }

            // Price line
            drawLine(context: context, size: size, values: closes, minY: minY, range: range, color: .primary.opacity(0.4), width: 1)
            // SMA 20
            let offset20 = closes.count - sma20.count
            drawLine(context: context, size: size, values: sma20, minY: minY, range: range, color: .orange, width: 1.5, xOffset: offset20)
            // SMA 50
            if !sma50.isEmpty {
                let offset50 = closes.count - sma50.count
                drawLine(context: context, size: size, values: sma50, minY: minY, range: range, color: .purple, width: 1.5, xOffset: offset50)
            }
        }
    }

    private func drawLine(context: GraphicsContext, size: CGSize, values: [Double], minY: Double, range: Double, color: Color, width: CGFloat, xOffset: Int = 0) {
        guard values.count >= 2 else { return }
        let totalPoints = values.count + xOffset
        let stepX = size.width / CGFloat(max(1, totalPoints - 1))
        var path = Path()
        for (i, val) in values.enumerated() {
            let x = CGFloat(i + xOffset) * stepX
            let y = size.height - ((val - minY) / range) * size.height
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: width)
    }
}


// MARK: - Bollinger Bands Chart
struct BollingerChartView: View {
    let data: [ChartDataPoint]
    let upper: [Double]
    let middle: [Double]
    let lower: [Double]

    var body: some View {
        Canvas { context, size in
            let closes = data.map(\.close)
            let all = closes + upper + lower
            let minY = all.min() ?? 0
            let maxY = all.max() ?? 1
            let range = maxY - minY
            guard range > 0, upper.count >= 2 else { return }

            let offset = closes.count - upper.count
            let totalPts = closes.count
            let stepX = size.width / CGFloat(max(1, totalPts - 1))

            // Band fill
            var bandPath = Path()
            for i in 0..<upper.count {
                let x = CGFloat(i + offset) * stepX
                let y = size.height - ((upper[i] - minY) / range) * size.height
                if i == 0 { bandPath.move(to: CGPoint(x: x, y: y)) }
                else { bandPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            for i in stride(from: lower.count - 1, through: 0, by: -1) {
                let x = CGFloat(i + offset) * stepX
                let y = size.height - ((lower[i] - minY) / range) * size.height
                bandPath.addLine(to: CGPoint(x: x, y: y))
            }
            bandPath.closeSubpath()
            context.fill(bandPath, with: .color(.blue.opacity(0.08)))

            // Lines
            drawBBLine(context: context, size: size, values: upper, minY: minY, range: range, color: .red.opacity(0.5), offset: offset, stepX: stepX)
            drawBBLine(context: context, size: size, values: middle, minY: minY, range: range, color: .blue.opacity(0.5), offset: offset, stepX: stepX)
            drawBBLine(context: context, size: size, values: lower, minY: minY, range: range, color: .green.opacity(0.5), offset: offset, stepX: stepX)

            // Price
            drawBBLine(context: context, size: size, values: closes, minY: minY, range: range, color: .primary, offset: 0, stepX: stepX)
        }
    }

    private func drawBBLine(context: GraphicsContext, size: CGSize, values: [Double], minY: Double, range: Double, color: Color, offset: Int, stepX: CGFloat) {
        guard values.count >= 2 else { return }
        var path = Path()
        for (i, val) in values.enumerated() {
            let x = CGFloat(i + offset) * stepX
            let y = size.height - ((val - minY) / range) * size.height
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}

// MARK: - RSI Chart
struct RSIChartView: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            let stepX = size.width / CGFloat(values.count - 1)

            // Overbought / oversold zones
            let ob = size.height * (1 - 70.0 / 100.0)
            let os = size.height * (1 - 30.0 / 100.0)
            let obRect = CGRect(x: 0, y: 0, width: size.width, height: ob)
            let osRect = CGRect(x: 0, y: os, width: size.width, height: size.height - os)
            context.fill(Path(obRect), with: .color(.red.opacity(0.06)))
            context.fill(Path(osRect), with: .color(.green.opacity(0.06)))

            // 70 / 30 lines
            var line70 = Path(); line70.move(to: CGPoint(x: 0, y: ob)); line70.addLine(to: CGPoint(x: size.width, y: ob))
            var line30 = Path(); line30.move(to: CGPoint(x: 0, y: os)); line30.addLine(to: CGPoint(x: size.width, y: os))
            context.stroke(line70, with: .color(.red.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            context.stroke(line30, with: .color(.green.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

            // RSI line
            var path = Path()
            for (i, val) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - val / 100.0)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.purple), lineWidth: 1.5)
        }
    }
}

// MARK: - MACD Chart
struct MACDChartView: View {
    let macd: TradingDashboardView.MACDResult

    var body: some View {
        Canvas { context, size in
            let all = macd.macdLine + macd.signalLine + macd.histogram
            guard !all.isEmpty else { return }
            let maxAbs = max(abs(all.min() ?? 0), abs(all.max() ?? 0), 0.01)
            let midY = size.height / 2

            // Zero line
            var zeroLine = Path()
            zeroLine.move(to: CGPoint(x: 0, y: midY))
            zeroLine.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(zeroLine, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)

            // Histogram bars
            let histCount = macd.histogram.count
            if histCount > 0 {
                let barW = max(1, (size.width / CGFloat(histCount)) * 0.6)
                let stepX = size.width / CGFloat(histCount)
                for (i, val) in macd.histogram.enumerated() {
                    let x = CGFloat(i) * stepX + stepX / 2
                    let h = (abs(val) / maxAbs) * (size.height / 2)
                    let y = val >= 0 ? midY - h : midY
                    let rect = CGRect(x: x - barW / 2, y: y, width: barW, height: h)
                    context.fill(Path(rect), with: .color(val >= 0 ? .green.opacity(0.4) : .red.opacity(0.4)))
                }
            }

            // MACD line
            drawMACDLine(context: context, size: size, values: macd.macdLine, maxAbs: maxAbs, midY: midY, color: .blue, width: 1.5)
            // Signal line
            drawMACDLine(context: context, size: size, values: macd.signalLine, maxAbs: maxAbs, midY: midY, color: .orange, width: 1.5)
        }
    }

    private func drawMACDLine(context: GraphicsContext, size: CGSize, values: [Double], maxAbs: Double, midY: CGFloat, color: Color, width: CGFloat) {
        guard values.count >= 2 else { return }
        let stepX = size.width / CGFloat(values.count - 1)
        var path = Path()
        for (i, val) in values.enumerated() {
            let x = CGFloat(i) * stepX
            let y = midY - (val / maxAbs) * (size.height / 2)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: width)
    }
}


// MARK: - Chart Info Sheet
struct ChartInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Widget Customization").font(.subheadline.bold())
                            Text("Tap the grid icon in the toolbar to toggle widgets on or off. Choose which indicators and data panels appear on your dashboard.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.blue)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chart Types").font(.subheadline.bold())
                            Text("Line charts show closing prices as a smooth curve — great for spotting trends. Candlestick charts show open, high, low, and close for each period — ideal for reading price action and patterns.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Crosshair & Zoom").font(.subheadline.bold())
                            Text("Long press on the chart to activate the crosshair — drag to see exact OHLCV data for any point. Pinch to zoom in and see more detail. High and low points are automatically marked on the chart.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "scope")
                            .foregroundStyle(.cyan)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Timeframes").font(.subheadline.bold())
                            Text("Switch between 1D, 5D, 1M, 3M, 6M, 1Y, and 5Y to view different time horizons. Shorter timeframes show intraday detail, longer ones reveal macro trends.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Technical Indicators") {
                    indicatorRow(icon: "chart.line.uptrend.xyaxis", color: .orange, title: "Moving Averages (SMA 20 & 50)",
                                 desc: "Simple Moving Averages smooth out price data. When the 20-day crosses above the 50-day, it's a bullish signal (golden cross). The reverse is bearish (death cross).")

                    indicatorRow(icon: "waveform.path.ecg", color: .purple, title: "RSI (Relative Strength Index)",
                                 desc: "Measures momentum on a 0–100 scale. Above 70 = overbought (may drop). Below 30 = oversold (may bounce). The 14-period default balances sensitivity and reliability.")

                    indicatorRow(icon: "arrow.up.arrow.down", color: .blue, title: "MACD (12, 26, 9)",
                                 desc: "Shows the relationship between two EMAs. When the MACD line crosses above the signal line, it's bullish. The histogram visualizes the gap between them.")

                    indicatorRow(icon: "rectangle.compress.vertical", color: .teal, title: "Bollinger Bands (20, 2)",
                                 desc: "A middle SMA with upper/lower bands at 2 standard deviations. Price touching the upper band may be overbought; touching the lower may be oversold. Band width shows volatility.")
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Volume Bars").font(.subheadline.bold())
                            Text("Volume confirms price moves. Rising price with high volume = strong trend. Rising price with low volume = weak move that may reverse.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.indigo)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Day Range & Key Stats").font(.subheadline.bold())
                            Text("Day Range shows where the current price sits between today's high and low. Key Stats include open, high, low, previous close, volume, and market cap.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "ruler")
                            .foregroundStyle(.mint)
                    }
                }
            }
            .navigationTitle("Charts Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func indicatorRow(icon: String, color: Color, title: String, desc: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
    }
}
