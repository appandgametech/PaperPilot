#if canImport(UIKit)
import UIKit
#endif

enum HapticManager {
    static func tradeFeedback() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    static func errorFeedback() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }

    static func selectionFeedback() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }
}
