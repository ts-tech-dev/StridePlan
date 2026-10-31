import XCTest
@testable import StridePlan

final class WorkoutStepTests: XCTestCase {

    let intervals: [WorkoutStep] = [
        WorkoutStep(kind: .warmup, duration: .time(600), zone: .easy),
        .repeated(6, [
            WorkoutStep(kind: .run, duration: .distance(400), zone: .interval),
            WorkoutStep(kind: .recover, duration: .time(90), zone: .recovery),
        ]),
        WorkoutStep(kind: .cooldown, duration: .time(600), zone: .easy),
    ]

    func testRepeatsExpandIntoFlatList() {
        let flat = WorkoutStep.flatten(intervals)
        XCTAssertEqual(flat.count, 14)
        XCTAssertEqual(flat.first?.kind, .warmup)
        XCTAssertEqual(flat.last?.kind, .cooldown)
        XCTAssertEqual(flat.map(\.index), Array(0..<14))
        XCTAssertEqual(flat[1].zone, .interval)
        XCTAssertEqual(flat[1].repeatIndex, 1)
        XCTAssertEqual(flat[12].repeatIndex, 6)
        XCTAssertEqual(flat[12].repeatCount, 6)
        XCTAssertEqual(flat[11].title, "Run 6/6")
    }

    func testNestedRepeats() {
        let nested: [WorkoutStep] = [.repeated(2, [
            .repeated(3, [WorkoutStep(kind: .run, duration: .distance(200), zone: .repetition)]),
            WorkoutStep(kind: .recover, duration: .time(180)),
        ])]
        let flat = WorkoutStep.flatten(nested)
        XCTAssertEqual(flat.map(\.kind), [.run, .run, .run, .recover, .run, .run, .run, .recover])
        XCTAssertEqual(flat[3].zone, .recovery, "recover steps default to the recovery zone")
    }

    func testZeroCountAndEmptyStepsAreSkipped() {
        let steps: [WorkoutStep] = [.repeated(0, [WorkoutStep(kind: .run, duration: .time(60))]),
                                    WorkoutStep(kind: .run, duration: .time(0))]
        XCTAssertTrue(WorkoutStep.flatten(steps).isEmpty)
    }

    func testEstimateUsesZonePaces() {
        let zones = PaceZones(ranges: [.easy: PaceRange(fast: 350, slow: 370),
                                       .interval: PaceRange(fast: 270, slow: 290),
                                       .recovery: PaceRange(fast: 400, slow: 440)])
        let estimate = WorkoutStep.flatten(intervals).estimate(zones: zones)
        let expectedTime = 1200 + 6 * (0.4 * 280) + 6 * 90.0
        let expectedDistance = 1200 / 360.0 * 1000 + 2400 + 540 / 420.0 * 1000
        XCTAssertEqual(estimate.durationSeconds, expectedTime, accuracy: 0.1)
        XCTAssertEqual(estimate.distanceMeters, expectedDistance, accuracy: 0.1)
    }

    func testStructureSummary() {
        let workout = WorkoutTemplate(id: "x", type: .intervals, title: "6 × 400 m", steps: intervals)
        XCTAssertEqual(workout.structureSummary(units: .metric), "10 min easy · 6 × (400 m interval + 1:30 min jog) · 10 min easy")
    }

    // MARK: Engine

    func testEngineAdvancesThroughTimeAndDistanceSteps() {
        var engine = WorkoutEngine(steps: WorkoutStep.flatten(intervals))
        XCTAssertEqual(engine.currentStep?.kind, .warmup)
        XCTAssertTrue(engine.update(movingTime: 300, distance: 800).isEmpty)
        XCTAssertEqual(engine.progress(movingTime: 300, distance: 800)?.remaining, 300)

        let done = engine.update(movingTime: 601, distance: 1650)
        XCTAssertEqual(done.map(\.step.kind), [.warmup])
        XCTAssertEqual(engine.currentStep?.kind, .run)

        // 400 m rep, then 90 s recovery
        XCTAssertTrue(engine.update(movingTime: 650, distance: 1900).isEmpty)
        XCTAssertEqual(engine.progress(movingTime: 650, distance: 1900)!.remaining, 150, accuracy: 0.001)
        XCTAssertEqual(engine.update(movingTime: 690, distance: 2050).map(\.step.kind), [.run])
        XCTAssertEqual(engine.currentStep?.kind, .recover)
    }

    func testEngineSkipAndFinish() {
        var engine = WorkoutEngine(steps: WorkoutStep.flatten(intervals))
        for _ in 0..<14 {
            XCTAssertNotNil(engine.skip(movingTime: 10, distance: 10))
        }
        XCTAssertTrue(engine.isFinished)
        XCTAssertNil(engine.currentStep)
        XCTAssertNil(engine.skip(movingTime: 10, distance: 10))
    }

    func testOpenEndedEngineNeverFinishes() {
        var engine = WorkoutEngine(steps: [])
        XCTAssertTrue(engine.isOpenEnded)
        XCTAssertTrue(engine.update(movingTime: 10_000, distance: 50_000).isEmpty)
        XCTAssertFalse(engine.isFinished)
    }
}
