import Foundation

enum PaceZoneKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case walk, recovery, easy, steady, tempo, threshold, interval, repetition, race

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walk: "Walk"
        case .recovery: "Recovery"
        case .easy: "Easy"
        case .steady: "Steady"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .interval: "Interval"
        case .repetition: "Repetition"
        case .race: "Race Pace"
        }
    }

    var shortName: String {
        switch self {
        case .walk: "walk"
        case .recovery: "jog"
        case .easy: "easy"
        case .steady: "steady"
        case .tempo: "tempo"
        case .threshold: "threshold"
        case .interval: "interval"
        case .repetition: "reps"
        case .race: "race pace"
        }
    }

    /// Effort-based guidance used when no reference time is available.
    var effortCue: String {
        switch self {
        case .walk: "Brisk walk · RPE 2"
        case .recovery: "Very easy jog · RPE 2–3"
        case .easy: "Conversational · RPE 3–4"
        case .steady: "Comfortably firm · RPE 5"
        case .tempo: "Comfortably hard · RPE 6–7"
        case .threshold: "Hard, controlled · RPE 7–8"
        case .interval: "Hard · RPE 8–9"
        case .repetition: "Fast & relaxed · RPE 9"
        case .race: "Goal race effort"
        }
    }

    /// Fraction of VDOT (VO₂max-equivalent) used to derive the zone's pace range.
    /// Lower fraction → slower pace. Loosely follows Daniels' training intensities.
    var vdotFractionRange: ClosedRange<Double>? {
        switch self {
        case .walk: nil
        case .recovery: 0.55...0.62
        case .easy: 0.62...0.72
        case .steady: 0.74...0.80
        case .tempo: 0.80...0.85
        case .threshold: 0.86...0.89
        case .interval: 0.95...1.00
        case .repetition: 1.05...1.10
        case .race: nil
        }
    }

    /// Typical pace (sec/km) used for estimates when the runner has no reference time.
    func defaultPace(for level: ExperienceLevel) -> Double {
        let easy: Double = switch level {
        case .new: 450
        case .returning: 400
        case .regular: 360
        case .advanced: 315
        }
        switch self {
        case .walk: return 600
        case .recovery: return easy + 30
        case .easy: return easy
        case .steady: return easy - 35
        case .tempo: return easy - 60
        case .threshold: return easy - 75
        case .interval: return easy - 95
        case .repetition: return easy - 110
        case .race: return easy - 55
        }
    }
}

/// A pace window in seconds per kilometer. `fast` is the smaller number.
struct PaceRange: Codable, Hashable {
    var fast: Double
    var slow: Double

    var midpoint: Double { (fast + slow) / 2 }

    func contains(_ pace: Double, tolerance: Double = 0) -> Bool {
        pace >= fast - tolerance && pace <= slow + tolerance
    }

    enum Compliance: String, Codable, Hashable {
        case under   // slower than target
        case hit
        case over    // faster than target
    }

    func compliance(for pace: Double, tolerance: Double = 5) -> Compliance {
        if pace < fast - tolerance { return .over }
        if pace > slow + tolerance { return .under }
        return .hit
    }
}

/// The runner's personal training paces. When `ranges` is empty the app falls back to effort cues.
struct PaceZones: Codable, Hashable {
    var vdot: Double?
    var ranges: [String: PaceRange]
    var level: ExperienceLevel

    init(vdot: Double? = nil, ranges: [PaceZoneKind: PaceRange] = [:], level: ExperienceLevel = .regular) {
        self.vdot = vdot
        self.ranges = Dictionary(uniqueKeysWithValues: ranges.map { ($0.key.rawValue, $0.value) })
        self.level = level
    }

    static func effortOnly(level: ExperienceLevel) -> PaceZones {
        PaceZones(level: level)
    }

    var isPaceBased: Bool { !ranges.isEmpty }

    func range(for zone: PaceZoneKind) -> PaceRange? {
        ranges[zone.rawValue]
    }

    func estimatedPace(for zone: PaceZoneKind) -> Double {
        range(for: zone)?.midpoint ?? zone.defaultPace(for: level)
    }
}
