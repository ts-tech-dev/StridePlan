import SwiftUI

/// The big, glanceable in-run screen.
struct RunningView: View {
    let session: RunSession
    let onEnd: (_ save: Bool) -> Void
    @State private var confirmingEnd = false

    private var units: UnitSystem { session.units }
    private var zoneColor: Color { session.currentStep?.zone.color ?? Theme.accent }

    var body: some View {
        VStack(spacing: 0) {
            stepPanel
            metrics
            controls
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            if session.phase == .paused {
                Text("PAUSED")
                    .font(.headline.weight(.heavy))
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(.yellow, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 4)
            }
        }
        .confirmationDialog("End this run?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("Save run") { onEnd(true) }
            Button("Discard run", role: .destructive) { onEnd(false) }
            Button("Keep running", role: .cancel) {}
        } message: {
            if !session.isWorkoutComplete && !session.isOpenEnded {
                Text("You still have steps left. Remaining steps will be marked as skipped.")
            }
        }
        .statusBarHidden(false)
    }

    // MARK: Step panel

    private var stepPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                gpsBadge
                Spacer()
                if let step = session.currentStep {
                    Text(step.zone.displayName.uppercased())
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.25), in: Capsule())
                }
            }
            if let step = session.currentStep, let progress = session.stepProgress {
                Text(step.title)
                    .font(.title2.bold())
                Text(remainingText(progress))
                    .font(.system(size: 72, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Remaining in step: \(remainingText(progress))")
                ProgressView(value: progress.fraction)
                    .tint(.white)
                    .background(.white.opacity(0.3))
                    .accessibilityHidden(true)
                HStack {
                    Image(systemName: "target")
                    if let target = session.currentTarget {
                        Text(Formatters.paceRange(target, units: units)).monospacedDigit()
                    } else {
                        Text(step.zone.effortCue)
                    }
                    Spacer()
                    if let next = session.nextStep {
                        Text("Next: \(next.title)")
                            .lineLimit(1)
                    }
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Text(session.isWorkoutComplete ? "Workout complete 🎉" : (session.workout == nil ? "Free run" : "Get ready"))
                    .font(.title.bold())
                Text(session.isWorkoutComplete ? "Cool down and end the run when you're ready." : "Run at whatever pace feels right.")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(zoneColor.gradient)
        .animation(.easeInOut, value: session.currentStep?.index)
    }

    private var gpsBadge: some View {
        let (label, symbol): (String, String) = switch session.gpsStatus {
        case .searching: ("Searching GPS", "location.slash")
        case .good: ("GPS", "location.fill")
        case .weak: ("Weak GPS", "location")
        }
        return Label(label, systemImage: symbol)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.black.opacity(0.2), in: Capsule())
            .accessibilityLabel("GPS status: \(label)")
    }

    private func remainingText(_ progress: WorkoutEngine.Progress) -> String {
        switch progress.step.duration.type {
        case .time: Formatters.duration(progress.remaining)
        case .distance:
            progress.remaining >= 1000
                ? Formatters.distance(progress.remaining, units: units)
                : "\(Int(progress.remaining.rounded())) m"
        }
    }

    // MARK: Metrics

    private var paceColor: Color {
        guard let target = session.currentTarget, let pace = session.currentPace else { return .primary }
        switch target.compliance(for: pace, tolerance: session.voiceSettings.toleranceSeconds) {
        case .hit: return ZonePalette.color(for: "easy")
        case .under: return .orange
        case .over: return .red
        }
    }

    private var metrics: some View {
        VStack(spacing: 18) {
            VStack(spacing: 0) {
                Text("PACE \(units.paceSuffix.uppercased())")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(Formatters.pace(session.currentPace, units: units))
                    .font(.system(size: 88, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(paceColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("avg \(Formatters.pace(session.averagePace, units: units))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current pace \(Formatters.pace(session.currentPace, units: units)) \(units.paceSuffix)")

            HStack {
                bigStat("TIME", Formatters.duration(session.movingTime))
                Divider().frame(height: 50)
                bigStat(units.distanceAbbreviation.uppercased(), Formatters.distanceValue(session.distance, units: units))
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal)
        .frame(maxHeight: .infinity)
    }

    private func bigStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.numeral(44))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 28) {
            controlButton("Skip step", symbol: "forward.end.fill", size: 60) {
                session.skipStep()
            }
            .disabled(session.currentStep == nil)
            .opacity(session.currentStep == nil ? 0.3 : 1)

            if session.phase == .paused {
                controlButton("Resume", symbol: "play.fill", size: 88, filled: true) { session.resume() }
            } else {
                controlButton("Pause", symbol: "pause.fill", size: 88, filled: true) { session.pause() }
            }

            controlButton("End run", symbol: "stop.fill", size: 60) {
                confirmingEnd = true
            }
        }
        .padding(.bottom, 24)
        .padding(.top, 8)
        .sensoryFeedback(.impact, trigger: session.phase)
    }

    private func controlButton(_ label: String, symbol: String, size: CGFloat, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .frame(width: size, height: size)
                .foregroundStyle(filled ? .white : .primary)
                .background(filled ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color(.secondarySystemFill)), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview("Running") {
    let session = RunSession(workout: PreviewData.intervalWorkout, zones: PreviewData.profile.paceZones, units: .metric,
                             voiceSettings: PreviewData.profile.voiceSettings, location: MockLocationService(),
                             voice: MockVoiceCoach(), haptics: SilentHaptics(), liveActivity: MockLiveActivityService())
    return RunningView(session: session) { _ in }
        .previewEnvironment()
}
