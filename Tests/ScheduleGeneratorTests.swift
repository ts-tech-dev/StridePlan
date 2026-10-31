import XCTest
@testable import StridePlan

final class ScheduleGeneratorTests: XCTestCase {
    let calendar = TestSupport.calendar
    lazy var generator = ScheduleGenerator(calendar: calendar)

    // Calendar weekdays: 1 Sun, 2 Mon, 3 Tue, 4 Wed, 5 Thu, 6 Fri, 7 Sat
    let tueThuSatSun: Set<Int> = [3, 5, 7, 1]

    func testStartDateAnchorsWeekOne() {
        let start = TestSupport.date(2026, 11, 2) // Monday
        let schedule = generator.generate(template: TestSupport.simplePlan(weeks: 3),
                                          request: ScheduleRequest(anchor: .start(start), weekdays: tueThuSatSun, longRunWeekday: 1))
        XCTAssertEqual(schedule.startDate, start)
        XCTAssertEqual(schedule.endDate, TestSupport.date(2026, 11, 22))
        XCTAssertEqual(schedule.workouts.count, 12)
        for workout in schedule.workouts {
            XCTAssertEqual(generator.weekIndex(of: workout.date, planStart: start), workout.week)
        }
    }

    func testOnlySelectedWeekdaysAreUsed() {
        let schedule = generator.generate(template: TestSupport.simplePlan(weeks: 4),
                                          request: ScheduleRequest(anchor: .start(TestSupport.date(2026, 11, 4)), weekdays: tueThuSatSun, longRunWeekday: 1))
        for workout in schedule.workouts {
            XCTAssertTrue(tueThuSatSun.contains(calendar.component(.weekday, from: workout.date)))
        }
    }

    func testLongRunLandsOnChosenDay() {
        let schedule = generator.generate(template: TestSupport.simplePlan(weeks: 4),
                                          request: ScheduleRequest(anchor: .start(TestSupport.date(2026, 11, 4)), weekdays: [2, 4, 6, 7], longRunWeekday: 7))
        let longRuns = schedule.workouts.filter { $0.type == .long }
        XCTAssertEqual(longRuns.count, 4)
        XCTAssertTrue(longRuns.allSatisfy { calendar.component(.weekday, from: $0.date) == 7 })
    }

    func testLongRunDayIsAddedEvenIfNotSelected() {
        let schedule = generator.generate(template: TestSupport.simplePlan(weeks: 1),
                                          request: ScheduleRequest(anchor: .start(TestSupport.date(2026, 11, 2)), weekdays: [2, 4, 6], longRunWeekday: 1))
        XCTAssertEqual(schedule.workouts.count, 4)
        XCTAssertEqual(calendar.component(.weekday, from: schedule.workouts.first { $0.type == .long }!.date), 1)
    }

    func testRaceDateBackSchedulesPlan() {
        let race = TestSupport.date(2027, 4, 25) // Sunday
        let plan = TestSupport.simplePlan(weeks: 12, raceAtEnd: true)
        let schedule = generator.generate(template: plan,
                                          request: ScheduleRequest(anchor: .race(race), weekdays: tueThuSatSun, longRunWeekday: 7))
        XCTAssertEqual(schedule.endDate, race)
        XCTAssertEqual(calendar.dateComponents([.day], from: schedule.startDate, to: race).day, 12 * 7 - 1)
        let raceWorkout = schedule.workouts.first { $0.type == .race }
        XCTAssertEqual(raceWorkout?.date, race)
        XCTAssertEqual(raceWorkout?.week, 12)
        XCTAssertEqual(schedule.workouts.last?.workoutID, "race")
    }

    func testRaceOnUnselectedWeekdayStillLandsOnRaceDate() {
        let race = TestSupport.date(2027, 3, 20) // Saturday — not in [Mon, Wed, Fri, Sun]
        let schedule = generator.generate(template: TestSupport.simplePlan(weeks: 4, raceAtEnd: true),
                                          request: ScheduleRequest(anchor: .race(race), weekdays: [2, 4, 6, 1], longRunWeekday: 1))
        XCTAssertEqual(schedule.workouts.first { $0.type == .race }?.date, race)
        XCTAssertTrue(schedule.workouts.allSatisfy { $0.date <= race })
    }

    func testQualityIsNotAdjacentToLongRunWhenAvoidable() {
        // Mon, Tue, Wed, Thu, Sat available; long run Sat → tempo should not be Thu or Fri.
        let schedule = generator.generate(template: TestSupport.simplePlan(weeks: 1),
                                          request: ScheduleRequest(anchor: .start(TestSupport.date(2026, 11, 2)), weekdays: [2, 3, 4, 5, 7], longRunWeekday: 7))
        let tempo = schedule.workouts.first { $0.type == .tempo }!
        let long = schedule.workouts.first { $0.type == .long }!
        let gap = calendar.dateComponents([.day], from: tempo.date, to: long.date).day!
        XCTAssertGreaterThanOrEqual(abs(gap), 2)
    }

    func testDropsLowestPriorityWhenTooFewDays() {
        let plan = TestSupport.simplePlan(weeks: 1, workoutsPerWeek: [.easy, .tempo, .recovery, .long, .crossTrain])
        let schedule = generator.generate(template: plan,
                                          request: ScheduleRequest(anchor: .start(TestSupport.date(2026, 11, 2)), weekdays: [3, 5], longRunWeekday: 7))
        XCTAssertEqual(Set(schedule.workouts.map(\.type)), [.long, .tempo, .easy])
        XCTAssertEqual(Set(schedule.droppedWorkoutIDs), ["w1-2", "w1-4"])
    }

    func testOneWorkoutPerDay() {
        for plan in TestSupport.loadPlans() {
            let schedule = generator.generate(template: plan,
                                              request: ScheduleRequest(anchor: .start(TestSupport.date(2026, 11, 2)), weekdays: [2, 3, 4, 5, 6, 7, 1], longRunWeekday: 1))
            let days = schedule.workouts.map { calendar.startOfDay(for: $0.date) }
            XCTAssertEqual(days.count, Set(days).count, plan.id)
            XCTAssertTrue(schedule.droppedWorkoutIDs.isEmpty, "\(plan.id) dropped \(schedule.droppedWorkoutIDs)")
        }
    }

    func testEveryBundledRacePlanBackSchedulesOntoRaceDay() {
        let race = TestSupport.date(2027, 5, 2)
        for plan in TestSupport.loadPlans() where plan.raceWorkout != nil {
            let schedule = generator.generate(template: plan,
                                              request: ScheduleRequest(anchor: .race(race), weekdays: [3, 5, 7, 1], longRunWeekday: 1))
            XCTAssertEqual(schedule.workouts.last?.date, race, plan.id)
            XCTAssertEqual(schedule.workouts.last?.type, .race, plan.id)
        }
    }
}
