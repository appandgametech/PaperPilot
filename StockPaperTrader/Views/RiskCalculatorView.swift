import SwiftUI

struct RiskCalculatorView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @EnvironmentObject var stockService: StockService
    @State private var symbol = ""
    @State private var riskPercent = "2"
    @State private var entryPrice = ""
    @State private var stopLossPrice = ""
    @State private var takeProfitPrice = ""

    private var currentPrice: Double {
        stockService.quotes[symbol.uppercased()]?.price ?? 0
    }

    private var entry: Double { Double(entryPrice) ?? currentPrice }
    private var stopLoss: Double { Double(stopLossPrice) ?? 0 }
    private var takeProfit: Double { Double(takeProfitPrice) ?? 0 }
    private var riskPct: Double { Double(riskPercent) ?? 2 }

    private var riskPerShare: Double { abs(entry - stopLoss) }
    private var rewardPerShare: Double { takeProfit > 0 ? abs(takeProfit - entry) : 0 }
    private var riskRewardRatio: Double {
        guard riskPerShare > 0 else { return 0 }
        return rewardPerShare / riskPerShare
    }

    private var calculation: (shares: Int, riskAmount: Double, positionValue: Double) {
        portfolio.calculatePositionSize(accountRiskPercent: riskPct, entryPrice: entry, stopLossPrice: stopLoss)
    }

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Calculate the right position size based on your risk tolerance. Never risk more than you can afford to lose on a single trade.")
                        .font(.caption).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "shield.checkered").foregroundStyle(.blue)
                }
            }

            Section("Account") {
                HStack {
                    Text("Portfolio Value")
                    Spacer()
                    Text(portfolio.formatCurrency(portfolio.totalPortfolioValue))
                        .font(.subheadline.bold().monospacedDigit())
                }
                HStack {
                    Text("Risk Per Trade")
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("%", text: $riskPercent)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("%")
                    }
                }
                HStack(spacing: 8) {
                    ForEach([1, 2, 3, 5], id: \.self) { pct in
                        Button("\(pct)%") {
                            riskPercent = "\(pct)"
                        }
                        .buttonStyle(.bordered)
                        .tint(riskPercent == "\(pct)" ? .blue : .secondary)
                        .font(.caption)
                    }
                }
            }

            Section("Trade Setup") {
                TextField("Symbol (e.g. AAPL)", text: $symbol)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: symbol) { _, newValue in
                        let upper = newValue.uppercased()
                        if stockService.quotes[upper] == nil && upper.count >= 1 {
                            Task { await stockService.fetchQuotes(for: [upper]) }
                        }
                        if currentPrice > 0 && entryPrice.isEmpty {
                            entryPrice = String(format: "%.2f", currentPrice)
                        }
                    }

                if currentPrice > 0 {
                    HStack {
                        Text("Current Price")
                        Spacer()
                        Text(portfolio.formatCurrency(currentPrice))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                TextField("Entry Price", text: $entryPrice)
                    .keyboardType(.decimalPad)
                TextField("Stop Loss Price", text: $stopLossPrice)
                    .keyboardType(.decimalPad)
                TextField("Take Profit Price (optional)", text: $takeProfitPrice)
                    .keyboardType(.decimalPad)

                if entry > 0 {
                    HStack(spacing: 8) {
                        ForEach([2, 5, 8, 10], id: \.self) { pct in
                            Button("SL -\(pct)%") {
                                stopLossPrice = String(format: "%.2f", entry * (1 - Double(pct) / 100))
                            }
                            .buttonStyle(.bordered).font(.caption2)
                        }
                    }
                }
            }

            if stopLoss > 0 && entry > 0 {
                Section("Results") {
                    resultRow("Max Risk Amount", portfolio.formatCurrency(calculation.riskAmount), color: .red)
                    resultRow("Position Size", "\(calculation.shares) shares", color: .blue)
                    resultRow("Position Value", portfolio.formatCurrency(calculation.positionValue), color: .primary)
                    resultRow("Risk Per Share", portfolio.formatCurrency(riskPerShare), color: .orange)

                    if takeProfit > 0 {
                        resultRow("Reward Per Share", portfolio.formatCurrency(rewardPerShare), color: .green)
                        HStack {
                            Text("Risk/Reward Ratio")
                            Spacer()
                            Text(String(format: "1 : %.1f", riskRewardRatio))
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(riskRewardRatio >= 2 ? .green : riskRewardRatio >= 1 ? .orange : .red)
                        }
                        // Visual bar
                        GeometryReader { geo in
                            let total = riskPerShare + rewardPerShare
                            let riskW = total > 0 ? CGFloat(riskPerShare / total) * geo.size.width : 0
                            HStack(spacing: 0) {
                                Rectangle().fill(.red.opacity(0.6)).frame(width: riskW)
                                Rectangle().fill(.green.opacity(0.6))
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 12)
                    }

                    // Verdict
                    if riskRewardRatio >= 2 {
                        Label("Good setup — reward outweighs risk by 2x+", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else if riskRewardRatio >= 1 && takeProfit > 0 {
                        Label("Acceptable — but aim for 2:1 or better", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    } else if takeProfit > 0 {
                        Label("Poor risk/reward — consider widening your target or tightening your stop", systemImage: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }

                    let pctOfPortfolio = portfolio.totalPortfolioValue > 0 ? (calculation.positionValue / portfolio.totalPortfolioValue) * 100 : 0
                    resultRow("% of Portfolio", String(format: "%.1f%%", pctOfPortfolio),
                              color: pctOfPortfolio > 25 ? .red : pctOfPortfolio > 10 ? .orange : .green)
                }
            }
        }
        .navigationTitle("Risk Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
