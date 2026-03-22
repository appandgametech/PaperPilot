import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var automationEngine: AutomationEngine
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Throttle warning
                    if stockService.isThrottled, let msg = stockService.throttleMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(msg).font(.caption)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Safety controls summary
                    if portfolio.safetyControls.dailyLossEnabled || portfolio.safetyControls.tradesPerDayEnabled {
                        safetyStatusCard
                    }

                    marketStatusBanner

                    // Hub-specific header
                    hubHeader

                    portfolioCard

                    // Hub-specific features
                    switch portfolio.activeHub {
                    case .paper:
                        paperHubContent
                    case .equities:
                        alpacaHubContent
                    case .futures:
                        futuresHubContent
                    }

                    // Shared: positions, trades, automation
                    if !portfolio.positions.isEmpty {
                        positionsSection
                    }

                    if isWide {
                        HStack(alignment: .top, spacing: 16) {
                            if !portfolio.tradeHistory.isEmpty {
                                recentTradesSection.frame(maxWidth: .infinity)
                            }
                            automationStatusCard.frame(maxWidth: .infinity)
                        }
                    } else {
                        if !portfolio.tradeHistory.isEmpty {
                            recentTradesSection
                        }
                        automationStatusCard
                    }

                    if portfolio.positions.isEmpty && portfolio.tradeHistory.isEmpty {
                        gettingStartedCard
                    }
                }
                .padding()
            }
            .navigationTitle(portfolio.activeHub.rawValue)
            .refreshable {
                await stockService.refreshAll()
            }
        }
    }

    // MARK: - Hub Header
    private var hubHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: portfolio.activeHub.icon)
                .font(.title3)
                .foregroundStyle(portfolio.activeHub.accentColor)
                .frame(width: 36, height: 36)
                .background(portfolio.activeHub.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(portfolio.activeHub.broker)
                    .font(.subheadline.bold())
                Text(portfolio.activeHub.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if portfolio.isLiveTrading {
                Text("LIVE")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
            } else {
                Text(portfolio.activeHub == .paper ? "Simulator" : "Paper")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(portfolio.activeHub.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(portfolio.activeHub.accentColor.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Paper Hub Content
    private var paperHubContent: some View {
        VStack(spacing: 12) {
            // Paper-specific: Yahoo data info + top movers
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Simulation Active")
                        .font(.caption.bold())
                    Text("No account needed · Yahoo market data · Unlimited practice")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            if stockService.quotes.count >= 3 {
                topMoversSection
            }

            if portfolio.portfolioHistory.count >= 2 {
                portfolioChartCard
            }
        }
    }

    // MARK: - Alpaca Hub Content
    private var alpacaHubContent: some View {
        VStack(spacing: 12) {
            // Connection status
            HStack(spacing: 10) {
                Image(systemName: portfolio.alpacaConnectionStatus.icon)
                    .foregroundStyle(portfolio.alpacaConnectionStatus.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alpaca \(portfolio.alpacaConnectionStatus.rawValue)")
                        .font(.caption.bold())
                    Text(portfolio.equitiesPortfolio.isLiveMode
                         ? "Live trading · Real money · Stocks, Options, Crypto"
                         : "Paper trading · Simulated · Stocks, Options, Crypto")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if portfolio.alpacaConnectionStatus == .disconnected {
                    Text("Set up in Settings")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .padding(10)
            .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            // Alpaca features
            alpacaFeaturesCard

            if stockService.quotes.count >= 3 {
                topMoversSection
            }

            if portfolio.portfolioHistory.count >= 2 {
                portfolioChartCard
            }
        }
    }

    // MARK: - Futures Hub Content
    private var futuresHubContent: some View {
        VStack(spacing: 12) {
            // Connection status
            HStack(spacing: 10) {
                Image(systemName: portfolio.ninjaTraderConnectionStatus.icon)
                    .foregroundStyle(portfolio.ninjaTraderConnectionStatus.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NinjaTrader \(portfolio.ninjaTraderConnectionStatus.rawValue)")
                        .font(.caption.bold())
                    Text(portfolio.futuresPortfolio.isLiveMode
                         ? "Live trading · Real money · Futures, Commodities"
                         : "Demo trading · Simulated · Futures, Commodities")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if portfolio.ninjaTraderConnectionStatus == .disconnected {
                    Text("Set up in Settings")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(10)
            .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            // Futures features
            futuresFeaturesCard

            if portfolio.portfolioHistory.count >= 2 {
                portfolioChartCard
            }
        }
    }

    // MARK: - Alpaca Features Card
    private var alpacaFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alpaca Features").font(.caption.bold()).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                featureChip(icon: "chart.line.uptrend.xyaxis", text: "Stocks", color: .blue)
                featureChip(icon: "bitcoinsign.circle", text: "Crypto", color: .orange)
                featureChip(icon: "divide.circle", text: "Fractional Shares", color: .purple)
                featureChip(icon: "doc.text", text: "Paper/Live Toggle", color: .green)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Futures Features Card
    private var futuresFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NinjaTrader Features").font(.caption.bold()).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                featureChip(icon: "bolt.horizontal.fill", text: "Futures", color: .orange)
                featureChip(icon: "cube.box", text: "Commodities", color: .brown)
                featureChip(icon: "server.rack", text: "Tradovate API", color: .blue)
                featureChip(icon: "shield.checkered", text: "Demo/Live", color: .green)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func featureChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Safety Status Card
    private var safetyStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(.green)
                Text("Safety Controls").font(.caption.bold())
                Spacer()
                if portfolio.safetyControls.emergencyStopEnabled {
                    Text("STOPPED")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
            HStack(spacing: 16) {
                if portfolio.safetyControls.tradesPerDayEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trades Today").font(.caption2).foregroundStyle(.secondary)
                        Text("\(portfolio.todayTradeCount)/\(portfolio.safetyControls.maxTradesPerDay)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(portfolio.todayTradeCount >= portfolio.safetyControls.maxTradesPerDay ? .red : .primary)
                    }
                }
                if portfolio.safetyControls.dailyLossEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily P&L").font(.caption2).foregroundStyle(.secondary)
                        Text(portfolio.formatCurrency(portfolio.todayPL))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(portfolio.todayPL < 0 ? .red : .green)
                    }
                }
                if portfolio.safetyControls.positionSizeEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max Position").font(.caption2).foregroundStyle(.secondary)
                        Text(portfolio.formatCurrency(portfolio.safetyControls.maxPositionSize))
                            .font(.caption.bold().monospacedDigit())
                    }
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Market Status
    private var marketStatusBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isMarketOpen ? .green : .red)
                .frame(width: 8, height: 8)
            Text(isMarketOpen ? "Market Open" : "Market Closed")
                .font(.caption.bold())
                .foregroundStyle(isMarketOpen ? .green : .secondary)
            Spacer()
            Text(Date(), format: .dateTime.weekday(.wide).hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var isMarketOpen: Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        guard weekday >= 2 && weekday <= 6 else { return false }
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let totalMinutes = hour * 60 + minute
        return totalMinutes >= 570 && totalMinutes < 960
    }

    // MARK: - Getting Started
    private var gettingStartedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: portfolio.activeHub.icon)
                .font(.system(size: 36))
                .foregroundStyle(portfolio.activeHub.accentColor)
            Text("Ready to start trading?")
                .font(.headline)
            Text(gettingStartedText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                switch portfolio.activeHub {
                case .paper:
                    quickTip(icon: "magnifyingglass", color: .blue, title: "Browse Markets",
                             detail: "Check the Markets tab to explore stocks and add them to your watchlist.")
                    quickTip(icon: "chart.xyaxis.line", color: .purple, title: "Analyze Charts",
                             detail: "Use the Charts tab for technical analysis with RSI, MACD, and more.")
                    quickTip(icon: "arrow.left.arrow.right", color: .green, title: "Place a Trade",
                             detail: "Go to the Trade tab and tap + to buy your first stock.")
                    quickTip(icon: "gearshape.2", color: .orange, title: "Set Up Automation",
                             detail: "Create rules to auto-trade when conditions are met.")
                case .equities:
                    quickTip(icon: "key.fill", color: .blue, title: "Connect Alpaca",
                             detail: "Go to Settings and enter your Alpaca API keys to get started.")
                    quickTip(icon: "arrow.left.arrow.right", color: .green, title: "Trade Stocks & Crypto",
                             detail: "Buy and sell equities, options, and crypto through Alpaca.")
                    quickTip(icon: "divide.circle", color: .purple, title: "Fractional Shares",
                             detail: "Invest any dollar amount — Alpaca supports fractional shares.")
                case .futures:
                    quickTip(icon: "key.fill", color: .orange, title: "Connect NinjaTrader",
                             detail: "Go to Settings and enter your Tradovate credentials.")
                    quickTip(icon: "bolt.horizontal.fill", color: .orange, title: "Trade Futures",
                             detail: "Execute futures and commodities trades through NinjaTrader.")
                    quickTip(icon: "shield.checkered", color: .green, title: "Start with Demo",
                             detail: "Use Demo mode first to test your strategies risk-free.")
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var gettingStartedText: String {
        switch portfolio.activeHub {
        case .paper:
            return "You have \(portfolio.formatCurrency(portfolio.cash)) in virtual cash. Practice trading risk-free."
        case .equities:
            return "Connect your Alpaca account to trade stocks, options, and crypto."
        case .futures:
            return "Connect NinjaTrader to trade futures and commodities."
        }
    }

    private func quickTip(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Portfolio Chart
    private var portfolioChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Portfolio History")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Canvas { context, size in
                let values = portfolio.portfolioHistory.map(\.totalValue)
                guard values.count >= 2 else { return }
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 1
                let range = maxV - minV
                guard range > 0 else { return }
                let stepX = size.width / CGFloat(values.count - 1)
                let isUp = (values.last ?? 0) >= (values.first ?? 0)
                let color: Color = isUp ? .green : .red

                var fill = Path()
                for (i, val) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = size.height - ((val - minV) / range) * size.height
                    if i == 0 { fill.move(to: CGPoint(x: x, y: y)) }
                    else { fill.addLine(to: CGPoint(x: x, y: y)) }
                }
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                context.fill(fill, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.25), color.opacity(0)]),
                    startPoint: .init(x: 0, y: 0), endPoint: .init(x: 0, y: size.height)))

                var line = Path()
                for (i, val) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = size.height - ((val - minV) / range) * size.height
                    if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                    else { line.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(line, with: .color(color), lineWidth: 2)
            }
            .frame(height: isWide ? 120 : 80)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Portfolio Card
    private var portfolioCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio Value")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(portfolio.formatCurrency(portfolio.totalPortfolioValue))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("P&L")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(portfolio.formatCurrency(portfolio.totalProfitLoss))
                        .font(.title3.bold())
                        .foregroundStyle(portfolio.totalProfitLoss >= 0 ? .green : .red)
                    Text(String(format: "%+.2f%%", portfolio.totalProfitLossPercent))
                        .font(.caption)
                        .foregroundStyle(portfolio.totalProfitLoss >= 0 ? .green : .red)
                }
            }
            Divider()
            HStack {
                Label(portfolio.formatCurrency(portfolio.cash), systemImage: "banknote")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Label("\(portfolio.positions.count) positions", systemImage: "chart.bar")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if portfolio.totalRealizedPL != 0 {
                HStack {
                    Label("Realized P&L", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(portfolio.formatCurrency(portfolio.totalRealizedPL))
                        .font(.caption.bold())
                        .foregroundStyle(portfolio.totalRealizedPL >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Positions
    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions").font(.headline)
            ForEach(portfolio.positions) { position in
                NavigationLink(destination: StockDetailView(symbol: position.symbol)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(position.symbol).font(.headline)
                            Text("\(portfolio.formatShares(position.shares)) shares @ \(portfolio.formatCurrency(position.averageCost))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(portfolio.formatCurrency(position.marketValue))
                                .font(.subheadline.bold())
                            Text(String(format: "%+.2f%%", position.profitLossPercent))
                                .font(.caption.bold())
                                .foregroundStyle(position.isPositive ? .green : .red)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 6)
                if position.id != portfolio.positions.last?.id { Divider() }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent Trades
    private var recentTradesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Trades").font(.headline)
            ForEach(portfolio.tradeHistory.prefix(5)) { trade in
                HStack {
                    Image(systemName: trade.type == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .foregroundStyle(trade.type == .buy ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(trade.type.rawValue) \(trade.symbol)")
                            .font(.subheadline.bold())
                        Text("\(portfolio.formatShares(trade.shares)) shares @ \(portfolio.formatCurrency(trade.price))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(portfolio.formatCurrency(trade.total)).font(.subheadline)
                        if let pl = trade.realizedPL {
                            Text(String(format: "%+.2f", pl))
                                .font(.caption2.bold())
                                .foregroundStyle(pl >= 0 ? .green : .red)
                        } else if trade.isAutomated {
                            Label("Auto", systemImage: "bolt.fill")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                        Text(trade.date, style: .relative)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Top Movers
    private var topMoversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Movers").font(.headline)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Gainers", systemImage: "arrow.up.right")
                        .font(.caption.bold()).foregroundStyle(.green)
                    ForEach(portfolio.topGainers(quotes: stockService.quotes)) { q in
                        HStack {
                            Text(q.symbol).font(.caption.bold())
                            Spacer()
                            Text(String(format: "%+.1f%%", q.changePercent))
                                .font(.caption.monospacedDigit()).foregroundStyle(.green)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Losers", systemImage: "arrow.down.right")
                        .font(.caption.bold()).foregroundStyle(.red)
                    ForEach(portfolio.topLosers(quotes: stockService.quotes)) { q in
                        HStack {
                            Text(q.symbol).font(.caption.bold())
                            Spacer()
                            Text(String(format: "%+.1f%%", q.changePercent))
                                .font(.caption.monospacedDigit()).foregroundStyle(.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Automation Status
    private var automationStatusCard: some View {
        let hubRuleCount = automationEngine.rules.filter { rule in
            guard let ruleHub = rule.hub else { return true }
            return ruleHub == portfolio.activeHub.rawValue && rule.isEnabled
        }.count

        return HStack {
            Image(systemName: automationEngine.isRunning ? "bolt.circle.fill" : "bolt.slash.circle")
                .font(.title2)
                .foregroundStyle(automationEngine.isRunning ? .green : .secondary)
            VStack(alignment: .leading) {
                Text("Automation").font(.subheadline.bold())
                Text(automationEngine.isRunning ? "\(hubRuleCount) active \(portfolio.activeHub.rawValue) rules" : "Stopped")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { automationEngine.isRunning },
                set: { $0 ? automationEngine.startEngine() : automationEngine.stopEngine() }
            ))
            .labelsHidden()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
