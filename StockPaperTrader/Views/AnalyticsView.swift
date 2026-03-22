import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isWide: Bool { sizeClass == .regular }

    private var winningTrades: [Trade] {
        portfolio.tradeHistory.filter { $0.type == .sell && ($0.realizedPL ?? 0) > 0 }
    }

    private var losingTrades: [Trade] {
        portfolio.tradeHistory.filter { $0.type == .sell && ($0.realizedPL ?? 0) < 0 }
    }

    private var winRate: Double {
        let sells = portfolio.tradeHistory.filter { $0.type == .sell }
        guard !sells.isEmpty else { return 0 }
        let wins = sells.filter { ($0.realizedPL ?? 0) > 0 }.count
        return (Double(wins) / Double(sells.count)) * 100
    }

    private var avgTradeSize: Double {
        guard !portfolio.tradeHistory.isEmpty else { return 0 }
        return portfolio.tradeHistory.reduce(0) { $0 + $1.total } / Double(portfolio.tradeHistory.count)
    }

    private var avgWin: Double {
        guard !winningTrades.isEmpty else { return 0 }
        return winningTrades.compactMap(\.realizedPL).reduce(0, +) / Double(winningTrades.count)
    }

    private var avgLoss: Double {
        guard !losingTrades.isEmpty else { return 0 }
        return losingTrades.compactMap(\.realizedPL).reduce(0, +) / Double(losingTrades.count)
    }

    private var totalTrades: Int { portfolio.tradeHistory.count }
    private var buyCount: Int { portfolio.tradeHistory.filter { $0.type == .buy }.count }
    private var sellCount: Int { portfolio.tradeHistory.filter { $0.type == .sell }.count }
    private var autoCount: Int { portfolio.tradeHistory.filter { $0.isAutomated }.count }

    private var biggestPosition: Position? {
        portfolio.positions.max(by: { $0.marketValue < $1.marketValue })
    }

    private var bestPerformer: Position? {
        portfolio.positions.max(by: { $0.profitLossPercent < $1.profitLossPercent })
    }

    private var worstPerformer: Position? {
        portfolio.positions.min(by: { $0.profitLossPercent < $1.profitLossPercent })
    }

    private var totalInvested: Double {
        portfolio.positions.reduce(0) { $0 + $1.totalCost }
    }

    private var totalMarketValue: Double {
        portfolio.positions.reduce(0) { $0 + $1.marketValue }
    }

    private var unrealizedPL: Double {
        totalMarketValue - totalInvested
    }

    private var portfolioAllocation: [(String, Double)] {
        guard totalMarketValue > 0 else { return [] }
        return portfolio.positions.map { ($0.symbol, ($0.marketValue / totalMarketValue) * 100) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // iPad: performance + allocation side by side
                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        performanceCard.frame(maxWidth: .infinity)
                        if !portfolio.positions.isEmpty {
                            allocationCard.frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    performanceCard
                    if !portfolio.positions.isEmpty {
                        allocationCard
                    }
                }

                // iPad: position stats + trade stats side by side
                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        if !portfolio.positions.isEmpty {
                            positionStatsCard.frame(maxWidth: .infinity)
                        }
                        tradeStatsCard.frame(maxWidth: .infinity)
                    }
                } else {
                    if !portfolio.positions.isEmpty {
                        positionStatsCard
                    }
                    tradeStatsCard
                }

                // Win/Loss breakdown
                if sellCount > 0 {
                    winLossCard
                }

                // Recent performance
                if !portfolio.positions.isEmpty {
                    topMoversCard
                }
            }
            .padding()
        }
        .navigationTitle("Analytics")
    }

    private var performanceCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Performance")
                    .font(.headline)
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: isWide ? 4 : 2), spacing: 12) {
                metricBox(title: "Total Value", value: portfolio.formatCurrency(portfolio.totalPortfolioValue), color: .primary)
                metricBox(title: "Total P&L", value: String(format: "%+.2f%%", portfolio.totalProfitLossPercent),
                          color: portfolio.totalProfitLoss >= 0 ? .green : .red)
                metricBox(title: "Cash", value: portfolio.formatCurrency(portfolio.cash), color: .blue)
                metricBox(title: "Invested", value: portfolio.formatCurrency(totalInvested), color: .orange)
                metricBox(title: "Unrealized P&L", value: portfolio.formatCurrency(unrealizedPL),
                          color: unrealizedPL >= 0 ? .green : .red)
                metricBox(title: "Realized P&L", value: portfolio.formatCurrency(portfolio.totalRealizedPL),
                          color: portfolio.totalRealizedPL >= 0 ? .green : .red)
                metricBox(title: "Win Rate", value: sellCount > 0 ? String(format: "%.0f%%", winRate) : "—",
                          color: winRate >= 50 ? .green : (sellCount > 0 ? .red : .secondary))
                metricBox(title: "Avg Trade", value: portfolio.formatCurrency(avgTradeSize), color: .purple)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allocation")
                .font(.headline)

            ForEach(portfolioAllocation, id: \.0) { symbol, pct in
                HStack {
                    Text(symbol)
                        .font(.subheadline.bold())
                        .frame(width: 50, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorForSymbol(symbol))
                            .frame(width: geo.size.width * (pct / 100))
                    }
                    .frame(height: 20)

                    Text(String(format: "%.1f%%", pct))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var positionStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Position Insights")
                .font(.headline)

            if let best = bestPerformer {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    Text("Best: \(best.symbol)")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%+.2f%%", best.profitLossPercent))
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                }
            }

            if let worst = worstPerformer {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.red)
                    Text("Worst: \(worst.symbol)")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%+.2f%%", worst.profitLossPercent))
                        .font(.subheadline.bold())
                        .foregroundStyle(worst.isPositive ? .green : .red)
                }
            }

            if let biggest = biggestPosition {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.blue)
                    Text("Largest: \(biggest.symbol)")
                        .font(.subheadline)
                    Spacer()
                    Text(portfolio.formatCurrency(biggest.marketValue))
                        .font(.subheadline.bold())
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var tradeStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trade Activity")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                miniStat(title: "Total", value: "\(totalTrades)", icon: "arrow.left.arrow.right")
                miniStat(title: "Buys", value: "\(buyCount)", icon: "arrow.down.circle")
                miniStat(title: "Sells", value: "\(sellCount)", icon: "arrow.up.circle")
                miniStat(title: "Auto", value: "\(autoCount)", icon: "bolt.fill")
                miniStat(title: "Manual", value: "\(totalTrades - autoCount)", icon: "hand.tap")
                miniStat(title: "Today", value: "\(tradesToday)", icon: "calendar")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var topMoversCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Movers")
                .font(.headline)

            let sorted = portfolio.positions.sorted { abs($0.profitLossPercent) > abs($1.profitLossPercent) }
            ForEach(sorted.prefix(5)) { pos in
                HStack {
                    Text(pos.symbol)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(portfolio.formatCurrency(pos.profitLoss))
                        .font(.caption.monospacedDigit())
                    Text(String(format: "%+.2f%%", pos.profitLossPercent))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(pos.isPositive ? .green : .red)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var winLossCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Win / Loss Breakdown")
                .font(.headline)

            // Win rate bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if winRate > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.green)
                            .frame(width: geo.size.width * (winRate / 100))
                    }
                    if winRate < 100 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.red)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(winningTrades.count) Wins", systemImage: "arrow.up.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    if avgWin > 0 {
                        Text("Avg: +\(portfolio.formatCurrency(avgWin))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .center, spacing: 4) {
                    Text(String(format: "%.0f%%", winRate))
                        .font(.title2.bold())
                        .foregroundStyle(winRate >= 50 ? .green : .red)
                    Text("Win Rate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label("\(losingTrades.count) Losses", systemImage: "arrow.down.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    if avgLoss < 0 {
                        Text("Avg: \(portfolio.formatCurrency(avgLoss))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers
    private var tradesToday: Int {
        let cal = Calendar.current
        return portfolio.tradeHistory.filter { cal.isDateInToday($0.date) }.count
    }

    private func metricBox(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func miniStat(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func colorForSymbol(_ symbol: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .cyan, .pink, .yellow, .mint, .indigo, .teal]
        let hash = abs(symbol.hashValue)
        return colors[hash % colors.count]
    }
}
