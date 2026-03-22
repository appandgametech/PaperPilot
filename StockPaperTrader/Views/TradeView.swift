import SwiftUI

struct TradeView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @EnvironmentObject var stockService: StockService
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showTradeSheet = false
    @State private var showToast = false
    @State private var showExportSheet = false
    @State private var showInfoSheet = false
    @State private var tradeFilter: TradeFilter = .all

    enum TradeFilter: String, CaseIterable {
        case all = "All"
        case buys = "Buys"
        case sells = "Sells"
        case automated = "Auto"
    }

    private var filteredTrades: [Trade] {
        switch tradeFilter {
        case .all: return portfolio.tradeHistory
        case .buys: return portfolio.tradeHistory.filter { $0.type == .buy }
        case .sells: return portfolio.tradeHistory.filter { $0.type == .sell }
        case .automated: return portfolio.tradeHistory.filter { $0.isAutomated }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Hub identity banner
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: portfolio.activeHub.icon)
                            .font(.title3)
                            .foregroundStyle(portfolio.activeHub.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(portfolio.activeHub.broker)
                                .font(.caption.bold())
                            Text(portfolio.isLiveTrading ? "Live Trading — Real Money" : portfolio.activeHub == .paper ? "Simulated Trading" : "Paper Mode")
                                .font(.caption2)
                                .foregroundStyle(portfolio.isLiveTrading ? .red : .secondary)
                        }
                        Spacer()
                        if portfolio.isLiveTrading {
                            Text("LIVE")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.red, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Cash Available")
                        Spacer()
                        Text(portfolio.formatCurrency(portfolio.cash))
                            .font(.headline.monospacedDigit())
                    }
                    HStack {
                        Text("Portfolio Value")
                        Spacer()
                        Text(portfolio.formatCurrency(portfolio.totalPortfolioValue))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                // Pending orders
                if !portfolio.pendingOrders.filter(\.isActive).isEmpty {
                    Section("Pending Orders") {
                        ForEach(portfolio.pendingOrders.filter(\.isActive)) { order in
                            pendingOrderRow(order)
                        }
                    }
                }

                // Filled pending orders (recent)
                let filledOrders = portfolio.pendingOrders.filter { !$0.isActive }.prefix(5)
                if !filledOrders.isEmpty {
                    Section("Recently Filled") {
                        ForEach(Array(filledOrders)) { order in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(order.type.rawValue) \(order.side.rawValue) \(order.symbol)")
                                        .font(.caption.bold())
                                    Text("\(Int(order.shares)) shares")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let filled = order.filledDate {
                                    Text(filled, style: .relative)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !portfolio.positions.isEmpty {
                    Section("Open Positions") {
                        ForEach(portfolio.positions) { position in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(position.symbol).font(.headline)
                                    Text("\(portfolio.formatShares(position.shares)) shares")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(portfolio.formatCurrency(position.marketValue))
                                        .font(.subheadline.monospacedDigit())
                                    Text(String(format: "%+.2f%%", position.profitLossPercent))
                                        .font(.caption.bold())
                                        .foregroundStyle(position.isPositive ? .green : .red)
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("Filter", selection: $tradeFilter) {
                        ForEach(TradeFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Trade History (\(filteredTrades.count))")
                }

                Section {
                    if filteredTrades.isEmpty {
                        ContentUnavailableView(
                            tradeFilter == .all ? "No Trades Yet" : "No \(tradeFilter.rawValue) Trades",
                            systemImage: "arrow.left.arrow.right.circle",
                            description: Text(tradeFilter == .all ? "Tap + to place your first trade." : "No trades match this filter.")
                        )
                    }
                    ForEach(filteredTrades) { trade in
                        TradeHistoryRow(trade: trade)
                    }
                }
            }
            .navigationTitle("\(portfolio.activeHub.rawValue) Trade")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button { showInfoSheet = true } label: {
                            Image(systemName: "info.circle")
                        }
                        if !portfolio.tradeHistory.isEmpty {
                            ShareLink(item: portfolio.exportTradesCSV(),
                                      preview: SharePreview("PaperPilot Trades.csv", image: Image(systemName: "doc.text"))) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTradeSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showTradeSheet) {
                TradeEntrySheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNewTrade)) { _ in
                showTradeSheet = true
            }
            .sheet(isPresented: $showInfoSheet) {
                TradeInfoSheet()
            }
            .overlay(alignment: .bottom) {
                if showToast, let msg = portfolio.lastTradeMessage {
                    Text(msg)
                        .font(.subheadline.bold())
                        .padding()
                        .background(.green.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: portfolio.lastTradeMessage) { _, newValue in
                guard newValue != nil else { return }
                withAnimation { showToast = true }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation {
                        showToast = false
                        portfolio.lastTradeMessage = nil
                    }
                }
            }
        }
    }

    private func pendingOrderRow(_ order: PendingOrder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(order.type.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                    Text("\(order.side.rawValue) \(order.symbol)")
                        .font(.subheadline.bold())
                }
                HStack(spacing: 8) {
                    Text("\(Int(order.shares)) shares")
                        .font(.caption).foregroundStyle(.secondary)
                    if let limit = order.limitPrice {
                        Text("Limit: $\(String(format: "%.2f", limit))")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let stop = order.stopPrice {
                        Text("Stop: $\(String(format: "%.2f", stop))")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Spacer()
            Button(role: .destructive) {
                portfolio.cancelPendingOrder(id: order.id)
            } label: {
                Text("Cancel")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }
}


// MARK: - Trade Entry Sheet with Order Types
struct TradeEntrySheet: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @EnvironmentObject var stockService: StockService
    @Environment(\.dismiss) var dismiss

    @State private var symbol = ""
    @State private var sharesText = ""
    @State private var tradeType: TradeType = .buy
    @State private var orderType: OrderType = .market
    @State private var limitPriceText = ""
    @State private var stopPriceText = ""
    @State private var isExecuting = false
    @State private var showConfirmation = false
    @State private var noteText = ""
    @State private var dollarAmountText = ""
    @State private var orderMode: OrderMode = .shares

    enum OrderMode: String, CaseIterable {
        case shares = "Shares"
        case dollars = "Dollars"
    }

    private var currentPrice: Double {
        stockService.quotes[symbol.uppercased()]?.price ?? 0
    }
    private var shares: Double {
        if orderMode == .dollars {
            return portfolio.sharesForDollarAmount(Double(dollarAmountText) ?? 0, price: currentPrice)
        }
        return Double(sharesText) ?? 0
    }
    private var estimatedTotal: Double {
        let price = orderType == .market ? currentPrice : (Double(limitPriceText) ?? currentPrice)
        return shares * price
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Order") {
                    Picker("Side", selection: $tradeType) {
                        ForEach(TradeType.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Order Type", selection: $orderType) {
                        ForEach(OrderType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Text(orderType.description)
                        .font(.caption2).foregroundStyle(.secondary)

                    TextField("Symbol (e.g. AAPL)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: symbol) { _, newValue in
                            let upper = newValue.uppercased()
                            if stockService.quotes[upper] == nil && upper.count >= 1 {
                                Task { await stockService.fetchQuotesForHub(portfolio.activeHub, symbols: [upper]) }
                            }
                        }

                    Picker("Order By", selection: $orderMode) {
                        ForEach(OrderMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    if orderMode == .shares {
                        TextField("Shares", text: $sharesText)
                            .keyboardType(.decimalPad)
                    } else {
                        TextField("Dollar Amount (e.g. 500)", text: $dollarAmountText)
                            .keyboardType(.decimalPad)
                        if currentPrice > 0, let dollars = Double(dollarAmountText), dollars > 0 {
                            Text("≈ \(portfolio.formatShares(portfolio.sharesForDollarAmount(dollars, price: currentPrice))) shares")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Journal Note (optional)") {
                    TextField("Why this trade?", text: $noteText)
                }

                if (orderType == .stopLoss || orderType == .stopLimit) && tradeType == .buy {
                    Section {
                        Label("Stop Loss orders are sell-only. Switch to Sell or use a different order type.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if orderType == .limit || orderType == .stopLimit {
                    Section("Limit Price") {
                        TextField("Limit Price", text: $limitPriceText)
                            .keyboardType(.decimalPad)
                        if currentPrice > 0 {
                            Button("Use current ($\(String(format: "%.2f", currentPrice)))") {
                                limitPriceText = String(format: "%.2f", currentPrice)
                            }
                            .font(.caption)
                        }
                    }
                }

                if orderType == .stopLoss || orderType == .stopLimit {
                    Section("Stop Price") {
                        TextField("Stop Price", text: $stopPriceText)
                            .keyboardType(.decimalPad)
                        if currentPrice > 0 {
                            HStack(spacing: 8) {
                                ForEach([2, 5, 10], id: \.self) { pct in
                                    Button("-\(pct)%") {
                                        stopPriceText = String(format: "%.2f", currentPrice * (1 - Double(pct) / 100))
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }

                Section("Preview") {
                    HStack {
                        Text("Current Price")
                        Spacer()
                        if currentPrice > 0 {
                            Text(portfolio.formatCurrency(currentPrice)).monospacedDigit()
                        } else {
                            Text("Enter symbol").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Estimated Total")
                        Spacer()
                        Text(portfolio.formatCurrency(estimatedTotal))
                            .font(.headline.monospacedDigit())
                    }
                    if tradeType == .buy {
                        HStack {
                            Text("Cash Available")
                            Spacer()
                            Text(portfolio.formatCurrency(portfolio.cash))
                                .foregroundStyle(estimatedTotal > portfolio.cash ? .red : .secondary)
                        }
                    }
                }

                if let error = portfolio.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        showConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isExecuting { ProgressView() }
                            else { Text(orderType == .market ? "Execute \(tradeType.rawValue)" : "Place \(orderType.rawValue) Order").font(.headline) }
                            Spacer()
                        }
                    }
                    .disabled(currentPrice <= 0 || shares <= 0 || isExecuting || ((orderType == .stopLoss || orderType == .stopLimit) && tradeType == .buy))
                }
            }
            .navigationTitle("New Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Confirm \(orderType.rawValue) Order", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button(orderType == .market ? "\(tradeType.rawValue) Now" : "Place Order",
                       role: tradeType == .sell ? .destructive : .none) {
                    executeOrder()
                }
            } message: {
                let displayShares = portfolio.formatShares(shares)
                if orderType == .market {
                    Text("\(tradeType.rawValue) \(displayShares) shares of \(symbol.uppercased()) at market price (\(portfolio.formatCurrency(currentPrice)))?")
                } else {
                    Text("Place \(orderType.rawValue) \(tradeType.rawValue) order for \(displayShares) shares of \(symbol.uppercased())?")
                }
            }
        }
    }

    private func executeOrder() {
        let sym = symbol.uppercased()
        let tradeNote = noteText.isEmpty ? nil : noteText
        if orderType == .market {
            isExecuting = true
            Task {
                switch tradeType {
                case .buy: await portfolio.buy(symbol: sym, shares: shares, price: currentPrice)
                case .sell: await portfolio.sell(symbol: sym, shares: shares, price: currentPrice)
                }
                // Attach note to the most recent trade
                if let tradeNote, let lastTrade = portfolio.tradeHistory.first {
                    portfolio.updateTradeNote(tradeId: lastTrade.id, note: tradeNote)
                }
                isExecuting = false
                if portfolio.errorMessage == nil { dismiss() }
            }
        } else {
            let order = PendingOrder(
                symbol: sym,
                type: orderType,
                side: tradeType,
                shares: shares,
                limitPrice: Double(limitPriceText),
                stopPrice: Double(stopPriceText)
            )
            portfolio.placePendingOrder(order)
            dismiss()
        }
    }
}

// MARK: - Quick Trade Sheet
struct QuickTradeSheet: View {
    let symbol: String
    let price: Double
    let tradeType: TradeType

    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.dismiss) var dismiss
    @State private var sharesText = ""
    @State private var isExecuting = false
    @State private var showConfirmation = false

    private var shares: Double { Double(sharesText) ?? 0 }
    private var total: Double { shares * price }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(symbol).font(.title2.bold())
                        Spacer()
                        Text(portfolio.formatCurrency(price))
                            .font(.title3.monospacedDigit())
                    }
                }

                Section("Shares") {
                    TextField("Number of shares", text: $sharesText)
                        .keyboardType(.decimalPad)
                    HStack(spacing: 12) {
                        ForEach([1, 5, 10, 25, 50], id: \.self) { qty in
                            Button("\(qty)") {
                                sharesText = "\(qty)"
                                HapticManager.selectionFeedback()
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                    }
                }

                Section("Summary") {
                    HStack {
                        Text("Total"); Spacer()
                        Text(portfolio.formatCurrency(total)).font(.headline.monospacedDigit())
                    }
                    if tradeType == .buy {
                        HStack {
                            Text("Cash After"); Spacer()
                            Text(portfolio.formatCurrency(portfolio.cash - total))
                                .foregroundStyle(total > portfolio.cash ? .red : .secondary)
                                .monospacedDigit()
                        }
                    }
                }

                if let error = portfolio.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                Section {
                    Button {
                        showConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isExecuting { ProgressView() }
                            else { Text("\(tradeType.rawValue) \(symbol)").font(.headline) }
                            Spacer()
                        }
                    }
                    .disabled(shares <= 0 || isExecuting)
                    .listRowBackground(tradeType == .buy ? Color.green : Color.red)
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("\(tradeType.rawValue) \(symbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Confirm Trade", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("\(tradeType.rawValue)", role: tradeType == .sell ? .destructive : .none) {
                    isExecuting = true
                    Task {
                        switch tradeType {
                        case .buy: await portfolio.buy(symbol: symbol, shares: shares, price: price)
                        case .sell: await portfolio.sell(symbol: symbol, shares: shares, price: price)
                        }
                        isExecuting = false
                        if portfolio.errorMessage == nil { dismiss() }
                    }
                }
            } message: {
                Text("\(tradeType.rawValue) \(sharesText) shares of \(symbol) at \(portfolio.formatCurrency(price)) for \(portfolio.formatCurrency(total))?")
            }
        }
    }
}

// MARK: - Trade History Row with Journal Note
struct TradeHistoryRow: View {
    let trade: Trade
    @EnvironmentObject var portfolio: PortfolioManager
    @State private var showNoteEditor = false
    @State private var noteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: trade.type == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(trade.type == .buy ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(trade.type.rawValue) \(trade.symbol)")
                            .font(.subheadline.bold())
                        if trade.isAutomated {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(trade.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(portfolio.formatCurrency(trade.total))
                        .font(.subheadline.monospacedDigit())
                    Text("\(portfolio.formatShares(trade.shares)) @ \(portfolio.formatCurrency(trade.price))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let pl = trade.realizedPL {
                        Text(String(format: "%+.2f", pl))
                            .font(.caption2.bold())
                            .foregroundStyle(pl >= 0 ? .green : .red)
                    }
                }
            }

            // Journal note
            if let note = trade.note, !note.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 28)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            noteText = trade.note ?? ""
            showNoteEditor = true
        }
        .alert("Trade Journal", isPresented: $showNoteEditor) {
            TextField("Add a note...", text: $noteText)
            Button("Save") {
                portfolio.updateTradeNote(tradeId: trade.id, note: noteText)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add a note to this \(trade.type.rawValue) of \(trade.symbol)")
        }
    }
}


// MARK: - Trade Info Sheet
struct TradeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Order Types").font(.subheadline.bold())
                            Text("Market orders execute instantly at the current price. Limit orders fill only at your target price or better. Stop Loss triggers a sell when price drops to your stop. Stop Limit combines both — triggers at the stop, then fills at the limit.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(.blue)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dollar-Based Orders").font(.subheadline.bold())
                            Text("Switch to \"Dollars\" mode to invest a specific dollar amount instead of choosing a share count. PaperPilot calculates fractional shares automatically.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "dollarsign.circle")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trade Journal").font(.subheadline.bold())
                            Text("Tap any trade in your history to add a journal note. Record your reasoning, strategy, or lessons learned. Great for reviewing your decisions later.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "note.text")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pending Orders").font(.subheadline.bold())
                            Text("Limit, Stop Loss, and Stop Limit orders appear in the Pending Orders section. They fill automatically when the market price meets your conditions. Cancel anytime.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.purple)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trade History & Filters").font(.subheadline.bold())
                            Text("Filter your history by All, Buys, Sells, or Auto (automated trades). Automated trades are marked with a bolt icon. Realized P&L is shown on sell trades.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(.indigo)
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CSV Export").font(.subheadline.bold())
                            Text("Tap the share icon to export your complete trade history as a CSV file. Includes timestamps, prices, shares, totals, journal notes, and realized P&L.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.teal)
                    }
                }
            }
            .navigationTitle("Trade Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
