import Foundation

// MARK: - Trading Service Protocol
// This is the abstraction layer. Swap implementations to go from paper → real.
protocol TradingServiceProtocol {
    func executeBuy(symbol: String, shares: Double, price: Double) async throws -> Trade
    func executeSell(symbol: String, shares: Double, price: Double) async throws -> Trade
    func getAccount() async throws -> (cash: Double, portfolioValue: Double)?
    func getPositions() async throws -> [AlpacaPosition]?
}

enum TradingError: LocalizedError {
    case insufficientFunds
    case insufficientShares
    case invalidOrder
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .insufficientFunds: return "Insufficient funds for this trade."
        case .insufficientShares: return "You don't have enough shares to sell."
        case .invalidOrder: return "Invalid order parameters."
        case .apiError(let msg): return msg
        }
    }
}

// MARK: - Local Paper Trading (no account needed)
class LocalPaperTradingService: TradingServiceProtocol {
    func executeBuy(symbol: String, shares: Double, price: Double) async throws -> Trade {
        // Simulate slight delay like a real fill
        try await Task.sleep(nanoseconds: 200_000_000)
        return Trade(symbol: symbol, type: .buy, shares: shares, price: price)
    }

    func executeSell(symbol: String, shares: Double, price: Double) async throws -> Trade {
        try await Task.sleep(nanoseconds: 200_000_000)
        return Trade(symbol: symbol, type: .sell, shares: shares, price: price)
    }

    func getAccount() async throws -> (cash: Double, portfolioValue: Double)? {
        return nil // managed locally by PortfolioManager
    }

    func getPositions() async throws -> [AlpacaPosition]? {
        return nil
    }
}

// MARK: - Alpaca Paper Trading (free signup, real simulation)
class AlpacaPaperTradingService: TradingServiceProtocol {
    private let baseURL = "https://paper-api.alpaca.markets"
    private var apiKey: String
    private var secretKey: String

    init(apiKey: String, secretKey: String) {
        self.apiKey = apiKey
        self.secretKey = secretKey
    }

    func updateKeys(apiKey: String, secretKey: String) {
        self.apiKey = apiKey
        self.secretKey = secretKey
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw TradingError.invalidOrder
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TradingError.apiError("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TradingError.apiError("Alpaca API (\(httpResponse.statusCode)): \(errorBody)")
        }

        return (data, httpResponse)
    }

    func executeBuy(symbol: String, shares: Double, price: Double) async throws -> Trade {
        let order = AlpacaOrderRequest(
            symbol: symbol,
            qty: String(format: "%.0f", shares),
            side: "buy",
            type: "market",
            time_in_force: "day"
        )
        let body = try JSONEncoder().encode(order)
        let (data, _) = try await makeRequest(path: "/v2/orders", method: "POST", body: body)
        let response = try JSONDecoder().decode(AlpacaOrderResponse.self, from: data)

        let filledPrice = Double(response.filled_avg_price ?? "") ?? price
        let filledQty = Double(response.filled_qty ?? response.qty ?? "") ?? shares

        return Trade(symbol: symbol, type: .buy, shares: filledQty, price: filledPrice)
    }

    func executeSell(symbol: String, shares: Double, price: Double) async throws -> Trade {
        let order = AlpacaOrderRequest(
            symbol: symbol,
            qty: String(format: "%.0f", shares),
            side: "sell",
            type: "market",
            time_in_force: "day"
        )
        let body = try JSONEncoder().encode(order)
        let (data, _) = try await makeRequest(path: "/v2/orders", method: "POST", body: body)
        let response = try JSONDecoder().decode(AlpacaOrderResponse.self, from: data)

        let filledPrice = Double(response.filled_avg_price ?? "") ?? price
        let filledQty = Double(response.filled_qty ?? response.qty ?? "") ?? shares

        return Trade(symbol: symbol, type: .sell, shares: filledQty, price: filledPrice)
    }

    func getAccount() async throws -> (cash: Double, portfolioValue: Double)? {
        let (data, _) = try await makeRequest(path: "/v2/account")
        let account = try JSONDecoder().decode(AlpacaAccount.self, from: data)
        return (
            cash: Double(account.cash) ?? 0,
            portfolioValue: Double(account.portfolio_value) ?? 0
        )
    }

    func getPositions() async throws -> [AlpacaPosition]? {
        let (data, _) = try await makeRequest(path: "/v2/positions")
        return try JSONDecoder().decode([AlpacaPosition].self, from: data)
    }
}


// MARK: - Alpaca Live Trading (real money)
class AlpacaLiveTradingService: TradingServiceProtocol {
    private let baseURL = "https://api.alpaca.markets"
    private var apiKey: String
    private var secretKey: String

    init(apiKey: String, secretKey: String) {
        self.apiKey = apiKey
        self.secretKey = secretKey
    }

    func updateKeys(apiKey: String, secretKey: String) {
        self.apiKey = apiKey
        self.secretKey = secretKey
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw TradingError.invalidOrder
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TradingError.apiError("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TradingError.apiError("Alpaca Live API (\(httpResponse.statusCode)): \(errorBody)")
        }

        return (data, httpResponse)
    }

    func executeBuy(symbol: String, shares: Double, price: Double) async throws -> Trade {
        let order = AlpacaOrderRequest(
            symbol: symbol,
            qty: String(format: "%.0f", shares),
            side: "buy",
            type: "market",
            time_in_force: "day"
        )
        let body = try JSONEncoder().encode(order)
        let (data, _) = try await makeRequest(path: "/v2/orders", method: "POST", body: body)
        let response = try JSONDecoder().decode(AlpacaOrderResponse.self, from: data)

        let filledPrice = Double(response.filled_avg_price ?? "") ?? price
        let filledQty = Double(response.filled_qty ?? response.qty ?? "") ?? shares

        return Trade(symbol: symbol, type: .buy, shares: filledQty, price: filledPrice)
    }

    func executeSell(symbol: String, shares: Double, price: Double) async throws -> Trade {
        let order = AlpacaOrderRequest(
            symbol: symbol,
            qty: String(format: "%.0f", shares),
            side: "sell",
            type: "market",
            time_in_force: "day"
        )
        let body = try JSONEncoder().encode(order)
        let (data, _) = try await makeRequest(path: "/v2/orders", method: "POST", body: body)
        let response = try JSONDecoder().decode(AlpacaOrderResponse.self, from: data)

        let filledPrice = Double(response.filled_avg_price ?? "") ?? price
        let filledQty = Double(response.filled_qty ?? response.qty ?? "") ?? shares

        return Trade(symbol: symbol, type: .sell, shares: filledQty, price: filledPrice)
    }

    func getAccount() async throws -> (cash: Double, portfolioValue: Double)? {
        let (data, _) = try await makeRequest(path: "/v2/account")
        let account = try JSONDecoder().decode(AlpacaAccount.self, from: data)
        return (
            cash: Double(account.cash) ?? 0,
            portfolioValue: Double(account.portfolio_value) ?? 0
        )
    }

    func getPositions() async throws -> [AlpacaPosition]? {
        let (data, _) = try await makeRequest(path: "/v2/positions")
        return try JSONDecoder().decode([AlpacaPosition].self, from: data)
    }
}

// MARK: - NinjaTrader / Tradovate Trading Service
class NinjaTraderTradingService: TradingServiceProtocol {
    private var username: String
    private var password: String
    private var cid: String
    private var secret: String
    private var environment: NTEnvironment

    private var accessToken: String?
    private var tokenExpiration: Date?
    private var accountId: Int?
    private var accountSpec: String?

    init(username: String, password: String, cid: String, secret: String, environment: NTEnvironment) {
        self.username = username
        self.password = password
        self.cid = cid
        self.secret = secret
        self.environment = environment
    }

    func updateCredentials(username: String, password: String, cid: String, secret: String, environment: NTEnvironment) {
        self.username = username
        self.password = password
        self.cid = cid
        self.secret = secret
        self.environment = environment
        self.accessToken = nil
        self.tokenExpiration = nil
        self.accountId = nil
    }

    private var baseURL: String { environment.baseURL }

    // MARK: - Authentication
    private func ensureAuthenticated() async throws {
        // Refresh if token expires within 5 minutes
        if let _ = accessToken, let exp = tokenExpiration, Date() < exp.addingTimeInterval(-300) {
            return // Token still valid
        }

        guard let url = URL(string: "\(baseURL)/auth/accessTokenRequest") else {
            throw TradingError.apiError("Invalid NinjaTrader URL")
        }

        var body: [String: Any] = [
            "name": username,
            "password": password,
            "appId": "PaperPilot",
            "appVersion": "1.0"
        ]
        if !cid.isEmpty { body["cid"] = cid }
        if !secret.isEmpty { body["sec"] = secret }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TradingError.apiError("Invalid response from NinjaTrader")
        }

        let decoded = try JSONDecoder().decode(NTAccessTokenResponse.self, from: data)

        if let errorText = decoded.errorText, !errorText.isEmpty {
            throw TradingError.apiError("NinjaTrader auth failed: \(errorText)")
        }

        guard let token = decoded.accessToken else {
            throw TradingError.apiError("NinjaTrader: No access token returned. Status: \(http.statusCode)")
        }

        accessToken = token
        accountSpec = decoded.name

        // Token expires in 90 min
        if let expStr = decoded.expirationTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            tokenExpiration = formatter.date(from: expStr) ?? Date().addingTimeInterval(5400)
        } else {
            tokenExpiration = Date().addingTimeInterval(5400)
        }

        // Fetch account ID
        try await fetchAccountId()
    }

    private func fetchAccountId() async throws {
        let (data, _) = try await authenticatedRequest(path: "/account/list", method: "GET")
        let accounts = try JSONDecoder().decode([NTAccount].self, from: data)
        guard let first = accounts.first else {
            throw TradingError.apiError("No NinjaTrader accounts found. Check your credentials.")
        }
        accountId = first.id
        accountSpec = first.name
    }

    private var retryingAuth = false

    private func authenticatedRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        try await ensureAuthenticated()

        guard let token = accessToken,
              let url = URL(string: "\(baseURL)\(path)") else {
            throw TradingError.apiError("NinjaTrader: Not authenticated")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TradingError.apiError("Invalid response")
        }

        if http.statusCode == 401 && !retryingAuth {
            // Token expired, clear and retry once
            retryingAuth = true
            accessToken = nil
            tokenExpiration = nil
            defer { retryingAuth = false }
            return try await authenticatedRequest(path: path, method: method, body: body)
        }

        if http.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TradingError.apiError("NinjaTrader (\(http.statusCode)): \(errorBody)")
        }

        return (data, http)
    }

    // MARK: - Trading
    func executeBuy(symbol: String, shares: Double, price: Double) async throws -> Trade {
        guard let acctId = accountId, let acctSpec = accountSpec else {
            try await ensureAuthenticated()
            guard accountId != nil else {
                throw TradingError.apiError("NinjaTrader: No account available")
            }
            return try await executeBuy(symbol: symbol, shares: shares, price: price)
        }

        let orderBody: [String: Any] = [
            "accountSpec": acctSpec,
            "accountId": acctId,
            "action": "Buy",
            "symbol": symbol,
            "orderQty": Int(shares),
            "orderType": "Market",
            "timeInForce": "Day",
            "isAutomated": true
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: orderBody)
        let (data, _) = try await authenticatedRequest(path: "/order/placeorder", method: "POST", body: jsonData)
        let result = try JSONDecoder().decode(NTPlaceOrderResult.self, from: data)

        if let failure = result.failureReason, failure != "Success" {
            throw TradingError.apiError("NinjaTrader order failed: \(result.failureText ?? failure)")
        }

        return Trade(symbol: symbol, type: .buy, shares: shares, price: price)
    }

    func executeSell(symbol: String, shares: Double, price: Double) async throws -> Trade {
        guard let acctId = accountId, let acctSpec = accountSpec else {
            try await ensureAuthenticated()
            guard accountId != nil else {
                throw TradingError.apiError("NinjaTrader: No account available")
            }
            return try await executeSell(symbol: symbol, shares: shares, price: price)
        }

        let orderBody: [String: Any] = [
            "accountSpec": acctSpec,
            "accountId": acctId,
            "action": "Sell",
            "symbol": symbol,
            "orderQty": Int(shares),
            "orderType": "Market",
            "timeInForce": "Day",
            "isAutomated": true
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: orderBody)
        let (data, _) = try await authenticatedRequest(path: "/order/placeorder", method: "POST", body: jsonData)
        let result = try JSONDecoder().decode(NTPlaceOrderResult.self, from: data)

        if let failure = result.failureReason, failure != "Success" {
            throw TradingError.apiError("NinjaTrader order failed: \(result.failureText ?? failure)")
        }

        return Trade(symbol: symbol, type: .sell, shares: shares, price: price)
    }

    func getAccount() async throws -> (cash: Double, portfolioValue: Double)? {
        let (data, _) = try await authenticatedRequest(path: "/account/list")
        let accounts = try JSONDecoder().decode([NTAccount].self, from: data)
        guard let acct = accounts.first else { return nil }

        // Get cash balance from account
        let (balData, _) = try await authenticatedRequest(path: "/cashBalance/deps?masterid=\(acct.id)")
        let balances = try JSONDecoder().decode([NTCashBalance].self, from: balData)
        let cash = balances.first?.cashBalance ?? 0

        return (cash: cash, portfolioValue: cash)
    }

    func getPositions() async throws -> [AlpacaPosition]? {
        // Return nil — NinjaTrader positions use a different model
        // Positions are tracked locally for now
        return nil
    }
}
