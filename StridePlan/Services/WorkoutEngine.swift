import Foundation

/// Walks a flat list of steps given cumulative moving time and distance.
/// Pure value type so it can be unit-tested without GPS.
struct WorkoutEngine {
    struct Progress: Equatable {
        var step: FlatStep
        var elapsed: Double
        var distance: Double
        /// Seconds or meters left in the step, depending on its duration type.
        var remaining: Double
        var fraction: Double
    }

    struct Completion: Equatable {
        var step: FlatStep
        var durationSeconds: Double
        var distanceMeters: Double
        var skipped: Bool
    }

    let steps: [FlatStep]
    private(set) var currentIndex = 0
    private(set) var stepStartTime: Double = 0
    private(set) var stepStartDistance: Double = 0

    init(steps: [FlatStep]) {
        self.steps = steps
    }

    var isOpenEnded: Bool { steps.isEmpty }
    var isFinished: Bool { !steps.isEmpty && currentIndex >= steps.count }
    var currentStep: FlatStep? { steps.indices.contains(currentIndex) ? steps[currentIndex] : nil }
    var nextStep: FlatStep? { steps.indices.contains(currentIndex + 1) ? steps[currentIndex + 1] : nil }

    func progress(movingTime: Double, distance: Double) -> Progress? {
        guard let step = currentStep else { return nil }
        let elapsed = movingTime - stepStartTime
        let covered = distance - stepStartDistance
        let done = step.duration.type == .time ? elapsed : covered
        let remaining = max(0, step.duration.value - done)
        return Progress(step: step, elapsed: elapsed, distance: covered, remaining: remaining,
                        fraction: min(1, max(0, done / step.duration.value)))
    }

    /// Advances through any steps whose target has been reached. Returns the steps that finished.
    mutating func update(movingTime: Double, distance: Double) -> [Completion] {
        var completed: [Completion] = []
        while let step = currentStep {
            let target = step.duration.value
            let endTime: Double
            let endDistance: Double
            switch step.duration.type {
            case .time:
                guard movingTime - stepStartTime >= target else { return completed }
                endTime = stepStartTime + target
                endDistance = distance
            case .distance:
                guard distance - stepStartDistance >= target else { return completed }
                endDistance = stepStartDistance + target
                endTime = movingTime
            }
            completed.append(Completion(step: step, durationSeconds: endTime - stepStartTime,
                                        distanceMeters: endDistance - stepStartDistance, skipped: false))
            stepStartTime = endTime
            stepStartDistance = endDistance
            currentIndex += 1
        }
        return completed
    }

    /// Ends the current step immediately.
    mutating func skip(movingTime: Double, distance: Double) -> Completion? {
        guard let step = currentStep else { return nil }
        let completion = Completion(step: step, durationSeconds: movingTime - stepStartTime,
                                    distanceMeters: distance - stepStartDistance, skipped: true)
        stepStartTime = movingTime
        stepStartDistance = distance
        currentIndex += 1
        return completion
    }
}
