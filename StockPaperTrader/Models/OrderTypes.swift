import Foundation

// MARK: - Order Types
enum OrderType: String, CaseIterable, Codable {
    case market = "Market"
    case limit = "Limit"
    case stopLoss = "Stop Loss"
    case stopLimit = "Stop Limit"

    var description: String {
        switch self {
        case .market: return "Execute immediately at current price"
        case .limit: return "Execute only at your price or better"
        case .stopLoss: return "Sell when price drops to stop price"
        case .stopLimit: return "Trigger limit order when stop price is hit"
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
    var createdDate: Date
    var isActive: Bool
    var filledDate: Date?

    init(symbol: String, type: OrderType, side: TradeType, shares: Double,
         limitPrice: Double? = nil, stopPrice: Double? = nil) {
        self.id = UUID()
        self.symbol = symbol
        self.type = type
        self.side = side
        self.shares = shares
        self.limitPrice = limitPrice
        self.stopPrice = stopPrice
        self.createdDate = Date()
        self.isActive = true
    }

    var triggerPrice: Double {
        stopPrice ?? limitPrice ?? 0
    }
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
