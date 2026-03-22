import SwiftUI

/// Standalone chart view for Mac multi-window support.
/// Reads its config from ChartWindowStore by UUID.
struct ChartWindowView: View {
    let windowID: UUID
    @StateObject private var store = ChartWindowStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let config = store.configs[windowID] {
            chartContent(config)
                .onDisappear {
                    store.remove(windowID)
                }
        } else {
            ContentUnavailableView("Chart Not Found",
                                   systemImage: "chart.xyaxis.line",
                                   description: Text("This chart window has expired."))
        }
    }

    @ViewBuilder
    private func chartContent(_ config: ChartWindowConfig) -> some View {
        let closes = config.chartData.map(\.close)
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if let q = config.quote {
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

                    widgetContent(config: config, closes: closes, height: geo.size.height - 100)
                        .padding(.horizontal, 8)
                }
            }
            .navigationTitle("\(config.symbol) — \(config.widget.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        #if canImport(UIKit)
                        ChartWindowManager.shared.closeWindow(id: windowID)
                        #endif
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func widgetContent(config: ChartWindowConfig, closes: [Double], height: CGFloat) -> some View {
        switch config.widget {
        case .priceChart:
            if config.chartStyle == "Line" {
                InteractiveLineChartView(data: config.chartData, timeframe: config.timeframe)
                    .frame(height: max(300, height))
            } else {
                InteractiveCandlestickChartView(data: config.chartData, timeframe: config.timeframe)
                    .frame(height: max(300, height))
            }

        case .volumeBars:
            VolumeBarView(data: config.chartData)
                .frame(height: max(200, height))

        case .movingAverages:
            let sma20 = TechnicalIndicators.sma(closes, period: 20)
            let sma50 = TechnicalIndicators.sma(closes, period: 50)
            VStack(spacing: 8) {
                MAChartView(data: config.chartData, sma20: sma20, sma50: sma50)
                    .frame(height: max(250, height - 40))
                HStack(spacing: 16) {
                    Label("SMA 20: \(String(format: "%.2f", sma20.last ?? 0))", systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                    Label("SMA 50: \(String(format: "%.2f", sma50.last ?? 0))", systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(.purple)
                }
            }

        case .bollingerBands:
            let bb = TechnicalIndicators.bollingerBands(closes, period: 20, multiplier: 2.0)
            VStack(spacing: 8) {
                BollingerChartView(data: config.chartData, upper: bb.upper, middle: bb.middle, lower: bb.lower)
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
            let rsiValues = TechnicalIndicators.rsi(closes, period: 14)
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
            let macdResult = TechnicalIndicators.macd(closes)
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
            Text("This widget doesn't have a chart view.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared Chart Indicator Functions
enum TechnicalIndicators {
    static func sma(_ data: [Double], period: Int) -> [Double] {
        guard data.count >= period else { return [] }
        var result: [Double] = []
        for i in (period - 1)..<data.count {
            let slice = data[(i - period + 1)...i]
            result.append(slice.reduce(0, +) / Double(period))
        }
        return result
    }

    static func ema(_ data: [Double], period: Int) -> [Double] {
        guard !data.isEmpty else { return [] }
        let k = 2.0 / Double(period + 1)
        var result: [Double] = [data[0]]
        for i in 1..<data.count {
            result.append(data[i] * k + result[i - 1] * (1 - k))
        }
        return result
    }

    static func bollingerBands(_ data: [Double], period: Int, multiplier: Double) -> (upper: [Double], middle: [Double], lower: [Double]) {
        let mid = sma(data, period: period)
        guard mid.count > 0 else { return ([], [], []) }
        var upper: [Double] = []
        var lower: [Double] = []
        let offset = data.count - mid.count
        for (i, m) in mid.enumerated() {
            let slice = Array(data[(i + offset - (period - 1))...(i + offset)])
            let mean = m
            let variance = slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(period)
            let sd = sqrt(variance)
            upper.append(m + multiplier * sd)
            lower.append(m - multiplier * sd)
        }
        return (upper, mid, lower)
    }

    static func rsi(_ data: [Double], period: Int) -> [Double] {
        guard data.count > period else { return [] }
        var gains: [Double] = []
        var losses: [Double] = []
        for i in 1..<data.count {
            let change = data[i] - data[i - 1]
            gains.append(max(0, change))
            losses.append(max(0, -change))
        }
        guard gains.count >= period else { return [] }
        var avgGain = gains[0..<period].reduce(0, +) / Double(period)
        var avgLoss = losses[0..<period].reduce(0, +) / Double(period)
        var result: [Double] = []
        if avgLoss == 0 { result.append(100) }
        else { result.append(100 - 100 / (1 + avgGain / avgLoss)) }
        for i in period..<gains.count {
            avgGain = (avgGain * Double(period - 1) + gains[i]) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + losses[i]) / Double(period)
            if avgLoss == 0 { result.append(100) }
            else { result.append(100 - 100 / (1 + avgGain / avgLoss)) }
        }
        return result
    }

    static func macd(_ data: [Double]) -> TradingDashboardView.MACDResult {
        let ema12 = ema(data, period: 12)
        let ema26 = ema(data, period: 26)
        guard ema12.count == ema26.count else {
            return TradingDashboardView.MACDResult(macdLine: [], signalLine: [], histogram: [])
        }
        let macdLine = zip(ema12, ema26).map { $0 - $1 }
        let signal = ema(macdLine, period: 9)
        let minLen = min(macdLine.count, signal.count)
        let offset = macdLine.count - minLen
        let histogram = (0..<minLen).map { macdLine[$0 + offset] - signal[$0 + (signal.count - minLen)] }
        return TradingDashboardView.MACDResult(macdLine: macdLine, signalLine: signal, histogram: histogram)
    }
}
