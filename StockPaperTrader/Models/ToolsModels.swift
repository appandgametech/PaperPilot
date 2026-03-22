import Foundation

// MARK: - Price Alert (unified — used by both PortfolioManager and AutomationEngine)
struct PriceAlert: Identifiable, Codable {
    let id: UUID
    var symbol: String
    var targetPrice: Double
    var condition: AlertCondition
    var isActive: Bool
    var hasTriggered: Bool
    var createdDate: Date
    var triggeredDate: Date?
    var note: String?

    init(symbol: String, targetPrice: Double, condition: AlertCondition, note: String? = nil) {
        self.id = UUID()
        self.symbol = symbol
        self.targetPrice = targetPrice
        self.condition = condition
        self.isActive = true
        self.hasTriggered = false
        self.createdDate = Date()
        self.note = note
    }

    /// Convenience init for AutomationEngine (uses AlertDirection)
    init(symbol: String, targetPrice: Double, direction: AlertDirection) {
        self.id = UUID()
        self.symbol = symbol
        self.targetPrice = targetPrice
        self.condition = direction.toCondition
        self.isActive = true
        self.hasTriggered = false
        self.createdDate = Date()
        self.note = nil
    }

    /// Backward-compat accessor for AutomationEngine code that uses .direction
    var direction: AlertDirection {
        AlertDirection(from: condition)
    }

    enum AlertCondition: String, Codable, CaseIterable {
        case above = "Above"
        case below = "Below"

        var icon: String {
            switch self {
            case .above: return "arrow.up.circle.fill"
            case .below: return "arrow.down.circle.fill"
            }
        }
    }
}

// MARK: - Screener Filter
struct ScreenerFilter {
    var minPrice: Double?
    var maxPrice: Double?
    var minVolume: Int64?
    var minMarketCap: Double?
    var maxMarketCap: Double?
    var minChangePercent: Double?
    var maxChangePercent: Double?
    var sector: StockSector?
}

enum StockSector: String, CaseIterable {
    case technology = "Technology"
    case healthcare = "Healthcare"
    case finance = "Finance"
    case energy = "Energy"
    case consumer = "Consumer"
    case industrial = "Industrial"
    case utilities = "Utilities"
    case realEstate = "Real Estate"
    case materials = "Materials"
    case communication = "Communication"

    var symbols: [String] {
        switch self {
        case .technology: return ["AAPL", "MSFT", "GOOGL", "NVDA", "META", "AVGO", "ORCL", "CRM", "AMD", "ADBE", "INTC", "CSCO", "QCOM", "TXN", "AMAT"]
        case .healthcare: return ["UNH", "JNJ", "LLY", "PFE", "ABBV", "MRK", "TMO", "ABT", "DHR", "BMY", "AMGN", "GILD", "ISRG", "MDT", "CVS"]
        case .finance: return ["JPM", "BAC", "WFC", "GS", "MS", "BLK", "SCHW", "AXP", "C", "USB", "PNC", "TFC", "COF", "BK", "CME"]
        case .energy: return ["XOM", "CVX", "COP", "SLB", "EOG", "MPC", "PSX", "VLO", "OXY", "PXD", "HES", "DVN", "HAL", "BKR", "FANG"]
        case .consumer: return ["AMZN", "TSLA", "HD", "MCD", "NKE", "SBUX", "TGT", "LOW", "COST", "WMT", "PG", "KO", "PEP", "CL", "EL"]
        case .industrial: return ["CAT", "DE", "UNP", "HON", "BA", "GE", "RTX", "LMT", "MMM", "UPS", "FDX", "EMR", "ITW", "ETN", "WM"]
        case .utilities: return ["NEE", "DUK", "SO", "D", "AEP", "SRE", "EXC", "XEL", "ED", "WEC", "ES", "AWK", "DTE", "PPL", "FE"]
        case .realEstate: return ["PLD", "AMT", "CCI", "EQIX", "PSA", "SPG", "O", "WELL", "DLR", "AVB", "EQR", "VTR", "ARE", "MAA", "UDR"]
        case .materials: return ["LIN", "APD", "SHW", "ECL", "FCX", "NEM", "NUE", "DOW", "DD", "PPG", "VMC", "MLM", "ALB", "CF", "MOS"]
        case .communication: return ["GOOG", "META", "DIS", "CMCSA", "NFLX", "T", "VZ", "TMUS", "CHTR", "EA", "ATVI", "TTWO", "WBD", "PARA", "FOX"]
        }
    }
}

// MARK: - Sector Performance
struct SectorPerformance: Identifiable {
    let id = UUID()
    let sector: String
    let etfSymbol: String
    var changePercent: Double
    var price: Double
}
