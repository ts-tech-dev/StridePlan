import XCTest
@testable import StridePlan

/// Runs the bundled sample GPX through the parser, tracker and step engine — the same path the
/// Simulator uses when "Simulate GPS" is on.
final class GPXReplayTests: XCTestCase {

    func sampleURL() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("StridePlan/Resources/GPX/SampleRun.gpx")
        if FileManager.default.fileExists(atPath: source.path) { return source }
        return try XCTUnwrap(Bundle.main.url(forResource: "SampleRun", withExtension: "gpx"))
    }

    func testParsesSampleTrack() throws {
        let points = try XCTUnwrap(GPXParser.parse(contentsOf: sampleURL()))
        XCTAssertGreaterThan(points.count, 2000)
        XCTAssertNotNil(points.first?.time)
        XCTAssertTrue(points.contains { $0.accuracy > 25 }, "sample includes noisy fixes")
    }

    func testReplayProducesPlausibleRun() throws {
        let points = try XCTUnwrap(GPXParser.parse(contentsOf: sampleURL()))
        let start = try XCTUnwrap(points.first?.time)
        var tracker = RunMetricsTracker(splitLength: 1000)
        var engine = WorkoutEngine(steps: WorkoutStep.flatten([
            WorkoutStep(kind: .warmup, duration: .time(600), zone: .easy),
            .repeated(6, [WorkoutStep(kind: .run, duration: .time(90), zone: .interval),
                          WorkoutStep(kind: .recover, duration: .time(90), zone: .recovery)]),
            WorkoutStep(kind: .cooldown, duration: .distance(1000), zone: .easy),
        ]))
        var completed = 0

        for point in points {
            let time = try XCTUnwrap(point.time)
            let elapsed = time.timeIntervalSince(start)
            let sample = LocationSample(latitude: point.latitude, longitude: point.longitude, altitude: point.elevation,
                                        timestamp: time, horizontalAccuracy: point.accuracy, speed: -1)
            tracker.ingest(sample, movingTime: elapsed, isPaused: false, now: time)
            completed += engine.update(movingTime: elapsed, distance: tracker.distance).count
        }

        XCTAssertEqual(tracker.distance, 6_200, accuracy: 300)
        XCTAssertGreaterThan(tracker.rejectedCount, 5)
        XCTAssertEqual(tracker.splits.count, 6)
        XCTAssertEqual(completed, 14, "warm-up, 12 interval/recovery steps and cool-down should all complete")
    }
}
