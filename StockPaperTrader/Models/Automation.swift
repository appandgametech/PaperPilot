import Foundation

struct AutomationRule: Identifiable, Codable {
    let id: UUID
    var name: String
    var symbol: String
    var isEnabled: Bool
    var conditions: [RuleCondition]
    var conditionLogic: ConditionLogic
    var action: RuleAction
    var shares: Double
    var repeatMode: RepeatMode
    var hasTriggered: Bool
    var triggerCount: Int
    var maxTriggers: Int  // 0 = unlimited
    var cooldownSeconds: Int // seconds between re-triggers
    var createdDate: Date
    var lastTriggeredDate: Date?
    var ruleTemplate: RuleTemplate?
    var hub: String? // "Equities" or "Futures" — nil = legacy/both

    // Migration: single condition init (backward compat)
    init(name: String, symbol: String, condition: RuleCondition, action: RuleAction, shares: Double) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.isEnabled = true
        self.conditions = [condition]
        self.conditionLogic = .all
        self.action = action
        self.shares = shares
        self.repeatMode = .once
        self.hasTriggered = false
        self.triggerCount = 0
        self.maxTriggers = 1
        self.cooldownSeconds = 0
        self.createdDate = Date()
        self.ruleTemplate = nil
    }

    // Full init
    init(name: String, symbol: String, conditions: [RuleCondition], logic: ConditionLogic,
         action: RuleAction, shares: Double, repeatMode: RepeatMode, maxTriggers: Int,
         cooldownSeconds: Int, template: RuleTemplate? = nil) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.isEnabled = true
        self.conditions = conditions
        self.conditionLogic = logic
        self.action = action
        self.shares = shares
        self.repeatMode = repeatMode
        self.hasTriggered = false
        self.triggerCount = 0
        self.maxTriggers = maxTriggers
        self.cooldownSeconds = cooldownSeconds
        self.createdDate = Date()
        self.ruleTemplate = template
    }

    // Backward compat accessor
    var condition: RuleCondition {
        conditions.first ?? RuleCondition(type: .price, value: 0, comparison: .above)
    }

    var canTriggerAgain: Bool {
        switch repeatMode {
        case .once:
            return !hasTriggered
        case .repeating:
            if maxTriggers > 0 && triggerCount >= maxTriggers { return false }
            if let last = lastTriggeredDate {
                return Date().timeIntervalSince(last) >= Double(cooldownSeconds)
            }
            return true
        }
    }
}

struct RuleCondition: Codable, Identifiable {
    let id: UUID
    var type: ConditionType
    var value: Double
    var comparison: ComparisonType

    init(type: ConditionType, value: Double, comparison: ComparisonType) {
        self.id = UUID()
        self.type = type
        self.value = value
        self.comparison = comparison
    }
}

enum ConditionLogic: String, Codable, CaseIterable {
    case all = "All (AND)"
    case any = "Any (OR)"
}

enum RepeatMode: String, Codable, CaseIterable {
    case once = "Once"
    case repeating = "Repeating"
}

enum RuleTemplate: String, Codable, CaseIterable {
    case custom = "Custom"
    case stopLoss = "Stop Loss"
    case takeProfit = "Take Profit"
    case buyTheDip = "Buy the Dip"
    case breakout = "Breakout"
    case meanReversion = "Mean Reversion"
    case trailingStopRule = "Trailing Stop"
    case timeBasedEntry = "Time-Based Entry"

    var description: String {
        switch self {
        case .custom: return "Build your own conditions"
        case .stopLoss: return "Sell when price drops below a threshold"
        case .takeProfit: return "Sell when price rises above a target"
        case .buyTheDip: return "Buy when price drops by a percentage"
        case .breakout: return "Buy when price breaks above day high"
        case .meanReversion: return "Buy when price drops below day low"
        case .trailingStopRule: return "Sell when price drops from high by trail amount"
        case .timeBasedEntry: return "Buy/sell at a specific time of day"
        }
    }

    var icon: String {
        switch self {
        case .custom: return "wrench.and.screwdriver"
        case .stopLoss: return "shield.slash"
        case .takeProfit: return "target"
        case .buyTheDip: return "arrow.down.to.line"
        case .breakout: return "arrow.up.forward"
        case .meanReversion: return "arrow.left.arrow.right"
        case .trailingStopRule: return "arrow.down.right"
        case .timeBasedEntry: return "clock"
        }
    }
}

enum ConditionType: String, Codable, CaseIterable {
    case price = "Price"
    case changePercent = "Change %"
    case volume = "Volume"
    case dayHigh = "Day High"
    case dayLow = "Day Low"
    case profitLossPercent = "Position P/L %"
    case rsiAbove = "RSI Above"
    case rsiBelow = "RSI Below"
    case macdCrossUp = "MACD Cross Up"
    case macdCrossDown = "MACD Cross Down"
    case timeOfDay = "Time of Day"
}

enum ComparisonType: String, Codable, CaseIterable {
    case above = "Above"
    case below = "Below"
    case equals = "Equals"
}

enum RuleAction: String, Codable, CaseIterable {
    case buy = "Buy"
    case sell = "Sell"
    case sellAll = "Sell All"
}

// AlertDirection is kept for AutomationEngine compatibility — maps to PriceAlert.AlertCondition
enum AlertDirection: String, Codable, CaseIterable {
    case above = "Goes Above"
    case below = "Goes Below"

    /// Convert to the unified AlertCondition used by PriceAlert
    var toCondition: PriceAlert.AlertCondition {
        switch self {
        case .above: return .above
        case .below: return .below
        }
    }

    /// Create from AlertCondition
    init(from condition: PriceAlert.AlertCondition) {
        switch condition {
        case .above: self = .above
        case .below: self = .below
        }
    }
}
