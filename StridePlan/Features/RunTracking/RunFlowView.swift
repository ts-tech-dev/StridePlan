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
    /// Finished treadmill run waiting for the user to confirm the machine's distance.
    @State private var treadmillToConfirm: RunSession?

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
                               isTreadmill: Binding(get: { session.isTreadmill }, set: { session.isTreadmill = $0 }),
                               onStart: { start(session) }, onCancel: { session.cancel(); dismiss() })
                case .countdown(let value):
                    CountdownView(value: value, step: session.currentStep)
                case .running, .paused:
                    RunningView(session: session, onEnd: { save in end(session, save: save) })
                case .finished:
                    ProgressView(treadmillToConfirm == nil ? "Saving…" : "")
                }
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: makeSession)
        .sheet(item: $treadmillToConfirm) { session in
            TreadmillDistanceSheet(estimate: session.distance, units: profile.units) { meters in
                session.correctTreadmillDistance(to: meters)
                treadmillToConfirm = nil
                save(session)
            }
            .interactiveDismissDisabled()
        }
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
            location: services.locationProvider(simulated: profile.simulateGPS), pedometer: services.pedometer,
            voice: services.voice,
            haptics: services.haptics, liveActivity: services.liveActivity)
    }

    private func start(_ session: RunSession) {
        if session.isTreadmill {
            session.begin()   // no GPS needed indoors
            return
        }
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
        if session.isTreadmill {
            treadmillToConfirm = session
        } else {
            self.save(session)
        }
    }

    private func save(_ session: RunSession) {
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

extension RunSession: Identifiable {}

/// Builds and enriches persisted runs.
@MainActor
enum RunRecorder {
    static func makeRecord(from session: RunSession) -> RunRecord {
        let start = session.startDate ?? .now
        let run = RunRecord(startDate: start, endDate: session.endDate ?? .now, distanceMeters: session.distance,
                            durationSeconds: session.movingTime, workoutTitle: session.title,
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
    @Binding var isTreadmill: Bool
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
                    Image(systemName: isTreadmill ? "figure.run.treadmill" : "figure.run")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(Theme.accent, in: Circle())
                        .accessibilityHidden(true)
                    Text(isTreadmill ? "Treadmill Run" : "Free Run").font(.largeTitle.bold())
                    Picker("Where", selection: $isTreadmill.animation(.snappy)) {
                        Label("Outdoor", systemImage: "sun.max").tag(false)
                        Label("Treadmill", systemImage: "figure.run.treadmill").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    Text(isTreadmill
                         ? "Distance and pace are estimated from your steps. When you finish, you can enter the distance shown on the treadmill."
                         : "No structure — just you and the road. We'll track distance, pace and splits.")
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

/// Lets the runner replace the step-based estimate with the treadmill's own distance reading.
private struct TreadmillDistanceSheet: View {
    let estimate: Double
    let units: UnitSystem
    let onSave: (Double) -> Void
    @State private var text: String

    init(estimate: Double, units: UnitSystem, onSave: @escaping (Double) -> Void) {
        self.estimate = estimate
        self.units = units
        self.onSave = onSave
        let value = estimate / units.metersPerUnit
        _text = State(initialValue: value > 0 ? String(format: "%.2f", value) : "")
    }

    private var enteredMeters: Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0, value < 200 else { return nil }
        return value * units.metersPerUnit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Distance", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.title2.monospacedDigit())
                        Text(units.distanceAbbreviation).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Treadmill distance")
                } footer: {
                    Text(estimate > 0
                         ? "Your steps suggest \(Formatters.distance(estimate, units: units, fractionDigits: 2)). Enter the treadmill's reading if it's different — splits and pace are adjusted to match."
                         : "Enter the distance shown on the treadmill.")
                }
            }
            .navigationTitle("How far did you run?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let enteredMeters { onSave(enteredMeters) }
                    }
                    .disabled(enteredMeters == nil)
                }
            }
        }
        .presentationDetents([.medium])
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
