import SwiftUI

struct AutomationView: View {
    @EnvironmentObject var automationEngine: AutomationEngine
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @State private var showAddRule = false
    @State private var showAddAlert = false
    @State private var showInfo = false
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Engine toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automation Engine")
                            .font(.subheadline.bold())
                        Text(automationEngine.isRunning ? "Active — checking every 10s" : "Stopped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { automationEngine.isRunning },
                        set: { $0 ? automationEngine.startEngine() : automationEngine.stopEngine() }
                    ))
                    .labelsHidden()
                }
                .padding()
                .background(.regularMaterial)

                Picker("Section", selection: $selectedTab) {
                    Text("Rules").tag(0)
                    Text("Alerts").tag(1)
                    Text("Log").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch selectedTab {
                case 0: rulesTab
                case 1: alertsTab
                case 2: logTab
                default: EmptyView()
                }
            }
            .navigationTitle("\(portfolio.activeHub.rawValue) Automate")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAddRule = true } label: {
                            Label("New Rule", systemImage: "gearshape.2")
                        }
                        Button { showAddAlert = true } label: {
                            Label("New Price Alert", systemImage: "bell")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAddRule) {
                AddRuleSheet()
            }
            .sheet(isPresented: $showAddAlert) {
                AddAlertSheet()
            }
            .sheet(isPresented: $showInfo) {
                AutomationInfoSheet()
            }
            .overlay(alignment: .top) {
                if let alert = automationEngine.triggeredAlerts.first {
                    alertBanner(alert)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // Hub-filtered rules — only show rules for the active hub
    private var hubRules: [AutomationRule] {
        let activeHubRaw = portfolio.activeHub.rawValue
        return automationEngine.rules.filter { rule in
            guard let ruleHub = rule.hub else { return true } // legacy rules with no hub show everywhere
            return ruleHub == activeHubRaw
        }
    }

    // MARK: - Rules Tab
    private var rulesTab: some View {
        List {
            if hubRules.isEmpty {
                ContentUnavailableView(
                    "No \(portfolio.activeHub.rawValue) Rules",
                    systemImage: "gearshape.2",
                    description: Text("Create rules to auto-trade based on conditions. Rules created here belong to the \(portfolio.activeHub.rawValue) hub.")
                )
            }
            ForEach(hubRules) { rule in
                RuleRowV2(rule: rule)
            }
            .onDelete { offsets in
                // Map filtered indices back to engine indices
                let rulesToDelete = offsets.map { hubRules[$0].id }
                for id in rulesToDelete {
                    if let idx = automationEngine.rules.firstIndex(where: { $0.id == id }) {
                        automationEngine.removeRule(at: IndexSet(integer: idx))
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Alerts Tab
    private var alertsTab: some View {
        List {
            if automationEngine.alerts.isEmpty {
                ContentUnavailableView(
                    "No Alerts",
                    systemImage: "bell.slash",
                    description: Text("Set price alerts to get notified when stocks hit your targets.")
                )
            }

            let active = automationEngine.alerts.filter { $0.isActive }
            let triggered = automationEngine.alerts.filter { $0.hasTriggered }

            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { alert in
                        alertRow(alert)
                    }
                }
            }
            if !triggered.isEmpty {
                Section("Triggered") {
                    ForEach(triggered) { alert in
                        alertRow(alert)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Log Tab
    private var logTab: some View {
        List {
            if automationEngine.automationLog.isEmpty {
                Text("No activity yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(automationEngine.automationLog, id: \.self) { entry in
                Text(entry)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        HStack {
            Image(systemName: alert.hasTriggered ? "bell.fill" : "bell")
                .foregroundStyle(alert.hasTriggered ? .orange : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.symbol).font(.subheadline.bold())
                Text("\(alert.condition.rawValue) $\(String(format: "%.2f", alert.targetPrice))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if alert.hasTriggered {
                Text("Triggered")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if let quote = stockService.quotes[alert.symbol] {
                Text("Now: $\(String(format: "%.2f", quote.price))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func alertBanner(_ alert: PriceAlert) -> some View {
        HStack {
            Image(systemName: "bell.fill")
                .foregroundStyle(.white)
            VStack(alignment: .leading) {
                Text("\(alert.symbol) Alert")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("\(alert.condition.rawValue) $\(String(format: "%.2f", alert.targetPrice))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Button {
                withAnimation { automationEngine.dismissTriggeredAlert(alert) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding()
        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}


// MARK: - RuleRowV2
struct RuleRowV2: View {
    @EnvironmentObject var automationEngine: AutomationEngine
    let rule: AutomationRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: name + template badge + toggle
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(rule.name)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if let template = rule.ruleTemplate, template != .custom {
                            Label(template.rawValue, systemImage: template.icon)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(rule.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in automationEngine.toggleRule(id: rule.id) }
                ))
                .labelsHidden()
            }

            // Conditions
            VStack(alignment: .leading, spacing: 3) {
                let logicLabel = rule.conditionLogic == .all ? "ALL" : "ANY"
                if rule.conditions.count > 1 {
                    Text("When \(logicLabel) match:")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                ForEach(rule.conditions) { cond in
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(.secondary)
                        Text("\(cond.type.rawValue) \(cond.comparison.rawValue) \(conditionValueText(cond))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Action + repeat info
            HStack {
                Label("\(rule.action.rawValue) \(rule.action == .sellAll ? "" : "\(Int(rule.shares)) shares")",
                      systemImage: rule.action == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(rule.action == .buy ? .green : .red)

                Spacer()

                // Repeat badge
                if rule.repeatMode == .repeating {
                    HStack(spacing: 3) {
                        Image(systemName: "repeat")
                        Text("\(rule.triggerCount)/\(rule.maxTriggers > 0 ? "\(rule.maxTriggers)" : "∞")")
                    }
                    .font(.caption2)
                    .foregroundStyle(.purple)
                } else {
                    if rule.hasTriggered {
                        Label("Fired", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Label("Once", systemImage: "1.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Cooldown info for repeating rules
            if rule.repeatMode == .repeating && rule.cooldownSeconds > 0 {
                Text("Cooldown: \(formatCooldown(rule.cooldownSeconds))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(rule.isEnabled ? 1 : 0.5)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                if let idx = automationEngine.rules.firstIndex(where: { $0.id == rule.id }) {
                    automationEngine.removeRule(at: IndexSet(integer: idx))
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if rule.hasTriggered {
                Button {
                    automationEngine.resetRule(id: rule.id)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .tint(.orange)
            }
        }
    }

    private func conditionValueText(_ cond: RuleCondition) -> String {
        switch cond.type {
        case .price, .dayHigh, .dayLow:
            return "$\(String(format: "%.2f", cond.value))"
        case .changePercent, .profitLossPercent:
            return "\(String(format: "%.1f", cond.value))%"
        case .volume:
            if cond.value >= 1_000_000 {
                return "\(String(format: "%.1fM", cond.value / 1_000_000))"
            } else if cond.value >= 1_000 {
                return "\(String(format: "%.0fK", cond.value / 1_000))"
            }
            return "\(Int(cond.value))"
        case .rsiAbove, .rsiBelow:
            return "\(String(format: "%.0f", cond.value))"
        case .macdCrossUp:
            return "Signal ↑"
        case .macdCrossDown:
            return "Signal ↓"
        case .timeOfDay:
            let hour = Int(cond.value)
            let min = Int((cond.value - Double(hour)) * 60)
            return String(format: "%d:%02d", hour, min)
        }
    }

    private func formatCooldown(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return "\(seconds / 3600)h"
        } else if seconds >= 60 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }
}


// MARK: - AddRuleSheet
struct AddRuleSheet: View {
    @EnvironmentObject var automationEngine: AutomationEngine
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplate: RuleTemplate = .custom
    @State private var name = ""
    @State private var symbol = ""
    @State private var conditions: [RuleCondition] = [RuleCondition(type: .price, value: 0, comparison: .above)]
    @State private var conditionLogic: ConditionLogic = .all
    @State private var action: RuleAction = .buy
    @State private var shares: String = "10"
    @State private var repeatMode: RepeatMode = .once
    @State private var maxTriggers: String = "1"
    @State private var cooldownMinutes: String = "60"
    @State private var symbolSearch = ""
    @State private var searchResults: [StockQuote] = []
    @State private var showSymbolPicker = false

    private var isValid: Bool {
        !name.isEmpty && !symbol.isEmpty && !conditions.isEmpty && (Double(shares) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // Template picker
                Section("Template") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(RuleTemplate.allCases, id: \.self) { template in
                                templateButton(template)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Basic info
                Section("Rule Info") {
                    TextField("Rule Name", text: $name)
                    HStack {
                        TextField("Symbol (e.g. AAPL)", text: $symbol)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button {
                            showSymbolPicker = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }

                // Conditions
                Section {
                    if conditions.count > 1 {
                        Picker("Logic", selection: $conditionLogic) {
                            ForEach(ConditionLogic.allCases, id: \.self) { logic in
                                Text(logic.rawValue).tag(logic)
                            }
                        }
                    }

                    ForEach(conditions.indices, id: \.self) { idx in
                        conditionRow(index: idx)
                    }
                    .onDelete { conditions.remove(atOffsets: $0) }

                    Button {
                        conditions.append(RuleCondition(type: .price, value: 0, comparison: .above))
                    } label: {
                        Label("Add Condition", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Conditions (\(conditions.count))")
                }

                // Action
                Section("Action") {
                    Picker("Action", selection: $action) {
                        ForEach(RuleAction.allCases, id: \.self) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    if action != .sellAll {
                        TextField("Shares", text: $shares)
                            .keyboardType(.decimalPad)
                    }
                }

                // Repeat settings
                Section("Repeat") {
                    Picker("Mode", selection: $repeatMode) {
                        ForEach(RepeatMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    if repeatMode == .repeating {
                        TextField("Max Triggers (0 = unlimited)", text: $maxTriggers)
                            .keyboardType(.numberPad)
                        TextField("Cooldown (minutes)", text: $cooldownMinutes)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createRule() }
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                symbolPickerSheet
            }
            .onChange(of: selectedTemplate) { _, newTemplate in
                applyTemplate(newTemplate)
            }
        }
    }

    private func templateButton(_ template: RuleTemplate) -> some View {
        Button {
            selectedTemplate = template
        } label: {
            VStack(spacing: 4) {
                Image(systemName: template.icon)
                    .font(.title3)
                Text(template.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: 72, height: 60)
            .background(selectedTemplate == template ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08),
                         in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedTemplate == template ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func conditionRow(index: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Type", selection: $conditions[index].type) {
                    ForEach(ConditionType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .labelsHidden()

                Picker("Comp", selection: $conditions[index].comparison) {
                    ForEach(ComparisonType.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text(valueLabel(for: conditions[index].type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Value", value: $conditions[index].value, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 2)
    }

    private func valueLabel(for type: ConditionType) -> String {
        switch type {
        case .price, .dayHigh, .dayLow: return "$"
        case .changePercent, .profitLossPercent: return "%"
        case .volume: return "#"
        case .rsiAbove, .rsiBelow: return "RSI"
        case .macdCrossUp, .macdCrossDown: return "—"
        case .timeOfDay: return "Hour"
        }
    }

    private var symbolPickerSheet: some View {
        NavigationStack {
            List {
                TextField("Search stocks...", text: $symbolSearch)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task {
                            searchResults = await stockService.searchStocks(query: symbolSearch)
                        }
                    }

                ForEach(searchResults) { quote in
                    Button {
                        symbol = quote.symbol
                        showSymbolPicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(quote.symbol).font(.subheadline.bold())
                                Text(quote.name).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("$\(String(format: "%.2f", quote.price))")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Find Symbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSymbolPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func applyTemplate(_ template: RuleTemplate) {
        guard template != .custom else { return }
        let sym = symbol.isEmpty ? "AAPL" : symbol

        // Use engine's template factory if we have a quote
        if let quote = stockService.quotes[sym],
           let rule = automationEngine.createFromTemplate(template, symbol: sym, quote: quote, portfolio: portfolio) {
            name = rule.name
            conditions = rule.conditions
            conditionLogic = rule.conditionLogic
            action = rule.action
            shares = "\(Int(rule.shares))"
            repeatMode = rule.repeatMode
            maxTriggers = "\(rule.maxTriggers)"
            cooldownMinutes = "\(rule.cooldownSeconds / 60)"
        } else {
            // Fallback defaults
            name = "\(template.rawValue): \(sym)"
            switch template {
            case .stopLoss:
                conditions = [RuleCondition(type: .profitLossPercent, value: -5, comparison: .below)]
                action = .sellAll
                repeatMode = .once
            case .takeProfit:
                conditions = [RuleCondition(type: .profitLossPercent, value: 10, comparison: .above)]
                action = .sellAll
                repeatMode = .once
            case .buyTheDip:
                conditions = [RuleCondition(type: .changePercent, value: -3, comparison: .below)]
                action = .buy
                repeatMode = .repeating
                maxTriggers = "3"
                cooldownMinutes = "60"
            case .breakout:
                conditions = [
                    RuleCondition(type: .changePercent, value: 2, comparison: .above),
                    RuleCondition(type: .volume, value: 1_000_000, comparison: .above)
                ]
                conditionLogic = .all
                action = .buy
                repeatMode = .once
            case .meanReversion:
                conditions = [RuleCondition(type: .changePercent, value: -5, comparison: .below)]
                action = .buy
                repeatMode = .repeating
                maxTriggers = "2"
                cooldownMinutes = "120"
            case .trailingStopRule:
                conditions = [RuleCondition(type: .profitLossPercent, value: -3, comparison: .below)]
                action = .sellAll
                repeatMode = .once
                name = "Trailing Stop: \(sym)"
            case .timeBasedEntry:
                conditions = [RuleCondition(type: .timeOfDay, value: 9.5, comparison: .equals)]
                action = .buy
                repeatMode = .repeating
                maxTriggers = "5"
                cooldownMinutes = "1440"
                name = "Time Entry: \(sym)"
            case .custom:
                break
            }
        }
    }

    private func createRule() {
        let sharesVal = Double(shares) ?? 10
        let maxTriggersVal = Int(maxTriggers) ?? 1
        let cooldownSec = (Int(cooldownMinutes) ?? 60) * 60

        var rule = AutomationRule(
            name: name,
            symbol: symbol.uppercased(),
            conditions: conditions,
            logic: conditionLogic,
            action: action,
            shares: sharesVal,
            repeatMode: repeatMode,
            maxTriggers: maxTriggersVal,
            cooldownSeconds: cooldownSec,
            template: selectedTemplate
        )
        rule.hub = portfolio.activeHub.rawValue
        automationEngine.addRule(rule)
        dismiss()
    }
}


// MARK: - AddAlertSheet
struct AddAlertSheet: View {
    @EnvironmentObject var automationEngine: AutomationEngine
    @EnvironmentObject var stockService: StockService
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var targetPrice: String = ""
    @State private var direction: PriceAlert.AlertCondition = .above
    @State private var symbolSearch = ""
    @State private var searchResults: [StockQuote] = []
    @State private var showSymbolPicker = false

    private var isValid: Bool {
        !symbol.isEmpty && (Double(targetPrice) ?? 0) > 0
    }

    private var currentPrice: Double? {
        stockService.quotes[symbol.uppercased()]?.price
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Symbol") {
                    HStack {
                        TextField("Symbol (e.g. AAPL)", text: $symbol)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button {
                            showSymbolPicker = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    if let price = currentPrice {
                        HStack {
                            Text("Current Price")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("$\(String(format: "%.2f", price))")
                                .font(.subheadline.bold().monospacedDigit())
                        }
                    }
                }

                Section("Alert Condition") {
                    Picker("Direction", selection: $direction) {
                        ForEach(PriceAlert.AlertCondition.allCases, id: \.self) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    TextField("Target Price", text: $targetPrice)
                        .keyboardType(.decimalPad)
                }

                if let price = currentPrice, let target = Double(targetPrice), target > 0 {
                    Section("Preview") {
                        let diff = target - price
                        let pct = (diff / price) * 100
                        HStack {
                            Text("Distance")
                            Spacer()
                            Text("\(String(format: "%+.2f", diff)) (\(String(format: "%+.1f%%", pct)))")
                                .foregroundStyle(diff >= 0 ? .green : .red)
                        }
                    }
                }
            }
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let alert = PriceAlert(
                            symbol: symbol.uppercased(),
                            targetPrice: Double(targetPrice) ?? 0,
                            condition: direction
                        )
                        automationEngine.addAlert(alert)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                NavigationStack {
                    List {
                        TextField("Search stocks...", text: $symbolSearch)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onSubmit {
                                Task {
                                    searchResults = await stockService.searchStocks(query: symbolSearch)
                                }
                            }
                        ForEach(searchResults) { quote in
                            Button {
                                symbol = quote.symbol
                                showSymbolPicker = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(quote.symbol).font(.subheadline.bold())
                                        Text(quote.name).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("$\(String(format: "%.2f", quote.price))")
                                        .font(.subheadline.monospacedDigit())
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    .navigationTitle("Find Symbol")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSymbolPicker = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}


// MARK: - Automation Info Sheet
struct AutomationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    infoSection(
                        icon: "gearshape.2.fill",
                        color: .blue,
                        title: "How Automation Works",
                        items: [
                            "The engine runs a check loop every 10 seconds while active.",
                            "Each rule's conditions are evaluated against live market quotes from your selected data provider (Yahoo Finance, Alpaca, etc.).",
                            "When all conditions match (AND) or any condition matches (OR), the rule fires and places a trade automatically.",
                            "Trades execute through whichever trading mode you've selected in Settings — Local Paper, Alpaca, or NinjaTrader."
                        ]
                    )

                    infoSection(
                        icon: "list.bullet.rectangle",
                        color: .purple,
                        title: "Rules",
                        items: [
                            "Rules combine one or more conditions with AND/OR logic.",
                            "Conditions can check: price, % change, volume, day high/low, or your position's P/L %.",
                            "Actions: Buy, Sell, or Sell All (liquidate entire position).",
                            "Use templates (Stop Loss, Take Profit, Buy the Dip, Breakout, Mean Reversion) for quick setup.",
                            "Rules can fire once or repeat with a cooldown and max trigger count."
                        ]
                    )

                    infoSection(
                        icon: "bell.fill",
                        color: .orange,
                        title: "Price Alerts",
                        items: [
                            "Alerts notify you when a stock goes above or below a target price.",
                            "They don't place trades — they're just notifications.",
                            "Once triggered, an alert is marked as fired and won't re-trigger."
                        ]
                    )

                    infoSection(
                        icon: "antenna.radiowaves.left.and.right",
                        color: .green,
                        title: "Data & Execution",
                        items: [
                            "Market data comes from Yahoo Finance (free, unofficial) or Alpaca (free signup, official IEX feed).",
                            "Yahoo Finance has no official API — we use their internal endpoints. They may throttle or block heavy usage. The app backs off automatically and shows a warning.",
                            "Refresh interval is 30s by default for Yahoo (minimum 15s). Lower intervals increase throttle risk.",
                            "Alpaca and NinjaTrader use official REST APIs with proper authentication.",
                            "Local Paper mode simulates trades on-device — no real money involved.",
                            "NinjaTrader Live mode uses REAL money. Be careful."
                        ]
                    )

                    infoSection(
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        title: "Good to Know",
                        items: [
                            "Automation only runs while the app is open and the engine toggle is ON.",
                            "If the app is backgrounded or closed, rules stop evaluating.",
                            "Quotes may be delayed depending on your data provider — Yahoo can lag by a few seconds to minutes.",
                            "Rules and alerts are saved locally on your device (UserDefaults). They persist across app launches.",
                            "The automation log keeps the last 500 entries.",
                            "Swipe left on a rule to delete it. Swipe right to reset a fired rule."
                        ]
                    )

                }
                .padding()
            }
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoSection(icon: String, color: Color, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
