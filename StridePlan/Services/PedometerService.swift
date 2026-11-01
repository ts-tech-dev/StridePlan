import CoreMotion
import Foundation

/// Step-based distance for indoor (treadmill) runs, where GPS can't measure movement.
protocol PedometerProviding: AnyObject {
    var isAvailable: Bool { get }
    /// Starts updates. Each element is the cumulative distance in meters since `start()`.
    /// Each call returns a fresh stream and finishes any previous one.
    func start() -> AsyncStream<Double>
    func stop()
}

final class PedometerService: PedometerProviding {
    private let pedometer = CMPedometer()
    private var continuation: AsyncStream<Double>.Continuation?

    var isAvailable: Bool { CMPedometer.isDistanceAvailable() }

    func start() -> AsyncStream<Double> {
        stop()
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        guard isAvailable else {
            continuation.finish()
            return stream
        }
        pedometer.startUpdates(from: Date()) { data, _ in
            guard let meters = data?.distance?.doubleValue else { return }
            continuation.yield(meters)
        }
        return stream
    }

    func stop() {
        pedometer.stopUpdates()
        continuation?.finish()
        continuation = nil
    }
}

/// Previews, tests and the Simulator: walks forward at a steady jog so the UI has numbers to show.
final class MockPedometer: PedometerProviding {
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<Double>.Continuation?
    let metersPerSecond: Double

    init(metersPerSecond: Double = 2.8) {
        self.metersPerSecond = metersPerSecond
    }

    var isAvailable: Bool { true }

    func start() -> AsyncStream<Double> {
        stop()
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        let speed = metersPerSecond
        task = Task {
            var meters = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                meters += speed * 2
                continuation.yield(meters)
            }
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
