import Foundation
import Combine
import UserNotifications

@MainActor
class AutomationEngine: ObservableObject {
    @Published var rules: [AutomationRule] = []
    @Published var alerts: [PriceAlert] = []
    @Published var automationLog: [String] = []
    @Published var isRunning = false
    @Published var triggeredAlerts: [PriceAlert] = [] // for UI notification

    var portfolio: PortfolioManager?
    var stockService: StockService?

    private var evaluationTimer: Timer?
    private let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init() {
        loadRules()
        loadAlerts()
    }

    deinit {
        evaluationTimer?.invalidate()
    }

    func startEngine() {
        guard !isRunning else { return }
        isRunning = true
        evaluationTimer?.invalidate()
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.evaluateAllRules()
                self.evaluateAlerts()
            }
        }
        log("Engine started")
    }

    func stopEngine() {
        isRunning = false
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        log("Engine stopped")
    }

    // MARK: - Rule CRUD
    func addRule(_ rule: AutomationRule) {
        rules.append(rule)
        saveRules()
        log("Rule added: \(rule.name)")
    }

    func removeRule(at offsets: IndexSet) {
        let names = offsets.map { rules[$0].name }
        rules.remove(atOffsets: offsets)
        saveRules()
        names.forEach { log("Rule removed: \($0)") }
    }

    func toggleRule(id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].isEnabled.toggle()
            saveRules()
            log("\(rules[idx].name) \(rules[idx].isEnabled ? "enabled" : "disabled")")
        }
    }

    func resetRule(id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].hasTriggered = false
            rules[idx].triggerCount = 0
            rules[idx].lastTriggeredDate = nil
            saveRules()
            log("\(rules[idx].name) reset")
        }
    }

    // MARK: - Alert CRUD
    func addAlert(_ alert: PriceAlert) {
        alerts.append(alert)
        saveAlerts()
        log("Alert added: \(alert.symbol) \(alert.condition.rawValue) $\(String(format: "%.2f", alert.targetPrice))")
    }

    func removeAlert(at offsets: IndexSet) {
        alerts.remove(atOffsets: offsets)
        saveAlerts()
    }

    func dismissTriggeredAlert(_ alert: PriceAlert) {
        triggeredAlerts.removeAll { $0.id == alert.id }
    }

    // MARK: - Rule Evaluation (compound conditions)
    func evaluateAllRules() {
        guard let stockService, let portfolio else { return }

        let activeHubRaw = portfolio.activeHub.rawValue

        for i in rules.indices {
            guard rules[i].isEnabled, rules[i].canTriggerAgain else { continue }

            // Filter by hub: if rule has a hub set, only evaluate in that hub
            if let ruleHub = rules[i].hub, ruleHub != activeHubRaw { continue }

            guard let quote = stockService.quotes[rules[i].symbol] else { continue }

            let position = portfolio.positions.first { $0.symbol == rules[i].symbol }
            let conditionsMet = evaluateCompoundConditions(rules[i], quote: quote, position: position)

            if conditionsMet {
                executeRule(index: i, quote: quote, portfolio: portfolio)
            }
        }
    }

    private func evaluateCompoundConditions(_ rule: AutomationRule, quote: StockQuote, position: Position?) -> Bool {
        guard !rule.conditions.isEmpty else { return false }

        switch rule.conditionLogic {
        case .all:
            return rule.conditions.allSatisfy { evaluateCondition($0, quote: quote, position: position) }
        case .any:
            return rule.conditions.contains { evaluateCondition($0, quote: quote, position: position) }
        }
    }

    private func evaluateCondition(_ condition: RuleCondition, quote: StockQuote, position: Position?) -> Bool {
        let actual: Double
        switch condition.type {
        case .price: actual = quote.price
        case .changePercent: actual = quote.changePercent
        case .volume: actual = Double(quote.volume)
        case .dayHigh: actual = quote.dayHigh
        case .dayLow: actual = quote.dayLow
        case .profitLossPercent: actual = position?.profitLossPercent ?? 0
        }

        switch condition.comparison {
        case .above: return actual > condition.value
        case .below: return actual < condition.value
        case .equals: return abs(actual - condition.value) < 0.01
        }
    }

    private func executeRule(index i: Int, quote: StockQuote, portfolio: PortfolioManager) {
        let symbol = rules[i].symbol
        let shares = rules[i].shares
        let price = quote.price
        let action = rules[i].action

        // Safety check before automated execution
        let tradeType: TradeType = action == .buy ? .buy : .sell
        let safety = portfolio.activeHubPortfolio.canExecuteTrade(shares: shares, price: price, type: tradeType)
        if !safety.allowed {
            log("BLOCKED: \(rules[i].name) — \(safety.reason ?? "Safety control")")
            sendNotification(title: "Automation Blocked", body: "\(rules[i].name): \(safety.reason ?? "Safety control triggered")")
            return
        }

        rules[i].hasTriggered = true
        rules[i].triggerCount += 1
        rules[i].lastTriggeredDate = Date()
        saveRules()

        Task {
            switch action {
            case .buy:
                await portfolio.buy(symbol: symbol, shares: shares, price: price, isAutomated: true)
                log("AUTO BUY: \(Int(shares)) \(symbol) @ $\(String(format: "%.2f", price))")
                sendNotification(title: "Auto Buy Executed", body: "Bought \(Int(shares)) shares of \(symbol) at $\(String(format: "%.2f", price))")
            case .sell:
                await portfolio.sell(symbol: symbol, shares: shares, price: price, isAutomated: true)
                log("AUTO SELL: \(Int(shares)) \(symbol) @ $\(String(format: "%.2f", price))")
                sendNotification(title: "Auto Sell Executed", body: "Sold \(Int(shares)) shares of \(symbol) at $\(String(format: "%.2f", price))")
            case .sellAll:
                if let pos = portfolio.positions.first(where: { $0.symbol == symbol }) {
                    await portfolio.sell(symbol: symbol, shares: pos.shares, price: price, isAutomated: true)
                    log("AUTO SELL ALL: \(Int(pos.shares)) \(symbol) @ $\(String(format: "%.2f", price))")
                    sendNotification(title: "Auto Sell All Executed", body: "Sold all \(Int(pos.shares)) shares of \(symbol) at $\(String(format: "%.2f", price))")
                }
            }
            HapticManager.tradeFeedback()
        }
    }

    // MARK: - Alert Evaluation
    func evaluateAlerts() {
        guard let stockService else { return }

        for i in alerts.indices {
            guard alerts[i].isActive, !alerts[i].hasTriggered else { continue }
            guard let quote = stockService.quotes[alerts[i].symbol] else { continue }

            let triggered: Bool
            switch alerts[i].condition {
            case .above: triggered = quote.price >= alerts[i].targetPrice
            case .below: triggered = quote.price <= alerts[i].targetPrice
            }

            if triggered {
                alerts[i].hasTriggered = true
                alerts[i].triggeredDate = Date()
                alerts[i].isActive = false
                triggeredAlerts.append(alerts[i])
                saveAlerts()
                log("ALERT: \(alerts[i].symbol) \(alerts[i].condition.rawValue) $\(String(format: "%.2f", alerts[i].targetPrice))")
                HapticManager.tradeFeedback()
                sendNotification(
                    title: "Price Alert: \(alerts[i].symbol)",
                    body: "\(alerts[i].symbol) is now \(alerts[i].condition.rawValue) $\(String(format: "%.2f", alerts[i].targetPrice)) — current: $\(String(format: "%.2f", quote.price))"
                )
            }
        }
    }

    // MARK: - Template Helpers
    func createFromTemplate(_ template: RuleTemplate, symbol: String, quote: StockQuote, portfolio: PortfolioManager) -> AutomationRule? {
        let position = portfolio.positions.first { $0.symbol == symbol }

        switch template {
        case .stopLoss:
            guard let pos = position else { return nil }
            let stopPrice = pos.averageCost * 0.95 // 5% stop loss
            return AutomationRule(
                name: "Stop Loss: \(symbol)",
                symbol: symbol,
                conditions: [RuleCondition(type: .price, value: stopPrice, comparison: .below)],
                logic: .all,
                action: .sellAll,
                shares: pos.shares,
                repeatMode: .once,
                maxTriggers: 1,
                cooldownSeconds: 0,
                template: .stopLoss
            )

        case .takeProfit:
            guard let pos = position else { return nil }
            let targetPrice = pos.averageCost * 1.10 // 10% take profit
            return AutomationRule(
                name: "Take Profit: \(symbol)",
                symbol: symbol,
                conditions: [RuleCondition(type: .price, value: targetPrice, comparison: .above)],
                logic: .all,
                action: .sellAll,
                shares: pos.shares,
                repeatMode: .once,
                maxTriggers: 1,
                cooldownSeconds: 0,
                template: .takeProfit
            )

        case .buyTheDip:
            return AutomationRule(
                name: "Buy Dip: \(symbol)",
                symbol: symbol,
                conditions: [
                    RuleCondition(type: .changePercent, value: -3.0, comparison: .below)
                ],
                logic: .all,
                action: .buy,
                shares: 5,
                repeatMode: .repeating,
                maxTriggers: 3,
                cooldownSeconds: 3600,
                template: .buyTheDip
            )

        case .breakout:
            return AutomationRule(
                name: "Breakout: \(symbol)",
                symbol: symbol,
                conditions: [
                    RuleCondition(type: .price, value: quote.dayHigh, comparison: .above),
                    RuleCondition(type: .changePercent, value: 1.0, comparison: .above)
                ],
                logic: .all,
                action: .buy,
                shares: 10,
                repeatMode: .once,
                maxTriggers: 1,
                cooldownSeconds: 0,
                template: .breakout
            )

        case .meanReversion:
            return AutomationRule(
                name: "Mean Reversion: \(symbol)",
                symbol: symbol,
                conditions: [
                    RuleCondition(type: .changePercent, value: -5.0, comparison: .below)
                ],
                logic: .all,
                action: .buy,
                shares: 10,
                repeatMode: .repeating,
                maxTriggers: 2,
                cooldownSeconds: 7200,
                template: .meanReversion
            )

        case .custom:
            return nil
        }
    }

    func log(_ message: String) {
        let timestamp = logFormatter.string(from: Date())
        automationLog.insert("[\(timestamp)] \(message)", at: 0)
        if automationLog.count > 500 {
            automationLog = Array(automationLog.prefix(500))
        }
    }

    // MARK: - Persistence
    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: "automation_rules_v2")
        }
    }

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: "automation_rules_v2"),
           let saved = try? JSONDecoder().decode([AutomationRule].self, from: data) {
            rules = saved
        }
    }

    private func saveAlerts() {
        if let data = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(data, forKey: "automation_alerts")
        }
    }

    private func loadAlerts() {
        if let data = UserDefaults.standard.data(forKey: "automation_alerts"),
           let saved = try? JSONDecoder().decode([PriceAlert].self, from: data) {
            alerts = saved
        }
    }

    // MARK: - Local Notifications
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
