import Foundation

struct StockQuote: Identifiable, Codable, Hashable {
    let id: String
    var symbol: String
    var name: String
    var price: Double
    var change: Double
    var changePercent: Double
    var volume: Int64
    var marketCap: Double
    var dayHigh: Double
    var dayLow: Double
    var previousClose: Double
    var lastUpdated: Date

    init(symbol: String, name: String = "", price: Double = 0, change: Double = 0,
         changePercent: Double = 0, volume: Int64 = 0, marketCap: Double = 0,
         dayHigh: Double = 0, dayLow: Double = 0, previousClose: Double = 0) {
        self.id = symbol
        self.symbol = symbol
        self.name = name
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.volume = volume
        self.marketCap = marketCap
        self.dayHigh = dayHigh
        self.dayLow = dayLow
        self.previousClose = previousClose
        self.lastUpdated = Date()
    }

    var isPositive: Bool { change >= 0 }
}

struct Position: Identifiable, Codable {
    let id: UUID
    var symbol: String
    var shares: Double
    var averageCost: Double
    var currentPrice: Double
    var dateOpened: Date

    init(symbol: String, shares: Double, averageCost: Double, currentPrice: Double = 0) {
        self.id = UUID()
        self.symbol = symbol
        self.shares = shares
        self.averageCost = averageCost
        self.currentPrice = currentPrice
        self.dateOpened = Date()
    }

    var totalCost: Double { shares * averageCost }
    var marketValue: Double { shares * currentPrice }
    var profitLoss: Double { marketValue - totalCost }
    var profitLossPercent: Double {
        guard totalCost > 0 else { return 0 }
        return (profitLoss / totalCost) * 100
    }
    var isPositive: Bool { profitLoss >= 0 }
}

struct Trade: Identifiable, Codable {
    let id: UUID
    var symbol: String
    var type: TradeType
    var shares: Double
    var price: Double
    var date: Date
    var isAutomated: Bool
    var note: String?           // Trade journal note
    var realizedPL: Double?     // P&L for sell trades (filled in at sell time)

    init(symbol: String, type: TradeType, shares: Double, price: Double, isAutomated: Bool = false, note: String? = nil, realizedPL: Double? = nil) {
        self.id = UUID()
        self.symbol = symbol
        self.type = type
        self.shares = shares
        self.price = price
        self.date = Date()
        self.isAutomated = isAutomated
        self.note = note
        self.realizedPL = realizedPL
    }

    var total: Double { shares * price }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

enum TradeType: String, Codable, CaseIterable {
    case buy = "Buy"
    case sell = "Sell"
}


// MARK: - Chart Data
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int64
}

enum ChartTimeframe: String, CaseIterable {
    case oneDay = "1D"
    case fiveDay = "5D"
    case oneMonth = "1M"
    case threeMonth = "3M"
    case sixMonth = "6M"
    case oneYear = "1Y"

    var yahooRange: String {
        switch self {
        case .oneDay: return "1d"
        case .fiveDay: return "5d"
        case .oneMonth: return "1mo"
        case .threeMonth: return "3mo"
        case .sixMonth: return "6mo"
        case .oneYear: return "1y"
        }
    }

    var yahooInterval: String {
        switch self {
        case .oneDay: return "5m"
        case .fiveDay: return "15m"
        case .oneMonth: return "1d"
        case .threeMonth: return "1d"
        case .sixMonth: return "1wk"
        case .oneYear: return "1wk"
        }
    }
}

// MARK: - Dashboard Widget Types
enum DashboardWidget: String, CaseIterable, Codable, Identifiable {
    case priceChart = "Price Chart"
    case volumeBars = "Volume"
    case movingAverages = "Moving Averages"
    case bollingerBands = "Bollinger Bands"
    case rsi = "RSI"
    case macd = "MACD"
    case dayRange = "Day Range"
    case stats = "Key Stats"
    case position = "My Position"
    case tradeHistory = "Recent Trades"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .priceChart: return "chart.xyaxis.line"
        case .volumeBars: return "chart.bar"
        case .movingAverages: return "line.3.horizontal"
        case .bollingerBands: return "rectangle.compress.vertical"
        case .rsi: return "gauge.with.needle"
        case .macd: return "waveform.path.ecg"
        case .dayRange: return "arrow.left.and.right"
        case .stats: return "number"
        case .position: return "briefcase"
        case .tradeHistory: return "clock.arrow.circlepath"
        }
    }
}
