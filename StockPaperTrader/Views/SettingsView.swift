import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager
    @State private var showResetConfirm = false
    @State private var resetCashText = "100000"
    @State private var showAlpacaInfo = false
    @State private var showNTInfo = false
    @State private var sliderValue: TimeInterval = 30
    @State private var connectionTestResult: String?
    @State private var ntTestResult: String?

    var body: some View {
        NavigationStack {
            Form {
                // Throttle warning banner
                if stockService.isThrottled, let msg = stockService.throttleMessage {
                    Section {
                        Label {
                            Text(msg).font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Hub-specific sections
                switch portfolio.activeHub {
                case .paper:
                    paperSettings
                case .equities:
                    alpacaSettings
                case .futures:
                    ninjaTraderSettings
                }

                // Shared sections
                refreshSection
                portfolioSection
                appearanceSection
                chartTimezoneSection
                safetyControlsSection
                hubVisibilitySection
                aboutSection
            }
            .navigationTitle("\(portfolio.activeHub.rawValue) Settings")
            .alert("Reset Portfolio?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    let cash = Double(resetCashText) ?? 100_000
                    portfolio.resetPortfolio(newStartingCash: cash)
                }
            } message: {
                Text("This will clear all \(portfolio.activeHub.rawValue) positions and trade history. Starting cash: $\(resetCashText).")
            }
            .sheet(isPresented: $showAlpacaInfo) { AlpacaSetupGuide() }
            .sheet(isPresented: $showNTInfo) { NinjaTraderSetupGuide() }
        }
    }

    // MARK: - Paper-Specific Settings
    private var paperSettings: some View {
        Group {
            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Local Simulation Active")
                        .font(.subheadline)
                    Spacer()
                }
                Text("Paper trading uses Yahoo Finance for market data and executes trades locally on your device. No account or signup needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Paper Trading", systemImage: "doc.text")
            }

            Section {
                Picker("Data Provider", selection: $stockService.dataProvider) {
                    ForEach(DataProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                Text(stockService.dataProvider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Market Data")
            } footer: {
                Text("Yahoo Finance works without signup but may throttle. Alpaca provides official IEX data with a free account.")
            }
        }
    }

    // MARK: - Alpaca-Specific Settings
    private var alpacaSettings: some View {
        Group {
            Section {
                // Live mode toggle
                Toggle(isOn: $portfolio.equitiesPortfolio.isLiveMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Trading")
                            .font(.subheadline)
                        Text(portfolio.equitiesPortfolio.isLiveMode ? "REAL MONEY — trades execute with real funds" : "Paper mode — simulated trading")
                            .font(.caption2)
                            .foregroundStyle(portfolio.equitiesPortfolio.isLiveMode ? .red : .secondary)
                    }
                }
                .tint(.red)
                .onChange(of: portfolio.equitiesPortfolio.isLiveMode) { _, _ in
                    portfolio.equitiesPortfolio.save()
                }

                HStack {
                    Text("Connection")
                    Spacer()
                    Image(systemName: portfolio.alpacaConnectionStatus.icon)
                        .foregroundStyle(portfolio.alpacaConnectionStatus.color)
                    Text(portfolio.alpacaConnectionStatus.rawValue)
                        .font(.caption)
                        .foregroundStyle(portfolio.alpacaConnectionStatus.color)
                }
            } header: {
                Label("Alpaca Equities", systemImage: "chart.line.uptrend.xyaxis")
            } footer: {
                Text("Alpaca supports stocks, options, and crypto. Paper mode simulates trades. Live mode uses real money.")
            }

            Section {
                SecureField("API Key ID", text: $stockService.alpacaApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Secret Key", text: $stockService.alpacaSecretKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    stockService.applySettings()
                    portfolio.configureAlpaca(
                        apiKey: stockService.alpacaApiKey,
                        secretKey: stockService.alpacaSecretKey
                    )
                    Task {
                        let success = await portfolio.testAlpacaConnection()
                        connectionTestResult = success ? "Connected successfully" : "Connection failed"
                    }
                } label: {
                    Label("Save & Test Connection", systemImage: "checkmark.circle")
                }
                .disabled(stockService.alpacaApiKey.isEmpty || stockService.alpacaSecretKey.isEmpty)

                if let result = connectionTestResult {
                    Label(result, systemImage: result.contains("success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(result.contains("success") ? .green : .red)
                }

                Button { showAlpacaInfo = true } label: {
                    Label("How to get Alpaca keys", systemImage: "questionmark.circle")
                }
            } header: {
                Text("Credentials")
            } footer: {
                Text("Keys are stored securely in your device Keychain. Sign up free at alpaca.markets.")
            }

            Section {
                Picker("Data Provider", selection: $stockService.dataProvider) {
                    ForEach(DataProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                Text("Alpaca data provider recommended for best experience with Alpaca hub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Market Data")
            }
        }
    }

    // MARK: - NinjaTrader-Specific Settings
    private var ninjaTraderSettings: some View {
        Group {
            Section {
                Toggle(isOn: $portfolio.futuresPortfolio.isLiveMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Trading")
                            .font(.subheadline)
                        Text(portfolio.futuresPortfolio.isLiveMode ? "REAL MONEY — trades execute with real funds" : "Demo mode — simulated trading")
                            .font(.caption2)
                            .foregroundStyle(portfolio.futuresPortfolio.isLiveMode ? .red : .secondary)
                    }
                }
                .tint(.red)
                .onChange(of: portfolio.futuresPortfolio.isLiveMode) { _, newValue in
                    portfolio.futuresPortfolio.save()
                    stockService.ntEnvironment = newValue ? .live : .demo
                    stockService.applySettings()
                }

                Picker("Environment", selection: $stockService.ntEnvironment) {
                    ForEach(NTEnvironment.allCases, id: \.self) { env in
                        Text(env.rawValue).tag(env)
                    }
                }

                if stockService.ntEnvironment == .live || portfolio.futuresPortfolio.isLiveMode {
                    Label("LIVE mode — real money will be used", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }

                HStack {
                    Text("Connection")
                    Spacer()
                    Image(systemName: portfolio.ninjaTraderConnectionStatus.icon)
                        .foregroundStyle(portfolio.ninjaTraderConnectionStatus.color)
                    Text(portfolio.ninjaTraderConnectionStatus.rawValue)
                        .font(.caption)
                        .foregroundStyle(portfolio.ninjaTraderConnectionStatus.color)
                }
            } header: {
                Label("NinjaTrader Futures", systemImage: "bolt.horizontal.fill")
            } footer: {
                Text("NinjaTrader uses the Tradovate API for futures and commodities trading. Demo is free simulated trading.")
            }

            Section {
                TextField("Username", text: $stockService.ntUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $stockService.ntPassword)
                TextField("Client ID (cid)", text: $stockService.ntCid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Secret", text: $stockService.ntSecret)

                Button {
                    stockService.applySettings()
                    portfolio.configureNinjaTrader(
                        username: stockService.ntUsername,
                        password: stockService.ntPassword,
                        cid: stockService.ntCid,
                        secret: stockService.ntSecret,
                        environment: stockService.ntEnvironment
                    )
                    Task {
                        let success = await portfolio.testNinjaTraderConnection()
                        ntTestResult = success ? "Connected to NinjaTrader" : "Connection failed — check credentials"
                    }
                } label: {
                    Label("Save & Test Connection", systemImage: "checkmark.circle")
                }
                .disabled(stockService.ntUsername.isEmpty || stockService.ntPassword.isEmpty)

                if let result = ntTestResult {
                    Label(result, systemImage: result.lowercased().contains("connected") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(result.lowercased().contains("connected") ? .green : .red)
                }

                Button { showNTInfo = true } label: {
                    Label("How to set up NinjaTrader", systemImage: "questionmark.circle")
                }
            } header: {
                Text("Credentials")
            } footer: {
                Text("Credentials stored securely in Keychain.")
            }

            Section {
                Text("NinjaTrader uses Yahoo Finance for chart data. Order execution goes through the Tradovate API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Market Data")
            }

            // ATM Strategy Management
            Section {
                ForEach(portfolio.atmStrategies.indices, id: \.self) { idx in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(portfolio.atmStrategies[idx].name)
                                .font(.subheadline.bold())
                            Text("SL: \(String(format: "%.1f", portfolio.atmStrategies[idx].stopLossPoints)) pts · TP: \(String(format: "%.1f", portfolio.atmStrategies[idx].takeProfitPoints)) pts")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if idx == portfolio.defaultATMIndex {
                            Text("Default")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        portfolio.defaultATMIndex = idx
                        portfolio.saveUserPreferences()
                    }
                }
            } header: {
                Label("ATM Strategies", systemImage: "target")
            } footer: {
                Text("Tap a strategy to set it as default. ATM strategies auto-attach stop loss and take profit to futures trades.")
            }
        }
    }

    // MARK: - Shared: Refresh Interval
    private var refreshSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Auto-Refresh Interval")
                    Spacer()
                    Text("\(Int(sliderValue))s")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $sliderValue,
                    in: (stockService.dataProvider == .yahoo
                         ? StockService.yahooMinRefreshInterval
                         : 5)...StockService.yahooMaxRefreshInterval,
                    step: 5
                )
                .onChange(of: sliderValue) { _, newValue in
                    stockService.setRefreshInterval(newValue)
                }
                if stockService.dataProvider == .yahoo {
                    Text("Yahoo Finance minimum: 15s. Lower values increase throttle risk. 30s recommended.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Refresh")
        }
        .onAppear { sliderValue = stockService.refreshInterval }
    }

    // MARK: - Shared: Portfolio (Starting Cash + Reset)
    private var portfolioSection: some View {
        Section {
            HStack {
                Text("Starting Cash")
                Spacer()
                TextField("Amount", text: $resetCashText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset \(portfolio.activeHub.rawValue) Portfolio", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Portfolio")
        } footer: {
            Text("Resets cash, positions, and trade history for the \(portfolio.activeHub.rawValue) hub only.")
        }
    }

    // MARK: - Shared: Appearance (Theme + Accent Color)
    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $portfolio.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .onChange(of: portfolio.appearanceMode) { _, _ in
                portfolio.saveUserPreferences()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Accent Color")
                    .font(.subheadline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(AccentTheme.allCases) { theme in
                        Button {
                            portfolio.accentTheme = theme
                            portfolio.saveUserPreferences()
                            HapticManager.selectionFeedback()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 36, height: 36)
                                if portfolio.accentTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Chart Timezone
    private var chartTimezoneSection: some View {
        Section {
            Picker("Chart Timezone", selection: $portfolio.chartTimezone) {
                ForEach(ChartTimezone.allCases) { tz in
                    Text("\(tz.rawValue) (\(tz.abbreviation))").tag(tz)
                }
            }
            .onChange(of: portfolio.chartTimezone) { _, _ in
                portfolio.saveUserPreferences()
            }
        } header: {
            Text("Charts")
        }
    }

    // MARK: - Shared: Safety Controls
    private var safetyControlsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { portfolio.safetyControls.emergencyStopEnabled },
                set: {
                    portfolio.safetyControls.emergencyStopEnabled = $0
                    portfolio.saveSafetyControls()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Emergency Stop")
                        .font(.subheadline)
                    Text("Halts all trading immediately")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.red)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max Daily Loss")
                    Spacer()
                    Text(portfolio.safetyControls.maxDailyLoss > 0
                         ? portfolio.formatCurrency(portfolio.safetyControls.maxDailyLoss)
                         : "Off")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { portfolio.safetyControls.maxDailyLoss },
                        set: {
                            portfolio.safetyControls.maxDailyLoss = $0
                            portfolio.saveSafetyControls()
                        }
                    ),
                    in: 0...10000,
                    step: 100
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max Position Size")
                    Spacer()
                    Text(portfolio.safetyControls.maxPositionSize > 0
                         ? portfolio.formatCurrency(portfolio.safetyControls.maxPositionSize)
                         : "Off")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { portfolio.safetyControls.maxPositionSize },
                        set: {
                            portfolio.safetyControls.maxPositionSize = $0
                            portfolio.saveSafetyControls()
                        }
                    ),
                    in: 0...100000,
                    step: 500
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max Trades / Day")
                    Spacer()
                    Text(portfolio.safetyControls.maxTradesPerDay > 0
                         ? "\(portfolio.safetyControls.maxTradesPerDay)"
                         : "Off")
                        .foregroundStyle(.secondary)
                }
                Stepper(
                    "",
                    value: Binding(
                        get: { portfolio.safetyControls.maxTradesPerDay },
                        set: {
                            portfolio.safetyControls.maxTradesPerDay = $0
                            portfolio.saveSafetyControls()
                        }
                    ),
                    in: 0...100
                )
                .labelsHidden()
            }

            Toggle(isOn: Binding(
                get: { portfolio.safetyControls.requireLiveConfirmation },
                set: {
                    portfolio.safetyControls.requireLiveConfirmation = $0
                    portfolio.saveSafetyControls()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require Live Confirmation")
                        .font(.subheadline)
                    Text("Show confirmation dialog before live trades")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Today's stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Trades").font(.caption).foregroundStyle(.secondary)
                    Text("\(portfolio.todayTradeCount)")
                        .font(.subheadline.bold().monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Today's P&L").font(.caption).foregroundStyle(.secondary)
                    Text(portfolio.formatCurrency(portfolio.todayPL))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(portfolio.todayPL >= 0 ? .green : .red)
                }
            }
        } header: {
            Label("Safety Controls", systemImage: "shield.checkered")
        } footer: {
            Text("Safety controls apply to the \(portfolio.activeHub.rawValue) hub. Each hub has independent safety settings.")
        }
    }

    // MARK: - Shared: Hub Visibility
    private var hubVisibilitySection: some View {
        Section {
            ForEach(TradingHub.allCases) { hub in
                Toggle(isOn: Binding(
                    get: { portfolio.enabledHubs.contains(hub) },
                    set: { enabled in
                        if enabled {
                            portfolio.enabledHubs.insert(hub)
                        } else if portfolio.enabledHubs.count > 1 {
                            portfolio.enabledHubs.remove(hub)
                            if portfolio.activeHub == hub {
                                portfolio.activeHub = portfolio.visibleHubs.first ?? .paper
                            }
                        }
                        portfolio.saveUserPreferences()
                    }
                )) {
                    HStack(spacing: 10) {
                        Image(systemName: hub.icon)
                            .foregroundStyle(hub.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hub.rawValue)
                                .font(.subheadline)
                            Text(hub.broker)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Hub Visibility")
        } footer: {
            Text("Hide hubs you don't use. At least one hub must remain visible.")
        }
    }

    // MARK: - Shared: About
    private var aboutSection: some View {
        Section {
            HStack {
                Text("App")
                Spacer()
                Text("PaperPilot").foregroundStyle(.secondary)
            }
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0").foregroundStyle(.secondary)
            }
            HStack {
                Text("Active Hub")
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: portfolio.activeHub.icon)
                        .foregroundStyle(portfolio.activeHub.accentColor)
                    Text(portfolio.activeHub.rawValue)
                }
                .foregroundStyle(.secondary)
            }
            Button {
                portfolio.hasCompletedOnboarding = false
                portfolio.saveUserPreferences()
            } label: {
                Label("Replay Onboarding", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("About")
        }
    }
}

// MARK: - Alpaca Setup Guide
struct AlpacaSetupGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    guideStep(number: 1, title: "Create an Alpaca Account",
                              detail: "Go to alpaca.markets and sign up for a free account. No minimum deposit required for paper trading.")
                    guideStep(number: 2, title: "Generate API Keys",
                              detail: "In your Alpaca dashboard, go to the API Keys section. Click 'Generate New Key' to create a key pair.")
                    guideStep(number: 3, title: "Copy Your Keys",
                              detail: "Copy both the API Key ID and the Secret Key. The secret key is only shown once — save it somewhere safe.")
                    guideStep(number: 4, title: "Paste in PaperPilot",
                              detail: "Come back here and paste your API Key ID and Secret Key into the fields above. Tap 'Save & Test Connection'.")
                    guideStep(number: 5, title: "Start Trading",
                              detail: "Once connected, you can trade stocks, options, and crypto through Alpaca. Start with paper mode to practice.")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alpaca Features")
                            .font(.headline)
                        featureRow(icon: "chart.line.uptrend.xyaxis", text: "Stocks & ETFs", color: .blue)
                        featureRow(icon: "bitcoinsign.circle", text: "Cryptocurrency", color: .orange)
                        featureRow(icon: "divide.circle", text: "Fractional Shares", color: .purple)
                        featureRow(icon: "doc.text", text: "Paper & Live Trading", color: .green)
                        featureRow(icon: "bolt.fill", text: "Real-time IEX Data", color: .cyan)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Alpaca Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func guideStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.blue, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func featureRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text).font(.subheadline)
        }
    }
}

// MARK: - NinjaTrader Setup Guide
struct NinjaTraderSetupGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    guideStep(number: 1, title: "Create a NinjaTrader Account",
                              detail: "Go to ninjatrader.com and sign up. You can start with a free demo account for simulated futures trading.")
                    guideStep(number: 2, title: "Enable Tradovate API Access",
                              detail: "NinjaTrader uses the Tradovate API for order execution. In your account settings, enable API access and note your credentials.")
                    guideStep(number: 3, title: "Get Your Credentials",
                              detail: "You'll need: Username, Password, Client ID (cid), and API Secret. These are found in your Tradovate/NinjaTrader account settings.")
                    guideStep(number: 4, title: "Enter Credentials in PaperPilot",
                              detail: "Paste your credentials into the fields above. Choose Demo or Live environment. Tap 'Save & Test Connection'.")
                    guideStep(number: 5, title: "Start Trading Futures",
                              detail: "Once connected, you can trade futures and commodities. Start with Demo mode to practice risk-free.")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NinjaTrader Features")
                            .font(.headline)
                        featureRow(icon: "bolt.horizontal.fill", text: "Futures Trading", color: .orange)
                        featureRow(icon: "cube.box", text: "Commodities", color: .brown)
                        featureRow(icon: "server.rack", text: "Tradovate API", color: .blue)
                        featureRow(icon: "shield.checkered", text: "Demo & Live Modes", color: .green)
                        featureRow(icon: "chart.xyaxis.line", text: "Advanced Charting", color: .purple)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("NinjaTrader Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func guideStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.orange, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func featureRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text).font(.subheadline)
        }
    }
}
