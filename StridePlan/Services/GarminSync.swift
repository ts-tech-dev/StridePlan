import Foundation
import SwiftData

/// Keeps the watch's workout list current and turns runs recorded on the watch into history entries.
@MainActor
enum GarminSync {
    /// The watch gets today's and the next few days' workouts, so it works without the phone nearby.
    static let daysAhead = 7
    static let maxWorkouts = 7

    static func handle(_ event: GarminEvent, profile: UserProfile, services: AppServices, context: ModelContext) {
        switch event {
        case .watchAppOpened:
            Task { try? await sendUpcoming(profile: profile, services: services, context: context) }
        case .runReceived(let run):
            importRun(run, profile: profile, plans: services.plans, context: context)
            // Ack even when the run was already imported, so the watch stops resending it.
            Task { try? await services.garmin.send(GarminProtocol.ackMessage(runID: run.header.id)) }
        }
    }

    /// Sends the upcoming workouts, making sure `including` is in the list even if it's further out.
    static func sendUpcoming(profile: UserProfile, services: AppServices, context: ModelContext,
                             including extra: ScheduledWorkout? = nil) async throws {
        let workouts = upcoming(plan: activePlan(context), plans: services.plans, including: extra)
        try await services.garmin.send(GarminProtocol.workoutsMessage(workouts, zones: profile.paceZones, units: profile.units))
    }

    static func upcoming(plan: ActivePlan?, plans: PlanProviding, including extra: ScheduledWorkout? = nil,
                         now: Date = .now, calendar: Calendar = .current) -> [GarminProtocol.OutgoingWorkout] {
        guard let plan, let template = plans.plan(id: plan.planID) else { return [] }
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
        var scheduled = plan.sortedWorkouts.filter { $0.status == .upcoming && $0.date >= today && $0.date < horizon }
        if let extra, !scheduled.contains(where: { $0 === extra }) {
            scheduled.insert(extra, at: 0)
        }
        let workouts = scheduled.compactMap { item -> GarminProtocol.OutgoingWorkout? in
            guard let workout = template.workout(id: item.templateWorkoutID), workout.type.isRun else { return nil }
            return GarminProtocol.OutgoingWorkout(id: workoutID(for: item, calendar: calendar), date: item.date, workout: workout)
        }
        return Array(workouts.prefix(maxWorkouts))
    }

    static func workoutID(for scheduled: ScheduledWorkout, calendar: Calendar = .current) -> String {
        GarminProtocol.workoutID(date: scheduled.date, orderInDay: scheduled.orderInDay,
                                 templateWorkoutID: scheduled.templateWorkoutID, calendar: calendar)
    }

    /// Saves a watch run to history and completes the scheduled workout it was recorded for.
    /// Returns nil when the run was imported before.
    @discardableResult
    static func importRun(_ run: GarminRun, profile: UserProfile, plans: PlanProviding, context: ModelContext) -> RunRecord? {
        let header = run.header
        let activityID = header.id
        let existing = (try? context.fetchCount(FetchDescriptor<RunRecord>(predicate: #Predicate { $0.garminActivityID == activityID }))) ?? 0
        guard existing == 0 else { return nil }

        let plan = activePlan(context)
        let scheduled = header.workoutID.flatMap { id in plan?.workouts.first { workoutID(for: $0) == id } }
        let workout = scheduled.flatMap { item in
            plan.flatMap { plans.plan(id: $0.planID) }?.workout(id: item.templateWorkoutID)
        }

        let record = RunRecord(startDate: header.start, endDate: header.end, distanceMeters: header.distanceMeters,
                               durationSeconds: header.movingSeconds, workoutTitle: workout?.title ?? header.title,
                               workoutType: workout?.type ?? .easy)
        record.garminActivityID = activityID
        record.averageHeartRate = header.averageHeartRate
        record.splits = header.splits
        record.route = run.route
        record.paceSamples = run.samples
        if let workout {
            record.stepResults = GarminProtocol.stepResults(planned: workout.flatSteps, totals: header.steps, zones: profile.paceZones)
        }
        context.insert(record)
        if let scheduled, scheduled.status != .completed {
            PlanManager.complete(scheduled, with: record)
        }
        try? context.save()
        return record
    }

    private static func activePlan(_ context: ModelContext) -> ActivePlan? {
        let descriptor = FetchDescriptor<ActivePlan>(predicate: #Predicate { $0.statusRaw == "active" })
        return (try? context.fetch(descriptor))?.first
    }
}
