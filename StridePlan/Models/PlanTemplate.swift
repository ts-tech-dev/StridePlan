import Foundation

// MARK: - Plan catalog (bundled JSON, never stored in SwiftData)

enum PlanGoal: String, Codable, CaseIterable, Identifiable, Hashable {
    case couchTo5K
    case fiveK
    case tenK
    case halfMarathon
    case marathon
    case baseBuilding

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .couchTo5K: "Couch to 5K"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half Marathon"
        case .marathon: "Marathon"
        case .baseBuilding: "Base Building"
        }
    }

    /// Race distance in meters, or nil for open-ended goals.
    var raceDistanceMeters: Double? {
        switch self {
        case .couchTo5K, .fiveK: 5_000
        case .tenK: 10_000
        case .halfMarathon: 21_097.5
        case .marathon: 42_195
        case .baseBuilding: nil
        }
    }

    var isRaceGoal: Bool { raceDistanceMeters != nil && self != .couchTo5K }

    var symbolName: String {
        switch self {
        case .couchTo5K: "figure.walk.motion"
        case .fiveK: "5.circle.fill"
        case .tenK: "10.circle.fill"
        case .halfMarathon: "medal"
        case .marathon: "trophy"
        case .baseBuilding: "chart.line.uptrend.xyaxis"
        }
    }
}

enum PlanLevel: String, Codable, CaseIterable, Identifiable, Hashable, Comparable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    private var order: Int {
        switch self {
        case .beginner: 0
        case .intermediate: 1
        case .advanced: 2
        }
    }

    static func < (lhs: PlanLevel, rhs: PlanLevel) -> Bool { lhs.order < rhs.order }
}

struct CountRange: Codable, Hashable {
    var min: Int
    var max: Int

    var displayText: String { min == max ? "\(min)" : "\(min)–\(max)" }

    func overlaps(_ other: ClosedRange<Int>) -> Bool {
        min <= other.upperBound && max >= other.lowerBound
    }
}

struct PlanPhase: Codable, Hashable {
    var name: String
    /// Inclusive `[firstWeek, lastWeek]`, 1-based.
    var weeks: [Int]

    var range: ClosedRange<Int> {
        let first = weeks.first ?? 1
        let last = weeks.last ?? first
        return first...Swift.max(first, last)
    }
}

struct PlanTemplate: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var goal: PlanGoal
    var level: PlanLevel
    var weeks: Int
    var runsPerWeek: CountRange
    var description: String
    var phases: [PlanPhase]
    var schedule: [PlanWeek]

    func week(_ number: Int) -> PlanWeek? {
        schedule.first { $0.week == number }
    }

    func phase(forWeek week: Int) -> String {
        phases.first { $0.range.contains(week) }?.name ?? ""
    }

    func workout(id workoutID: String) -> WorkoutTemplate? {
        for week in schedule {
            if let match = week.workouts.first(where: { $0.id == workoutID }) {
                return match
            }
        }
        return nil
    }

    var raceWorkout: WorkoutTemplate? {
        schedule.last?.workouts.last { $0.type == .race }
    }
}

struct PlanWeek: Codable, Hashable {
    var week: Int
    var workouts: [WorkoutTemplate]

    /// Workouts that need a calendar slot (rest days are implicit).
    var scheduledWorkouts: [WorkoutTemplate] {
        workouts.filter { $0.type != .rest }
    }
}

enum WorkoutType: String, Codable, CaseIterable, Hashable {
    case easy, recovery, long, tempo, intervals, hills, fartlek, progression, race, crossTrain, rest

    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .recovery: "Recovery"
        case .long: "Long Run"
        case .tempo: "Tempo"
        case .intervals: "Intervals"
        case .hills: "Hills"
        case .fartlek: "Fartlek"
        case .progression: "Progression"
        case .race: "Race"
        case .crossTrain: "Cross-Train"
        case .rest: "Rest"
        }
    }

    /// Sessions that should be separated from each other and from the long run.
    var isQuality: Bool {
        switch self {
        case .tempo, .intervals, .hills, .fartlek, .progression, .race: true
        default: false
        }
    }

    /// Lower values are dropped first when a week has more workouts than available days.
    var schedulingPriority: Int {
        switch self {
        case .race: 100
        case .long: 90
        case .tempo, .intervals: 80
        case .hills, .progression, .fartlek: 70
        case .easy: 50
        case .recovery: 40
        case .crossTrain: 20
        case .rest: 0
        }
    }

    var symbolName: String {
        switch self {
        case .easy: "figure.run"
        case .recovery: "leaf"
        case .long: "road.lanes"
        case .tempo: "speedometer"
        case .intervals: "repeat"
        case .hills: "mountain.2"
        case .fartlek: "shuffle"
        case .progression: "chart.line.uptrend.xyaxis"
        case .race: "flag.checkered"
        case .crossTrain: "bicycle"
        case .rest: "bed.double"
        }
    }

    var isRun: Bool { self != .crossTrain && self != .rest }
}

struct WorkoutTemplate: Codable, Identifiable, Hashable {
    var id: String
    var type: WorkoutType
    var title: String
    var isLongRun: Bool
    var notes: String?
    var steps: [WorkoutStep]

    init(id: String, type: WorkoutType, title: String, isLongRun: Bool = false, notes: String? = nil, steps: [WorkoutStep]) {
        self.id = id
        self.type = type
        self.title = title
        self.isLongRun = isLongRun
        self.notes = notes
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(WorkoutType.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        isLongRun = try c.decodeIfPresent(Bool.self, forKey: .isLongRun) ?? (type == .long)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        steps = try c.decodeIfPresent([WorkoutStep].self, forKey: .steps) ?? []
    }

    var flatSteps: [FlatStep] { WorkoutStep.flatten(steps) }
}
