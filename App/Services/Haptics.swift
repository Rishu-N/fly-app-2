import UIKit

/// Imperative haptics for actions that don't originate from a SwiftUI control
/// (notification actions, intents, conveyor). Views prefer `.sensoryFeedback`.
@MainActor
enum Haptics {
    static var enabled = true

    enum Kind { case start, complete, cancel, pause, warning, tap }

    static func play(_ kind: Kind) {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        switch kind {
        case .start: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .complete: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .cancel: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .pause: UISelectionFeedbackGenerator().selectionChanged()
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .tap: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        }
    }
}
