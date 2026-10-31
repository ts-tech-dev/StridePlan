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
}
