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

struct ContentView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var automationEngine: AutomationEngine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showOnboarding = false
    @State private var showHubLauncher = false
    @State private var paperTab: PaperTab = .home
    @State private var alpacaTab: AlpacaTab = .home
    @State private var futuresTab: FuturesTab = .home

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
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
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { startingCash in
                portfolio.resetPortfolio(newStartingCash: startingCash)
                portfolio.hasCompletedOnboarding = true
                portfolio.saveUserPreferences()
                showOnboarding = false
            }
        }
        .sheet(isPresented: $showHubLauncher) {
            HubLauncherView()
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

// MARK: - Hub Launcher View
struct HubLauncherView: View {
    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Choose Your Trading Hub")
                    .font(.title2.bold())
                    .padding(.top, 20)

                ForEach(portfolio.visibleHubs) { hub in
                    Button {
                        portfolio.activeHub = hub
                        portfolio.saveUserPreferences()
                        dismiss()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: hub.icon)
                                .font(.title2)
                                .foregroundStyle(hub.accentColor)
                                .frame(width: 48, height: 48)
                                .background(hub.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hub.rawValue)
                                    .font(.headline)
                                Text(hub.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(hub.broker)
                                    .font(.caption2)
                                    .foregroundStyle(hub.accentColor)
                            }
                            Spacer()
                            if portfolio.activeHub == hub {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(hub.accentColor)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(portfolio.activeHub == hub ? hub.accentColor.opacity(0.3) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
