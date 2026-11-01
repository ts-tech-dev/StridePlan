import SwiftUI

/// Dependency container. Views read it from the environment; previews and tests get mocks by default.
final class AppServices {
    let plans: PlanProviding
    let health: HealthServicing
    let voice: VoiceCoaching
    let notifications: NotificationScheduling
    let liveActivity: RunActivityControlling
    let haptics: HapticsProviding
    let garmin: GarminConnecting
    private let stepPedometer: PedometerProviding
    private let gpsLocation: LocationProviding
    private let makeSimulatedLocation: () -> LocationProviding

    init(
        plans: PlanProviding,
        location: LocationProviding,
        simulatedLocation: @escaping () -> LocationProviding,
        health: HealthServicing,
        voice: VoiceCoaching,
        notifications: NotificationScheduling,
        liveActivity: RunActivityControlling,
        haptics: HapticsProviding,
        garmin: GarminConnecting,
        pedometer: PedometerProviding = MockPedometer()
    ) {
        self.plans = plans
        self.gpsLocation = location
        self.makeSimulatedLocation = simulatedLocation
        self.health = health
        self.voice = voice
        self.notifications = notifications
        self.liveActivity = liveActivity
        self.haptics = haptics
        self.garmin = garmin
        self.stepPedometer = pedometer
    }

    /// Step-based distance for treadmill runs (a steady mock in the Simulator, which has no motion data).
    var pedometer: PedometerProviding {
        #if targetEnvironment(simulator)
        return MockPedometer()
        #else
        return stepPedometer
        #endif
    }

    /// Real GPS, or a GPX replay when the user enables "Simulate GPS" (always on in the Simulator).
    func locationProvider(simulated: Bool) -> LocationProviding {
        #if targetEnvironment(simulator)
        return makeSimulatedLocation()
        #else
        return simulated ? makeSimulatedLocation() : gpsLocation
        #endif
    }

    @MainActor
    static func live() -> AppServices {
        AppServices(
            plans: PlanLoader(),
            location: CoreLocationService(),
            simulatedLocation: { GPXReplayLocationService(speedMultiplier: 1) },
            health: HealthKitService(),
            voice: VoiceCoachService(),
            notifications: NotificationService(),
            liveActivity: LiveActivityService(),
            haptics: Haptics(),
            garmin: GarminService(),
            pedometer: PedometerService()
        )
    }

    static let preview = AppServices(
        plans: PlanLoader(),
        location: MockLocationService(),
        simulatedLocation: { GPXReplayLocationService(speedMultiplier: 10) },
        health: MockHealthService(),
        voice: MockVoiceCoach(),
        notifications: MockNotificationService(),
        liveActivity: MockLiveActivityService(),
        haptics: SilentHaptics(),
        garmin: MockGarminService()
    )
}

extension EnvironmentValues {
    @Entry var services: AppServices = .preview
}
