import Foundation
import Observation

/// Drives a guided run: GPS → metrics, metrics → step engine, events → voice, haptics and Live Activity.
@MainActor
@Observable
final class RunSession {
    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case running
        case paused
        case finished
    }

    enum GPSStatus {
        case searching, good, weak
    }

    // Inputs
    let workout: WorkoutTemplate?
    let zones: PaceZones
    let units: UnitSystem
    let voiceSettings: VoiceSettings

    // Published state
    private(set) var phase: Phase = .ready
    private(set) var distance: Double = 0
    private(set) var movingTime: Double = 0
    private(set) var currentPace: Double?
    private(set) var averagePace: Double?
    private(set) var stepProgress: WorkoutEngine.Progress?
    private(set) var stepResults: [StepResult] = []
    private(set) var gpsStatus: GPSStatus = .searching
    private(set) var lastSplit: Split?
    private(set) var startDate: Date?
    private(set) var endDate: Date?

    var currentStep: FlatStep? { engine.currentStep }
    var nextStep: FlatStep? { engine.nextStep }
    var isWorkoutComplete: Bool { engine.isFinished }
    var isOpenEnded: Bool { engine.isOpenEnded }
    var splits: [Split] { correctedSplits ?? tracker.splits }
    var route: [RoutePoint] { tracker.route }
    private(set) var paceSamples: [PaceSample] = []

    /// Indoor run: distance comes from the pedometer instead of GPS. Set before `begin()`.
    var isTreadmill = false

    var currentTarget: PaceRange? { currentStep.flatMap { zones.range(for: $0.zone) } }

    // Collaborators
    private let location: LocationProviding
    private let pedometer: PedometerProviding?
    private let voice: VoiceCoaching
    private let haptics: HapticsProviding
    private let liveActivity: RunActivityControlling

    private var engine: WorkoutEngine
    private var tracker: RunMetricsTracker
    private var accumulatedTime: Double = 0
    private var resumedAt: Date?
    private var tickTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var lastPedometerMeters: Double = 0
    /// (moving time, distance) after each treadmill update, used to rebuild splits if the distance is corrected.
    private var distanceCurve: [(time: Double, distance: Double)] = []
    private var lastPaceAlertTime: Double = -.infinity
    private var lastActivityUpdate: Date = .distantPast
    private var lastSampleTime: Double = -.infinity
    private var announcedComplete = false

    init(workout: WorkoutTemplate?, zones: PaceZones, units: UnitSystem, voiceSettings: VoiceSettings,
         location: LocationProviding, pedometer: PedometerProviding? = nil,
         voice: VoiceCoaching, haptics: HapticsProviding, liveActivity: RunActivityControlling) {
        self.workout = workout
        self.zones = zones
        self.units = units
        self.voiceSettings = voiceSettings
        self.location = location
        self.pedometer = pedometer
        self.voice = voice
        self.haptics = haptics
        self.liveActivity = liveActivity
        self.engine = WorkoutEngine(steps: workout?.flatSteps ?? [])
        self.tracker = RunMetricsTracker(splitLength: units.metersPerUnit)
    }

    // MARK: Lifecycle

    func requestLocation() async -> LocationAuthorization {
        await location.requestAuthorization()
    }

    /// Starts GPS immediately (so it can lock on during the countdown), then begins the run.
    func begin(countdown: Int = 3) {
        guard phase == .ready else { return }
        if isTreadmill {
            gpsStatus = .good
            startPedometerUpdates()
        } else {
            startLocationUpdates()
        }
        Task {
            for value in stride(from: countdown, through: 1, by: -1) {
                phase = .countdown(value)
                try? await Task.sleep(for: .seconds(1))
            }
            startRunning()
        }
    }

    private func startRunning() {
        let now = Date()
        startDate = now
        resumedAt = now
        phase = .running
        haptics.runStarted()
        if let step = engine.currentStep {
            sayAlways("Starting \(workout?.title ?? "your run"). \(describe(step))")
        } else {
            sayAlways("Run started.")
        }
        liveActivity.start(attributes: RunActivityAttributes(workoutTitle: title,
                                                             paceUnit: units.paceSuffix, distanceUnit: units.distanceAbbreviation),
                           state: activityState())
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func pause() {
        guard phase == .running else { return }
        accumulatedTime = currentMovingTime()
        resumedAt = nil
        phase = .paused
        haptics.stepChanged()
        sayAlways("Paused.")
        pushActivity(force: true)
    }

    func resume() {
        guard phase == .paused else { return }
        resumedAt = Date()
        phase = .running
        haptics.stepChanged()
        sayAlways("Resuming.")
        pushActivity(force: true)
    }

    func skipStep() {
        guard phase == .running || phase == .paused, let completion = engine.skip(movingTime: movingTime, distance: distance) else { return }
        record(completion)
        announceNextStep()
        pushActivity(force: true)
    }

    func finish() {
        guard phase != .finished else { return }
        if phase == .running { accumulatedTime = currentMovingTime() }
        movingTime = accumulatedTime
        resumedAt = nil
        endDate = Date()
        if startDate == nil { startDate = endDate }
        tickTask?.cancel()
        locationTask?.cancel()
        location.stop()
        pedometer?.stop()

        // Close the step in progress (counts unless barely started) and mark the rest as skipped.
        if let completion = engine.skip(movingTime: movingTime, distance: distance) {
            record(completion, skipped: completion.durationSeconds < 5)
        }
        while let completion = engine.skip(movingTime: movingTime, distance: distance) {
            record(completion)
        }
        tracker.finalizeSplits(movingTime: movingTime)
        phase = .finished
        haptics.runStopped()
        sayAlways("Run complete. \(Formatters.spokenDistance(distance, units: units)) in \(Formatters.spokenDuration(movingTime)).")
        liveActivity.end(activityState())
    }

    func cancel() {
        tickTask?.cancel()
        locationTask?.cancel()
        location.stop()
        pedometer?.stop()
        voice.stop()
        liveActivity.end(activityState())
        phase = .finished
    }

    /// Name used for the run when there is no planned workout.
    var title: String { workout?.title ?? (isTreadmill ? "Treadmill Run" : "Free Run") }

    var hasMeaningfulData: Bool { distance > 100 || movingTime > 60 }

    /// Replaces the step-estimated treadmill distance with the one shown on the machine, rescaling
    /// splits, pace samples and step distances to match. Only valid after `finish()`.
    func correctTreadmillDistance(to meters: Double) {
        guard isTreadmill, phase == .finished, meters > 0 else { return }
        let factor = distance > 0 ? meters / distance : 0
        if factor > 0 {
            correctedSplits = RunMetricsTracker.splits(
                fromCurve: distanceCurve.map { (time: $0.time, distance: $0.distance * factor) } + [(time: movingTime, distance: meters)],
                splitLength: units.metersPerUnit)
            paceSamples = paceSamples.map { sample in
                var copy = sample
                copy.distanceMeters *= factor
                copy.paceSecondsPerKm /= factor
                return copy
            }
            stepResults = stepResults.map { result in
                var copy = result
                copy.distanceMeters *= factor
                return copy
            }
        } else {
            // Nothing was measured: assume an even pace for the whole run.
            correctedSplits = RunMetricsTracker.splits(fromCurve: [(0, 0), (movingTime, meters)],
                                                       splitLength: units.metersPerUnit)
        }
        distance = meters
    }

    private var correctedSplits: [Split]?

    // MARK: Updates

    private func startPedometerUpdates() {
        guard let pedometer else { return }
        let stream = pedometer.start()
        lastPedometerMeters = 0
        locationTask = Task { [weak self] in
            for await meters in stream {
                self?.handlePedometer(meters)
            }
        }
    }

    private func handlePedometer(_ cumulative: Double) {
        let delta = max(0, cumulative - lastPedometerMeters)
        lastPedometerMeters = cumulative
        guard phase == .running, delta > 0 else { return }
        let time = currentMovingTime()
        let before = tracker.splits.count
        tracker.addDistance(delta, movingTime: time)
        distanceCurve.append((time, tracker.distance))
        for split in tracker.splits.dropFirst(before) {
            announce(split)
        }
        update(time: time)
    }

    private func startLocationUpdates() {
        let stream = location.start()
        locationTask = Task { [weak self] in
            for await sample in stream {
                self?.handle(sample)
            }
        }
    }

    private func handle(_ sample: LocationSample) {
        let isRunning = phase == .running
        let time = currentMovingTime()
        let before = tracker.splits.count
        tracker.ingest(sample, movingTime: time, isPaused: !isRunning)
        if tracker.lastFixDate == sample.timestamp {
            gpsStatus = sample.horizontalAccuracy <= 15 ? .good : .weak
        }
        guard isRunning else { return }
        distance = tracker.distance
        for split in tracker.splits.dropFirst(before) {
            announce(split)
        }
        update(time: time)
    }

    private func tick() {
        guard phase == .running else { return }
        if !isTreadmill, let last = tracker.lastFixDate, Date().timeIntervalSince(last) > 10 {
            gpsStatus = .weak
        }
        update(time: currentMovingTime())
    }

    private func update(time: Double) {
        movingTime = time
        distance = tracker.distance
        currentPace = tracker.currentPace(movingTime: time)
        averagePace = tracker.averagePace(movingTime: time)

        let completions = engine.update(movingTime: time, distance: distance)
        for completion in completions {
            record(completion)
        }
        if !completions.isEmpty {
            announceNextStep()
        }
        stepProgress = engine.progress(movingTime: time, distance: distance)

        if time - lastSampleTime >= 10, let currentPace {
            paceSamples.append(PaceSample(distanceMeters: distance, elapsedSeconds: time, paceSecondsPerKm: currentPace))
            lastSampleTime = time
        }
        checkPaceDrift(time: time)
        pushActivity(force: !completions.isEmpty)
    }

    private func currentMovingTime() -> Double {
        accumulatedTime + (resumedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func record(_ completion: WorkoutEngine.Completion, skipped: Bool? = nil) {
        let step = completion.step
        stepResults.append(StepResult(
            index: step.index, title: step.title, kind: step.kind, zone: step.zone,
            target: zones.range(for: step.zone), plannedDuration: step.duration,
            durationSeconds: completion.durationSeconds, distanceMeters: completion.distanceMeters,
            skipped: skipped ?? completion.skipped))
    }

    // MARK: Cues

    private func announceNextStep() {
        haptics.stepChanged()
        if let step = engine.currentStep {
            say(describe(step), category: \.stepChanges)
        } else if !announcedComplete, !engine.isOpenEnded {
            announcedComplete = true
            say("Workout complete! Great job. Keep moving to cool down, or end the run when you're ready.", category: \.stepChanges)
        }
    }

    private func announce(_ split: Split) {
        lastSplit = split
        var text = "\(units == .metric ? "Kilometer" : "Mile") \(split.index). Split \(Formatters.spokenPace(split.paceSecondsPerKm, units: units))."
        if let averagePace {
            text += " Average \(Formatters.spokenPace(averagePace, units: units))."
        }
        say(text, category: \.splits)
    }

    private func checkPaceDrift(time: Double) {
        guard voiceSettings.paceAlerts, let step = engine.currentStep, let target = currentTarget, let pace = currentPace,
              step.kind != .recover, step.kind != .walk,
              let progress = stepProgress, progress.elapsed > 30,
              time - lastPaceAlertTime > 60 else { return }
        switch target.compliance(for: pace, tolerance: voiceSettings.toleranceSeconds) {
        case .hit:
            return
        case .under:
            say("Pick it up a little. You're at \(Formatters.spokenPace(pace, units: units)). Target \(Formatters.spokenPace(target.slow, units: units)) or faster.", category: \.paceAlerts)
        case .over:
            say("Ease off. You're at \(Formatters.spokenPace(pace, units: units)). Target \(Formatters.spokenPace(target.fast, units: units)) or slower.", category: \.paceAlerts)
        }
        haptics.warning()
        lastPaceAlertTime = time
    }

    func describe(_ step: FlatStep) -> String {
        let amount: String = switch step.duration.type {
        case .time: Formatters.spokenDuration(step.duration.value)
        case .distance: Formatters.spokenDistance(step.duration.value, units: units)
        }
        var text = "\(step.title). \(amount) \(step.zone == .walk ? "walking" : step.zone.displayName.lowercased())."
        if let range = zones.range(for: step.zone), step.zone != .walk {
            text += " Target \(Formatters.spokenPace(range.fast, units: units)) to \(Formatters.spokenPace(range.slow, units: units))."
        } else if step.zone != .walk {
            text += " \(step.zone.effortCue.replacingOccurrences(of: "RPE", with: "effort"))."
        }
        return text
    }

    /// Speaks a cue if voice coaching and the cue's category are enabled.
    private func say(_ text: String, category: KeyPath<VoiceSettings, Bool>) {
        guard voiceSettings.enabled, voiceSettings[keyPath: category] else { return }
        voice.speak(text)
    }

    /// Speaks a lifecycle cue (start, pause, finish) whenever voice coaching is on.
    private func sayAlways(_ text: String) {
        guard voiceSettings.enabled else { return }
        voice.speak(text)
    }

    // MARK: Live Activity

    private func pushActivity(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastActivityUpdate) >= 5 else { return }
        lastActivityUpdate = now
        liveActivity.update(activityState())
    }

    func activityState() -> RunActivityAttributes.ContentState {
        let step = engine.currentStep
        let remaining: String = {
            guard let progress = stepProgress, let step else { return "" }
            return step.duration.type == .time
                ? Formatters.duration(progress.remaining)
                : Formatters.stepDistance((progress.remaining / 10).rounded() * 10, units: units)
        }()
        return RunActivityAttributes.ContentState(
            stepTitle: step?.title ?? (engine.isFinished ? "Workout complete" : "Free run"),
            zoneRaw: step?.zone.rawValue ?? "easy",
            targetPace: step.flatMap { zones.range(for: $0.zone) }.map { Formatters.paceRange($0, units: units) } ?? (step?.zone.effortCue ?? ""),
            currentPace: Formatters.pace(currentPace, units: units),
            distance: Formatters.distanceValue(distance, units: units),
            stepRemaining: remaining,
            timerStart: Date().addingTimeInterval(-movingTime),
            isPaused: phase == .paused,
            elapsedWhenPaused: Formatters.duration(movingTime))
    }
}
