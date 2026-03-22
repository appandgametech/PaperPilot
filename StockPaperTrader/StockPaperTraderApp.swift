import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct StockPaperTraderApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var portfolio = PortfolioManager()
    @StateObject private var stockService = StockService()
    @StateObject private var automationEngine = AutomationEngine()
    @State private var showSplash = true

    var body: some Scene {
        // Main app window
        WindowGroup("PaperPilot") {
            ZStack {
                ContentView()
                    .environmentObject(portfolio)
                    .environmentObject(stockService)
                    .environmentObject(automationEngine)
                    .onAppear {
                        automationEngine.portfolio = portfolio
                        automationEngine.stockService = stockService

                        if !stockService.alpacaApiKey.isEmpty, !stockService.alpacaSecretKey.isEmpty {
                            portfolio.configureAlpaca(
                                apiKey: stockService.alpacaApiKey,
                                secretKey: stockService.alpacaSecretKey
                            )
                        }
                        if !stockService.ntUsername.isEmpty, !stockService.ntPassword.isEmpty {
                            portfolio.configureNinjaTrader(
                                username: stockService.ntUsername,
                                password: stockService.ntPassword,
                                cid: stockService.ntCid,
                                secret: stockService.ntSecret,
                                environment: stockService.ntEnvironment
                            )
                        }
                    }
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    showSplash = false
                                }
                            }
                        }
                }
            }
            .frame(minWidth: 375, idealWidth: 1200, minHeight: 600, idealHeight: 800)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh All Data") {
                    Task { await stockService.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("New Trade") {
                    NotificationCenter.default.post(name: .openNewTrade, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("PaperPilot Help") {
                    // placeholder
                }
            }
        }
    }
}

// MARK: - Notification for keyboard shortcuts
extension Notification.Name {
    static let openNewTrade = Notification.Name("openNewTrade")
}

// MARK: - App & Scene Delegates for Multi-Window Chart Support
#if canImport(UIKit)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Check if this scene session is for a chart window
        if let activity = options.userActivities.first,
           activity.activityType == "com.tradepilot.chart" {
            let config = UISceneConfiguration(name: "Chart Configuration", sessionRole: .windowApplication)
            config.delegateClass = ChartSceneDelegate.self
            return config
        }
        // Default: let SwiftUI manage the main window
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: .windowApplication)
        return config
    }
}

/// Scene delegate for chart pop-out windows
class ChartSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    var window: UIWindow?
    @Published var chartID: UUID?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Extract chart ID from the user activity
        if let activity = connectionOptions.userActivities.first,
           activity.activityType == "com.tradepilot.chart",
           let idString = activity.userInfo?["chartID"] as? String,
           let id = UUID(uuidString: idString) {
            chartID = id
        }

        guard let windowScene = scene as? UIWindowScene else { return }

        // Set size restrictions for the chart window
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 500, height: 400)
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: 2000, height: 1500)

        // Build the SwiftUI chart view
        let chartView = ChartPopoutRootView(sceneDelegate: self)
        let hostingController = UIHostingController(rootView: chartView)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        self.window = window

        // Set the window title
        if let id = chartID, let config = ChartWindowStore.shared.configs[id] {
            windowScene.title = "\(config.symbol) — \(config.widget.rawValue)"
        } else {
            windowScene.title = "Chart"
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Clean up the chart config when the window is closed
        if let id = chartID {
            Task { @MainActor in
                ChartWindowStore.shared.remove(id)
            }
        }
    }
}

/// Root view for chart pop-out windows — reads chart ID from the scene delegate
struct ChartPopoutRootView: View {
    @ObservedObject var sceneDelegate: ChartSceneDelegate

    var body: some View {
        Group {
            if let id = sceneDelegate.chartID {
                ChartWindowView(windowID: id)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading chart...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#endif
