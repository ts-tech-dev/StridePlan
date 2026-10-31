import SwiftUI

struct WorkoutDetailView: View {
    let scheduled: ScheduledWorkout?
    let plan: ActivePlan?
    let workout: WorkoutTemplate
    let template: PlanTemplate?
    let profile: UserProfile
    @Environment(RunLauncher.self) private var launcher

    init(scheduled: ScheduledWorkout, plan: ActivePlan, template: PlanTemplate, profile: UserProfile) {
        self.scheduled = scheduled
        self.plan = plan
        self.template = template
        self.profile = profile
        self.workout = template.workout(id: scheduled.templateWorkoutID)
            ?? WorkoutTemplate(id: scheduled.templateWorkoutID, type: .easy, title: "Workout", steps: [])
    }

    private var zones: PaceZones { profile.paceZones }
    private var units: UnitSystem { profile.units }

    var body: some View {
        let estimate = workout.estimate(zones: zones)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if workout.type.isRun {
                    HStack {
                        StatTile(title: "Est. distance", value: Formatters.distanceValue(estimate.distanceMeters, units: units, fractionDigits: 1), unit: units.distanceAbbreviation)
                        StatTile(title: "Est. time", value: Formatters.duration(estimate.durationSeconds, style: .compact), valueFont: Theme.numeral(24))
                    }
                    .card()
                }
                if let notes = workout.notes {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Coach's note", systemImage: "quote.bubble")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                        Text(notes)
                    }
                    .card()
                }
                if !workout.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Structure").font(.headline)
                        StepStripView(steps: workout.flatSteps, zones: zones, height: 10)
                        ForEach(Array(workout.steps.enumerated()), id: \.offset) { _, step in
                            StepRow(step: step, zones: zones, units: units)
                        }
                    }
                    .card()
                }
                if !zones.isPaceBased && workout.type.isRun {
                    Label("Targets are effort-based. Add a recent race result in Settings for personal paces.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let run = scheduled?.run {
                    NavigationLink {
                        RunSummaryView(run: run, profile: profile, isNewRun: false)
                    } label: {
                        Label("View completed run", systemImage: "chart.xyaxis.line")
                    }
                    .buttonStyle(.secondary)
                }
            }
            .padding()
            .padding(.bottom, 100)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let scheduled, let plan, let template {
                Menu {
                    WorkoutActionsMenu(workout: scheduled, plan: plan, template: template)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Workout options")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if workout.type.isRun, scheduled?.status != .completed {
                VStack(spacing: 8) {
                    Button {
                        launcher.startRun(workout, scheduled: scheduled)
                    } label: {
                        Label("Start guided run", systemImage: "play.fill")
                    }
                    .buttonStyle(.primary)
                    Button("Log manually (treadmill / no GPS)") {
                        launcher.logManually(workout, scheduled: scheduled)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 36)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            WorkoutTypeIcon(type: workout.type, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.type.displayName.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(workout.type.color)
                Text(workout.title).font(.title2.bold())
                if let scheduled {
                    HStack(spacing: 6) {
                        Text(DateText.relativeDay(scheduled.date))
                        if let plan, let template {
                            Text("· Week \(PlanManager.weekIndex(of: scheduled.date, in: plan)) · \(template.phase(forWeek: scheduled.templateWeek))")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if scheduled.status != .upcoming {
                        Label(scheduled.status.label, systemImage: scheduled.status.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(scheduled.status.color)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Renders a template step; repeat blocks show their children indented.
private struct StepRow: View {
    let step: WorkoutStep
    let zones: PaceZones
    let units: UnitSystem

    var body: some View {
        if step.kind == .repeat {
            VStack(alignment: .leading, spacing: 8) {
                Label("Repeat \(step.count ?? 1)×", systemImage: "repeat")
                    .font(.subheadline.weight(.bold))
                ForEach(Array((step.steps ?? []).enumerated()), id: \.offset) { _, child in
                    StepRow(step: child, zones: zones, units: units)
                        .padding(.leading, 12)
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        } else {
            let zone = step.zone ?? step.kind.defaultZone
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(zone.color)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(step.kind.displayName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(step.duration.map(durationText) ?? "")
                            .font(.subheadline.monospacedDigit())
                    }
                    HStack(spacing: 6) {
                        ZoneBadge(zone: zone)
                        TargetText(zone: zone, zones: zones, units: units)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = step.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    private func durationText(_ duration: StepDuration) -> String {
        switch duration.type {
        case .time: Formatters.duration(duration.value, style: .compact)
        case .distance: Formatters.stepDistance(duration.value, units: units)
        }
    }
}

#Preview {
    NavigationStack {
        if let plan = PreviewData.plan, let workout = PreviewData.upcomingWorkout {
            WorkoutDetailView(scheduled: workout, plan: plan, template: PreviewData.template, profile: PreviewData.profile)
        }
    }
    .previewEnvironment()
}
