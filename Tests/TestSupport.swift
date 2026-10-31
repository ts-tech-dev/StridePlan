import Foundation
@testable import StridePlan

enum TestSupport {
    /// Calendar pinned to UTC/Gregorian so date math is deterministic.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Plan JSON files, read from the source tree (the same files the app bundles).
    /// Falls back to the host app bundle if the sources aren't reachable.
    static func bundledPlanURLs() -> [URL] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("StridePlan/Resources/Plans")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let fromSource = files.filter { $0.pathExtension == "json" }
        if !fromSource.isEmpty { return fromSource }
        return Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil).map { URL(fileURLWithPath: $0) }
    }

    static func loadPlans() -> [PlanTemplate] {
        PlanLoader.load(urls: bundledPlanURLs()).plans
    }

    static func simplePlan(weeks: Int = 2, workoutsPerWeek: [WorkoutType] = [.easy, .tempo, .easy, .long], raceAtEnd: Bool = false) -> PlanTemplate {
        let schedule = (1...weeks).map { week -> PlanWeek in
            var workouts = workoutsPerWeek.enumerated().map { index, type in
                WorkoutTemplate(id: "w\(week)-\(index)", type: type, title: type.displayName,
                                isLongRun: type == .long,
                                steps: [WorkoutStep(kind: .run, duration: .distance(5000), zone: .easy)])
            }
            if raceAtEnd, week == weeks {
                workouts.removeLast()
                workouts.append(WorkoutTemplate(id: "race", type: .race, title: "Race",
                                                steps: [WorkoutStep(kind: .run, duration: .distance(10_000), zone: .race)]))
            }
            return PlanWeek(week: week, workouts: workouts)
        }
        return PlanTemplate(id: "test", title: "Test", goal: .tenK, level: .intermediate, weeks: weeks,
                            runsPerWeek: CountRange(min: 3, max: 4), description: "",
                            phases: [PlanPhase(name: "Base", weeks: [1, weeks])], schedule: schedule)
    }
}
