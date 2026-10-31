import SwiftData
import SwiftUI

/// In-memory data for SwiftUI previews: an onboarded runner three weeks into a half-marathon plan.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: UserProfile.self, ActivePlan.self, ScheduledWorkout.self, RunRecord.self,
                                           configurations: configuration)
        } catch {
            fatalError("Preview container failed: \(error)")
        }
        seed(container.mainContext)
        return container
    }()

    static var context: ModelContext { container.mainContext }

    static var profile: UserProfile {
        (try? context.fetch(FetchDescriptor<UserProfile>()).first) ?? UserProfile()
    }

    static var plan: ActivePlan? {
        try? context.fetch(FetchDescriptor<ActivePlan>()).first
    }

    static var run: RunRecord {
        (try? context.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])).first) ?? sampleRun(daysAgo: 1)
    }

    static var template: PlanTemplate {
        AppServices.preview.plans.plan(id: "half-marathon-intermediate-12w") ?? AppServices.preview.plans.allPlans()[0]
    }

    static var intervalWorkout: WorkoutTemplate {
        template.schedule.flatMap(\.workouts).first { $0.type == .intervals } ?? template.schedule[0].workouts[0]
    }

    static var upcomingWorkout: ScheduledWorkout? {
        plan?.sortedWorkouts.first { $0.status == .upcoming }
    }

    private static func seed(_ context: ModelContext) {
        let profile = UserProfile(name: "Alex", units: .metric, level: .regular)
        profile.hasCompletedOnboarding = true
        profile.weeklyVolumeMeters = 25_000
        profile.referenceResult = RaceResult(distanceMeters: 5_000, timeSeconds: 25 * 60, date: .now.addingTimeInterval(-30 * 86_400))
        context.insert(profile)

        let template = Self.template
        let start = Calendar.current.date(byAdding: .day, value: -17, to: .now) ?? .now
        let plan = PlanManager.startPlan(
            template: template,
            request: ScheduleRequest(anchor: .start(start), weekdays: [3, 5, 7, 1], longRunWeekday: 1),
            goalTimeSeconds: 115 * 60, profile: profile, context: context)

        // Complete most past workouts, leave one missed.
        let past = plan.sortedWorkouts.filter { $0.date < Calendar.current.startOfDay(for: .now) }
        for (index, workout) in past.enumerated() where index != past.count - 2 {
            let item = template.workout(id: workout.templateWorkoutID)
            let estimate = item?.estimate(zones: profile.paceZones)
            let run = sampleRun(date: workout.date, distance: estimate?.distanceMeters ?? 6_000,
                                title: item?.title ?? "Run", type: item?.type ?? .easy, steps: item?.flatSteps ?? [], zones: profile.paceZones)
            context.insert(run)
            PlanManager.complete(workout, with: run)
        }
        PlanManager.refreshStatuses(plan)
        try? context.save()
    }

    static func sampleRun(daysAgo: Int) -> RunRecord {
        sampleRun(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now,
                  distance: 8_000, title: "Easy 8 km", type: .easy, steps: [], zones: .effortOnly(level: .regular))
    }

    static func sampleRun(date: Date, distance: Double, title: String, type: WorkoutType, steps: [FlatStep], zones: PaceZones) -> RunRecord {
        let pace = 345.0
        let duration = distance / 1000 * pace
        let start = Calendar.current.date(bySettingHour: 7, minute: 10, second: 0, of: date) ?? date
        let run = RunRecord(startDate: start, endDate: start.addingTimeInterval(duration + 30), distanceMeters: distance,
                            durationSeconds: duration, workoutTitle: title, workoutType: type)
        run.rpe = 5
        run.averageHeartRate = 148

        // Loop route around a park.
        let center = (lat: 51.5073, lon: -0.1657)
        let count = 120
        run.route = (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi
            return RoutePoint(latitude: center.lat + 0.006 * sin(angle), longitude: center.lon + 0.010 * cos(angle) + 0.0006 * sin(angle * 5),
                              altitude: 20, timestamp: start.addingTimeInterval(duration * Double(i) / Double(count)),
                              horizontalAccuracy: 5, speed: 1000 / pace)
        }
        let unit = 1000.0
        let fullSplits = Int(distance / unit)
        run.splits = (0..<fullSplits).map { Split(index: $0 + 1, distanceMeters: unit, durationSeconds: pace + Double(($0 * 7) % 13) - 6) }
        run.paceSamples = stride(from: 0.0, through: duration, by: 30).map { t in
            PaceSample(distanceMeters: t / pace * 1000, elapsedSeconds: t, paceSecondsPerKm: pace + 12 * sin(t / 200), heartRate: 140 + 10 * sin(t / 400))
        }
        run.stepResults = steps.map { step in
            let target = zones.range(for: step.zone)
            let stepPace = (target?.midpoint ?? pace) + Double(step.index % 3 - 1) * 8
            let seconds = step.duration.type == .time ? step.duration.value : step.duration.value / 1000 * stepPace
            let meters = step.duration.type == .distance ? step.duration.value : step.duration.value / stepPace * 1000
            return StepResult(index: step.index, title: step.title, kind: step.kind, zone: step.zone, target: target,
                              plannedDuration: step.duration, durationSeconds: seconds, distanceMeters: meters, skipped: false)
        }
        return run
    }
}

extension View {
    /// Injects everything a screen needs to render in a preview.
    @MainActor
    func previewEnvironment() -> some View {
        self
            .modelContainer(PreviewData.container)
            .environment(\.services, .preview)
            .environment(RunLauncher())
            .tint(Theme.accent)
    }
}
