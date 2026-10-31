import XCTest
@testable import StridePlan

final class RunMetricsTrackerTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fix `meters` north of the origin, `seconds` after `start`.
    func fix(meters: Double, seconds: Double, accuracy: Double = 5) -> LocationSample {
        LocationSample(latitude: 51.5 + meters / 111_195, longitude: -0.12, altitude: 10,
                       timestamp: start.addingTimeInterval(seconds), horizontalAccuracy: accuracy, speed: 3)
    }

    func run(_ tracker: inout RunMetricsTracker, metersPerSecond: Double, seconds: Int, from offset: Double = 0, startTime: Int = 0) {
        for s in startTime...(startTime + seconds) {
            let t = Double(s)
            tracker.ingest(fix(meters: offset + metersPerSecond * Double(s - startTime), seconds: t),
                           movingTime: t, isPaused: false, now: start.addingTimeInterval(t))
        }
    }

    func testDistanceAndPaceOnStraightLine() throws {
        var tracker = RunMetricsTracker(splitLength: 1000)
        run(&tracker, metersPerSecond: 3.333, seconds: 620) // 5:00/km
        XCTAssertEqual(tracker.distance, 2066, accuracy: 15)
        XCTAssertEqual(try XCTUnwrap(tracker.currentPace(movingTime: 620)), 300, accuracy: 5)
        XCTAssertEqual(tracker.splits.count, 2)
        XCTAssertEqual(tracker.splits[0].durationSeconds, 300, accuracy: 3)
    }

    func testRejectsInaccurateAndTeleportingFixes() {
        var tracker = RunMetricsTracker(splitLength: 1000)
        run(&tracker, metersPerSecond: 3, seconds: 60)
        let before = tracker.distance
        // Poor accuracy
        tracker.ingest(fix(meters: 500, seconds: 61, accuracy: 80), movingTime: 61, isPaused: false, now: start.addingTimeInterval(61))
        // 400 m in one second
        tracker.ingest(fix(meters: 580, seconds: 62), movingTime: 62, isPaused: false, now: start.addingTimeInterval(62))
        XCTAssertEqual(tracker.distance, before, accuracy: 0.001)
        XCTAssertEqual(tracker.rejectedCount, 2)
    }

    func testRejectsStaleAndOutOfOrderFixes() {
        var tracker = RunMetricsTracker(splitLength: 1000)
        run(&tracker, metersPerSecond: 3, seconds: 30)
        tracker.ingest(fix(meters: 60, seconds: 20), movingTime: 31, isPaused: false, now: start.addingTimeInterval(31))
        tracker.ingest(fix(meters: 100, seconds: 0), movingTime: 31, isPaused: false, now: start.addingTimeInterval(31))
        XCTAssertEqual(tracker.rejectedCount, 2)
    }

    func testMovementWhilePausedIsNotCounted() {
        var tracker = RunMetricsTracker(splitLength: 1000)
        run(&tracker, metersPerSecond: 3, seconds: 100)
        let atPause = tracker.distance
        for s in 101...160 {
            tracker.ingest(fix(meters: 300 + Double(s - 100) * 1.5, seconds: Double(s)), movingTime: 100, isPaused: true,
                           now: start.addingTimeInterval(Double(s)))
        }
        XCTAssertEqual(tracker.distance, atPause, accuracy: 0.001)
        // Resume from the new position: no jump.
        for i in 1...4 {
            tracker.ingest(fix(meters: 390 + Double(i) * 3, seconds: Double(160 + i)), movingTime: Double(100 + i), isPaused: false,
                           now: start.addingTimeInterval(Double(160 + i)))
        }
        XCTAssertEqual(tracker.distance, atPause + 12, accuracy: 4)
    }

    func testGPSDropoutBridgesGap() {
        var tracker = RunMetricsTracker(splitLength: 1000)
        run(&tracker, metersPerSecond: 3, seconds: 60)
        // No fixes for 20 s, then resume at the expected position.
        run(&tracker, metersPerSecond: 3, seconds: 60, from: 240, startTime: 80)
        XCTAssertEqual(tracker.distance, 420, accuracy: 10)
    }

    func testFinalPartialSplit() {
        var tracker = RunMetricsTracker(splitLength: 1609.344)
        run(&tracker, metersPerSecond: 4, seconds: 500) // 2 km
        tracker.finalizeSplits(movingTime: 500)
        XCTAssertEqual(tracker.splits.count, 2)
        XCTAssertEqual(tracker.splits[1].distanceMeters, 2000 - 1609.344, accuracy: 15)
    }
}
