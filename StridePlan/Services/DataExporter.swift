import Foundation
import SwiftData

/// Exports everything the user has created as one JSON document.
@MainActor
enum DataExporter {
    struct Export: Codable {
        var exportedAt: Date
        var app: String
        var profile: ProfileExport?
        var plans: [PlanExport]
        var runs: [RunExport]
    }

    struct ProfileExport: Codable {
        var name: String
        var units: UnitSystem
        var level: ExperienceLevel
        var weeklyVolumeMeters: Double
        var referenceResult: RaceResult?
        var paceZones: PaceZones
    }

    struct PlanExport: Codable {
        var planID: String
        var title: String
        var status: String
        var startDate: Date
        var raceDate: Date?
        var weekdays: [Int]
        var longRunWeekday: Int
        var goalTimeSeconds: Double?
        var workouts: [WorkoutExport]
    }

    struct WorkoutExport: Codable {
        var date: Date
        var templateWeek: Int
        var templateWorkoutID: String
        var status: String
        var runID: UUID?
    }

    struct RunExport: Codable {
        var id: UUID
        var startDate: Date
        var endDate: Date
        var title: String
        var type: String
        var distanceMeters: Double
        var durationSeconds: Double
        var isManual: Bool
        var rpe: Int?
        var notes: String
        var averageHeartRate: Double?
        var splits: [Split]
        var steps: [StepResult]
        var route: [RoutePoint]
    }

    static func makeExport(context: ModelContext) throws -> Data {
        let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        let plans = try context.fetch(FetchDescriptor<ActivePlan>(sortBy: [SortDescriptor(\.createdAt)]))
        let runs = try context.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.startDate)]))

        let export = Export(
            exportedAt: .now,
            app: AppBrand.name,
            profile: profile.map {
                ProfileExport(name: $0.name, units: $0.units, level: $0.level, weeklyVolumeMeters: $0.weeklyVolumeMeters,
                              referenceResult: $0.referenceResult, paceZones: $0.paceZones)
            },
            plans: plans.map { plan in
                PlanExport(planID: plan.planID, title: plan.planTitle, status: plan.statusRaw, startDate: plan.startDate,
                           raceDate: plan.raceDate, weekdays: plan.weekdays, longRunWeekday: plan.longRunWeekday,
                           goalTimeSeconds: plan.goalTimeSeconds,
                           workouts: plan.sortedWorkouts.map {
                               WorkoutExport(date: $0.date, templateWeek: $0.templateWeek, templateWorkoutID: $0.templateWorkoutID,
                                             status: $0.statusRaw, runID: $0.run?.id)
                           })
            },
            runs: runs.map {
                RunExport(id: $0.id, startDate: $0.startDate, endDate: $0.endDate, title: $0.workoutTitle, type: $0.workoutTypeRaw,
                          distanceMeters: $0.distanceMeters, durationSeconds: $0.durationSeconds, isManual: $0.isManual,
                          rpe: $0.rpe, notes: $0.notes, averageHeartRate: $0.averageHeartRate,
                          splits: $0.splits, steps: $0.stepResults, route: $0.route)
            })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// Writes the export to a temporary file suitable for `ShareLink`.
    static func writeExportFile(context: ModelContext) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppBrand.name)-export-\(formatter.string(from: .now)).json")
        try makeExport(context: context).write(to: url, options: .atomic)
        return url
    }
}
