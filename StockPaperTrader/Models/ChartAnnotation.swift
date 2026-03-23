import SwiftUI

// MARK: - Chart Annotation Types (NinjaTrader-style drawing tools)

/// The type of drawing tool the user selected
enum ChartDrawingTool: String, CaseIterable, Identifiable, Codable {
    case horizontalLine = "Horizontal Line"
    case trendLine = "Trend Line"
    case horizontalRay = "Horizontal Ray"
    case fibonacciRetracement = "Fibonacci Retracement"
    case rectangle = "Rectangle"
    case text = "Text"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .horizontalLine: return "minus"
        case .trendLine: return "line.diagonal"
        case .horizontalRay: return "arrow.right"
        case .fibonacciRetracement: return "percent"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        }
    }

    var pointsRequired: Int {
        switch self {
        case .horizontalLine, .horizontalRay, .text: return 1
        case .trendLine, .fibonacciRetracement, .rectangle: return 2
        }
    }
}

/// A single user-drawn annotation on the chart
struct ChartAnnotation: Identifiable, Codable {
    let id: UUID
    var tool: ChartDrawingTool
    var label: String
    var colorHex: String  // stored as hex for Codable
    var lineWidth: Double
    var price1: Double          // primary price level
    var price2: Double?         // secondary price level (for trend line, fib, rect)
    var dateIndex1: Int         // index into chart data for point 1
    var dateIndex2: Int?        // index into chart data for point 2
    var textContent: String?    // for text annotations
    var isVisible: Bool
    var createdAt: Date

    init(
        tool: ChartDrawingTool,
        label: String = "",
        colorHex: String = "FF9500",
        lineWidth: Double = 1.5,
        price1: Double,
        price2: Double? = nil,
        dateIndex1: Int,
        dateIndex2: Int? = nil,
        textContent: String? = nil
    ) {
        self.id = UUID()
        self.tool = tool
        self.label = label
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.price1 = price1
        self.price2 = price2
        self.dateIndex1 = dateIndex1
        self.dateIndex2 = dateIndex2
        self.textContent = textContent
        self.isVisible = true
        self.createdAt = Date()
    }

    var color: Color {
        Color(hex: colorHex) ?? .orange
    }

    static let fibLevels: [Double] = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0]
}

// MARK: - Preset annotation colors (NinjaTrader palette)
struct AnnotationColor: Identifiable {
    let id = UUID()
    let name: String
    let hex: String
    var color: Color { Color(hex: hex) ?? .orange }

    static let presets: [AnnotationColor] = [
        .init(name: "Red", hex: "FF3B30"),
        .init(name: "Orange", hex: "FF9500"),
        .init(name: "Yellow", hex: "FFCC00"),
        .init(name: "Green", hex: "34C759"),
        .init(name: "Cyan", hex: "32ADE6"),
        .init(name: "Blue", hex: "007AFF"),
        .init(name: "Purple", hex: "AF52DE"),
        .init(name: "Magenta", hex: "FF2D55"),
        .init(name: "White", hex: "FFFFFF"),
        .init(name: "Gray", hex: "8E8E93"),
    ]
}

// MARK: - Chart Timezone
enum ChartTimezone: String, CaseIterable, Identifiable, Codable {
    case eastern = "EST/EDT"
    case central = "CST/CDT"
    case mountain = "MST/MDT"
    case pacific = "PST/PDT"
    case utc = "UTC"
    case london = "London"
    case tokyo = "Tokyo"
    case sydney = "Sydney"

    var id: String { rawValue }

    var timeZone: TimeZone {
        switch self {
        case .eastern: return TimeZone(identifier: "America/New_York")!
        case .central: return TimeZone(identifier: "America/Chicago")!
        case .mountain: return TimeZone(identifier: "America/Denver")!
        case .pacific: return TimeZone(identifier: "America/Los_Angeles")!
        case .utc: return TimeZone(identifier: "UTC")!
        case .london: return TimeZone(identifier: "Europe/London")!
        case .tokyo: return TimeZone(identifier: "Asia/Tokyo")!
        case .sydney: return TimeZone(identifier: "Australia/Sydney")!
        }
    }

    var abbreviation: String {
        switch self {
        case .eastern: return "ET"
        case .central: return "CT"
        case .mountain: return "MT"
        case .pacific: return "PT"
        case .utc: return "UTC"
        case .london: return "GMT"
        case .tokyo: return "JST"
        case .sydney: return "AEST"
        }
    }
}

// MARK: - Annotation Store (per-hub, per-symbol persistence)
@MainActor
class ChartAnnotationStore: ObservableObject {
    static let shared = ChartAnnotationStore()

    @Published var annotations: [String: [ChartAnnotation]] = [:]  // key = "hub_symbol"

    func key(hub: TradingHub, symbol: String) -> String {
        "\(hub.prefix)_\(symbol)"
    }

    func annotationsFor(hub: TradingHub, symbol: String) -> [ChartAnnotation] {
        annotations[key(hub: hub, symbol: symbol)] ?? []
    }

    func add(_ annotation: ChartAnnotation, hub: TradingHub, symbol: String) {
        let k = key(hub: hub, symbol: symbol)
        var list = annotations[k] ?? []
        list.append(annotation)
        annotations[k] = list
        save(hub: hub, symbol: symbol)
    }

    func remove(id: UUID, hub: TradingHub, symbol: String) {
        let k = key(hub: hub, symbol: symbol)
        annotations[k]?.removeAll { $0.id == id }
        save(hub: hub, symbol: symbol)
    }

    func update(_ annotation: ChartAnnotation, hub: TradingHub, symbol: String) {
        let k = key(hub: hub, symbol: symbol)
        if let idx = annotations[k]?.firstIndex(where: { $0.id == annotation.id }) {
            annotations[k]?[idx] = annotation
            save(hub: hub, symbol: symbol)
        }
    }

    func toggleVisibility(id: UUID, hub: TradingHub, symbol: String) {
        let k = key(hub: hub, symbol: symbol)
        if let idx = annotations[k]?.firstIndex(where: { $0.id == id }) {
            annotations[k]?[idx].isVisible.toggle()
            save(hub: hub, symbol: symbol)
        }
    }

    func clearAll(hub: TradingHub, symbol: String) {
        let k = key(hub: hub, symbol: symbol)
        annotations[k] = []
        save(hub: hub, symbol: symbol)
    }

    // MARK: - Persistence
    private func save(hub: TradingHub, symbol: String) {
        let k = key(hub: hub, symbol: symbol)
        if let data = try? JSONEncoder().encode(annotations[k]) {
            UserDefaults.standard.set(data, forKey: "annotations_\(k)")
        }
    }

    func loadAnnotations(hub: TradingHub, symbol: String) {
        let k = key(hub: hub, symbol: symbol)
        if let data = UserDefaults.standard.data(forKey: "annotations_\(k)"),
           let saved = try? JSONDecoder().decode([ChartAnnotation].self, from: data) {
            annotations[k] = saved
        }
    }
}

// MARK: - Color hex extension
extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard h.count == 6, let int = UInt64(h, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
