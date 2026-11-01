import Foundation

/// Messages exchanged with the StridePlan Connect IQ watch app (source in `Garmin/`).
///
/// Connect IQ only carries plists of strings, numbers, booleans, arrays and dictionaries, so every message is a
/// dictionary with a `"t"` (type) key. Steps and chunks use positional arrays to keep messages small on the watch.
/// Foundation-only so it can be unit-tested without the Garmin SDK. See `Garmin/README.md` for the full format.
///
/// Phone → watch
///   `workouts`  replaces the watch's list of upcoming workouts
///   `ack`       the phone has saved run `id`; the watch can delete its copy
/// Watch → phone
///   `hello`     the watch app opened; the phone answers with `workouts`
///   `run`       summary of a recorded run, followed by `parts` × `chunk` (route and pace samples)
enum GarminProtocol {
    static let version = 1

    /// Route and pace-sample chunks hold this many points each (must match `CHUNK_POINTS` on the watch).
    static let chunkPoints = 60

    // MARK: Phone → watch

    struct OutgoingWorkout {
        /// Echoed back with the recorded run so it can be matched to the schedule (see `workoutID`).
        var id: String
        var date: Date
        var workout: WorkoutTemplate
    }

    /// Indices into each step array of a `workouts` message. Paces are seconds per km; 0 means no pace target.
    enum StepField: Int, CaseIterable {
        case kind, title, zoneKey, zoneName, durationType, durationValue, fastPace, slowPace
    }

    /// `cues` maps each zone used to its effort description, shown when a step has no pace target.
    static func workoutsMessage(_ workouts: [OutgoingWorkout], zones: PaceZones, units: UnitSystem,
                                calendar: Calendar = .current) -> [String: Any] {
        let usedZones = Set(workouts.flatMap { $0.workout.flatSteps.map(\.zone) })
        return [
            "t": "workouts",
            "v": version,
            "units": units.distanceAbbreviation,
            "cues": Dictionary(uniqueKeysWithValues: usedZones.map { ($0.rawValue, watchText($0.effortCue)) }),
            "list": workouts.map { payload(for: $0, zones: zones, calendar: calendar) },
        ]
    }

    static func payload(for item: OutgoingWorkout, zones: PaceZones, calendar: Calendar = .current) -> [String: Any] {
        let steps: [[Any]] = item.workout.flatSteps.map { step in
            let range = zones.range(for: step.zone)
            return [
                step.kind.rawValue,
                watchText(step.title),
                step.zone.rawValue,
                step.zone.displayName,
                step.duration.type == .time ? 0 : 1,
                step.duration.value,
                Int((range?.fast ?? 0).rounded()),
                Int((range?.slow ?? 0).rounded()),
            ]
        }
        return ["id": item.id, "day": dayNumber(item.date, calendar: calendar), "title": watchText(item.workout.title), "steps": steps]
    }

    /// Older watch fonts only cover Latin-1, so dashes and curly quotes become their ASCII forms.
    static func watchText(_ text: String) -> String {
        text.replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "’", with: "'")
    }

    static func ackMessage(runID: String) -> [String: Any] {
        ["t": "ack", "v": version, "id": runID]
    }

    /// The date as `yyyymmdd`, which the watch turns into "Today", "Tomorrow" or a weekday.
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// Stable identifier for a scheduled workout: its day, position in the day and template workout.
    static func workoutID(date: Date, orderInDay: Int, templateWorkoutID: String, calendar: Calendar = .current) -> String {
        "\(dayNumber(date, calendar: calendar))-\(orderInDay)-\(templateWorkoutID)"
    }

    // MARK: Watch → phone

    enum Incoming: Equatable {
        case hello(pendingRuns: Int)
        case runHeader(RunHeader)
        case chunk(Chunk)
    }

    struct RunHeader: Equatable {
        var id: String
        var workoutID: String?
        var title: String
        var start: Date
        var end: Date
        var distanceMeters: Double
        var movingSeconds: Double
        var averageHeartRate: Double?
        var steps: [StepTotal]
        var splits: [Split]
        var parts: Int
    }

    struct StepTotal: Equatable {
        var durationSeconds: Double
        var distanceMeters: Double
        var skipped: Bool
    }

    struct Chunk: Equatable {
        enum Kind: String { case route, samples }
        var runID: String
        var seq: Int
        var kind: Kind
        var data: [Double]
    }

    static func parse(_ message: Any) -> Incoming? {
        guard let dict = message as? [String: Any], let type = dict["t"] as? String else { return nil }
        switch type {
        case "hello":
            return .hello(pendingRuns: int(dict["pending"]) ?? 0)
        case "run":
            guard let id = dict["id"] as? String, !id.isEmpty,
                  let start = number(dict["start"]), let end = number(dict["end"]),
                  let distance = number(dict["dist"]), let time = number(dict["time"]) else { return nil }
            let steps = (dict["steps"] as? [Any] ?? []).compactMap { item -> StepTotal? in
                let values = numbers(item)
                guard values.count >= 3 else { return nil }
                return StepTotal(durationSeconds: values[0], distanceMeters: values[1], skipped: values[2] != 0)
            }
            let splits = (dict["splits"] as? [Any] ?? []).enumerated().compactMap { offset, item -> Split? in
                let values = numbers(item)
                guard values.count >= 2 else { return nil }
                return Split(index: offset + 1, distanceMeters: values[0], durationSeconds: values[1])
            }
            let heartRate = number(dict["hr"]).flatMap { $0 > 0 ? $0 : nil }
            let workoutID = (dict["wid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .runHeader(RunHeader(
                id: id, workoutID: workoutID, title: dict["title"] as? String ?? "Garmin Run",
                start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
                distanceMeters: distance, movingSeconds: time, averageHeartRate: heartRate,
                steps: steps, splits: splits, parts: int(dict["parts"]) ?? 0))
        case "chunk":
            guard let id = dict["id"] as? String, let seq = int(dict["seq"]),
                  let kind = (dict["kind"] as? String).flatMap(Chunk.Kind.init(rawValue:)) else { return nil }
            return .chunk(Chunk(runID: id, seq: seq, kind: kind, data: numbers(dict["data"])))
        default:
            return nil
        }
    }

    // MARK: Building app models

    /// Route chunks are flat `[lat, lon, altitude, secondsSinceStart, …]`.
    static func routePoints(_ flat: [Double], start: Date) -> [RoutePoint] {
        stride(from: 0, to: flat.count - flat.count % 4, by: 4).map { i in
            RoutePoint(latitude: flat[i], longitude: flat[i + 1], altitude: flat[i + 2],
                       timestamp: start.addingTimeInterval(flat[i + 3]), horizontalAccuracy: 5, speed: -1)
        }
    }

    /// Sample chunks are flat `[distanceMeters, movingSeconds, secondsPerKm, heartRate (0 = none), …]`.
    static func paceSamples(_ flat: [Double]) -> [PaceSample] {
        stride(from: 0, to: flat.count - flat.count % 4, by: 4).map { i in
            PaceSample(distanceMeters: flat[i], elapsedSeconds: flat[i + 1], paceSecondsPerKm: flat[i + 2],
                       heartRate: flat[i + 3] > 0 ? flat[i + 3] : nil)
        }
    }

    /// Pairs the watch's per-step totals with the planned steps. Steps the watch never reached count as skipped.
    static func stepResults(planned: [FlatStep], totals: [StepTotal], zones: PaceZones) -> [StepResult] {
        planned.map { step in
            let total = totals.indices.contains(step.index) ? totals[step.index] : StepTotal(durationSeconds: 0, distanceMeters: 0, skipped: true)
            return StepResult(index: step.index, title: step.title, kind: step.kind, zone: step.zone,
                              target: zones.range(for: step.zone), plannedDuration: step.duration,
                              durationSeconds: total.durationSeconds, distanceMeters: total.distanceMeters,
                              skipped: total.skipped)
        }
    }

    // MARK: Values

    /// Numbers arrive as `NSNumber` from the SDK and as Swift numerics in tests.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as Float: Double(value)
        case let value as Int64: Double(value)
        case let value as NSNumber: value.doubleValue
        default: nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        number(value).map { Int($0) }
    }

    static func numbers(_ value: Any?) -> [Double] {
        (value as? [Any] ?? []).compactMap { number($0) }
    }
}

/// A run recorded on the watch, assembled from its header and chunks.
struct GarminRun: Equatable {
    var header: GarminProtocol.RunHeader
    var route: [RoutePoint]
    var samples: [PaceSample]
}

/// Collects a run's messages, which can arrive out of order or repeat when the watch retries.
struct GarminRunAssembler {
    private var headers: [String: GarminProtocol.RunHeader] = [:]
    private var chunks: [String: [Int: GarminProtocol.Chunk]] = [:]

    /// Feeds one message. Returns the run once its header and every chunk have arrived.
    mutating func receive(_ message: GarminProtocol.Incoming) -> GarminRun? {
        let id: String
        switch message {
        case .hello:
            return nil
        case .runHeader(let header):
            id = header.id
            headers[id] = header
        case .chunk(let chunk):
            id = chunk.runID
            chunks[id, default: [:]][chunk.seq] = chunk
        }
        guard let header = headers[id] else { return nil }
        let received = chunks[id] ?? [:]
        guard (0..<header.parts).allSatisfy({ received[$0] != nil }) else { return nil }

        let ordered = (0..<header.parts).compactMap { received[$0] }
        let routeData = ordered.filter { $0.kind == .route }.flatMap(\.data)
        let sampleData = ordered.filter { $0.kind == .samples }.flatMap(\.data)
        headers[id] = nil
        chunks[id] = nil
        return GarminRun(header: header,
                         route: GarminProtocol.routePoints(routeData, start: header.start),
                         samples: GarminProtocol.paceSamples(sampleData))
    }
}
