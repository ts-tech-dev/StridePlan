import XCTest
@testable import StridePlan

final class PlanCatalogTests: XCTestCase {

    func testEveryBundledPlanDecodes() {
        let urls = TestSupport.bundledPlanURLs()
        XCTAssertGreaterThanOrEqual(urls.count, 10)
        let result = PlanLoader.load(urls: urls)
        XCTAssertTrue(result.errors.isEmpty, result.errors.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(result.plans.count, urls.count)
    }

    func testEveryPlanPassesValidation() {
        for plan in TestSupport.loadPlans() {
            XCTAssertEqual(PlanValidator.problems(in: plan), [], plan.id)
        }
    }

    func testCatalogCoversEveryGoalAndLevel() {
        let plans = TestSupport.loadPlans()
        XCTAssertEqual(Set(plans.map(\.goal)), Set(PlanGoal.allCases))
        XCTAssertEqual(Set(plans.map(\.level)), Set(PlanLevel.allCases))
        XCTAssertEqual(Set(plans.map(\.id)).count, plans.count, "plan IDs must be unique")
    }

    func testPlanIDsMatchFileNames() {
        for url in TestSupport.bundledPlanURLs() {
            let plan = try? PlanLoader.decode(Data(contentsOf: url))
            XCTAssertEqual(plan?.id, url.deletingPathExtension().lastPathComponent)
        }
    }

    func testDecodesSchemaExample() throws {
        let json = """
        {
          "id": "example", "title": "Example", "goal": "halfMarathon", "level": "intermediate",
          "weeks": 1, "runsPerWeek": { "min": 2, "max": 2 }, "description": "d",
          "phases": [{ "name": "Base", "weeks": [1, 1] }],
          "schedule": [{ "week": 1, "workouts": [
            { "id": "w1-easy-1", "type": "easy", "title": "Easy Run",
              "steps": [{ "kind": "run", "duration": { "type": "distance", "value": 5000 }, "zone": "easy" }] },
            { "id": "w1-intervals", "type": "intervals", "title": "6 × 400 m",
              "steps": [
                { "kind": "warmup", "duration": { "type": "time", "value": 600 }, "zone": "easy" },
                { "kind": "repeat", "count": 6, "steps": [
                  { "kind": "run", "duration": { "type": "distance", "value": 400 }, "zone": "interval" },
                  { "kind": "recover", "duration": { "type": "time", "value": 90 }, "zone": "recovery" } ] },
                { "kind": "cooldown", "duration": { "type": "time", "value": 600 }, "zone": "easy" } ] },
            { "id": "w1-rest", "type": "rest", "title": "Rest" }
          ] }]
        }
        """
        let plan = try PlanLoader.decode(Data(json.utf8))
        XCTAssertEqual(plan.schedule[0].workouts.count, 3)
        XCTAssertEqual(plan.schedule[0].scheduledWorkouts.count, 2)
        XCTAssertFalse(plan.schedule[0].workouts[0].isLongRun)
        XCTAssertEqual(plan.workout(id: "w1-intervals")?.flatSteps.count, 14)
        XCTAssertEqual(plan.phase(forWeek: 1), "Base")
    }

    func testRacePlansEndWithTheirRaceDistance() {
        for plan in TestSupport.loadPlans() {
            guard let distance = plan.goal.raceDistanceMeters, let race = plan.raceWorkout else { continue }
            let raceStep = race.flatSteps.last
            XCTAssertEqual(raceStep?.duration.type, .distance, plan.id)
            XCTAssertEqual(raceStep?.duration.value ?? 0, distance, accuracy: 0.5, plan.id)
        }
    }
    func testEveryFamilyOffersSeveralLengths() {
        let loader = PlanLoader(plans: TestSupport.loadPlans())
        let current = loader.catalogPlans()
        XCTAssertGreaterThanOrEqual(current.count, 40)
        for goal in PlanGoal.allCases {
            for level in PlanLevel.allCases where goal != .couchTo5K || level == .beginner {
                let lengths = current.filter { $0.goal == goal && $0.level == level }.map(\.weeks).sorted()
                let expected = goal == .marathon ? (level == .beginner ? [16, 18] : [12, 16, 18]) : [8, 10, 12]
                XCTAssertEqual(lengths, expected, "\(goal) \(level)")
            }
        }
        for plan in current {
            XCTAssertEqual(loader.lengthOptions(for: plan).map(\.weeks), loader.lengthOptions(for: plan).map(\.weeks).sorted())
            XCTAssertNotNil(plan.fitNote, plan.id)
        }
    }

    func testRetiredPlansStayLoadableButHidden() {
        let loader = PlanLoader(plans: TestSupport.loadPlans())
        let retired = loader.allPlans().filter(\.isRetired)
        XCTAssertTrue(retired.contains { $0.id == "couch-to-5k-beginner-9w" })
        for plan in retired {
            XCTAssertNotNil(loader.plan(id: plan.id))
            XCTAssertFalse(loader.catalogPlans().contains(plan))
            XCTAssertEqual(loader.lengthOptions(for: plan), [plan])
        }
    }

    func testCouchTo5KStartsGently() {
        let zones = PaceZones.effortOnly(level: .new)
        for plan in TestSupport.loadPlans() where plan.goal == .couchTo5K && !plan.isRetired {
            for workout in plan.schedule[0].workouts {
                let running = workout.flatSteps.filter { $0.zone != .walk }.reduce(0) { $0 + $1.duration.value }
                XCTAssertLessThanOrEqual(running, 4 * 60, "\(plan.id) week 1 running time")
                XCTAssertLessThanOrEqual(workout.estimate(zones: zones).durationSeconds, 25 * 60, plan.id)
            }
        }
    }
}
