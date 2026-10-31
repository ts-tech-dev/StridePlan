import Foundation
import SwiftData

/// One calendar week of an active plan, as shown on the Plan tab.
struct PlanWeekGroup: Identifiable {
    var index: Int
    var startDate: Date
    var endDate: Date
    var templateWeek: Int
    var phase: String
    var workouts: [ScheduledWorkout]
    var plannedDistance: Double
    var completedDistance: Double

    var id: Int { index }
    var completedCount: Int { workouts.filter { $0.status == .completed }.count }
    var missedCount: Int { workouts.filter { $0.status == .missed }.count }
    var progress: Double {
        let countable = workouts.filter { $0.status != .skipped }.count
        return countable == 0 ? 0 : Double(completedCount) / Double(countable)
    }
}

/// All mutations of the user's schedule live here so views stay thin and behaviour is consistent.
@MainActor
enum PlanManager {
    static var calendar: Calendar { .current }

    // MARK: Creating

    @discardableResult
    static func startPlan(
        template: PlanTemplate,
        request: ScheduleRequest,
        goalTimeSeconds: Double?,
        profile: UserProfile,
        context: ModelContext
    ) -> ActivePlan {
        let existing = (try? context.fetch(FetchDescriptor<ActivePlan>())) ?? []
        for plan in existing where plan.status == .active {
            end(plan, context: context)
        }

        let schedule = ScheduleGenerator(calendar: calendar).generate(template: template, request: request)
        var raceDate: Date?
        if case .race(let date) = request.anchor { raceDate = date }

        let plan = ActivePlan(planID: template.id, planTitle: template.title, startDate: schedule.startDate,
                              raceDate: raceDate, weekdays: request.weekdays.sorted(),
                              longRunWeekday: request.longRunWeekday, goalTimeSeconds: goalTimeSeconds)
        context.insert(plan)
        for item in schedule.workouts {
            let workout = ScheduledWorkout(date: item.date, templateWeek: item.week, templateWorkoutID: item.workoutID)
            workout.plan = plan
            context.insert(workout)
        }
        profile.recalculateZones(activePlan: plan, template: template)
        refreshStatuses(plan)
        try? context.save()
        return plan
    }

    /// Regenerates the remaining plan from today using the same settings.
    static func restart(_ plan: ActivePlan, template: PlanTemplate, profile: UserProfile, context: ModelContext) {
        let request = ScheduleRequest(anchor: .start(.now), weekdays: Set(plan.weekdays), longRunWeekday: plan.longRunWeekday)
        startPlan(template: template, request: request, goalTimeSeconds: plan.goalTimeSeconds, profile: profile, context: context)
    }

    static func end(_ plan: ActivePlan, context: ModelContext) {
        plan.status = .ended
        for workout in plan.workouts where workout.status != .completed {
            context.delete(workout)
        }
        try? context.save()
    }

    // MARK: Status

    /// Marks past, unfinished workouts as missed and completes the plan when everything is done.
    static func refreshStatuses(_ plan: ActivePlan, now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        for workout in plan.workouts where workout.status == .upcoming && workout.date < today {
            workout.status = .missed
        }
        if plan.status == .active, plan.endDate < today {
            plan.status = .completed
        }
    }

    static func complete(_ workout: ScheduledWorkout, with run: RunRecord) {
        workout.status = .completed
        workout.run = run
    }

    static func skip(_ workout: ScheduledWorkout) {
        workout.status = .skipped
    }

    static func restore(_ workout: ScheduledWorkout) {
        workout.status = workout.date < calendar.startOfDay(for: .now) ? .missed : .upcoming
    }

    // MARK: Rearranging

    static func swap(_ a: ScheduledWorkout, _ b: ScheduledWorkout) {
        let date = a.date
        a.date = b.date
        b.date = date
        for workout in [a, b] where workout.status != .completed && workout.status != .skipped {
            restore(workout)
        }
    }

    /// Moves a workout to another day. If that day already holds a workout, the two are swapped.
    static func move(_ workout: ScheduledWorkout, to day: Date, in plan: ActivePlan) {
        let target = calendar.startOfDay(for: day)
        if let occupant = plan.workouts.first(where: { $0 !== workout && calendar.isDate($0.date, inSameDayAs: target) && $0.status != .completed }) {
            swap(workout, occupant)
        } else {
            workout.date = target
            if workout.status != .skipped { restore(workout) }
        }
    }

    /// Days in the same calendar week as `workout` (for move/swap pickers).
    static func daysInWeek(of workout: ScheduledWorkout, plan: ActivePlan) -> [Date] {
        let index = weekIndex(of: workout.date, in: plan)
        let start = calendar.date(byAdding: .day, value: (index - 1) * 7, to: plan.startDate) ?? plan.startDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: Grouping

    static func weekIndex(of date: Date, in plan: ActivePlan) -> Int {
        max(1, ScheduleGenerator(calendar: calendar).weekIndex(of: date, planStart: plan.startDate))
    }

    static func currentWeekIndex(in plan: ActivePlan, now: Date = .now) -> Int {
        weekIndex(of: now, in: plan)
    }

    static func weeks(for plan: ActivePlan, template: PlanTemplate?, zones: PaceZones) -> [PlanWeekGroup] {
        let grouped = Dictionary(grouping: plan.sortedWorkouts) { weekIndex(of: $0.date, in: plan) }
        return grouped.keys.sorted().map { index in
            let workouts = grouped[index] ?? []
            let start = calendar.date(byAdding: .day, value: (index - 1) * 7, to: plan.startDate) ?? plan.startDate
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let templateWeek = workouts.map(\.templateWeek).max() ?? index
            let planned = workouts.reduce(0.0) { total, workout in
                total + (template?.workout(id: workout.templateWorkoutID)?.estimate(zones: zones).distanceMeters ?? 0)
            }
            let completed = workouts.reduce(0.0) { $0 + ($1.run?.distanceMeters ?? 0) }
            return PlanWeekGroup(index: index, startDate: start, endDate: end, templateWeek: templateWeek,
                                 phase: template?.phase(forWeek: templateWeek) ?? "",
                                 workouts: workouts, plannedDistance: planned, completedDistance: completed)
        }
    }

    // MARK: Adaptation

    /// Returns the most recent week (up to the current one) with 2+ missed workouts that hasn't been handled yet.
    static func weekNeedingAdaptation(in plan: ActivePlan, now: Date = .now) -> Int? {
        guard plan.status == .active else { return nil }
        let current = currentWeekIndex(in: plan, now: now)
        let grouped = Dictionary(grouping: plan.workouts) { weekIndex(of: $0.date, in: plan) }
        return grouped
            .filter { $0.key <= current && !plan.adaptationPromptedWeeks.contains($0.key) }
            .filter { $0.value.filter { $0.status == .missed }.count >= 2 }
            .keys.max()
    }

    static func dismissAdaptation(week: Int, in plan: ActivePlan) {
        plan.adaptationPromptedWeeks.append(week)
    }

    /// Repeats the template week behind calendar week `week` next week, pushing everything later back by 7 days.
    static func repeatWeek(_ week: Int, in plan: ActivePlan, template: PlanTemplate, context: ModelContext, now: Date = .now) {
        plan.adaptationPromptedWeeks.append(week)
        let sourceWorkouts = plan.workouts.filter { weekIndex(of: $0.date, in: plan) == week }
        guard let templateWeek = sourceWorkouts.map(\.templateWeek).max(), let weekTemplate = template.week(templateWeek) else { return }

        let nextWindow = currentWeekIndex(in: plan, now: now) + 1
        guard let windowStart = calendar.date(byAdding: .day, value: (nextWindow - 1) * 7, to: plan.startDate) else { return }

        for workout in plan.workouts where workout.date >= windowStart {
            workout.date = calendar.date(byAdding: .day, value: 7, to: workout.date) ?? workout.date
        }
        plan.adaptationPromptedWeeks = plan.adaptationPromptedWeeks.map { $0 >= nextWindow ? $0 + 1 : $0 }
        if let raceDate = plan.raceDate {
            plan.raceDate = calendar.date(byAdding: .day, value: 7, to: raceDate)
        }

        let assignment = ScheduleGenerator(calendar: calendar).assign(
            workouts: weekTemplate.scheduledWorkouts.filter { $0.type != .race },
            windowStart: windowStart,
            weekdays: Set(plan.weekdays),
            longRunWeekday: plan.longRunWeekday)
        for item in assignment.assigned {
            let workout = ScheduledWorkout(date: item.date, templateWeek: templateWeek, templateWorkoutID: item.workout.id, isRepeat: true)
            workout.plan = plan
            context.insert(workout)
        }
        try? context.save()
    }

    // MARK: Reminders

    static func reminders(for plan: ActivePlan, template: PlanTemplate) -> [WorkoutReminder] {
        plan.sortedWorkouts
            .filter { $0.status == .upcoming }
            .compactMap { workout in
                guard let item = template.workout(id: workout.templateWorkoutID) else { return nil }
                return WorkoutReminder(
                    id: "\(template.id)-\(workout.templateWorkoutID)-\(Int(workout.date.timeIntervalSince1970))",
                    date: workout.date,
                    title: "Today: \(item.title)",
                    body: item.notes ?? "Your \(item.type.displayName.lowercased()) session is scheduled for today.")
            }
    }

    static func refreshReminders(plan: ActivePlan?, template: PlanTemplate?, profile: UserProfile, notifications: NotificationScheduling) async {
        guard profile.remindersEnabled, let plan, plan.status == .active, let template else {
            notifications.cancelAll()
            return
        }
        await notifications.scheduleReminders(reminders(for: plan, template: template), at: profile.reminderTime)
    }
}
