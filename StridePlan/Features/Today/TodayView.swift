import SwiftData
import SwiftUI

struct TodayView: View {
    let profile: UserProfile
    @Binding var selectedTab: AppTab
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var context
    @Environment(RunLauncher.self) private var launcher
    @Query(filter: #Predicate<ActivePlan> { $0.statusRaw == "active" }) private var activePlans: [ActivePlan]
    @State private var adaptationWeek: Int?

    private var plan: ActivePlan? { activePlans.first }
    private var template: PlanTemplate? { plan.flatMap { services.plans.plan(id: $0.planID) } }
    private var zones: PaceZones { profile.paceZones }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greeting
                    if let plan, let template {
                        todaySection(plan: plan, template: template)
                        weekProgress(plan: plan, template: template)
                        upNext(plan: plan, template: template)
                    } else {
                        noPlanCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationDestination(for: ScheduledWorkout.self) { workout in
                if let plan, let template {
                    WorkoutDetailView(scheduled: workout, plan: plan, template: template, profile: profile)
                }
            }
            .toolbar {
                Menu {
                    Button {
                        launcher.startRun(nil, scheduled: nil)
                    } label: {
                        Label("Free run", systemImage: "figure.run")
                    }
                    Button {
                        launcher.logManually(nil, scheduled: nil)
                    } label: {
                        Label("Log a run manually", systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .accessibilityLabel("Add run")
                }
            }
            .onAppear(perform: checkAdaptation)
            .sheet(item: Binding(get: { adaptationWeek.map { AdaptationPrompt(week: $0) } }, set: { adaptationWeek = $0?.week })) { prompt in
                if let plan, let template {
                    AdaptationSheet(week: prompt.week, plan: plan, template: template)
                        .presentationDetents([.medium])
                }
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(profile.name.isEmpty ? "Ready to run?" : "Hi, \(profile.name)")
                .font(.title.bold())
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func todaySection(plan: ActivePlan, template: PlanTemplate) -> some View {
        let today = plan.sortedWorkouts.filter { Calendar.current.isDateInToday($0.date) }
        if today.isEmpty {
            RestDayCard(next: plan.sortedWorkouts.first { $0.date > .now && $0.status == .upcoming }, template: template)
        } else {
            ForEach(today) { workout in
                if let item = template.workout(id: workout.templateWorkoutID) {
                    TodayWorkoutCard(scheduled: workout, workout: item, zones: zones, units: profile.units) {
                        launcher.startRun(item, scheduled: workout)
                    }
                }
            }
        }
    }

    private func weekProgress(plan: ActivePlan, template: PlanTemplate) -> some View {
        let weeks = PlanManager.weeks(for: plan, template: template, zones: zones)
        let currentIndex = PlanManager.currentWeekIndex(in: plan)
        let week = weeks.first { $0.index == currentIndex }
        return HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: week?.progress ?? 0, lineWidth: 12)
                VStack(spacing: 0) {
                    Text("\(week?.completedCount ?? 0)/\(week?.workouts.filter { $0.status != .skipped }.count ?? 0)")
                        .font(Theme.numeral(22))
                    Text("runs").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text("Week \(currentIndex) of \(weeks.last?.index ?? template.weeks)")
                    .font(.headline)
                if let phase = week?.phase, !phase.isEmpty {
                    Text("\(phase) phase")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
                if let week {
                    Text("\(Formatters.distance(week.completedDistance, units: profile.units, fractionDigits: 1)) of \(Formatters.distance(week.plannedDistance, units: profile.units, fractionDigits: 0))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func upNext(plan: ActivePlan, template: PlanTemplate) -> some View {
        let upcoming = plan.sortedWorkouts
            .filter { $0.status == .upcoming && !Calendar.current.isDateInToday($0.date) && $0.date > .now }
            .prefix(3)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Up next").font(.title3.bold())
                    Spacer()
                    Button("Full plan") { selectedTab = .plan }
                        .font(.subheadline)
                }
                ForEach(Array(upcoming)) { workout in
                    if let item = template.workout(id: workout.templateWorkoutID) {
                        NavigationLink(value: workout) {
                            ScheduledWorkoutRow(scheduled: workout, workout: item, zones: zones, units: profile.units)
                                .card(padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var noPlanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text("Choose a training plan").font(.title2.bold())
            Text("Pick a goal — from your first 5K to a marathon — and get a schedule built around your week.")
                .foregroundStyle(.secondary)
            Button("Browse plans") { selectedTab = .catalog }
                .buttonStyle(.primary)
            Button("Just go for a run") { launcher.startRun(nil, scheduled: nil) }
                .buttonStyle(.secondary)
        }
        .card(padding: 20)
    }

    private func checkAdaptation() {
        guard let plan else { return }
        PlanManager.refreshStatuses(plan)
        adaptationWeek = PlanManager.weekNeedingAdaptation(in: plan)
    }
}

private struct AdaptationPrompt: Identifiable {
    let week: Int
    var id: Int { week }
}

struct TodayWorkoutCard: View {
    let scheduled: ScheduledWorkout
    let workout: WorkoutTemplate
    let zones: PaceZones
    let units: UnitSystem
    let onStart: () -> Void

    var body: some View {
        let estimate = workout.estimate(zones: zones)
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: scheduled) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        WorkoutTypeIcon(type: workout.type, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.type.displayName.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(workout.type.color)
                            Text(workout.title).font(.title2.bold())
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    if workout.type.isRun {
                        StepStripView(steps: workout.flatSteps, zones: zones, height: 10)
                        HStack {
                            StatTile(title: "Distance", value: Formatters.distanceValue(estimate.distanceMeters, units: units, fractionDigits: 1), unit: units.distanceAbbreviation)
                            StatTile(title: "Time", value: Formatters.duration(estimate.durationSeconds, style: .compact), valueFont: Theme.numeral(24))
                        }
                    }
                    if let notes = workout.notes {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .buttonStyle(.plain)

            switch scheduled.status {
            case .completed:
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(WorkoutStatus.completed.color)
            case .skipped:
                Label("Skipped", systemImage: WorkoutStatus.skipped.symbolName)
                    .font(.headline)
                    .foregroundStyle(.orange)
            case .upcoming, .missed:
                if workout.type.isRun {
                    Button(action: onStart) {
                        Label("Start workout", systemImage: "play.fill")
                    }
                    .buttonStyle(.primary)
                } else {
                    Button("Mark as done") {
                        scheduled.status = .completed
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
        .card(padding: 20)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.cornerRadius, bottomLeadingRadius: Theme.cornerRadius)
                .fill(workout.type.color)
                .frame(width: 6)
                .accessibilityHidden(true)
        }
    }
}

struct RestDayCard: View {
    let next: ScheduledWorkout?
    let template: PlanTemplate

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 34))
                .foregroundStyle(ZonePalette.color(for: "recovery"))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Rest day").font(.title2.bold())
                Text("Recovery is when the fitness gains happen. Stretch, sleep well, stay hydrated.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let next, let item = template.workout(id: next.templateWorkoutID) {
                    Text("Next: \(item.title) · \(DateText.relativeDay(next.date))")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
            }
        }
        .card(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

struct ScheduledWorkoutRow: View {
    let scheduled: ScheduledWorkout
    let workout: WorkoutTemplate
    let zones: PaceZones
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            WorkoutTypeIcon(type: workout.type, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(DateText.relativeDay(scheduled.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(scheduled.status == .skipped)
                if workout.type.isRun {
                    Text(Formatters.distance(scheduled.run?.distanceMeters ?? workout.estimate(zones: zones).distanceMeters, units: units, fractionDigits: 1))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: scheduled.status.symbolName)
                .foregroundStyle(scheduled.status.color)
                .font(.title3)
                .accessibilityLabel(scheduled.status.label)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TodayView(profile: PreviewData.profile, selectedTab: .constant(.today))
        .previewEnvironment()
}
