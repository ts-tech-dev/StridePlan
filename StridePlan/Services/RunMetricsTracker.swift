import Foundation

/// Platform-neutral GPS fix so filtering/distance logic can be unit-tested without CoreLocation.
struct LocationSample: Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    /// Meters per second, negative when unknown.
    var speed: Double

    /// Great-circle distance in meters (haversine).
    func distance(to other: LocationSample) -> Double {
        let r = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    var routePoint: RoutePoint {
        RoutePoint(latitude: latitude, longitude: longitude, altitude: altitude, timestamp: timestamp,
                   horizontalAccuracy: horizontalAccuracy, speed: speed)
    }
}

/// Turns a noisy stream of GPS fixes into distance, rolling pace, splits and a route.
///
/// - Drops fixes with poor accuracy, stale timestamps, or impossible speed jumps.
/// - Lightly smooths coordinates to reduce zig-zag distance inflation.
/// - Fixes received while paused move the anchor without adding distance.
struct RunMetricsTracker {
    var maxHorizontalAccuracy: Double = 25
    var maxSpeed: Double = 11            // m/s — faster than any human sustained pace
    var minSegment: Double = 3           // meters; shorter moves accumulate until they exceed this
    var smoothing: Double = 0.65         // weight of the newest fix
    var paceWindowSeconds: Double = 30

    let splitLength: Double

    private(set) var distance: Double = 0
    private(set) var route: [RoutePoint] = []
    private(set) var splits: [Split] = []
    private(set) var lastFixDate: Date?
    private(set) var rejectedCount = 0

    private var anchor: LocationSample?
    private var smoothed: LocationSample?
    private var paceWindow: [(time: Double, distance: Double)] = []
    private var splitStartTime: Double = 0
    private var splitStartDistance: Double = 0

    init(splitLength: Double) {
        self.splitLength = splitLength
    }

    /// Feeds a fix. Returns any splits completed by it.
    @discardableResult
    mutating func ingest(_ sample: LocationSample, movingTime: Double, isPaused: Bool, now: Date = Date()) -> [Split] {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= maxHorizontalAccuracy,
              now.timeIntervalSince(sample.timestamp) < 10 else {
            rejectedCount += 1
            return []
        }
        if let last = smoothed, sample.timestamp <= last.timestamp {
            rejectedCount += 1
            return []
        }

        let filtered = smooth(sample)
        lastFixDate = sample.timestamp

        guard let previous = anchor else {
            anchor = filtered
            smoothed = filtered
            route.append(filtered.routePoint)
            return []
        }

        let segment = previous.distance(to: filtered)
        let dt = filtered.timestamp.timeIntervalSince(previous.timestamp)
        if dt > 0, segment / dt > maxSpeed {
            rejectedCount += 1
            return []
        }
        smoothed = filtered

        if isPaused {
            anchor = filtered
            return []
        }
        guard segment >= minSegment else { return [] }

        anchor = filtered
        route.append(filtered.routePoint)
        return advance(by: segment, movingTime: movingTime)
    }

    /// Adds distance not coming from GPS (e.g. treadmill estimate). Keeps splits consistent.
    @discardableResult
    mutating func addDistance(_ meters: Double, movingTime: Double) -> [Split] {
        advance(by: meters, movingTime: movingTime)
    }

    /// Rebuilds splits from a (moving time, cumulative distance) curve by interpolating each boundary
    /// crossing. Used when a treadmill run's distance is corrected after the fact. Points must be in time order.
    static func splits(fromCurve curve: [(time: Double, distance: Double)], splitLength: Double) -> [Split] {
        var tracker = RunMetricsTracker(splitLength: splitLength)
        var lastTime = 0.0
        for point in curve where point.distance > tracker.distance || point.time > lastTime {
            tracker.advance(by: max(0, point.distance - tracker.distance), movingTime: point.time)
            lastTime = point.time
        }
        tracker.finalizeSplits(movingTime: lastTime)
        return tracker.splits
    }

    /// Rolling pace in seconds per kilometer over the last `paceWindowSeconds`.
    func currentPace(movingTime: Double) -> Double? {
        guard let first = paceWindow.first(where: { movingTime - $0.time <= paceWindowSeconds }) else { return nil }
        let dd = distance - first.distance
        let dt = movingTime - first.time
        guard dd > 10, dt > 5 else { return nil }
        return dt / dd * 1000
    }

    func averagePace(movingTime: Double) -> Double? {
        distance > 50 ? movingTime / distance * 1000 : nil
    }

    /// The split in progress (not yet complete).
    func partialSplit(movingTime: Double) -> Split {
        Split(index: splits.count + 1, distanceMeters: distance - splitStartDistance, durationSeconds: movingTime - splitStartTime)
    }

    /// Call when the run ends to record the final partial split.
    mutating func finalizeSplits(movingTime: Double) {
        let partial = partialSplit(movingTime: movingTime)
        if partial.distanceMeters > 50 { splits.append(partial) }
    }

    private mutating func smooth(_ sample: LocationSample) -> LocationSample {
        guard let last = smoothed else { return sample }
        var result = sample
        result.latitude = last.latitude + (sample.latitude - last.latitude) * smoothing
        result.longitude = last.longitude + (sample.longitude - last.longitude) * smoothing
        return result
    }

    @discardableResult
    private mutating func advance(by meters: Double, movingTime: Double) -> [Split] {
        let previousTime = paceWindow.last?.time ?? splitStartTime
        let previousDistance = distance
        distance += meters
        paceWindow.append((movingTime, distance))
        paceWindow.removeAll { movingTime - $0.time > paceWindowSeconds }

        var closed: [Split] = []
        while distance - splitStartDistance >= splitLength {
            // Interpolate the moment the split boundary was crossed between the last two samples.
            let boundary = splitStartDistance + splitLength
            let fraction = (boundary - previousDistance) / (distance - previousDistance)
            let crossing = max(splitStartTime, previousTime + (movingTime - previousTime) * min(max(fraction, 0), 1))
            let split = Split(index: splits.count + 1, distanceMeters: splitLength, durationSeconds: crossing - splitStartTime)
            splits.append(split)
            closed.append(split)
            splitStartTime = crossing
            splitStartDistance = boundary
        }
        return closed
    }
}
