import Foundation

enum UnitSystem: String, Codable, CaseIterable, Identifiable, Hashable {
    case metric
    case imperial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metric: "Kilometers"
        case .imperial: "Miles"
        }
    }

    var distanceAbbreviation: String {
        switch self {
        case .metric: "km"
        case .imperial: "mi"
        }
    }

    var paceSuffix: String { "/\(distanceAbbreviation)" }

    /// Meters in one display unit (1 km or 1 mile).
    var metersPerUnit: Double {
        switch self {
        case .metric: 1_000
        case .imperial: 1_609.344
        }
    }

    var splitName: String {
        switch self {
        case .metric: "kilometer"
        case .imperial: "mile"
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case new
    case returning
    case regular
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .new: "New to running"
        case .returning: "Returning"
        case .regular: "Regular runner"
        case .advanced: "Advanced"
        }
    }

    var detail: String {
        switch self {
        case .new: "I'm just getting started or can't yet run 5K."
        case .returning: "I used to run and I'm getting back into it."
        case .regular: "I run a few times a week."
        case .advanced: "I train consistently and race often."
        }
    }

    var suggestedPlanLevel: PlanLevel {
        switch self {
        case .new, .returning: .beginner
        case .regular: .intermediate
        case .advanced: .advanced
        }
    }
}

/// A reference performance used to compute pace zones.
struct RaceResult: Codable, Hashable {
    var distanceMeters: Double
    var timeSeconds: Double
    var date: Date

    struct CommonDistance: Hashable, Identifiable {
        var name: String
        var meters: Double
        var id: String { name }
    }

    static let commonDistances: [CommonDistance] = [
        CommonDistance(name: "1 mile", meters: 1_609.344),
        CommonDistance(name: "5K", meters: 5_000),
        CommonDistance(name: "10K", meters: 10_000),
        CommonDistance(name: "Half", meters: 21_097.5),
        CommonDistance(name: "Marathon", meters: 42_195),
    ]

    static func name(forDistance meters: Double) -> String {
        commonDistances.first { abs($0.meters - meters) < 1 }?.name
            ?? String(format: "%.1f km", meters / 1000)
    }
}
