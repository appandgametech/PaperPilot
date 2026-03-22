import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Chart Window Configuration
struct ChartWindowConfig: Identifiable {
    let id: UUID
    let widget: DashboardWidget
    let chartData: [ChartDataPoint]
    let chartStyle: String // "Line" or "Candle"
    let timeframe: ChartTimeframe
    let quote: StockQuote?
    let symbol: String
}

// MARK: - Shared Store
@MainActor
final class ChartWindowStore: ObservableObject {
    static let shared = ChartWindowStore()
    @Published var configs: [UUID: ChartWindowConfig] = [:]

    func store(_ config: ChartWindowConfig) {
        configs[config.id] = config
    }

    func remove(_ id: UUID) {
        configs.removeValue(forKey: id)
    }
}

// MARK: - Window Manager — opens real separate windows on Mac Catalyst
#if canImport(UIKit)
@MainActor
final class ChartWindowManager {
    static let shared = ChartWindowManager()

    func openChartWindow(config: ChartWindowConfig) {
        ChartWindowStore.shared.store(config)

        // Create a user activity to pass the chart ID to the new scene
        let activity = NSUserActivity(activityType: "com.tradepilot.chart")
        activity.userInfo = ["chartID": config.id.uuidString]
        activity.targetContentIdentifier = "chart-\(config.id.uuidString)"

        // Request a brand new scene session — this creates a separate OS window
        UIApplication.shared.requestSceneSessionActivation(
            nil,           // nil = create new session
            userActivity: activity,
            options: nil,
            errorHandler: { error in
                print("Chart window error: \(error.localizedDescription)")
            }
        )
    }

    func closeWindow(id: UUID) {
        ChartWindowStore.shared.remove(id)

        // Find and destroy the scene session for this chart
        for session in UIApplication.shared.openSessions {
            if let delegate = session.scene?.delegate as? ChartSceneDelegate,
               delegate.chartID == id {
                UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
                break
            }
        }
    }
}
#endif
