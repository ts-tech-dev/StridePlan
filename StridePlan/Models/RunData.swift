import Foundation

/// Value types serialized into `RunRecord` blobs. Foundation-only so they're easy to test and export.

struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    var speed: Double
}

struct Split: Codable, Hashable, Identifiable {
    /// 1-based split number.
    var index: Int
    var distanceMeters: Double
    var durationSeconds: Double

    var id: Int { index }
    var paceSecondsPerKm: Double { distanceMeters > 0 ? durationSeconds / distanceMeters * 1000 : 0 }
}

struct StepResult: Codable, Hashable, Identifiable {
    var index: Int
    var title: String
    var kind: StepKind
    var zone: PaceZoneKind
    var target: PaceRange?
    var plannedDuration: StepDuration
    var durationSeconds: Double
    var distanceMeters: Double
    var skipped: Bool

    var id: Int { index }

    var paceSecondsPerKm: Double? {
        distanceMeters > 20 ? durationSeconds / distanceMeters * 1000 : nil
    }

    var compliance: PaceRange.Compliance? {
        guard !skipped, let target, let pace = paceSecondsPerKm else { return nil }
        return target.compliance(for: pace)
    }
}

/// A sample for the pace chart: distance covered vs. smoothed pace at that point.
struct PaceSample: Codable, Hashable, Identifiable {
    var distanceMeters: Double
    var elapsedSeconds: Double
    var paceSecondsPerKm: Double
    var heartRate: Double?

    var id: Double { elapsedSeconds }
}
