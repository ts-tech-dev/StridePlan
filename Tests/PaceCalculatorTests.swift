import XCTest
@testable import StridePlan

final class PaceCalculatorTests: XCTestCase {

    func testVDOTMatchesPublishedTables() throws {
        // Daniels' tables: 5K in 20:00 ≈ VDOT 49.8; 10K in 50:00 ≈ VDOT 40; marathon 3:00:00 ≈ VDOT 53.5
        XCTAssertEqual(try XCTUnwrap(PaceCalculator.vdot(distanceMeters: 5_000, timeSeconds: 20 * 60)), 49.8, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(PaceCalculator.vdot(distanceMeters: 10_000, timeSeconds: 50 * 60)), 40.0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(PaceCalculator.vdot(distanceMeters: 42_195, timeSeconds: 3 * 3600)), 53.5, accuracy: 0.6)
    }

    func testVDOTRejectsNonsense() {
        XCTAssertNil(PaceCalculator.vdot(distanceMeters: 100, timeSeconds: 10))
        XCTAssertNil(PaceCalculator.vdot(distanceMeters: 5_000, timeSeconds: 0))
        XCTAssertNil(PaceCalculator.vdot(distanceMeters: 5_000, timeSeconds: 7 * 60)) // faster than world record
    }

    func testVelocityInvertsOxygenCost() {
        for v in stride(from: 150.0, through: 400, by: 25) {
            let vo2 = PaceCalculator.oxygenCost(velocity: v)
            XCTAssertEqual(PaceCalculator.velocity(forOxygenCost: vo2), v, accuracy: 0.001)
        }
    }

    func testPredictedTimeRoundTrips() throws {
        let vdot = try XCTUnwrap(PaceCalculator.vdot(distanceMeters: 10_000, timeSeconds: 45 * 60))
        XCTAssertEqual(PaceCalculator.predictedTime(vdot: vdot, distanceMeters: 10_000), 45 * 60, accuracy: 1)
        // A 45:00 10K predicts roughly a 1:39–1:41 half.
        let half = PaceCalculator.predictedTime(vdot: vdot, distanceMeters: 21_097.5)
        XCTAssertEqual(half, 100 * 60, accuracy: 120)
    }

    func testRiegel() {
        let predicted = PaceCalculator.riegel(timeSeconds: 25 * 60, fromMeters: 5_000, toMeters: 10_000)
        XCTAssertEqual(predicted, 25 * 60 * pow(2, 1.06), accuracy: 0.001)
        XCTAssertEqual(predicted, 52 * 60 + 7, accuracy: 3)
    }

    func testZonesAreOrderedFromSlowToFast() {
        let zones = PaceCalculator.zones(
            reference: RaceResult(distanceMeters: 5_000, timeSeconds: 25 * 60, date: .now),
            raceDistanceMeters: 10_000, level: .regular)
        XCTAssertTrue(zones.isPaceBased)
        let order: [PaceZoneKind] = [.recovery, .easy, .steady, .tempo, .threshold, .interval, .repetition]
        let mids = order.compactMap { zones.range(for: $0)?.midpoint }
        XCTAssertEqual(mids.count, order.count)
        XCTAssertEqual(mids, mids.sorted(by: >), "each zone should be faster than the previous")
        for zone in order {
            let range = zones.range(for: zone)!
            XCTAssertLessThan(range.fast, range.slow)
        }
    }

    func testZonesFor25Minute5K() throws {
        // VDOT ≈ 38.3 → easy ≈ 6:10–6:50/km, threshold ≈ 5:10–5:20/km, interval ≈ 4:45/km.
        let zones = PaceCalculator.zones(
            reference: RaceResult(distanceMeters: 5_000, timeSeconds: 25 * 60, date: .now),
            level: .regular)
        let easy = try XCTUnwrap(zones.range(for: .easy))
        XCTAssertEqual(easy.midpoint, 390, accuracy: 25)
        let threshold = try XCTUnwrap(zones.range(for: .threshold))
        XCTAssertEqual(threshold.midpoint, 315, accuracy: 12)
        let interval = try XCTUnwrap(zones.range(for: .interval))
        XCTAssertEqual(interval.midpoint, 290, accuracy: 12)
    }

    func testGoalTimeSetsRacePace() throws {
        let zones = PaceCalculator.zones(reference: nil, goalTimeSeconds: 2 * 3600, raceDistanceMeters: 21_097.5, level: .regular)
        let race = try XCTUnwrap(zones.range(for: .race))
        XCTAssertEqual(race.midpoint, 7200 / 21.0975, accuracy: 0.5)
        XCTAssertNotNil(zones.vdot)
    }

    func testReferenceResultDrivesTrainingWhenBothGiven() throws {
        let reference = RaceResult(distanceMeters: 10_000, timeSeconds: 50 * 60, date: .now)
        let zones = PaceCalculator.zones(reference: reference, goalTimeSeconds: 100 * 60, raceDistanceMeters: 21_097.5, level: .regular)
        XCTAssertEqual(try XCTUnwrap(zones.vdot), PaceCalculator.vdot(distanceMeters: 10_000, timeSeconds: 3000)!, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(zones.range(for: .race)).midpoint, 6000 / 21.0975, accuracy: 0.5)
    }

    func testFallsBackToEffortZones() {
        let zones = PaceCalculator.zones(reference: nil, level: .new)
        XCTAssertFalse(zones.isPaceBased)
        XCTAssertNil(zones.range(for: .easy))
        XCTAssertEqual(zones.estimatedPace(for: .easy), PaceZoneKind.easy.defaultPace(for: .new))
    }

    func testCompliance() {
        let range = PaceRange(fast: 300, slow: 320)
        XCTAssertEqual(range.compliance(for: 310), .hit)
        XCTAssertEqual(range.compliance(for: 323), .hit) // inside tolerance
        XCTAssertEqual(range.compliance(for: 340), .under)
        XCTAssertEqual(range.compliance(for: 280), .over)
    }

    func testPaceFormattingInUnits() {
        XCTAssertEqual(Formatters.pace(300, units: .metric), "5:00")
        XCTAssertEqual(Formatters.pace(300, units: .imperial), "8:03")
        XCTAssertEqual(Formatters.pace(nil, units: .metric), "--:--")
        XCTAssertEqual(Formatters.parseDuration("28:00"), 1680)
        XCTAssertEqual(Formatters.parseDuration("1:45:30"), 6330)
        XCTAssertNil(Formatters.parseDuration("abc"))
    }
}
