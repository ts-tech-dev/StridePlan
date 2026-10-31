import SwiftUI

struct PlanConfirmationView: View {
    let model: PlanSetupModel
    let profile: UserProfile
    let existingPlan: ActivePlan?
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.services) private var services
    @State private var isStarting = false

    private var schedule: GeneratedSchedule { model.preview }

    /// Zones as they'll be after committing (goal time may change race pace).
    private var zones: PaceZones {
        PaceCalculator.zones(reference: profile.referenceResult, goalTimeSeconds: model.goalTimeSeconds,
                             raceDistanceMeters: model.plan.goal.raceDistanceMeters, level: profile.level)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Plan", value: model.plan.title)
                LabeledContent("Starts", value: schedule.startDate.formatted(date: .complete, time: .omitted))
                LabeledContent(model.anchor == .race ? "Race day" : "Ends", value: schedule.endDate.formatted(date: .complete, time: .omitted))
                LabeledContent("Workouts", value: "\(schedule.workouts.count)")
                if let goal = model.goalTimeSeconds {
                    LabeledContent("Goal time", value: Formatters.duration(goal))
                }
            } header: {
                Text("Summary")
            }

            if existingPlan != nil {
                Section {
                    Label("Starting this plan ends your current plan. Completed runs stay in your history.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            if !schedule.droppedWorkoutIDs.isEmpty {
                Section {
                    Label("\(schedule.droppedWorkoutIDs.count) lower-priority sessions don't fit your chosen days and were left out.",
                          systemImage: "info.circle")
                }
            }

            Section("Week 1") {
                ForEach(schedule.workouts.filter { $0.week == 1 }, id: \.self) { item in
                    if let workout = model.plan.workout(id: item.workoutID) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.date.formatted(.dateTime.weekday(.wide).day().month()))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TemplateWorkoutRow(workout: workout, zones: zones, units: profile.units)
                        }
                    }
                }
            }

            Section {
                PaceZonesList(zones: zones, units: profile.units)
            } header: {
                Text("Your pace zones")
            } footer: {
                Text(zones.isPaceBased
                     ? "Calculated from \(profile.referenceResult != nil ? "your recent result" : "your goal time"). Update them anytime by logging a new result."
                     : "Add a recent race result in Settings to get pace targets. Until then, follow the effort cues.")
            }
        }
        .navigationTitle("Review")
        .safeAreaInset(edge: .bottom) {
            Button {
                start()
            } label: {
                if isStarting { ProgressView().tint(.white) } else { Text("Start plan") }
            }
            .buttonStyle(.primary)
            .disabled(isStarting)
            .padding()
            .background(.bar)
        }
    }

    private func start() {
        isStarting = true
        let plan = PlanManager.startPlan(template: model.plan, request: model.request, goalTimeSeconds: model.goalTimeSeconds,
                                         profile: profile, context: context)
        Task {
            // Ask for notifications in context: right when the plan begins.
            if profile.remindersEnabled {
                _ = await services.notifications.requestAuthorization()
            }
            await PlanManager.refreshReminders(plan: plan, template: model.plan, profile: profile, notifications: services.notifications)
            onFinish()
        }
    }
}

struct PaceZonesList: View {
    let zones: PaceZones
    let units: UnitSystem
    var kinds: [PaceZoneKind] = [.recovery, .easy, .steady, .tempo, .threshold, .interval, .repetition, .race]

    var body: some View {
        ForEach(kinds.filter { $0 != .race || zones.range(for: .race) != nil }) { zone in
            HStack {
                Circle().fill(zone.color).frame(width: 10, height: 10)
                Text(zone.displayName)
                Spacer()
                TargetText(zone: zone, zones: zones, units: units)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    NavigationStack {
        PlanConfirmationView(model: PlanSetupModel(plan: PreviewData.template), profile: PreviewData.profile, existingPlan: nil) {}
    }
    .previewEnvironment()
}
