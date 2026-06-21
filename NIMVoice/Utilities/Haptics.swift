import UIKit

/// Thin wrapper over UIKit feedback generators for state-transition haptics.
@MainActor
enum Haptics {
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
