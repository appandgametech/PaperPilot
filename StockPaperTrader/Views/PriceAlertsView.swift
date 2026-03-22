import SwiftUI

struct PriceAlertsView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @EnvironmentObject var stockService: StockService
    @State private var showAddAlert = false

    private var activeAlerts: [PriceAlert] { portfolio.priceAlerts.filter(\.isActive) }
    private var triggeredAlerts: [PriceAlert] { portfolio.priceAlerts.filter { !$0.isActive } }

    var body: some View {
        List {
            if activeAlerts.isEmpty && triggeredAlerts.isEmpty {
                ContentUnavailableView(
                    "No Price Alerts",
                    systemImage: "bell.slash",
                    description: Text("Tap + to create an alert. You'll be notified when a stock hits your target price.")
                )
            }

            if !activeAlerts.isEmpty {
                Section("Active (\(activeAlerts.count))") {
                    ForEach(activeAlerts) { alert in
                        alertRow(alert)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { activeAlerts[$0].id }
                        ids.forEach { portfolio.removePriceAlert(id: $0) }
                    }
                }
            }

            if !triggeredAlerts.isEmpty {
                Section("Triggered") {
                    ForEach(triggeredAlerts.prefix(20)) { alert in
                        alertRow(alert)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { triggeredAlerts[$0].id }
                        ids.forEach { portfolio.removePriceAlert(id: $0) }
                    }
                }
            }
        }
        .navigationTitle("Price Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddAlert = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showAddAlert) {
            AddPriceAlertSheet()
        }
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        HStack {
            Image(systemName: alert.condition.icon)
                .foregroundStyle(alert.isActive ? (alert.condition == .above ? .green : .red) : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(alert.symbol).font(.subheadline.bold())
                    Text(alert.condition.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(alert.condition == .above ? Color.green.opacity(0.12) : Color.red.opacity(0.12), in: Capsule())
                        .foregroundStyle(alert.condition == .above ? .green : .red)
                }
                if let note = alert.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(portfolio.formatCurrency(alert.targetPrice))
                    .font(.subheadline.bold().monospacedDigit())
                if let current = stockService.quotes[alert.symbol]?.price, alert.isActive {
                    let diff = ((alert.targetPrice - current) / current) * 100
                    Text(String(format: "%+.1f%%", diff))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let triggered = alert.triggeredDate {
                    Text(triggered, style: .relative)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !alert.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            }
        }
    }
}

// MARK: - Add Price Alert Sheet
struct AddPriceAlertSheet: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @EnvironmentObject var stockService: StockService
    @Environment(\.dismiss) var dismiss
    @State private var symbol = ""
    @State private var targetPrice = ""
    @State private var condition: PriceAlert.AlertCondition = .above
    @State private var note = ""

    private var currentPrice: Double {
        stockService.quotes[symbol.uppercased()]?.price ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stock") {
                    TextField("Symbol (e.g. AAPL)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: symbol) { _, newValue in
                            let upper = newValue.uppercased()
                            if stockService.quotes[upper] == nil && upper.count >= 1 {
                                Task { await stockService.fetchQuotesForHub(.paper, symbols: [upper]) }
                            }
                        }
                    if currentPrice > 0 {
                        HStack {
                            Text("Current Price")
                            Spacer()
                            Text(portfolio.formatCurrency(currentPrice))
                                .font(.subheadline.bold().monospacedDigit())
                        }
                    }
                }

                Section("Alert When Price Is") {
                    Picker("Condition", selection: $condition) {
                        ForEach(PriceAlert.AlertCondition.allCases, id: \.self) {
                            Text($0.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Target Price", text: $targetPrice)
                        .keyboardType(.decimalPad)

                    if currentPrice > 0, let target = Double(targetPrice), target > 0 {
                        let diff = ((target - currentPrice) / currentPrice) * 100
                        Text(String(format: "%+.1f%% from current", diff))
                            .font(.caption).foregroundStyle(diff >= 0 ? .green : .red)
                    }
                }

                if currentPrice > 0 {
                    Section("Quick Set") {
                        HStack(spacing: 8) {
                            ForEach([2, 5, 10, 15, 20], id: \.self) { pct in
                                Button(condition == .above ? "+\(pct)%" : "-\(pct)%") {
                                    let mult = condition == .above ? (1 + Double(pct) / 100) : (1 - Double(pct) / 100)
                                    targetPrice = String(format: "%.2f", currentPrice * mult)
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                    }
                }

                Section("Note (optional)") {
                    TextField("Why this alert?", text: $note)
                }

                Section {
                    Button {
                        let alert = PriceAlert(
                            symbol: symbol.uppercased(),
                            targetPrice: Double(targetPrice) ?? 0,
                            condition: condition,
                            note: note.isEmpty ? nil : note
                        )
                        portfolio.addPriceAlert(alert)
                        dismiss()
                    } label: {
                        HStack { Spacer(); Text("Create Alert").font(.headline); Spacer() }
                    }
                    .disabled(symbol.isEmpty || Double(targetPrice) == nil || (Double(targetPrice) ?? 0) <= 0)
                }
            }
            .navigationTitle("New Price Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
