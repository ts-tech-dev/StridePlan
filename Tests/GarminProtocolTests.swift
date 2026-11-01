import XCTest
@testable import StridePlan

final class GarminProtocolTests: XCTestCase {

    let intervals = WorkoutTemplate(id: "w3-2", type: .intervals, title: "6 × 400 m", steps: [
        WorkoutStep(kind: .warmup, duration: .time(600), zone: .easy),
        .repeated(2, [
            WorkoutStep(kind: .run, duration: .distance(400), zone: .interval),
            WorkoutStep(kind: .recover, duration: .time(90), zone: .recovery),
        ]),
        WorkoutStep(kind: .cooldown, duration: .time(600), zone: .easy),
    ])

    let zones = PaceZones(vdot: 45, ranges: [.easy: PaceRange(fast: 330, slow: 365), .interval: PaceRange(fast: 236, slow: 244.6)])

    // MARK: Phone → watch

    func testWorkoutsMessageFlattensStepsWithTargets() throws {
        let date = TestSupport.date(2026, 11, 3)
        let message = GarminProtocol.workoutsMessage(
            [.init(id: "abc", date: date, workout: intervals)], zones: zones, units: .imperial, calendar: TestSupport.calendar)

        XCTAssertEqual(message["t"] as? String, "workouts")
        XCTAssertEqual(message["units"] as? String, "mi")
        let cues = try XCTUnwrap(message["cues"] as? [String: String])
        XCTAssertEqual(Set(cues.keys), ["easy", "interval", "recovery"], "one effort cue per zone used")
        XCTAssertEqual(cues["recovery"], "Very easy jog · RPE 2-3", "en dashes become hyphens for watch fonts")
        let list = try XCTUnwrap(message["list"] as? [[String: Any]])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0]["id"] as? String, "abc")
        XCTAssertEqual(list[0]["day"] as? Int, 20261103)
        XCTAssertEqual(list[0]["title"] as? String, "6 × 400 m")

        let steps = try XCTUnwrap(list[0]["steps"] as? [[Any]])
        XCTAssertEqual(steps.count, 6, "repeats are expanded for the watch")
        XCTAssert(steps.allSatisfy { $0.count == GarminProtocol.StepField.allCases.count })

        let rep = steps[1]
        XCTAssertEqual(rep[GarminProtocol.StepField.kind.rawValue] as? String, "run")
        XCTAssertEqual(rep[GarminProtocol.StepField.title.rawValue] as? String, "Run 1/2")
        XCTAssertEqual(rep[GarminProtocol.StepField.zoneKey.rawValue] as? String, "interval")
        XCTAssertEqual(rep[GarminProtocol.StepField.zoneName.rawValue] as? String, "Interval")
        XCTAssertEqual(rep[GarminProtocol.StepField.durationType.rawValue] as? Int, 1)
        XCTAssertEqual(rep[GarminProtocol.StepField.durationValue.rawValue] as? Double, 400)
        XCTAssertEqual(rep[GarminProtocol.StepField.fastPace.rawValue] as? Int, 236)
        XCTAssertEqual(rep[GarminProtocol.StepField.slowPace.rawValue] as? Int, 245, "paces are rounded to whole seconds")

        let recover = steps[2]
        XCTAssertEqual(recover[GarminProtocol.StepField.durationType.rawValue] as? Int, 0)
        XCTAssertEqual(recover[GarminProtocol.StepField.fastPace.rawValue] as? Int, 0, "no pace range → 0 so the watch shows the effort cue")
    }

    func testWorkoutIDIsStablePerScheduledSlot() {
        let date = TestSupport.date(2026, 1, 9)
        let id = GarminProtocol.workoutID(date: date, orderInDay: 1, templateWorkoutID: "w2-0", calendar: TestSupport.calendar)
        XCTAssertEqual(id, "20260109-1-w2-0")
    }

    // MARK: Watch → phone

    func testParsesHello() {
        XCTAssertEqual(GarminProtocol.parse(["t": "hello", "v": 1, "pending": 2]), .hello(pendingRuns: 2))
        XCTAssertEqual(GarminProtocol.parse(["t": "hello"]), .hello(pendingRuns: 0))
    }

    func testRejectsMalformedMessages() {
        XCTAssertNil(GarminProtocol.parse("hello"))
        XCTAssertNil(GarminProtocol.parse(["t": "nope"]))
        XCTAssertNil(GarminProtocol.parse(["t": "run", "id": "x"]), "a run needs its times and distance")
        XCTAssertNil(GarminProtocol.parse(["t": "chunk", "id": "x", "seq": 0, "kind": "laps", "data": []]))
    }

    func testParsesRunHeaderWithMixedNumberTypes() throws {
        let message: [String: Any] = [
            "t": "run", "v": 1, "id": "g1", "wid": "", "title": "Easy",
            "start": 1_790_000_000, "end": 1_790_001_900.5, "dist": Float(5012.5), "time": 1800, "hr": 0,
            "steps": [[600, 1700.0, 0], [1200.5, 3312, 1]],
            "splits": [[1000, 355], [1000, 349.2]],
            "parts": 3,
        ]
        guard case .runHeader(let header) = try XCTUnwrap(GarminProtocol.parse(message)) else { return XCTFail() }
        XCTAssertEqual(header.id, "g1")
        XCTAssertNil(header.workoutID, "an empty workout id means a free run")
        XCTAssertNil(header.averageHeartRate, "0 means no heart rate")
        XCTAssertEqual(header.start, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(header.distanceMeters, 5012.5)
        XCTAssertEqual(header.movingSeconds, 1800)
        XCTAssertEqual(header.steps, [.init(durationSeconds: 600, distanceMeters: 1700, skipped: false),
                                      .init(durationSeconds: 1200.5, distanceMeters: 3312, skipped: true)])
        XCTAssertEqual(header.splits.map(\.index), [1, 2])
        XCTAssertEqual(header.splits[1].durationSeconds, 349.2, accuracy: 0.001)
        XCTAssertEqual(header.parts, 3)
    }

    func testAssemblesRunFromOutOfOrderAndRepeatedChunks() throws {
        var assembler = GarminRunAssembler()
        let start = 1_790_000_000.0
        let header: [String: Any] = ["t": "run", "id": "g2", "wid": "20261103-0-w3-2", "title": "Intervals",
                                     "start": start, "end": start + 2000, "dist": 6000, "time": 1990, "hr": 151,
                                     "steps": [], "splits": [], "parts": 3]
        let route0: [String: Any] = ["t": "chunk", "id": "g2", "seq": 0, "kind": "route",
                                     "data": [51.5, -0.12, 20, 0, 51.501, -0.121, 21, 10]]
        let route1: [String: Any] = ["t": "chunk", "id": "g2", "seq": 1, "kind": "route", "data": [51.502, -0.122, 22, 20]]
        let samples: [String: Any] = ["t": "chunk", "id": "g2", "seq": 2, "kind": "samples",
                                      "data": [30, 10, 333, 140, 60, 20, 330, 0]]

        func feed(_ message: [String: Any]) -> GarminRun? {
            assembler.receive(GarminProtocol.parse(message)!)
        }

        XCTAssertNil(feed(route1), "chunks before the header are held")
        XCTAssertNil(feed(header))
        XCTAssertNil(feed(samples))
        XCTAssertNil(feed(route1), "a repeated chunk doesn't complete the run")
        let run = try XCTUnwrap(feed(route0))

        XCTAssertEqual(run.header.workoutID, "20261103-0-w3-2")
        XCTAssertEqual(run.header.averageHeartRate, 151)
        XCTAssertEqual(run.route.map(\.latitude), [51.5, 51.501, 51.502], "route chunks are joined in sequence order")
        XCTAssertEqual(run.route[2].timestamp, Date(timeIntervalSince1970: start + 20))
        XCTAssertEqual(run.samples.count, 2)
        XCTAssertEqual(run.samples[0].heartRate, 140)
        XCTAssertNil(run.samples[1].heartRate)

        XCTAssertNil(feed(route0), "a completed run is forgotten, so a late duplicate doesn't produce it again")
    }

    func testRunWithoutChunksCompletesOnHeader() {
        var assembler = GarminRunAssembler()
        let header: [String: Any] = ["t": "run", "id": "g3", "start": 0, "end": 60, "dist": 0, "time": 60, "parts": 0]
        XCTAssertNotNil(assembler.receive(GarminProtocol.parse(header)!))
    }

    func testIncompleteFlatArraysDropTrailingValues() {
        XCTAssertEqual(GarminProtocol.routePoints([1, 2, 3, 4, 5, 6], start: .now).count, 1)
        XCTAssertEqual(GarminProtocol.paceSamples([1, 2, 3]).count, 0)
    }

    func testStepResultsPairPlannedStepsWithWatchTotals() {
        let planned = intervals.flatSteps
        let totals: [GarminProtocol.StepTotal] = [
            .init(durationSeconds: 600, distanceMeters: 1800, skipped: false),
            .init(durationSeconds: 95, distanceMeters: 400, skipped: false),
        ]
        let results = GarminProtocol.stepResults(planned: planned, totals: totals, zones: zones)
        XCTAssertEqual(results.count, planned.count)
        XCTAssertEqual(results[1].title, "Run 1/2")
        XCTAssertEqual(results[1].target, zones.range(for: .interval))
        XCTAssertEqual(results[1].compliance, .hit)
        XCTAssertFalse(results[0].skipped)
        XCTAssert(results[2...].allSatisfy(\.skipped), "steps the watch never reached are skipped")
    }
}
