import CoreLocation
import Foundation

enum LocationAuthorization {
    case notDetermined, denied, authorized
}

/// Anything that produces GPS fixes. Implemented by CoreLocation, a GPX replayer, and a static mock.
protocol LocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorization() async -> LocationAuthorization
    /// Starts updates. Each call returns a fresh stream and finishes any previous one.
    func start() -> AsyncStream<LocationSample>
    func stop()
}

extension LocationSample {
    init(_ location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                  altitude: location.altitude, timestamp: location.timestamp,
                  horizontalAccuracy: location.horizontalAccuracy, speed: location.speed)
    }

    var clLocation: CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: altitude,
                   horizontalAccuracy: horizontalAccuracy, verticalAccuracy: -1, course: -1, speed: speed, timestamp: timestamp)
    }
}

extension RoutePoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var clLocation: CLLocation {
        CLLocation(coordinate: coordinate, altitude: altitude, horizontalAccuracy: horizontalAccuracy,
                   verticalAccuracy: -1, course: -1, speed: speed, timestamp: timestamp)
    }
}

// MARK: - CoreLocation

final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<LocationSample>.Continuation?
    private var authorizationContinuation: CheckedContinuation<LocationAuthorization, Never>?
    private var backgroundSession: CLBackgroundActivitySession?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorization: LocationAuthorization { Self.map(manager.authorizationStatus) }

    func requestAuthorization() async -> LocationAuthorization {
        guard manager.authorizationStatus == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() -> AsyncStream<LocationSample> {
        stop()
        let (stream, continuation) = AsyncStream<LocationSample>.makeStream(bufferingPolicy: .bufferingNewest(50))
        self.continuation = continuation
        // Keeps updates flowing with the screen locked (requires the `location` background mode).
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        backgroundSession = CLBackgroundActivitySession()
        manager.startUpdatingLocation()
        return stream
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
        continuation?.finish()
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            continuation?.yield(LocationSample(location))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (e.g. kCLErrorLocationUnknown) are expected; the tracker copes with gaps.
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined, let pending = authorizationContinuation else { return }
        authorizationContinuation = nil
        pending.resume(returning: Self.map(manager.authorizationStatus))
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        default: .denied
        }
    }
}

// MARK: - GPX replay (Simulator / demo)

/// Replays a bundled GPX track in real time (or faster) with fresh timestamps.
final class GPXReplayLocationService: LocationProviding {
    private let points: [GPXPoint]
    private let speedMultiplier: Double
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<LocationSample>.Continuation?

    init(resource: String = "SampleRun", bundle: Bundle = .main, speedMultiplier: Double = 1) {
        let url = bundle.url(forResource: resource, withExtension: "gpx")
        self.points = url.flatMap { GPXParser.parse(contentsOf: $0) } ?? []
        self.speedMultiplier = max(speedMultiplier, 0.1)
    }

    var authorization: LocationAuthorization { .authorized }

    func requestAuthorization() async -> LocationAuthorization { .authorized }

    func start() -> AsyncStream<LocationSample> {
        stop()
        let (stream, continuation) = AsyncStream<LocationSample>.makeStream(bufferingPolicy: .bufferingNewest(50))
        self.continuation = continuation
        let points = points
        let multiplier = speedMultiplier
        task = Task {
            guard let first = points.first else { return }
            var previousTime = first.time ?? .distantPast
            for (index, point) in points.enumerated() {
                let gap = index == 0 ? 0 : max(0.2, (point.time ?? previousTime.addingTimeInterval(1)).timeIntervalSince(previousTime))
                previousTime = point.time ?? previousTime.addingTimeInterval(1)
                try? await Task.sleep(for: .seconds(gap / multiplier))
                if Task.isCancelled { return }
                continuation.yield(LocationSample(latitude: point.latitude, longitude: point.longitude,
                                                  altitude: point.elevation, timestamp: Date(),
                                                  horizontalAccuracy: point.accuracy, speed: -1))
            }
            continuation.finish()
        }
        return stream
    }

    func stop() {
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
    }
}

// MARK: - Static mock (previews / tests)

final class MockLocationService: LocationProviding {
    var authorization: LocationAuthorization = .authorized
    private var continuation: AsyncStream<LocationSample>.Continuation?

    func requestAuthorization() async -> LocationAuthorization { authorization }

    func start() -> AsyncStream<LocationSample> {
        let (stream, continuation) = AsyncStream<LocationSample>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
    }

    /// Pushes a fix to the active stream (for tests).
    func send(_ sample: LocationSample) {
        continuation?.yield(sample)
    }
}
