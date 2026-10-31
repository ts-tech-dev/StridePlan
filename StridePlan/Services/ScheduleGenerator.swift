import Foundation

/// How the plan is anchored on the calendar.
enum ScheduleAnchor: Hashable {
    /// Week 1 begins on this day.
    case start(Date)
    /// The plan is back-scheduled so its final day (the race) lands on this day.
    case race(Date)
}

struct ScheduleRequest: Hashable {
    var anchor: ScheduleAnchor
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int>
    var longRunWeekday: Int
}

struct GeneratedWorkout: Hashable {
    var date: Date
    var week: Int
    var workoutID: String
    var type: WorkoutType
}

struct GeneratedSchedule: Hashable {
    var startDate: Date
    var endDate: Date
    var workouts: [GeneratedWorkout]
    /// Template workouts that didn't fit into the runner's available days.
    var droppedWorkoutIDs: [String]
}

/// Maps a plan template onto real dates. Training weeks are rolling 7-day windows starting at the plan start date.
struct ScheduleGenerator {
    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func planStartDate(weeks: Int, anchor: ScheduleAnchor) -> Date {
        switch anchor {
        case .start(let date):
            return calendar.startOfDay(for: date)
        case .race(let raceDate):
            let race = calendar.startOfDay(for: raceDate)
            return calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: race) ?? race
        }
    }

    func generate(template: PlanTemplate, request: ScheduleRequest) -> GeneratedSchedule {
        let start = planStartDate(weeks: template.weeks, anchor: request.anchor)
        var weekdays = request.weekdays
        weekdays.insert(request.longRunWeekday)

        var generated: [GeneratedWorkout] = []
        var dropped: [String] = []

        for weekNumber in 1...max(template.weeks, 1) {
            guard let week = template.week(weekNumber) else { continue }
            let windowStart = calendar.date(byAdding: .day, value: (weekNumber - 1) * 7, to: start) ?? start
            var raceDay: Date?
            if case .race(let date) = request.anchor, weekNumber == template.weeks {
                raceDay = calendar.startOfDay(for: date)
            }
            let result = assign(
                workouts: week.scheduledWorkouts,
                windowStart: windowStart,
                weekdays: weekdays,
                longRunWeekday: request.longRunWeekday,
                raceDay: raceDay
            )
            generated += result.assigned.map {
                GeneratedWorkout(date: $0.date, week: weekNumber, workoutID: $0.workout.id, type: $0.workout.type)
            }
            dropped += result.dropped.map(\.id)
        }

        let end = calendar.date(byAdding: .day, value: template.weeks * 7 - 1, to: start) ?? start
        return GeneratedSchedule(startDate: start, endDate: end, workouts: generated.sorted { $0.date < $1.date }, droppedWorkoutIDs: dropped)
    }

    struct WeekAssignment {
        var assigned: [(workout: WorkoutTemplate, date: Date)]
        var dropped: [WorkoutTemplate]
    }

    /// Places one week's workouts into a 7-day window.
    /// Race → race day (or long-run day), long run → long-run day, quality sessions spread apart, easy runs fill the gaps.
    func assign(
        workouts: [WorkoutTemplate],
        windowStart: Date,
        weekdays: Set<Int>,
        longRunWeekday: Int,
        raceDay: Date? = nil
    ) -> WeekAssignment {
        let start = calendar.startOfDay(for: windowStart)
        let window = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        var available: [Int] = window.indices.filter { weekdays.contains(calendar.component(.weekday, from: window[$0])) }
        let raceIndex = raceDay.flatMap { day in window.firstIndex { calendar.isDate($0, inSameDayAs: day) } }
        if let raceIndex, !available.contains(raceIndex) {
            available.append(raceIndex)
            available.sort()
        }

        // Keep the highest-priority workouts if there are more workouts than days.
        var kept = workouts
        var dropped: [WorkoutTemplate] = []
        if kept.count > available.count {
            let ranked = kept.enumerated().sorted {
                $0.element.type.schedulingPriority != $1.element.type.schedulingPriority
                    ? $0.element.type.schedulingPriority > $1.element.type.schedulingPriority
                    : $0.offset < $1.offset
            }
            let keepOffsets = Set(ranked.prefix(available.count).map(\.offset))
            dropped = kept.enumerated().filter { !keepOffsets.contains($0.offset) }.map(\.element)
            kept = kept.enumerated().filter { keepOffsets.contains($0.offset) }.map(\.element)
        }

        var taken: [Int: WorkoutTemplate] = [:]
        var hard: [Int] = []
        let longRunIndex = window.indices.first { calendar.component(.weekday, from: window[$0]) == longRunWeekday }

        func free(_ index: Int?) -> Int? {
            guard let index, available.contains(index), taken[index] == nil else { return nil }
            return index
        }

        func spreadOut(from reference: [Int]) -> Int? {
            let candidates = available.filter { taken[$0] == nil }
            guard !reference.isEmpty else { return candidates.first }
            return candidates.max { a, b in
                let ga = reference.map { abs($0 - a) }.min() ?? 7
                let gb = reference.map { abs($0 - b) }.min() ?? 7
                return ga != gb ? ga < gb : a > b  // tie → earlier day wins
            }
        }

        var remaining = kept

        func place(_ predicate: (WorkoutTemplate) -> Bool, choose: () -> Int?, isHard: Bool) {
            while let i = remaining.firstIndex(where: predicate) {
                guard let day = choose() else { return }
                taken[day] = remaining.remove(at: i)
                if isHard { hard.append(day) }
            }
        }

        place({ $0.type == .race }, choose: { free(raceIndex) ?? free(longRunIndex) ?? available.last(where: { taken[$0] == nil }) }, isHard: true)
        place({ $0.isLongRun || $0.type == .long }, choose: { free(longRunIndex) ?? spreadOut(from: hard) }, isHard: true)
        place({ $0.type.isQuality }, choose: { spreadOut(from: hard) }, isHard: true)
        place({ _ in true }, choose: { spreadOut(from: Array(taken.keys)) }, isHard: false)
        dropped += remaining

        let assigned = taken.keys.sorted().map { (workout: taken[$0]!, date: window[$0]) }
        return WeekAssignment(assigned: assigned, dropped: dropped)
    }

    /// 1-based training week for `date` relative to `planStart`.
    func weekIndex(of date: Date, planStart: Date) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: planStart), to: calendar.startOfDay(for: date)).day ?? 0
        return days >= 0 ? days / 7 + 1 : 0
    }
}
