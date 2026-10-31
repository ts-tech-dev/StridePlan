import Foundation

enum StepKind: String, Codable, Hashable {
    case warmup, run, recover, cooldown, walk, `repeat`

    var displayName: String {
        switch self {
        case .warmup: "Warm-up"
        case .run: "Run"
        case .recover: "Recover"
        case .cooldown: "Cool-down"
        case .walk: "Walk"
        case .repeat: "Repeat"
        }
    }
}

enum DurationType: String, Codable, Hashable {
    case time
    case distance
}

struct StepDuration: Codable, Hashable {
    var type: DurationType
    /// Seconds for `.time`, meters for `.distance`.
    var value: Double

    static func time(_ seconds: Double) -> StepDuration { .init(type: .time, value: seconds) }
    static func distance(_ meters: Double) -> StepDuration { .init(type: .distance, value: meters) }
}

/// A node in a structured workout. `repeat` nodes carry `count` and nested `steps`.
struct WorkoutStep: Codable, Hashable {
    var kind: StepKind
    var duration: StepDuration?
    var zone: PaceZoneKind?
    var count: Int?
    var steps: [WorkoutStep]?
    var note: String?

    init(kind: StepKind, duration: StepDuration? = nil, zone: PaceZoneKind? = nil, count: Int? = nil, steps: [WorkoutStep]? = nil, note: String? = nil) {
        self.kind = kind
        self.duration = duration
        self.zone = zone
        self.count = count
        self.steps = steps
        self.note = note
    }

    static func repeated(_ count: Int, _ steps: [WorkoutStep]) -> WorkoutStep {
        WorkoutStep(kind: .repeat, count: count, steps: steps)
    }

    /// Expands repeat blocks into a linear list the run engine can walk through.
    static func flatten(_ steps: [WorkoutStep]) -> [FlatStep] {
        var result: [FlatStep] = []
        func visit(_ nodes: [WorkoutStep], repeatContext: (index: Int, count: Int)?) {
            for node in nodes {
                if node.kind == .repeat {
                    let count = max(node.count ?? 1, 0)
                    guard count > 0 else { continue }
                    for i in 0..<count {
                        visit(node.steps ?? [], repeatContext: (i + 1, count))
                    }
                } else if let duration = node.duration, duration.value > 0 {
                    result.append(FlatStep(
                        index: result.count,
                        kind: node.kind,
                        duration: duration,
                        zone: node.zone ?? node.kind.defaultZone,
                        repeatIndex: repeatContext?.index,
                        repeatCount: repeatContext?.count,
                        note: node.note
                    ))
                }
            }
        }
        visit(steps, repeatContext: nil)
        return result
    }
}

extension StepKind {
    var defaultZone: PaceZoneKind {
        switch self {
        case .warmup, .cooldown, .run: .easy
        case .recover: .recovery
        case .walk, .repeat: .walk
        }
    }
}

/// A single executable step after repeat expansion.
struct FlatStep: Hashable, Identifiable, Codable {
    var index: Int
    var kind: StepKind
    var duration: StepDuration
    var zone: PaceZoneKind
    var repeatIndex: Int?
    var repeatCount: Int?
    var note: String?

    var id: Int { index }

    var title: String {
        if let repeatIndex, let repeatCount {
            return "\(kind.displayName) \(repeatIndex)/\(repeatCount)"
        }
        return kind.displayName
    }
}

// MARK: - Estimates

struct WorkoutEstimate: Hashable {
    var durationSeconds: Double
    var distanceMeters: Double
}

extension Array where Element == FlatStep {
    /// Estimated total time and distance using the midpoint of each step's pace range.
    func estimate(zones: PaceZones) -> WorkoutEstimate {
        var time = 0.0
        var distance = 0.0
        for step in self {
            let pace = zones.estimatedPace(for: step.zone)
            switch step.duration.type {
            case .time:
                time += step.duration.value
                distance += step.duration.value / pace * 1000
            case .distance:
                distance += step.duration.value
                time += step.duration.value / 1000 * pace
            }
        }
        return WorkoutEstimate(durationSeconds: time, distanceMeters: distance)
    }
}

extension WorkoutTemplate {
    func estimate(zones: PaceZones) -> WorkoutEstimate {
        flatSteps.estimate(zones: zones)
    }

    /// One-line structure summary, e.g. "10:00 WU · 6 × 400 m · 10:00 CD".
    func structureSummary(units: UnitSystem) -> String {
        steps.map { $0.summary(units: units) }.joined(separator: " · ")
    }
}

extension WorkoutStep {
    func summary(units: UnitSystem) -> String {
        if kind == .repeat {
            let inner = (steps ?? []).map { $0.summary(units: units) }.joined(separator: " + ")
            return "\(count ?? 1) × (\(inner))"
        }
        guard let duration else { return kind.displayName }
        let amount: String = switch duration.type {
        case .time: Formatters.duration(duration.value, style: .compact)
        case .distance: Formatters.stepDistance(duration.value, units: units)
        }
        let zoneText = zone.map { " \($0.shortName)" } ?? ""
        return "\(amount)\(zoneText)"
    }
}
