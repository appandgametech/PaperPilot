import Foundation

// MARK: - Yahoo Finance Response Models

struct YahooChartResponse: Codable {
    let chart: ChartBody
}

struct ChartBody: Codable {
    let result: [ChartResult]?
}

struct ChartResult: Codable {
    let meta: ChartMeta?
    let timestamp: [Int]?
    let indicators: ChartIndicators?
}

struct ChartIndicators: Codable {
    let quote: [ChartQuoteData]?
}

struct ChartQuoteData: Codable {
    let open: [Double?]?
    let high: [Double?]?
    let low: [Double?]?
    let close: [Double?]?
    let volume: [Int64?]?
}

struct ChartMeta: Codable {
    let symbol: String
    let shortName: String?
    let regularMarketPrice: Double
    let chartPreviousClose: Double
    let regularMarketDayHigh: Double?
    let regularMarketDayLow: Double?
    let regularMarketVolume: Int64?
}

struct YahooSearchResponse: Codable {
    let quotes: [YahooSearchQuote]
}

struct YahooSearchQuote: Codable {
    let symbol: String
    let shortname: String?
    let quoteType: String?
}

// MARK: - Alpaca Response Models

struct AlpacaSnapshot: Codable {
    let latestTrade: AlpacaTrade?
    let minuteBar: AlpacaBar?
    let dailyBar: AlpacaBar?
    let prevDailyBar: AlpacaBar?
}

struct AlpacaTrade: Codable {
    let p: Double // price
    let s: Int?   // size
}

struct AlpacaBar: Codable {
    let o: Double  // open
    let h: Double  // high
    let l: Double  // low
    let c: Double  // close
    let v: Int64   // volume
}

// MARK: - Alpaca Order Models

struct AlpacaOrderRequest: Codable {
    let symbol: String
    let qty: String
    let side: String       // "buy" or "sell"
    let type: String       // "market"
    let time_in_force: String // "day"
}

struct AlpacaOrderResponse: Codable {
    let id: String
    let status: String
    let symbol: String
    let qty: String?
    let filled_qty: String?
    let filled_avg_price: String?
    let side: String
    let type: String
    let created_at: String
}

struct AlpacaAccount: Codable {
    let id: String
    let status: String
    let cash: String
    let portfolio_value: String
    let buying_power: String
    let equity: String
}

struct AlpacaPosition: Codable {
    let symbol: String
    let qty: String
    let avg_entry_price: String
    let current_price: String
    let market_value: String
    let unrealized_pl: String
    let unrealized_plpc: String
}


// MARK: - NinjaTrader / Tradovate Response Models

struct NTAccessTokenResponse: Codable {
    let errorText: String?
    let accessToken: String?
    let expirationTime: String?
    let userStatus: String?
    let userId: Int?
    let name: String?
    let hasLive: Bool?
}

struct NTAccount: Codable {
    let id: Int
    let name: String
    let userId: Int?
    let accountType: String?
    let active: Bool?
    let riskCategoryId: Int?
}

struct NTCashBalance: Codable {
    let id: Int?
    let accountId: Int?
    let cashBalance: Double?
    let realizedPnL: Double?
    let unrealizedPnL: Double?
}

struct NTPlaceOrderResult: Codable {
    let orderId: Int?
    let failureReason: String?
    let failureText: String?
}

struct NTPosition: Codable {
    let id: Int
    let accountId: Int
    let contractId: Int
    let netPos: Int
    let netPrice: Double?
    let bought: Int?
    let sold: Int?
}


// MARK: - Alpaca Bars Response (for chart data)

struct AlpacaBarsResponse: Codable {
    let bars: [AlpacaBarData]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bars = (try? container.decode([AlpacaBarData].self, forKey: .bars)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case bars
    }
}

struct AlpacaBarData: Codable {
    let t: String  // timestamp ISO8601
    let o: Double  // open
    let h: Double  // high
    let l: Double  // low
    let c: Double  // close
    let v: Int     // volume
}
