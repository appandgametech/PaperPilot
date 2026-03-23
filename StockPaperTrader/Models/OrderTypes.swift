import Foundation

// MARK: - Order Types
enum OrderType: String, CaseIterable, Codable {
    case market = "Market"
    case limit = "Limit"
    case stopLoss = "Stop Loss"
    case stopLimit = "Stop Limit"
    case trailingStop = "Trailing Stop"

    var description: String {
        switch self {
        case .market: return "Execute immediately at current price"
        case .limit: return "Execute only at your price or better"
        case .stopLoss: return "Sell when price drops to stop price"
        case .stopLimit: return "Trigger limit order when stop price is hit"
        case .trailingStop: return "Stop follows price up, sells when it drops by trail amount"
        }
    }
}

struct PendingOrder: Identifiable, Codable {
    let id: UUID
    var symbol: String
    var type: OrderType
    var side: TradeType
    var shares: Double
    var limitPrice: Double?   // for limit & stop-limit
    var stopPrice: Double?    // for stop & stop-limit
    var trailAmount: Double?  // for trailing stop (dollar amount)
    var trailPercent: Double? // for trailing stop (percentage)
    var highWaterMark: Double? // tracks highest price for trailing stop
    var bracketStopLoss: Double?   // OCO bracket: auto stop loss
    var bracketTakeProfit: Double?  // OCO bracket: auto take profit
    var createdDate: Date
    var isActive: Bool
    var filledDate: Date?

    init(symbol: String, type: OrderType, side: TradeType, shares: Double,
         limitPrice: Double? = nil, stopPrice: Double? = nil,
         trailAmount: Double? = nil, trailPercent: Double? = nil,
         bracketStopLoss: Double? = nil, bracketTakeProfit: Double? = nil) {
        self.id = UUID()
        self.symbol = symbol
        self.type = type
        self.side = side
        self.shares = shares
        self.limitPrice = limitPrice
        self.stopPrice = stopPrice
        self.trailAmount = trailAmount
        self.trailPercent = trailPercent
        self.highWaterMark = nil
        self.bracketStopLoss = bracketStopLoss
        self.bracketTakeProfit = bracketTakeProfit
        self.createdDate = Date()
        self.isActive = true
    }

    var triggerPrice: Double {
        stopPrice ?? limitPrice ?? 0
    }

    var isBracketOrder: Bool {
        bracketStopLoss != nil || bracketTakeProfit != nil
    }
}

// MARK: - ATM Strategy (NinjaTrader Advanced Trade Management)
struct ATMStrategy: Identifiable, Codable {
    let id: UUID
    var name: String
    var stopLossPoints: Double    // points below entry for stop loss
    var takeProfitPoints: Double  // points above entry for take profit
    var trailAfterProfit: Bool    // start trailing after reaching profit target
    var trailAmount: Double       // trail amount once in profit
    var isDefault: Bool

    init(name: String, stopLossPoints: Double, takeProfitPoints: Double,
         trailAfterProfit: Bool = false, trailAmount: Double = 0, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.stopLossPoints = stopLossPoints
        self.takeProfitPoints = takeProfitPoints
        self.trailAfterProfit = trailAfterProfit
        self.trailAmount = trailAmount
        self.isDefault = isDefault
    }

    static let presets: [ATMStrategy] = [
        ATMStrategy(name: "Tight (2/4)", stopLossPoints: 2, takeProfitPoints: 4),
        ATMStrategy(name: "Standard (5/10)", stopLossPoints: 5, takeProfitPoints: 10),
        ATMStrategy(name: "Wide (10/20)", stopLossPoints: 10, takeProfitPoints: 20),
        ATMStrategy(name: "Trail (5/10 + Trail 3)", stopLossPoints: 5, takeProfitPoints: 10, trailAfterProfit: true, trailAmount: 3),
    ]
}

// MARK: - Portfolio Snapshot (for P&L history)
struct PortfolioSnapshot: Codable, Identifiable {
    let id: UUID
    let date: Date
    let totalValue: Double
    let cash: Double
    let positionCount: Int

    init(totalValue: Double, cash: Double, positionCount: Int) {
        self.id = UUID()
        self.date = Date()
        self.totalValue = totalValue
        self.cash = cash
        self.positionCount = positionCount
    }
}

// MARK: - News Item
struct NewsItem: Identifiable {
    let id = UUID()
    let title: String
    let source: String
    let url: String
    let publishedDate: Date
    let relatedSymbols: [String]
}

// MARK: - Watchlist Sort
enum WatchlistSort: String, CaseIterable {
    case name = "Name"
    case price = "Price"
    case changePercent = "% Change"
    case volume = "Volume"
    // Note: "custom" is handled separately in WatchlistView via a dedicated button
}
