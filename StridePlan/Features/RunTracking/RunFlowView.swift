import SwiftData
import SwiftUI

/// Full-screen container: pre-run → countdown → live tracking → summary.
struct RunFlowView: View {
    let request: RunRequest
    let profile: UserProfile
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RunLauncher.self) private var launcher
    @State private var session: RunSession?
    @State private var savedRun: RunRecord?
    @State private var showingLocationDenied = false

    var body: some View {
        Group {
            if let savedRun {
                NavigationStack {
                    RunSummaryView(run: savedRun, profile: profile, isNewRun: true) {
                        dismiss()
                    }
                }
            } else if let session {
                switch session.phase {
                case .ready:
                    PreRunView(workout: request.template, session: session, zones: profile.paceZones, units: profile.units,
                               onStart: { start(session) }, onCancel: { session.cancel(); dismiss() })
                case .countdown(let value):
                    CountdownView(value: value, step: session.currentStep)
                case .running, .paused:
                    RunningView(session: session, onEnd: { save in end(session, save: save) })
                case .finished:
                    ProgressView("Saving…")
                }
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: makeSession)
        .alert("Location access needed", isPresented: $showingLocationDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Log manually instead") {
                dismiss()
                launcher.logManually(request.template, scheduled: request.scheduled)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(AppBrand.name) uses your location to measure distance and pace during runs. You can enable it in Settings, or log this run manually.")
        }
    }

    private func makeSession() {
        guard session == nil else { return }
        session = RunSession(
            workout: request.template, zones: profile.paceZones, units: profile.units, voiceSettings: profile.voiceSettings,
            location: services.locationProvider(simulated: profile.simulateGPS), voice: services.voice,
            haptics: services.haptics, liveActivity: services.liveActivity)
    }

    private func start(_ session: RunSession) {
        Task {
            // Location permission is requested in context, right as the first run starts.
            let status = await session.requestLocation()
            if status == .authorized {
                session.begin()
            } else {
                showingLocationDenied = true
            }
        }
    }

    private func end(_ session: RunSession, save: Bool) {
        session.finish()
        guard save, session.hasMeaningfulData else {
            dismiss()
            return
        }
        let run = RunRecorder.makeRecord(from: session)
        context.insert(run)
        if let scheduled = request.scheduled {
            PlanManager.complete(scheduled, with: run)
        }
        try? context.save()
        savedRun = run
        RunRecorder.syncHealth(run: run, profile: profile, health: services.health, context: context)
    }
}

/// Builds and enriches persisted runs.
@MainActor
enum RunRecorder {
    static func makeRecord(from session: RunSession) -> RunRecord {
        let start = session.startDate ?? .now
        let run = RunRecord(startDate: start, endDate: session.endDate ?? .now, distanceMeters: session.distance,
                            durationSeconds: session.movingTime, workoutTitle: session.workout?.title ?? "Free Run",
                            workoutType: session.workout?.type ?? .easy)
        run.splits = session.splits
        run.route = session.route
        run.stepResults = session.stepResults
        run.paceSamples = session.paceSamples
        return run
    }

    /// Saves to Apple Health (if enabled) and pulls average heart rate for the run window.
    /// Garmin runs are skipped: Garmin Connect writes those to Apple Health itself.
    static func syncHealth(run: RunRecord, profile: UserProfile, health: HealthServicing, context: ModelContext) {
        guard profile.healthKitEnabled, health.isAvailable, run.healthKitUUID == nil, !run.isFromGarmin else { return }
        let input = HealthRunInput(start: run.startDate, end: run.endDate, distanceMeters: run.distanceMeters,
                                   isIndoor: run.isManual || run.route.isEmpty,
                                   route: run.route.map(\.clLocation), title: run.workoutTitle)
        Task {
            do {
                run.healthKitUUID = try await health.saveRun(input)
            } catch {
                print("[Health] save failed: \(error)")
            }
            if run.averageHeartRate == nil {
                run.averageHeartRate = await health.averageHeartRate(from: run.startDate, to: run.endDate)
            }
            try? context.save()
        }
    }
}

// MARK: - Pre-run

private struct PreRunView: View {
    let workout: WorkoutTemplate?
    let session: RunSession
    let zones: PaceZones
    let units: UnitSystem
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                if let workout {
                    WorkoutTypeIcon(type: workout.type, size: 80)
                    Text(workout.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text(workout.structureSummary(units: units))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    StepStripView(steps: workout.flatSteps, zones: zones, height: 12)
                        .padding(.horizontal)
                } else {
                    WorkoutTypeIcon(type: .easy, size: 80)
                    Text("Free Run").font(.largeTitle.bold())
                    Text("No structure — just you and the road. We'll track distance, pace and splits.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Label("Lock your screen anytime — tracking and voice cues keep going.", systemImage: "lock.iphone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

private struct CountdownView: View {
    let value: Int
    let step: FlatStep?

    var body: some View {
        ZStack {
            (step?.zone.color ?? Theme.accent).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("\(value)")
                    .font(.system(size: 160, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: value)
                if let step {
                    Text("First up: \(step.title)").font(.title2.bold())
                }
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Starting in \(value)")
    }
}
