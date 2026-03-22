import Foundation
import Combine
import Network

// MARK: - Data Provider Selection
enum DataProvider: String, CaseIterable, Codable {
    case yahoo = "Yahoo Finance"
    case alpaca = "Alpaca Markets"

    var description: String {
        switch self {
        case .yahoo: return "Free, no signup. Quotes via Yahoo Finance (unofficial, may throttle)."
        case .alpaca: return "Free signup at alpaca.markets. Real-time IEX data."
        }
    }
}

// MARK: - NinjaTrader Environment
enum NTEnvironment: String, CaseIterable, Codable {
    case demo = "Demo (Simulated)"
    case live = "Live (Real Money)"

    var baseURL: String {
        switch self {
        case .demo: return "https://demo.tradovateapi.com/v1"
        case .live: return "https://live.tradovateapi.com/v1"
        }
    }
}

// MARK: - Yahoo Rate Limiter
actor YahooRateLimiter {
    // Safe limits: max 1 request per 2 seconds, batch symbols to reduce calls
    private let minRequestInterval: TimeInterval = 2.0
    private var lastRequestTime: Date = .distantPast
    private var consecutiveFailures = 0
    private var backoffUntil: Date = .distantPast

    var currentBackoffSeconds: Int {
        let remaining = backoffUntil.timeIntervalSinceNow
        return remaining > 0 ? Int(ceil(remaining)) : 0
    }

    var isBackedOff: Bool {
        Date() < backoffUntil
    }

    func waitForSlot() async {
        // If we're in backoff, wait it out
        if Date() < backoffUntil {
            let wait = backoffUntil.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }

        // Enforce minimum interval between requests
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            let delay = minRequestInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequestTime = Date()
    }

    func recordSuccess() {
        consecutiveFailures = 0
    }

    func recordRateLimit() {
        consecutiveFailures += 1
        // Exponential backoff: 30s, 60s, 120s, 240s, max 5 min
        let backoffSeconds = min(300, 30 * Int(pow(2.0, Double(consecutiveFailures - 1))))
        backoffUntil = Date().addingTimeInterval(Double(backoffSeconds))
    }

    func recordBlockOrForbidden() {
        consecutiveFailures += 1
        // Longer backoff for 403: 2 min, 5 min, 10 min
        let backoffSeconds = min(600, 120 * Int(pow(2.0, Double(consecutiveFailures - 1))))
        backoffUntil = Date().addingTimeInterval(Double(backoffSeconds))
    }
}


// MARK: - Stock Data Service
@MainActor
class StockService: ObservableObject {
    @Published var quotes: [String: StockQuote] = [:]
    @Published var watchlist: [String] = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "NVDA", "META", "SPY"]
    @Published var alpacaWatchlist: [String] = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "NVDA", "META", "SPY"]

    // Futures symbols — fixed contract list for NinjaTrader hub
    let futuresSymbols: [String] = ["ES=F", "NQ=F", "CL=F", "GC=F", "SI=F", "ZB=F", "YM=F", "RTY=F"]

    // Hub-aware watchlist accessor
    func watchlistForHub(_ hub: TradingHub) -> [String] {
        switch hub {
        case .paper: return watchlist
        case .equities: return alpacaWatchlist
        case .futures: return futuresSymbols
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchResults: [StockQuote] = []
    @Published var dataProvider: DataProvider = .yahoo
    @Published var refreshInterval: TimeInterval = 30 // Safe default: 30s
    @Published var isConnected = true
    @Published var isThrottled = false       // True when Yahoo is rate-limiting us
    @Published var throttleMessage: String?  // User-facing throttle explanation
    @Published var sparklines: [String: [Double]] = [:]  // symbol -> recent closes for sparkline

    // Alpaca credentials (stored in Keychain)
    @Published var alpacaApiKey: String = ""
    @Published var alpacaSecretKey: String = ""

    private var refreshTimer: Timer?
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var searchTask: Task<Void, Never>?
    private let rateLimiter = YahooRateLimiter()

    // Safe refresh bounds — don't let user go below 15s for Yahoo
    static let yahooMinRefreshInterval: TimeInterval = 15
    static let yahooSafeRefreshInterval: TimeInterval = 30
    static let yahooMaxRefreshInterval: TimeInterval = 300

    init() {
        loadSettings()
        startNetworkMonitor()
        startAutoRefresh()
    }

    deinit {
        refreshTimer?.invalidate()
        networkMonitor.cancel()
    }

    // MARK: - Network Monitor
    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
                if path.status == .satisfied {
                    self?.errorMessage = nil
                    await self?.refreshAll()
                } else {
                    self?.errorMessage = "No internet connection. Showing cached data."
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Fetch dispatcher
    func fetchQuotes(for symbols: [String]) async {
        guard !symbols.isEmpty else { return }
        guard isConnected else {
            errorMessage = "No internet connection."
            return
        }
        isLoading = true
        errorMessage = nil

        switch dataProvider {
        case .yahoo:
            await fetchFromYahoo(symbols: symbols)
        case .alpaca:
            await fetchFromAlpaca(symbols: symbols)
        }

        isLoading = false
    }


    // MARK: - Yahoo Finance (unofficial, rate-limited) — sequential with throttle
    private func fetchFromYahoo(symbols: [String]) async {
        // Check if we're currently backed off
        if await rateLimiter.isBackedOff {
            let secs = await rateLimiter.currentBackoffSeconds
            isThrottled = true
            throttleMessage = "Yahoo Finance is rate-limiting us. Retrying in \(secs)s. Showing cached data."
            return
        }

        isThrottled = false
        throttleMessage = nil

        // Batch in groups of 4 to reduce burst, with delay between batches
        let batchSize = 4
        for batch in stride(from: 0, to: symbols.count, by: batchSize) {
            let end = min(batch + batchSize, symbols.count)
            let batchSymbols = Array(symbols[batch..<end])

            await withTaskGroup(of: Void.self) { group in
                for symbol in batchSymbols {
                    group.addTask { [weak self] in
                        await self?.fetchYahooChart(symbol: symbol)
                    }
                }
            }

            // Pause between batches to stay under radar
            if end < symbols.count {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s between batches
            }
        }
    }

    private func fetchYahooChart(symbol: String) async {
        await rateLimiter.waitForSlot()

        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=5d"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        // Rotate user agents to reduce fingerprinting
        let agents = [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]
        request.setValue(agents.randomElement(), forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            switch http.statusCode {
            case 200:
                await rateLimiter.recordSuccess()
                let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
                if let result = decoded.chart.result?.first, let meta = result.meta {
                    let prevClose = meta.chartPreviousClose
                    let price = meta.regularMarketPrice
                    let change = price - prevClose
                    let changePct = prevClose > 0 ? (change / prevClose) * 100 : 0
                    let quote = StockQuote(
                        symbol: symbol,
                        name: meta.shortName ?? symbol,
                        price: price,
                        change: change,
                        changePercent: changePct,
                        volume: meta.regularMarketVolume ?? 0,
                        dayHigh: meta.regularMarketDayHigh ?? price,
                        dayLow: meta.regularMarketDayLow ?? price,
                        previousClose: prevClose
                    )
                    quotes[symbol] = quote

                    // Extract sparkline data from the 5d chart closes
                    if let closes = result.indicators?.quote?.first?.close {
                        let validCloses = closes.compactMap { $0 }
                        if validCloses.count >= 2 {
                            sparklines[symbol] = validCloses
                        }
                    }
                }

            case 429:
                await rateLimiter.recordRateLimit()
                let secs = await rateLimiter.currentBackoffSeconds
                isThrottled = true
                throttleMessage = "Yahoo Finance rate limit hit. Backing off for \(secs)s. Cached data still visible."
                errorMessage = "Rate limited by Yahoo Finance. Will retry automatically."

            case 403:
                await rateLimiter.recordBlockOrForbidden()
                let secs = await rateLimiter.currentBackoffSeconds
                isThrottled = true
                throttleMessage = "Yahoo Finance blocked our request (403). Backing off for \(secs)s. Consider switching to Alpaca or NinjaTrader in Settings."
                errorMessage = "Blocked by Yahoo Finance. Try a different data provider."

            default:
                if quotes[symbol] == nil {
                    errorMessage = "Yahoo returned \(http.statusCode) for \(symbol)"
                }
            }
        } catch is CancellationError {
            return
        } catch {
            if quotes[symbol] == nil {
                errorMessage = "Failed to fetch \(symbol)"
            }
        }
    }

    // MARK: - Alpaca Market Data (free tier, IEX)
    private func fetchFromAlpaca(symbols: [String]) async {
        guard !alpacaApiKey.isEmpty, !alpacaSecretKey.isEmpty else {
            errorMessage = "Alpaca API keys not configured. Go to Settings."
            return
        }

        let joined = symbols.joined(separator: ",")
        guard let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://data.alpaca.markets/v2/stocks/snapshots?symbols=\(encoded)&feed=iex") else { return }

        var request = URLRequest(url: url)
        request.setValue(alpacaApiKey, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(alpacaSecretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 401 || http.statusCode == 403 {
                errorMessage = "Alpaca authentication failed. Check your API keys in Settings."
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Alpaca API error (\(http.statusCode))."
                return
            }

            let snapshots = try JSONDecoder().decode([String: AlpacaSnapshot].self, from: data)
            for (symbol, snap) in snapshots {
                let price = snap.latestTrade?.p ?? snap.minuteBar?.c ?? 0
                let prevClose = snap.prevDailyBar?.c ?? price
                let change = price - prevClose
                let changePct = prevClose > 0 ? (change / prevClose) * 100 : 0
                let quote = StockQuote(
                    symbol: symbol,
                    name: symbol,
                    price: price,
                    change: change,
                    changePercent: changePct,
                    volume: snap.dailyBar?.v ?? 0,
                    dayHigh: snap.dailyBar?.h ?? price,
                    dayLow: snap.dailyBar?.l ?? price,
                    previousClose: prevClose
                )
                quotes[symbol] = quote
            }
        } catch {
            errorMessage = "Alpaca fetch error: \(error.localizedDescription)"
        }
    }


    // MARK: - Search with debounce
    func searchStocks(query: String) async -> [StockQuote] {
        guard query.count >= 1 else { return [] }
        // Add small delay for debounce
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return [] }
        return await performSearch(query: query)
    }

    private func performSearch(query: String) async -> [StockQuote] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=8&newsCount=0"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        do {
            await rateLimiter.waitForSlot()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard !Task.isCancelled else { return [] }
            let decoded = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
            return decoded.quotes.compactMap { item in
                guard item.quoteType == "EQUITY" || item.quoteType == "ETF" else { return nil }
                return StockQuote(symbol: item.symbol, name: item.shortname ?? item.symbol)
            }
        } catch {
            return []
        }
    }

    // MARK: - Watchlist (hub-aware)
    func addToWatchlist(_ symbol: String, hub: TradingHub = .paper) {
        let upper = symbol.uppercased()
        switch hub {
        case .paper:
            guard !watchlist.contains(upper) else { return }
            watchlist.append(upper)
        case .equities:
            guard !alpacaWatchlist.contains(upper) else { return }
            alpacaWatchlist.append(upper)
        case .futures:
            return // Futures has fixed symbols
        }
        Task { await fetchQuotes(for: [upper]) }
        saveSettings()
    }

    func removeFromWatchlist(_ symbol: String, hub: TradingHub = .paper) {
        switch hub {
        case .paper:
            watchlist.removeAll { $0 == symbol }
        case .equities:
            alpacaWatchlist.removeAll { $0 == symbol }
        case .futures:
            return // Futures has fixed symbols
        }
        quotes.removeValue(forKey: symbol)
        saveSettings()
    }

    func moveWatchlistItem(from source: IndexSet, to destination: Int, hub: TradingHub = .paper) {
        switch hub {
        case .paper:
            watchlist.move(fromOffsets: source, toOffset: destination)
        case .equities:
            alpacaWatchlist.move(fromOffsets: source, toOffset: destination)
        case .futures:
            return
        }
        saveSettings()
    }

    // MARK: - Auto Refresh
    func refreshAll() async {
        // Fetch quotes for all watchlists + futures symbols
        var allSymbols = Set(watchlist)
        allSymbols.formUnion(alpacaWatchlist)
        allSymbols.formUnion(futuresSymbols)
        await fetchQuotes(for: Array(allSymbols))
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        // Enforce safe minimum for Yahoo
        let safeInterval: TimeInterval
        if dataProvider == .yahoo {
            safeInterval = max(StockService.yahooMinRefreshInterval, refreshInterval)
        } else {
            safeInterval = max(5, refreshInterval)
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: safeInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refreshAll() }
        }
        Task { await refreshAll() }
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        if dataProvider == .yahoo {
            refreshInterval = max(StockService.yahooMinRefreshInterval, min(interval, StockService.yahooMaxRefreshInterval))
        } else {
            refreshInterval = max(5, interval)
        }
        startAutoRefresh()
        saveSettings()
    }

    // MARK: - Persistence (credentials in Keychain)
    private func saveSettings() {
        UserDefaults.standard.set(watchlist, forKey: "watchlist")
        UserDefaults.standard.set(alpacaWatchlist, forKey: "alpacaWatchlist")
        UserDefaults.standard.set(dataProvider.rawValue, forKey: "dataProvider")
        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        KeychainHelper.save(key: "alpacaApiKey", value: alpacaApiKey)
        KeychainHelper.save(key: "alpacaSecretKey", value: alpacaSecretKey)
        KeychainHelper.save(key: "ntUsername", value: ntUsername)
        KeychainHelper.save(key: "ntPassword", value: ntPassword)
        KeychainHelper.save(key: "ntCid", value: ntCid)
        KeychainHelper.save(key: "ntSecret", value: ntSecret)
        UserDefaults.standard.set(ntEnvironment.rawValue, forKey: "ntEnvironment")
    }

    private func loadSettings() {
        if let saved = UserDefaults.standard.stringArray(forKey: "watchlist"), !saved.isEmpty {
            watchlist = saved
        }
        if let saved = UserDefaults.standard.stringArray(forKey: "alpacaWatchlist"), !saved.isEmpty {
            alpacaWatchlist = saved
        }
        if let dp = UserDefaults.standard.string(forKey: "dataProvider"),
           let provider = DataProvider(rawValue: dp) {
            dataProvider = provider
        }
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        if interval >= 5 { refreshInterval = interval }
        alpacaApiKey = KeychainHelper.load(key: "alpacaApiKey") ?? ""
        alpacaSecretKey = KeychainHelper.load(key: "alpacaSecretKey") ?? ""
        ntUsername = KeychainHelper.load(key: "ntUsername") ?? ""
        ntPassword = KeychainHelper.load(key: "ntPassword") ?? ""
        ntCid = KeychainHelper.load(key: "ntCid") ?? ""
        ntSecret = KeychainHelper.load(key: "ntSecret") ?? ""
        if let env = UserDefaults.standard.string(forKey: "ntEnvironment"),
           let e = NTEnvironment(rawValue: env) {
            ntEnvironment = e
        }
    }

    func applySettings() {
        saveSettings()
        startAutoRefresh()
    }

    // MARK: - NinjaTrader (Tradovate) credentials
    @Published var ntUsername: String = ""
    @Published var ntPassword: String = ""
    @Published var ntCid: String = ""       // Client ID from NinjaTrader partner app
    @Published var ntSecret: String = ""    // API secret
    @Published var ntEnvironment: NTEnvironment = .demo

    // MARK: - Alpaca Bars API (for Alpaca hub charts)
    func fetchAlpacaBars(symbol: String, timeframe: ChartTimeframe) async -> [ChartDataPoint] {
        guard !alpacaApiKey.isEmpty, !alpacaSecretKey.isEmpty else { return [] }

        let tf: String
        let start: String
        let cal = Calendar.current
        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        switch timeframe {
        case .oneDay:
            tf = "5Min"
            start = fmt.string(from: cal.date(byAdding: .day, value: -1, to: now) ?? now)
        case .fiveDay:
            tf = "15Min"
            start = fmt.string(from: cal.date(byAdding: .day, value: -5, to: now) ?? now)
        case .oneMonth:
            tf = "1Hour"
            start = fmt.string(from: cal.date(byAdding: .month, value: -1, to: now) ?? now)
        case .threeMonth:
            tf = "1Day"
            start = fmt.string(from: cal.date(byAdding: .month, value: -3, to: now) ?? now)
        case .sixMonth:
            tf = "1Day"
            start = fmt.string(from: cal.date(byAdding: .month, value: -6, to: now) ?? now)
        case .oneYear:
            tf = "1Day"
            start = fmt.string(from: cal.date(byAdding: .year, value: -1, to: now) ?? now)
        }

        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://data.alpaca.markets/v2/stocks/\(encoded)/bars?timeframe=\(tf)&start=\(start)&limit=500&feed=iex") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(alpacaApiKey, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(alpacaSecretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            let decoded = try JSONDecoder().decode(AlpacaBarsResponse.self, from: data)
            return decoded.bars.compactMap { bar in
                guard let date = ISO8601DateFormatter().date(from: bar.t) else { return nil }
                return ChartDataPoint(
                    date: date,
                    open: bar.o, high: bar.h, low: bar.l, close: bar.c,
                    volume: Int64(bar.v)
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Chart Data Fetching
    func fetchChartData(symbol: String, timeframe: ChartTimeframe) async -> [ChartDataPoint] {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=\(timeframe.yahooInterval)&range=\(timeframe.yahooRange)"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        do {
            await rateLimiter.waitForSlot()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            await rateLimiter.recordSuccess()
            let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = decoded.chart.result?.first,
                  let timestamps = result.timestamp,
                  let quoteData = result.indicators?.quote?.first else { return [] }

            let opens = quoteData.open ?? []
            let highs = quoteData.high ?? []
            let lows = quoteData.low ?? []
            let closes = quoteData.close ?? []
            let volumes = quoteData.volume ?? []

            var points: [ChartDataPoint] = []
            for i in 0..<timestamps.count {
                guard let o = opens[safe: i] ?? nil,
                      let h = highs[safe: i] ?? nil,
                      let l = lows[safe: i] ?? nil,
                      let c = closes[safe: i] ?? nil else { continue }
                let v: Int64 = (volumes[safe: i] ?? nil) ?? 0
                points.append(ChartDataPoint(
                    date: Date(timeIntervalSince1970: TimeInterval(timestamps[i])),
                    open: o, high: h, low: l, close: c, volume: v
                ))
            }
            return points
        } catch {
            return []
        }
    }
}

// Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
