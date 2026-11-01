import Foundation

protocol PlanProviding {
    func allPlans() -> [PlanTemplate]
    func plan(id: String) -> PlanTemplate?
}

extension PlanProviding {
    /// Plans offered to new runners (retired plans excluded).
    func catalogPlans() -> [PlanTemplate] { allPlans().filter { !$0.isRetired } }

    /// The lengths a plan comes in (same goal and level), shortest first. A retired plan only offers itself.
    func lengthOptions(for plan: PlanTemplate) -> [PlanTemplate] {
        guard !plan.isRetired else { return [plan] }
        let options = catalogPlans().filter { $0.goal == plan.goal && $0.level == plan.level }
        return options.isEmpty ? [plan] : options.sorted { $0.weeks < $1.weeks }
    }
}

/// Loads plan templates from bundled `*.json` files. Drop a new file into `Resources/Plans` to add a plan.
final class PlanLoader: PlanProviding {
    enum LoadError: Error, CustomStringConvertible {
        case decoding(file: String, underlying: Error)

        var description: String {
            switch self {
            case .decoding(let file, let underlying): "Failed to decode \(file): \(underlying)"
            }
        }
    }

    private let plans: [PlanTemplate]
    private let byID: [String: PlanTemplate]

    init(bundle: Bundle = .main) {
        let urls = bundle.paths(forResourcesOfType: "json", inDirectory: nil).map { URL(fileURLWithPath: $0) }
        self.plans = Self.load(urls: urls).plans
        self.byID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(plans: [PlanTemplate]) {
        self.plans = plans
        self.byID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func allPlans() -> [PlanTemplate] { plans }

    func plan(id: String) -> PlanTemplate? { byID[id] }

    static func decode(_ data: Data) throws -> PlanTemplate {
        try JSONDecoder().decode(PlanTemplate.self, from: data)
    }

    /// Decodes every URL, collecting failures instead of crashing so one bad file can't break the catalog.
    static func load(urls: [URL]) -> (plans: [PlanTemplate], errors: [LoadError]) {
        var plans: [PlanTemplate] = []
        var errors: [LoadError] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                plans.append(try decode(Data(contentsOf: url)))
            } catch {
                errors.append(.decoding(file: url.lastPathComponent, underlying: error))
            }
        }
        for error in errors {
            print("[PlanLoader] \(error)")
        }
        return (plans.sorted(by: sortOrder), errors)
    }

    private static func sortOrder(_ a: PlanTemplate, _ b: PlanTemplate) -> Bool {
        let goals = PlanGoal.allCases
        let ga = goals.firstIndex(of: a.goal) ?? 0
        let gb = goals.firstIndex(of: b.goal) ?? 0
        if ga != gb { return ga < gb }
        if a.level != b.level { return a.level < b.level }
        return a.weeks < b.weeks
    }
}

/// Structural checks applied to every bundled plan (run in unit tests).
enum PlanValidator {
    static func problems(in plan: PlanTemplate) -> [String] {
        var issues: [String] = []
        let weekNumbers = plan.schedule.map(\.week)
        if weekNumbers != Array(1...max(plan.weeks, 1)) {
            issues.append("schedule weeks \(weekNumbers) don't match weeks=\(plan.weeks)")
        }

        var ids = Set<String>()
        for week in plan.schedule {
            for workout in week.workouts {
                if !ids.insert(workout.id).inserted { issues.append("duplicate workout id \(workout.id)") }
                if workout.type != .rest, workout.type != .crossTrain, workout.flatSteps.isEmpty {
                    issues.append("\(workout.id) has no executable steps")
                }
                if workout.type == .race, week.week != plan.weeks {
                    issues.append("\(workout.id) is a race outside the final week")
                }
            }
            let runs = week.scheduledWorkouts.filter { $0.type.isRun }.count
            if runs > plan.runsPerWeek.max || runs < max(plan.runsPerWeek.min - 1, 1) {
                issues.append("week \(week.week) has \(runs) runs, outside \(plan.runsPerWeek.displayText)")
            }
            if week.scheduledWorkouts.count > 7 {
                issues.append("week \(week.week) has more than 7 workouts")
            }
        }

        let covered = plan.phases.flatMap { Array($0.range) }.sorted()
        if covered != Array(1...max(plan.weeks, 1)) {
            issues.append("phases don't cover each week exactly once")
        }

        if plan.goal.isRaceGoal, plan.raceWorkout == nil {
            issues.append("race plan must end with a race workout")
        }
        return issues
    }
}
