import Foundation
import SwiftData

// Complex value types are stored as JSON `Data` blobs with typed accessors. This keeps the
// SwiftData schema simple and makes migrations predictable.

@Model
final class UserProfile {
    var name: String
    var unitsRaw: String
    var levelRaw: String
    var weeklyVolumeMeters: Double
    var referenceResultData: Data?
    var paceZonesData: Data?
    var hasCompletedOnboarding: Bool

    // Settings
    var voiceCuesEnabled: Bool
    var voiceStepChanges: Bool
    var voiceSplits: Bool
    var voicePaceAlerts: Bool
    var paceAlertToleranceSeconds: Double
    var remindersEnabled: Bool
    /// Minutes after midnight.
    var reminderMinutes: Int
    var healthKitEnabled: Bool
    var simulateGPS: Bool
    var createdAt: Date

    init(name: String = "", units: UnitSystem = .metric, level: ExperienceLevel = .regular) {
        self.name = name
        self.unitsRaw = units.rawValue
        self.levelRaw = level.rawValue
        self.weeklyVolumeMeters = 0
        self.hasCompletedOnboarding = false
        self.voiceCuesEnabled = true
        self.voiceStepChanges = true
        self.voiceSplits = true
        self.voicePaceAlerts = true
        self.paceAlertToleranceSeconds = 10
        self.remindersEnabled = true
        self.reminderMinutes = 7 * 60
        self.healthKitEnabled = false
        self.simulateGPS = false
        self.createdAt = .now
    }

    var units: UnitSystem {
        get { UnitSystem(rawValue: unitsRaw) ?? .metric }
        set { unitsRaw = newValue.rawValue }
    }

    var level: ExperienceLevel {
        get { ExperienceLevel(rawValue: levelRaw) ?? .regular }
        set { levelRaw = newValue.rawValue }
    }

    var referenceResult: RaceResult? {
        get { referenceResultData.flatMap { try? JSONDecoder().decode(RaceResult.self, from: $0) } }
        set { referenceResultData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Stored zones, or effort-based fallback zones when none have been computed.
    var paceZones: PaceZones {
        get { paceZonesData.flatMap { try? JSONDecoder().decode(PaceZones.self, from: $0) } ?? .effortOnly(level: level) }
        set { paceZonesData = try? JSONEncoder().encode(newValue) }
    }

    var reminderTime: DateComponents {
        DateComponents(hour: reminderMinutes / 60, minute: reminderMinutes % 60)
    }

    var voiceSettings: VoiceSettings {
        VoiceSettings(enabled: voiceCuesEnabled, stepChanges: voiceStepChanges, splits: voiceSplits,
                      paceAlerts: voicePaceAlerts, toleranceSeconds: paceAlertToleranceSeconds)
    }

    /// Recomputes zones from the reference result and, if present, the active plan's goal.
    func recalculateZones(activePlan: ActivePlan?, template: PlanTemplate?) {
        paceZones = PaceCalculator.zones(
            reference: referenceResult,
            goalTimeSeconds: activePlan?.goalTimeSeconds,
            raceDistanceMeters: template?.goal.raceDistanceMeters,
            level: level
        )
    }
}

struct VoiceSettings: Hashable {
    var enabled: Bool
    var stepChanges: Bool
    var splits: Bool
    var paceAlerts: Bool
    var toleranceSeconds: Double
}

enum PlanStatus: String, Codable {
    case active, completed, ended
}

@Model
final class ActivePlan {
    var planID: String
    var planTitle: String
    var startDate: Date
    var raceDate: Date?
    var weekdays: [Int]
    var longRunWeekday: Int
    var goalTimeSeconds: Double?
    var statusRaw: String
    var createdAt: Date
    /// Calendar weeks for which the "missed workouts" prompt has already been shown.
    var adaptationPromptedWeeks: [Int]

    @Relationship(deleteRule: .cascade, inverse: \ScheduledWorkout.plan)
    var workouts: [ScheduledWorkout] = []

    init(planID: String, planTitle: String, startDate: Date, raceDate: Date?, weekdays: [Int], longRunWeekday: Int, goalTimeSeconds: Double?) {
        self.planID = planID
        self.planTitle = planTitle
        self.startDate = startDate
        self.raceDate = raceDate
        self.weekdays = weekdays
        self.longRunWeekday = longRunWeekday
        self.goalTimeSeconds = goalTimeSeconds
        self.statusRaw = PlanStatus.active.rawValue
        self.createdAt = .now
        self.adaptationPromptedWeeks = []
    }

    var status: PlanStatus {
        get { PlanStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var sortedWorkouts: [ScheduledWorkout] {
        workouts.sorted { $0.date == $1.date ? $0.orderInDay < $1.orderInDay : $0.date < $1.date }
    }

    var endDate: Date {
        workouts.map(\.date).max() ?? startDate
    }
}

enum WorkoutStatus: String, Codable, CaseIterable {
    case upcoming, completed, skipped, missed
}

@Model
final class ScheduledWorkout {
    var date: Date
    /// Template week the workout comes from (used to look up the template and phase).
    var templateWeek: Int
    var templateWorkoutID: String
    var statusRaw: String
    var orderInDay: Int
    var isRepeat: Bool
    var plan: ActivePlan?

    @Relationship(deleteRule: .nullify)
    var run: RunRecord?

    init(date: Date, templateWeek: Int, templateWorkoutID: String, orderInDay: Int = 0, isRepeat: Bool = false) {
        self.date = date
        self.templateWeek = templateWeek
        self.templateWorkoutID = templateWorkoutID
        self.statusRaw = WorkoutStatus.upcoming.rawValue
        self.orderInDay = orderInDay
        self.isRepeat = isRepeat
    }

    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .upcoming }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class RunRecord {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date
    var distanceMeters: Double
    /// Moving time, excluding pauses.
    var durationSeconds: Double
    var workoutTitle: String
    var workoutTypeRaw: String
    var splitsData: Data?
    var routeData: Data?
    var stepResultsData: Data?
    var paceSamplesData: Data?
    var rpe: Int?
    var notes: String
    var healthKitUUID: UUID?
    var isManual: Bool
    var averageHeartRate: Double?
    /// Set for runs recorded on a Garmin watch; used to skip re-imports.
    var garminActivityID: String?

    @Relationship(inverse: \ScheduledWorkout.run)
    var scheduledWorkout: ScheduledWorkout?

    init(id: UUID = UUID(), startDate: Date, endDate: Date, distanceMeters: Double, durationSeconds: Double,
         workoutTitle: String, workoutType: WorkoutType, isManual: Bool = false, notes: String = "") {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.workoutTitle = workoutTitle
        self.workoutTypeRaw = workoutType.rawValue
        self.isManual = isManual
        self.notes = notes
    }

    var workoutType: WorkoutType { WorkoutType(rawValue: workoutTypeRaw) ?? .easy }

    var isFromGarmin: Bool { garminActivityID != nil }

    var averagePaceSecondsPerKm: Double? {
        distanceMeters > 50 ? durationSeconds / distanceMeters * 1000 : nil
    }

    var splits: [Split] {
        get { decode(splitsData) ?? [] }
        set { splitsData = encode(newValue) }
    }

    var route: [RoutePoint] {
        get { decode(routeData) ?? [] }
        set { routeData = encode(newValue) }
    }

    var stepResults: [StepResult] {
        get { decode(stepResultsData) ?? [] }
        set { stepResultsData = encode(newValue) }
    }

    var paceSamples: [PaceSample] {
        get { decode(paceSamplesData) ?? [] }
        set { paceSamplesData = encode(newValue) }
    }

    private func decode<T: Decodable>(_ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [UserProfile.self, ActivePlan.self, ScheduledWorkout.self, RunRecord.self]
}
