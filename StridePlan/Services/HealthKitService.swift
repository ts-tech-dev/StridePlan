import CoreLocation
import Foundation
import HealthKit

struct HealthRunInput {
    var start: Date
    var end: Date
    var distanceMeters: Double
    var isIndoor: Bool
    var route: [CLLocation]
    var title: String
}

protocol HealthServicing: AnyObject {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    /// Saves a running workout (with route when available). Returns the HealthKit workout UUID.
    func saveRun(_ input: HealthRunInput) async throws -> UUID
    func averageHeartRate(from start: Date, to end: Date) async -> Double?
}

enum HealthError: LocalizedError {
    case unavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health isn't available on this device."
        case .saveFailed: "The workout couldn't be saved to Apple Health."
        }
    }
}

final class HealthKitService: HealthServicing {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning), HKSeriesType.workoutRoute()]
    }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKObjectType.workoutType()]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func saveRun(_ input: HealthRunInput) async throws -> UUID {
        guard isAvailable else { throw HealthError.unavailable }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = input.isIndoor ? .indoor : .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: input.start)

        if input.distanceMeters > 0 {
            let distance = HKQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: input.distanceMeters),
                start: input.start, end: input.end)
            try await builder.addSamples([distance])
        }
        try await builder.addMetadata([
            HKMetadataKeyIndoorWorkout: input.isIndoor,
            HKMetadataKeyWorkoutBrandName: AppBrand.name,
        ])
        try await builder.endCollection(at: input.end)
        // Typed as optional so this compiles whether the SDK imports the result as optional or not.
        let finished: HKWorkout? = try await builder.finishWorkout()
        guard let workout = finished else { throw HealthError.saveFailed }

        if !input.route.isEmpty {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await routeBuilder.insertRouteData(input.route)
            _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
        return workout.uuid
    }

    func averageHeartRate(from start: Date, to end: Date) async -> Double? {
        guard isAvailable else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate),
            options: .discreteAverage)
        let stats = try? await descriptor.result(for: store)
        return stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }
}

final class MockHealthService: HealthServicing {
    var isAvailable: Bool { true }
    private(set) var savedRuns: [HealthRunInput] = []

    func requestAuthorization() async throws {}

    func saveRun(_ input: HealthRunInput) async throws -> UUID {
        savedRuns.append(input)
        return UUID()
    }

    func averageHeartRate(from start: Date, to end: Date) async -> Double? { 152 }
}
