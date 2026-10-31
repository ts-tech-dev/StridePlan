import UIKit

@MainActor
protocol HapticsProviding: AnyObject {
    func runStarted()
    func runStopped()
    func stepChanged()
    func warning()
}

@MainActor
final class Haptics: HapticsProviding {
    private let notification = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .heavy)

    func runStarted() { notification.notificationOccurred(.success) }
    func runStopped() { notification.notificationOccurred(.success) }
    func stepChanged() { impact.impactOccurred(intensity: 1) }
    func warning() { notification.notificationOccurred(.warning) }
}

/// Conformance lives in an extension so the type itself stays nonisolated and can be built anywhere (previews, tests).
final class SilentHaptics {}

extension SilentHaptics: HapticsProviding {
    func runStarted() {}
    func runStopped() {}
    func stepChanged() {}
    func warning() {}
}
