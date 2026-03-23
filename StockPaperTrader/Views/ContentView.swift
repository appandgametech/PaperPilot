import SwiftUI
import UserNotifications

// MARK: - Hub-Specific Tab Definitions
enum PaperTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case charts = "Charts"
    case markets = "Markets"
    case trade = "Trade"
    case automate = "Automate"
    case analytics = "Analytics"
    case tools = "Tools"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"
        case .charts: return "chart.xyaxis.line"
        case .markets: return "list.bullet.rectangle"
        case .trade: return "arrow.left.arrow.right"
        case .automate: return "gearshape.2"
        case .analytics: return "chart.pie"
        case .tools: return "wrench.and.screwdriver"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum AlpacaTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case charts = "Charts"
    case markets = "Markets"
    case trade = "Trade"
    case automate = "Automate"
    case analytics = "Analytics"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"
        case .charts: return "chart.xyaxis.line"
        case .markets: return "list.bullet.rectangle"
        case .trade: return "arrow.left.arrow.right"
        case .automate: return "gearshape.2"
        case .analytics: return "chart.pie"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum FuturesTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case charts = "Charts"
    case trade = "Trade"
    case automate = "Automate"
    case analytics = "Analytics"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"
        case .charts: return "chart.xyaxis.line"
        case .trade: return "arrow.left.arrow.right"
        case .automate: return "gearshape.2"
        case .analytics: return "chart.pie"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var automationEngine: AutomationEngine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showOnboarding = false
    @State private var showLauncher = false
    @State private var paperTab: PaperTab = .home
    @State private var alpacaTab: AlpacaTab = .home
    @State private var futuresTab: FuturesTab = .home

    var body: some View {
        Group {
            if showLauncher {
                AppLauncherView {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        showLauncher = false
                        portfolio.hasSelectedInitialHub = true
                        portfolio.saveUserPreferences()
                    }
                }
            } else if horizontalSizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .tint(portfolio.activeHub.accentColor)
        .preferredColorScheme(portfolio.appearanceMode.colorScheme)
        .onReceive(stockService.$quotes) { quotes in
            portfolio.updatePositionPrices(quotes: quotes)
            portfolio.evaluatePendingOrders(quotes: quotes)
            portfolio.evaluatePriceAlerts(quotes: quotes)
        }
        .onAppear {
            portfolio.takeSnapshot()
            requestNotificationPermission()
            if !portfolio.hasCompletedOnboarding {
                showOnboarding = true
            } else if !portfolio.hasSelectedInitialHub {
                showLauncher = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { startingCash in
                portfolio.resetPortfolio(newStartingCash: startingCash)
                portfolio.hasCompletedOnboarding = true
                portfolio.saveUserPreferences()
                showOnboarding = false
                // After onboarding, show the launcher
                showLauncher = true
            }
        }
    }

    // MARK: - Hub Switcher Bar
    private var hubSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(portfolio.visibleHubs) { hub in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        portfolio.activeHub = hub
                        portfolio.saveUserPreferences()
                    }
                    HapticManager.selectionFeedback()
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: hub.icon)
                                .font(.caption)
                            Text(hub.rawValue)
                                .font(.subheadline.bold())
                        }
                        Text(hub.subtitle)
                            .font(.caption2)
                            .foregroundStyle(portfolio.activeHub == hub ? hub.accentColor.opacity(0.8) : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        portfolio.activeHub == hub
                            ? hub.accentColor.opacity(0.12)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(portfolio.activeHub == hub ? hub.accentColor.opacity(0.3) : .clear, lineWidth: 1)
                    )
                }
                .foregroundStyle(portfolio.activeHub == hub ? hub.accentColor : .secondary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Live Mode Banner
    @ViewBuilder
    private var liveBanner: some View {
        if portfolio.isLiveTrading {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("LIVE TRADING — Real money at risk")
                    .font(.caption.bold())
                Spacer()
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .modifier(PulseModifier())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.red.gradient)
        }

        if portfolio.safetyControls.emergencyStopEnabled {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.caption)
                Text("EMERGENCY STOP ACTIVE — All trading paused")
                    .font(.caption.bold())
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.orange.gradient)
        }
    }

    // MARK: - iPhone (Compact) — Hub-Specific Tab Bars
    private var compactLayout: some View {
        VStack(spacing: 0) {
            liveBanner
            hubSwitcher
            switch portfolio.activeHub {
            case .paper:
                paperTabView
            case .equities:
                alpacaTabView
            case .futures:
                futuresTabView
            }
        }
    }

    private var paperTabView: some View {
        TabView(selection: $paperTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(PaperTab.home)
            TradingDashboardView()
                .tabItem { Label("Charts", systemImage: "chart.xyaxis.line") }
                .tag(PaperTab.charts)
            WatchlistView()
                .tabItem { Label("Markets", systemImage: "list.bullet.rectangle") }
                .tag(PaperTab.markets)
            TradeView()
                .tabItem { Label("Trade", systemImage: "arrow.left.arrow.right") }
                .tag(PaperTab.trade)
            AutomationView()
                .tabItem { Label("Automate", systemImage: "gearshape.2") }
                .tag(PaperTab.automate)
            NavigationStack { AnalyticsView() }
                .tabItem { Label("Analytics", systemImage: "chart.pie") }
                .tag(PaperTab.analytics)
            ToolsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(PaperTab.tools)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(PaperTab.settings)
        }
    }

    private var alpacaTabView: some View {
        TabView(selection: $alpacaTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AlpacaTab.home)
            TradingDashboardView()
                .tabItem { Label("Charts", systemImage: "chart.xyaxis.line") }
                .tag(AlpacaTab.charts)
            WatchlistView()
                .tabItem { Label("Markets", systemImage: "list.bullet.rectangle") }
                .tag(AlpacaTab.markets)
            TradeView()
                .tabItem { Label("Trade", systemImage: "arrow.left.arrow.right") }
                .tag(AlpacaTab.trade)
            AutomationView()
                .tabItem { Label("Automate", systemImage: "gearshape.2") }
                .tag(AlpacaTab.automate)
            NavigationStack { AnalyticsView() }
                .tabItem { Label("Analytics", systemImage: "chart.pie") }
                .tag(AlpacaTab.analytics)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(AlpacaTab.settings)
        }
    }

    private var futuresTabView: some View {
        TabView(selection: $futuresTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(FuturesTab.home)
            TradingDashboardView()
                .tabItem { Label("Charts", systemImage: "chart.xyaxis.line") }
                .tag(FuturesTab.charts)
            TradeView()
                .tabItem { Label("Trade", systemImage: "arrow.left.arrow.right") }
                .tag(FuturesTab.trade)
            AutomationView()
                .tabItem { Label("Automate", systemImage: "gearshape.2") }
                .tag(FuturesTab.automate)
            NavigationStack { AnalyticsView() }
                .tabItem { Label("Analytics", systemImage: "chart.pie") }
                .tag(FuturesTab.analytics)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(FuturesTab.settings)
        }
    }

    // MARK: - iPad / Mac (Regular) — Sidebar with hub-specific items
    private var regularLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                hubSwitcher
                    .padding(.top, 8)
                List {
                    switch portfolio.activeHub {
                    case .paper:
                        ForEach(PaperTab.allCases) { tab in
                            Button { paperTab = tab } label: {
                                Label(tab.rawValue, systemImage: tab.icon)
                            }
                            .listRowBackground(paperTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundStyle(paperTab == tab ? .green : .primary)
                        }
                    case .equities:
                        ForEach(AlpacaTab.allCases) { tab in
                            Button { alpacaTab = tab } label: {
                                Label(tab.rawValue, systemImage: tab.icon)
                            }
                            .listRowBackground(alpacaTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundStyle(alpacaTab == tab ? .blue : .primary)
                        }
                    case .futures:
                        ForEach(FuturesTab.allCases) { tab in
                            Button { futuresTab = tab } label: {
                                Label(tab.rawValue, systemImage: tab.icon)
                            }
                            .listRowBackground(futuresTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundStyle(futuresTab == tab ? .orange : .primary)
                        }
                    }

                    Section("Connection") {
                        switch portfolio.activeHub {
                        case .paper:
                            brokerStatusRow(hub: .paper, status: .connected)
                        case .equities:
                            brokerStatusRow(hub: .equities, status: portfolio.alpacaConnectionStatus)
                        case .futures:
                            brokerStatusRow(hub: .futures, status: portfolio.ninjaTraderConnectionStatus)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle(portfolio.activeHub.rawValue)
        } detail: {
            VStack(spacing: 0) {
                liveBanner
                switch portfolio.activeHub {
                case .paper: paperDetailView
                case .equities: alpacaDetailView
                case .futures: futuresDetailView
                }
            }
        }
    }

    @ViewBuilder
    private var paperDetailView: some View {
        switch paperTab {
        case .home: DashboardView()
        case .charts: TradingDashboardView()
        case .markets: WatchlistView()
        case .trade: TradeView()
        case .automate: AutomationView()
        case .analytics: NavigationStack { AnalyticsView() }
        case .tools: ToolsView()
        case .settings: SettingsView()
        }
    }

    @ViewBuilder
    private var alpacaDetailView: some View {
        switch alpacaTab {
        case .home: DashboardView()
        case .charts: TradingDashboardView()
        case .markets: WatchlistView()
        case .trade: TradeView()
        case .automate: AutomationView()
        case .analytics: NavigationStack { AnalyticsView() }
        case .settings: SettingsView()
        }
    }

    @ViewBuilder
    private var futuresDetailView: some View {
        switch futuresTab {
        case .home: DashboardView()
        case .charts: TradingDashboardView()
        case .trade: TradeView()
        case .automate: AutomationView()
        case .analytics: NavigationStack { AnalyticsView() }
        case .settings: SettingsView()
        }
    }

    private func brokerStatusRow(hub: TradingHub, status: BrokerConnectionStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(hub.broker)
                    .font(.caption.bold())
                Text(status.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

// MARK: - App Launcher View (First Launch Home Screen)
struct AppLauncherView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onSelectHub: () -> Void

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: isWide ? 32 : 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.system(size: isWide ? 52 : 44))
                        .foregroundStyle(.blue)
                        .symbolEffect(.bounce, value: true)

                    Text("PaperPilot")
                        .font(isWide ? .largeTitle.bold() : .title.bold())

                    Text("3 Trading Apps. 1 Platform.")
                        .font(isWide ? .title3 : .headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, isWide ? 40 : 28)

                // Why 3 apps explanation
                VStack(spacing: 6) {
                    Text("Choose your integration, platform, and automation level. Each app is fully isolated with its own portfolio, watchlist, and settings — so you can practice, trade live, or explore futures without any data mixing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, isWide ? 80 : 24)
                }

                // App Cards
                VStack(spacing: isWide ? 20 : 16) {
                    appCard(
                        hub: .paper,
                        tagline: "Risk-Free Simulation",
                        purpose: "Practice trading with virtual money using real market data. No account needed — just learn, experiment, and build confidence.",
                        tradingMode: "Simulation Only",
                        tradingModeIcon: "shield.checkered",
                        integration: "Yahoo Finance",
                        integrationDetail: "Real-time quotes, charts, news, sector data",
                        features: [
                            ("doc.text", "Full sandbox with $10K–$1M virtual cash"),
                            ("chart.xyaxis.line", "Candlestick charts with RSI, MACD, Bollinger"),
                            ("gearshape.2", "Automation engine: stop loss, take profit, buy the dip"),
                            ("wrench.and.screwdriver", "Tools: screener, comparison, risk calculator, sector map"),
                            ("list.bullet.rectangle", "Watchlist, price alerts, trade journal"),
                        ],
                        tabCount: 8
                    )

                    appCard(
                        hub: .equities,
                        tagline: "Real Brokerage Trading",
                        purpose: "Connect your Alpaca account to trade stocks, options, and crypto with real or paper money through a regulated broker.",
                        tradingMode: "Paper & Live Trading",
                        tradingModeIcon: "arrow.left.arrow.right.circle",
                        integration: "Alpaca Markets API",
                        integrationDetail: "Equities, options, crypto, fractional shares",
                        features: [
                            ("chart.line.uptrend.xyaxis", "Alpaca Bars API for real brokerage charts"),
                            ("lock.shield", "Paper mode for practice, live mode for real trades"),
                            ("dollarsign.circle", "Fractional shares and dollar-based investing"),
                            ("gearshape.2", "Automation with live execution through Alpaca"),
                            ("bell", "Real-time order fills and portfolio sync"),
                        ],
                        tabCount: 7
                    )

                    appCard(
                        hub: .futures,
                        tagline: "Futures & Commodities",
                        purpose: "Trade futures contracts through NinjaTrader and Tradovate. Access ES, NQ, crude oil, gold, and more.",
                        tradingMode: "Demo & Live Trading",
                        tradingModeIcon: "bolt.horizontal.circle",
                        integration: "NinjaTrader / Tradovate API",
                        integrationDetail: "Futures execution, Yahoo for market data",
                        features: [
                            ("bolt.horizontal.fill", "Futures: ES, NQ, CL, GC, and more"),
                            ("chart.xyaxis.line", "Yahoo-powered charts for futures symbols"),
                            ("gearshape.2", "Automation rules for futures strategies"),
                            ("shield.checkered", "Demo mode to practice, live mode for real execution"),
                            ("arrow.triangle.2.circlepath", "Tradovate API for order routing"),
                        ],
                        tabCount: 6
                    )
                }
                .padding(.horizontal, isWide ? 40 : 16)

                // Footer
                VStack(spacing: 4) {
                    Text("You can switch between apps anytime using the hub bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Each app keeps its own data — nothing is shared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, isWide ? 40 : 28)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - App Card
    private func appCard(
        hub: TradingHub,
        tagline: String,
        purpose: String,
        tradingMode: String,
        tradingModeIcon: String,
        integration: String,
        integrationDetail: String,
        features: [(icon: String, text: String)],
        tabCount: Int
    ) -> some View {
        Button {
            portfolio.activeHub = hub
            portfolio.saveUserPreferences()
            HapticManager.tradeFeedback()
            onSelectHub()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Top row: icon + name + tagline
                HStack(spacing: 12) {
                    Image(systemName: hub.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(hub.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hub.rawValue)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                        Text(tagline)
                            .font(.caption)
                            .foregroundStyle(hub.accentColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(hub.accentColor)
                }

                // Purpose
                Text(purpose)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Trading mode + Integration badges
                HStack(spacing: 8) {
                    Label(tradingMode, systemImage: tradingModeIcon)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(hub.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(hub.accentColor)

                    Label(integration, systemImage: "link")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Text(integrationDetail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // Feature list
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(features, id: \.text) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: feature.icon)
                                .font(.caption)
                                .foregroundStyle(hub.accentColor)
                                .frame(width: 18)
                            Text(feature.text)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                // Tab count
                HStack {
                    Spacer()
                    Text("\(tabCount) tabs")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(hub.accentColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pulse Animation Modifier
struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
