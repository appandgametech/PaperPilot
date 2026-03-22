import Foundation
import Combine
import UserNotifications
import SwiftUI

// MARK: - Trading Hub
enum TradingHub: String, CaseIterable, Codable, Identifiable {
    case paper = "Paper"
    case equities = "Equities"
    case futures = "Futures"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .paper: return "doc.text"
        case .equities: return "chart.line.uptrend.xyaxis"
        case .futures: return "bolt.horizontal.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .paper: return "Practice · No Account"
        case .equities: return "Stocks · Options · Crypto"
        case .futures: return "Futures · Commodities"
        }
    }

    var broker: String {
        switch self {
        case .paper: return "Local (Yahoo)"
        case .equities: return "Alpaca"
        case .futures: return "NinjaTrader"
        }
    }

    var accentColor: Color {
        switch self {
        case .paper: return .green
        case .equities: return .blue
        case .futures: return .orange
        }
    }

    var prefix: String { rawValue.lowercased() }
}

// MARK: - Broker Connection Status
enum BrokerConnectionStatus: String, Codable {
    case disconnected = "Disconnected"
    case connected = "Connected"
    case error = "Error"

    var icon: String {
        switch self {
        case .disconnected: return "xmark.circle"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connected: return .green
        case .error: return .red
        }
    }
}

// MARK: - Safety Controls
struct SafetyControls: Codable {
    var maxDailyLoss: Double = 0
    var maxPositionSize: Double = 0
    var maxTradesPerDay: Int = 0
    var emergencyStopEnabled: Bool = false
    var requireLiveConfirmation: Bool = true

    var dailyLossEnabled: Bool { maxDailyLoss > 0 }
    var positionSizeEnabled: Bool { maxPositionSize > 0 }
    var tradesPerDayEnabled: Bool { maxTradesPerDay > 0 }
}

// MARK: - Hub Portfolio (isolated per-hub state)
class HubPortfolio: ObservableObject {
    let hub: TradingHub

    @Published var cash: Double
    @Published var startingCash: Double
    @Published var positions: [Position] = []
    @Published var tradeHistory: [Trade] = []
    @Published var pendingOrders: [PendingOrder] = []
    @Published var portfolioHistory: [PortfolioSnapshot] = []
    @Published var totalRealizedPL: Double = 0
    @Published var priceAlerts: [PriceAlert] = []
    @Published var safetyControls: SafetyControls = SafetyControls()
    @Published var todayTradeCount: Int = 0
    @Published var todayPL: Double = 0
    @Published var isLiveMode: Bool = false

    var totalPortfolioValue: Double {
        cash + positions.reduce(0) { $0 + $1.marketValue }
    }
    var totalProfitLoss: Double { totalPortfolioValue - startingCash }
    var totalProfitLossPercent: Double {
        guard startingCash > 0 else { return 0 }
        return (totalProfitLoss / startingCash) * 100
    }

    private var p: String { hub.prefix }

    init(hub: TradingHub, defaultCash: Double = 100_000) {
        self.hub = hub
        self.cash = defaultCash
        self.startingCash = defaultCash
        load()
    }

    // MARK: - Safety
    func canExecuteTrade(shares: Double, price: Double, type: TradeType) -> (allowed: Bool, reason: String?) {
        if safetyControls.emergencyStopEnabled {
            return (false, "Emergency stop is active. Disable it in Settings to resume trading.")
        }
        if safetyControls.tradesPerDayEnabled && todayTradeCount >= safetyControls.maxTradesPerDay {
            return (false, "Daily trade limit reached (\(safetyControls.maxTradesPerDay)). Reset tomorrow or adjust in Settings.")
        }
        if safetyControls.dailyLossEnabled && todayPL <= -safetyControls.maxDailyLoss {
            return (false, "Daily loss limit reached. Trading paused until tomorrow.")
        }
        if safetyControls.positionSizeEnabled && type == .buy {
            if shares * price > safetyControls.maxPositionSize {
                return (false, "Order exceeds max position size.")
            }
        }
        return (true, nil)
    }

    func recalculateTodayStats() {
        let cal = Calendar.current
        let today = tradeHistory.filter { cal.isDateInToday($0.date) }
        todayTradeCount = today.count
        todayPL = today.compactMap(\.realizedPL).reduce(0, +)
    }

    // MARK: - Apply trades
    func applyBuy(trade: Trade) {
        cash -= trade.total
        tradeHistory.insert(trade, at: 0)
        if let idx = positions.firstIndex(where: { $0.symbol == trade.symbol }) {
            let existing = positions[idx]
            let totalShares = existing.shares + trade.shares
            let totalCost = (existing.shares * existing.averageCost) + (trade.shares * trade.price)
            positions[idx].shares = totalShares
            positions[idx].averageCost = totalCost / totalShares
            positions[idx].currentPrice = trade.price
        } else {
            positions.append(Position(symbol: trade.symbol, shares: trade.shares,
                                      averageCost: trade.price, currentPrice: trade.price))
        }
        save()
    }

    func applySell(trade: Trade, positionIndex: Int) {
        var t = trade
        let avgCost = positions[positionIndex].averageCost
        t.realizedPL = (trade.price - avgCost) * trade.shares
        cash += t.total
        tradeHistory.insert(t, at: 0)
        totalRealizedPL += t.realizedPL ?? 0
        positions[positionIndex].shares -= t.shares
        positions[positionIndex].currentPrice = t.price
        if positions[positionIndex].shares <= 0.0001 {
            positions.remove(at: positionIndex)
        }
        save()
    }

    func updatePositionPrices(quotes: [String: StockQuote]) {
        for i in positions.indices {
            if let q = quotes[positions[i].symbol] {
                positions[i].currentPrice = q.price
            }
        }
    }

    // MARK: - Pending Orders
    func placePendingOrder(_ order: PendingOrder) {
        pendingOrders.append(order)
        savePendingOrders()
    }

    func cancelPendingOrder(id: UUID) {
        pendingOrders.removeAll { $0.id == id }
        savePendingOrders()
    }

    // MARK: - Price Alerts
    func addPriceAlert(_ alert: PriceAlert) {
        priceAlerts.append(alert)
        savePriceAlerts()
    }

    func removePriceAlert(id: UUID) {
        priceAlerts.removeAll { $0.id == id }
        savePriceAlerts()
    }

    // MARK: - Snapshots
    func takeSnapshot() {
        let snap = PortfolioSnapshot(totalValue: totalPortfolioValue, cash: cash, positionCount: positions.count)
        portfolioHistory.append(snap)
        if portfolioHistory.count > 365 { portfolioHistory = Array(portfolioHistory.suffix(365)) }
        saveSnapshots()
    }

    // MARK: - Reset
    func reset(newCash: Double = 100_000) {
        startingCash = newCash
        cash = newCash
        positions = []
        tradeHistory = []
        pendingOrders = []
        portfolioHistory = []
        totalRealizedPL = 0
        todayTradeCount = 0
        todayPL = 0
        priceAlerts = []
        save()
        savePendingOrders()
        saveSnapshots()
        savePriceAlerts()
        saveSafetyControls()
    }

    // MARK: - Trade Journal
    func updateTradeNote(tradeId: UUID, note: String) {
        if let idx = tradeHistory.firstIndex(where: { $0.id == tradeId }) {
            tradeHistory[idx].note = note.isEmpty ? nil : note
            save()
        }
    }

    // MARK: - Export
    func exportTradesCSV() -> String {
        var csv = "Date,Type,Symbol,Shares,Price,Total,Automated,Realized P&L,Note\n"
        let fmt = ISO8601DateFormatter()
        for t in tradeHistory {
            let d = fmt.string(from: t.date)
            let pl = t.realizedPL.map { String(format: "%.2f", $0) } ?? ""
            let n = (t.note ?? "").replacingOccurrences(of: ",", with: ";")
            csv += "\(d),\(t.type.rawValue),\(t.symbol),\(t.shares),\(t.price),\(t.total),\(t.isAutomated),\(pl),\(n)\n"
        }
        return csv
    }

    // MARK: - Persistence
    func save() {
        UserDefaults.standard.set(cash, forKey: "\(p)_cash")
        UserDefaults.standard.set(startingCash, forKey: "\(p)_startingCash")
        UserDefaults.standard.set(totalRealizedPL, forKey: "\(p)_realizedPL")
        UserDefaults.standard.set(isLiveMode, forKey: "\(p)_isLiveMode")
        if let d = try? JSONEncoder().encode(positions) { UserDefaults.standard.set(d, forKey: "\(p)_positions") }
        if let d = try? JSONEncoder().encode(tradeHistory) { UserDefaults.standard.set(d, forKey: "\(p)_trades") }
    }

    private func load() {
        let c = UserDefaults.standard.double(forKey: "\(p)_cash")
        if c > 0 { cash = c }
        let s = UserDefaults.standard.double(forKey: "\(p)_startingCash")
        if s > 0 { startingCash = s }
        totalRealizedPL = UserDefaults.standard.double(forKey: "\(p)_realizedPL")
        isLiveMode = UserDefaults.standard.bool(forKey: "\(p)_isLiveMode")
        if let d = UserDefaults.standard.data(forKey: "\(p)_positions"),
           let saved = try? JSONDecoder().decode([Position].self, from: d) { positions = saved }
        if let d = UserDefaults.standard.data(forKey: "\(p)_trades"),
           let saved = try? JSONDecoder().decode([Trade].self, from: d) { tradeHistory = saved }
        let recalc = tradeHistory.compactMap(\.realizedPL).reduce(0, +)
        if abs(recalc - totalRealizedPL) > 0.01 { totalRealizedPL = recalc }
        loadPendingOrders()
        loadSnapshots()
        loadPriceAlerts()
        loadSafetyControls()
        recalculateTodayStats()
    }

    func savePendingOrders() {
        if let d = try? JSONEncoder().encode(pendingOrders) { UserDefaults.standard.set(d, forKey: "\(p)_pendingOrders") }
    }
    private func loadPendingOrders() {
        if let d = UserDefaults.standard.data(forKey: "\(p)_pendingOrders"),
           let saved = try? JSONDecoder().decode([PendingOrder].self, from: d) { pendingOrders = saved }
    }
    private func saveSnapshots() {
        if let d = try? JSONEncoder().encode(portfolioHistory) { UserDefaults.standard.set(d, forKey: "\(p)_snapshots") }
    }
    private func loadSnapshots() {
        if let d = UserDefaults.standard.data(forKey: "\(p)_snapshots"),
           let saved = try? JSONDecoder().decode([PortfolioSnapshot].self, from: d) { portfolioHistory = saved }
    }
    func savePriceAlerts() {
        if let d = try? JSONEncoder().encode(priceAlerts) { UserDefaults.standard.set(d, forKey: "\(p)_priceAlerts") }
    }
    private func loadPriceAlerts() {
        if let d = UserDefaults.standard.data(forKey: "\(p)_priceAlerts"),
           let saved = try? JSONDecoder().decode([PriceAlert].self, from: d) { priceAlerts = saved }
    }
    func saveSafetyControls() {
        if let d = try? JSONEncoder().encode(safetyControls) { UserDefaults.standard.set(d, forKey: "\(p)_safety") }
    }
    private func loadSafetyControls() {
        if let d = UserDefaults.standard.data(forKey: "\(p)_safety"),
           let saved = try? JSONDecoder().decode(SafetyControls.self, from: d) { safetyControls = saved }
    }
}


// MARK: - Portfolio Manager (owns 3 isolated hub portfolios)
@MainActor
class PortfolioManager: ObservableObject {
    // Hub portfolios — fully isolated
    @Published var paperPortfolio: HubPortfolio
    @Published var equitiesPortfolio: HubPortfolio
    @Published var futuresPortfolio: HubPortfolio

    // Active hub
    @Published var activeHub: TradingHub = .paper
    @Published var enabledHubs: Set<TradingHub> = Set(TradingHub.allCases)

    // Broker connections
    @Published var alpacaConnectionStatus: BrokerConnectionStatus = .disconnected
    @Published var ninjaTraderConnectionStatus: BrokerConnectionStatus = .disconnected

    // App-wide preferences (not per-hub)
    @Published var appearanceMode: AppearanceMode = .system
    @Published var accentTheme: AccentTheme = .blue
    @Published var hasCompletedOnboarding: Bool = false
    @Published var errorMessage: String?
    @Published var lastTradeMessage: String?

    // Broker services
    private var localService = LocalPaperTradingService()
    private var alpacaService: AlpacaPaperTradingService?
    private var alpacaLiveService: AlpacaLiveTradingService?
    private var ninjaTraderService: NinjaTraderTradingService?

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    // MARK: - Active Hub Accessors
    var activeHubPortfolio: HubPortfolio {
        switch activeHub {
        case .paper: return paperPortfolio
        case .equities: return equitiesPortfolio
        case .futures: return futuresPortfolio
        }
    }

    var tradingService: TradingServiceProtocol {
        switch activeHub {
        case .paper:
            return localService
        case .equities:
            if equitiesPortfolio.isLiveMode {
                return alpacaLiveService ?? localService
            }
            return alpacaService ?? localService
        case .futures:
            return ninjaTraderService ?? localService
        }
    }

    // Convenience accessors that delegate to active hub
    var cash: Double { activeHubPortfolio.cash }
    var positions: [Position] { activeHubPortfolio.positions }
    var tradeHistory: [Trade] { activeHubPortfolio.tradeHistory }
    var pendingOrders: [PendingOrder] { activeHubPortfolio.pendingOrders }
    var portfolioHistory: [PortfolioSnapshot] { activeHubPortfolio.portfolioHistory }
    var totalRealizedPL: Double { activeHubPortfolio.totalRealizedPL }
    var totalPortfolioValue: Double { activeHubPortfolio.totalPortfolioValue }
    var totalProfitLoss: Double { activeHubPortfolio.totalProfitLoss }
    var totalProfitLossPercent: Double { activeHubPortfolio.totalProfitLossPercent }
    var safetyControls: SafetyControls {
        get { activeHubPortfolio.safetyControls }
        set { activeHubPortfolio.safetyControls = newValue }
    }
    var todayTradeCount: Int { activeHubPortfolio.todayTradeCount }
    var todayPL: Double { activeHubPortfolio.todayPL }
    var priceAlerts: [PriceAlert] { activeHubPortfolio.priceAlerts }
    var startingCash: Double { activeHubPortfolio.startingCash }

    var visibleHubs: [TradingHub] {
        TradingHub.allCases.filter { enabledHubs.contains($0) }
    }

    var isLiveTrading: Bool {
        switch activeHub {
        case .paper: return false
        case .equities: return equitiesPortfolio.isLiveMode
        case .futures: return futuresPortfolio.isLiveMode
        }
    }

    init() {
        self.paperPortfolio = HubPortfolio(hub: .paper, defaultCash: 100_000)
        self.equitiesPortfolio = HubPortfolio(hub: .equities, defaultCash: 0)
        self.futuresPortfolio = HubPortfolio(hub: .futures, defaultCash: 0)
        loadAppPreferences()
        migrateOldDataIfNeeded()
    }

    // MARK: - Buy
    func buy(symbol: String, shares: Double, price: Double, isAutomated: Bool = false) async {
        errorMessage = nil
        lastTradeMessage = nil
        let hp = activeHubPortfolio

        let safety = hp.canExecuteTrade(shares: shares, price: price, type: .buy)
        if !safety.allowed {
            errorMessage = safety.reason
            HapticManager.errorFeedback()
            return
        }
        let cost = shares * price
        guard cost <= hp.cash else {
            errorMessage = "Insufficient funds. Need \(formatCurrency(cost)), have \(formatCurrency(hp.cash))."
            HapticManager.errorFeedback()
            return
        }
        guard shares > 0, price > 0 else {
            errorMessage = "Invalid trade parameters."
            HapticManager.errorFeedback()
            return
        }
        do {
            var trade = try await tradingService.executeBuy(symbol: symbol, shares: shares, price: price)
            trade.isAutomated = isAutomated
            hp.applyBuy(trade: trade)
            lastTradeMessage = "Bought \(formatShares(shares)) \(symbol) @ \(formatCurrency(price))"
            hp.recalculateTodayStats()
            HapticManager.tradeFeedback()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.errorFeedback()
        }
    }

    // MARK: - Sell
    func sell(symbol: String, shares: Double, price: Double, isAutomated: Bool = false) async {
        errorMessage = nil
        lastTradeMessage = nil
        let hp = activeHubPortfolio

        let safety = hp.canExecuteTrade(shares: shares, price: price, type: .sell)
        if !safety.allowed {
            errorMessage = safety.reason
            HapticManager.errorFeedback()
            return
        }
        guard let idx = hp.positions.firstIndex(where: { $0.symbol == symbol }) else {
            errorMessage = "No position in \(symbol)."
            HapticManager.errorFeedback()
            return
        }
        guard hp.positions[idx].shares >= shares else {
            errorMessage = "Only have \(formatShares(hp.positions[idx].shares)) shares of \(symbol)."
            HapticManager.errorFeedback()
            return
        }
        guard shares > 0, price > 0 else {
            errorMessage = "Invalid trade parameters."
            HapticManager.errorFeedback()
            return
        }
        do {
            var trade = try await tradingService.executeSell(symbol: symbol, shares: shares, price: price)
            trade.isAutomated = isAutomated
            hp.applySell(trade: trade, positionIndex: idx)
            lastTradeMessage = "Sold \(formatShares(shares)) \(symbol) @ \(formatCurrency(price))"
            hp.recalculateTodayStats()
            HapticManager.tradeFeedback()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.errorFeedback()
        }
    }

    // MARK: - Delegated methods
    func updatePositionPrices(quotes: [String: StockQuote]) {
        activeHubPortfolio.updatePositionPrices(quotes: quotes)
    }

    func evaluatePendingOrders(quotes: [String: StockQuote]) {
        let hp = activeHubPortfolio
        var ordersToFill: [(index: Int, price: Double)] = []

        for i in hp.pendingOrders.indices.reversed() {
            guard hp.pendingOrders[i].isActive else { continue }
            guard let quote = quotes[hp.pendingOrders[i].symbol] else { continue }
            let order = hp.pendingOrders[i]
            var shouldFill = false

            switch order.type {
            case .market: shouldFill = true
            case .limit:
                if let limit = order.limitPrice {
                    shouldFill = order.side == .buy ? quote.price <= limit : quote.price >= limit
                }
            case .stopLoss:
                if let stop = order.stopPrice { shouldFill = quote.price <= stop }
            case .stopLimit:
                if let stop = order.stopPrice, let limit = order.limitPrice, quote.price <= stop {
                    shouldFill = order.side == .sell ? quote.price >= limit : quote.price <= limit
                }
            }

            if shouldFill {
                let fillPrice: Double
                switch order.type {
                case .stopLoss: fillPrice = quote.price
                case .limit: fillPrice = order.limitPrice ?? quote.price
                case .stopLimit: fillPrice = order.limitPrice ?? quote.price
                case .market: fillPrice = quote.price
                }
                ordersToFill.append((index: i, price: fillPrice))
            }
        }

        guard !ordersToFill.isEmpty else { return }
        for item in ordersToFill {
            hp.pendingOrders[item.index].isActive = false
            hp.pendingOrders[item.index].filledDate = Date()
        }
        hp.savePendingOrders()

        Task {
            for item in ordersToFill {
                let order = hp.pendingOrders[item.index]
                sendLocalNotification(title: "Order Filled",
                    body: "\(order.type.rawValue) \(order.side.rawValue) \(Int(order.shares)) \(order.symbol) @ $\(String(format: "%.2f", item.price))")
                switch order.side {
                case .buy: await buy(symbol: order.symbol, shares: order.shares, price: item.price, isAutomated: true)
                case .sell: await sell(symbol: order.symbol, shares: order.shares, price: item.price, isAutomated: true)
                }
            }
        }
    }

    func evaluatePriceAlerts(quotes: [String: StockQuote]) {
        let hp = activeHubPortfolio
        var didTrigger = false
        for i in hp.priceAlerts.indices {
            guard hp.priceAlerts[i].isActive else { continue }
            guard let quote = quotes[hp.priceAlerts[i].symbol] else { continue }
            let triggered: Bool
            switch hp.priceAlerts[i].condition {
            case .above: triggered = quote.price >= hp.priceAlerts[i].targetPrice
            case .below: triggered = quote.price <= hp.priceAlerts[i].targetPrice
            }
            if triggered {
                hp.priceAlerts[i].isActive = false
                hp.priceAlerts[i].hasTriggered = true
                hp.priceAlerts[i].triggeredDate = Date()
                didTrigger = true
                let dir = hp.priceAlerts[i].condition == .above ? "above" : "below"
                sendLocalNotification(title: "🔔 \(hp.priceAlerts[i].symbol)",
                    body: "\(hp.priceAlerts[i].symbol) is now \(dir) \(formatCurrency(hp.priceAlerts[i].targetPrice))")
                HapticManager.tradeFeedback()
            }
        }
        if didTrigger { hp.savePriceAlerts() }
    }

    func placePendingOrder(_ order: PendingOrder) {
        activeHubPortfolio.placePendingOrder(order)
        lastTradeMessage = "\(order.type.rawValue) \(order.side.rawValue) order placed for \(order.symbol)"
    }

    func cancelPendingOrder(id: UUID) { activeHubPortfolio.cancelPendingOrder(id: id) }
    func addPriceAlert(_ alert: PriceAlert) { activeHubPortfolio.addPriceAlert(alert) }
    func removePriceAlert(id: UUID) { activeHubPortfolio.removePriceAlert(id: id) }
    func takeSnapshot() { activeHubPortfolio.takeSnapshot() }
    func exportTradesCSV() -> String { activeHubPortfolio.exportTradesCSV() }

    func updateTradeNote(tradeId: UUID, note: String) {
        activeHubPortfolio.updateTradeNote(tradeId: tradeId, note: note)
    }

    func resetPortfolio(newStartingCash: Double = 100_000) {
        activeHubPortfolio.reset(newCash: newStartingCash)
        errorMessage = nil
        lastTradeMessage = nil
    }

    func saveSafetyControls() { activeHubPortfolio.saveSafetyControls() }

    // MARK: - Broker Configuration
    func configureAlpaca(apiKey: String, secretKey: String) {
        if alpacaService == nil {
            alpacaService = AlpacaPaperTradingService(apiKey: apiKey, secretKey: secretKey)
        } else {
            alpacaService?.updateKeys(apiKey: apiKey, secretKey: secretKey)
        }
        if alpacaLiveService == nil {
            alpacaLiveService = AlpacaLiveTradingService(apiKey: apiKey, secretKey: secretKey)
        } else {
            alpacaLiveService?.updateKeys(apiKey: apiKey, secretKey: secretKey)
        }
    }

    func configureNinjaTrader(username: String, password: String, cid: String, secret: String, environment: NTEnvironment) {
        if ninjaTraderService == nil {
            ninjaTraderService = NinjaTraderTradingService(username: username, password: password,
                                                            cid: cid, secret: secret, environment: environment)
        } else {
            ninjaTraderService?.updateCredentials(username: username, password: password,
                                                   cid: cid, secret: secret, environment: environment)
        }
    }

    func testAlpacaConnection() async -> Bool {
        do {
            let service: TradingServiceProtocol? = alpacaLiveService ?? alpacaService
            if let _ = try await service?.getAccount() {
                alpacaConnectionStatus = .connected
                return true
            }
            alpacaConnectionStatus = .disconnected
            return false
        } catch {
            alpacaConnectionStatus = .error
            return false
        }
    }

    func testNinjaTraderConnection() async -> Bool {
        do {
            if let _ = try await ninjaTraderService?.getAccount() {
                ninjaTraderConnectionStatus = .connected
                return true
            }
            ninjaTraderConnectionStatus = .disconnected
            return false
        } catch {
            ninjaTraderConnectionStatus = .error
            return false
        }
    }

    func syncWithAlpaca() async {
        guard activeHub == .equities else { return }
        do {
            if let account = try await tradingService.getAccount() {
                equitiesPortfolio.cash = account.cash
                equitiesPortfolio.save()
            }
        } catch {
            errorMessage = "Alpaca sync error: \(error.localizedDescription)"
        }
    }

    // MARK: - Formatting
    func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }

    func formatShares(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    func sharesForDollarAmount(_ dollars: Double, price: Double) -> Double {
        guard price > 0 else { return 0 }
        return (dollars / price * 100).rounded() / 100
    }

    func topGainers(quotes: [String: StockQuote], limit: Int = 3) -> [StockQuote] {
        Array(quotes.values.sorted { $0.changePercent > $1.changePercent }.prefix(limit))
    }

    func topLosers(quotes: [String: StockQuote], limit: Int = 3) -> [StockQuote] {
        Array(quotes.values.sorted { $0.changePercent < $1.changePercent }.prefix(limit))
    }

    func calculatePositionSize(accountRiskPercent: Double, entryPrice: Double, stopLossPrice: Double) -> (shares: Int, riskAmount: Double, positionValue: Double) {
        let riskAmount = totalPortfolioValue * (accountRiskPercent / 100)
        let riskPerShare = abs(entryPrice - stopLossPrice)
        guard riskPerShare > 0 else { return (0, 0, 0) }
        let shares = Int(riskAmount / riskPerShare)
        return (shares, riskAmount, Double(shares) * entryPrice)
    }

    // MARK: - App-wide Preferences Persistence
    func saveUserPreferences() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        UserDefaults.standard.set(accentTheme.rawValue, forKey: "accentTheme")
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(activeHub.rawValue, forKey: "activeHub")
        if let d = try? JSONEncoder().encode(enabledHubs) { UserDefaults.standard.set(d, forKey: "enabledHubs") }
    }

    private func loadAppPreferences() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if let m = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: m) { appearanceMode = mode }
        if let h = UserDefaults.standard.string(forKey: "activeHub"),
           let hub = TradingHub(rawValue: h) { activeHub = hub }
        if let d = UserDefaults.standard.data(forKey: "enabledHubs"),
           let saved = try? JSONDecoder().decode(Set<TradingHub>.self, from: d) { enabledHubs = saved }
        if let t = UserDefaults.standard.string(forKey: "accentTheme"),
           let theme = AccentTheme(rawValue: t) { accentTheme = theme }
    }

    /// Migrate old shared portfolio data into Paper hub on first launch
    private func migrateOldDataIfNeeded() {
        let migrated = UserDefaults.standard.bool(forKey: "hub_migration_done")
        guard !migrated else { return }
        // If old shared data exists, move it to Paper hub
        let oldCash = UserDefaults.standard.double(forKey: "portfolio_cash")
        if oldCash > 0 {
            paperPortfolio.cash = oldCash
            let oldStarting = UserDefaults.standard.double(forKey: "portfolio_startingCash")
            if oldStarting > 0 { paperPortfolio.startingCash = oldStarting }
            paperPortfolio.totalRealizedPL = UserDefaults.standard.double(forKey: "portfolio_realizedPL")
            if let d = UserDefaults.standard.data(forKey: "portfolio_positions"),
               let saved = try? JSONDecoder().decode([Position].self, from: d) { paperPortfolio.positions = saved }
            if let d = UserDefaults.standard.data(forKey: "portfolio_trades"),
               let saved = try? JSONDecoder().decode([Trade].self, from: d) { paperPortfolio.tradeHistory = saved }
            if let d = UserDefaults.standard.data(forKey: "pending_orders"),
               let saved = try? JSONDecoder().decode([PendingOrder].self, from: d) { paperPortfolio.pendingOrders = saved }
            if let d = UserDefaults.standard.data(forKey: "portfolio_snapshots"),
               let saved = try? JSONDecoder().decode([PortfolioSnapshot].self, from: d) { paperPortfolio.portfolioHistory = saved }
            if let d = UserDefaults.standard.data(forKey: "price_alerts"),
               let saved = try? JSONDecoder().decode([PriceAlert].self, from: d) { paperPortfolio.priceAlerts = saved }
            if let d = UserDefaults.standard.data(forKey: "safety_controls"),
               let saved = try? JSONDecoder().decode(SafetyControls.self, from: d) { paperPortfolio.safetyControls = saved }
            paperPortfolio.save()
            paperPortfolio.savePendingOrders()
            paperPortfolio.savePriceAlerts()
            paperPortfolio.saveSafetyControls()
            paperPortfolio.recalculateTodayStats()
        }
        UserDefaults.standard.set(true, forKey: "hub_migration_done")
    }

    // MARK: - Notifications
    func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}


// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Accent Color Theme
enum AccentTheme: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case cyan = "Cyan"
    case teal = "Teal"
    case green = "Green"
    case mint = "Mint"
    case indigo = "Indigo"
    case purple = "Purple"
    case violet = "Violet"
    case pink = "Pink"
    case magenta = "Magenta"
    case red = "Red"
    case coral = "Coral"
    case orange = "Orange"
    case amber = "Amber"
    case yellow = "Yellow"
    case lime = "Lime"
    case emerald = "Emerald"
    case sky = "Sky"
    case steel = "Steel"
    case monochrome = "Mono"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .cyan: return .cyan
        case .teal: return .teal
        case .green: return .green
        case .mint: return .mint
        case .indigo: return .indigo
        case .purple: return .purple
        case .violet: return Color(red: 0.55, green: 0.24, blue: 0.88)
        case .pink: return .pink
        case .magenta: return Color(red: 0.85, green: 0.15, blue: 0.55)
        case .red: return .red
        case .coral: return Color(red: 1.0, green: 0.45, blue: 0.35)
        case .orange: return .orange
        case .amber: return Color(red: 1.0, green: 0.75, blue: 0.0)
        case .yellow: return .yellow
        case .lime: return Color(red: 0.5, green: 0.85, blue: 0.1)
        case .emerald: return Color(red: 0.15, green: 0.75, blue: 0.45)
        case .sky: return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .steel: return Color(red: 0.45, green: 0.52, blue: 0.6)
        case .monochrome: return .gray
        }
    }
}
