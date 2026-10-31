import Charts
import SwiftData
import SwiftUI

struct ScheduleView: View {
    let profile: UserProfile
    @Binding var selectedTab: AppTab
    @Environment(\.services) private var services
    @Query(filter: #Predicate<ActivePlan> { $0.statusRaw == "active" }) private var activePlans: [ActivePlan]

    private var plan: ActivePlan? { activePlans.first }
    private var template: PlanTemplate? { plan.flatMap { services.plans.plan(id: $0.planID) } }

    var body: some View {
        NavigationStack {
            Group {
                if let plan, let template {
                    ScheduleList(plan: plan, template: template, profile: profile)
                } else {
                    EmptyStateView(symbol: "calendar.badge.plus", title: "No active plan",
                                   message: "Start a plan to see your schedule here.", actionTitle: "Browse plans") {
                        selectedTab = .catalog
                    }
                }
            }
            .navigationTitle(plan?.planTitle ?? "Plan")
            .navigationDestination(for: ScheduledWorkout.self) { workout in
                if let plan, let template {
                    WorkoutDetailView(scheduled: workout, plan: plan, template: template, profile: profile)
                }
            }
        }
    }
}

private struct ScheduleList: View {
    let plan: ActivePlan
    let template: PlanTemplate
    let profile: UserProfile

    private var weeks: [PlanWeekGroup] { PlanManager.weeks(for: plan, template: template, zones: profile.paceZones) }
    private var currentWeek: Int { PlanManager.currentWeekIndex(in: plan) }

    var body: some View {
        let groups = weeks
        ScrollViewReader { proxy in
            List {
                Section {
                    WeeklySummaryChart(weeks: groups, currentWeek: currentWeek, units: profile.units)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
                ForEach(groups) { week in
                    Section {
                        ForEach(week.workouts) { workout in
                            if let item = template.workout(id: workout.templateWorkoutID) {
                                NavigationLink(value: workout) {
                                    ScheduledWorkoutRow(scheduled: workout, workout: item, zones: profile.paceZones, units: profile.units)
                                }
                                .contextMenu { WorkoutActionsMenu(workout: workout, plan: plan, template: template) }
                                .swipeActions(edge: .trailing) {
                                    if workout.status == .upcoming || workout.status == .missed {
                                        Button("Skip") { PlanManager.skip(workout) }
                                            .tint(.orange)
                                    } else if workout.status == .skipped {
                                        Button("Restore") { PlanManager.restore(workout) }
                                            .tint(.blue)
                                    }
                                }
                            }
                        }
                    } header: {
                        WeekHeader(week: week, isCurrent: week.index == currentWeek, units: profile.units)
                    }
                    .id(week.index)
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                proxy.scrollTo(currentWeek, anchor: .top)
            }
        }
    }
}

private struct WeekHeader: View {
    let week: PlanWeekGroup
    let isCurrent: Bool
    let units: UnitSystem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Week \(week.index)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if isCurrent {
                        Text("NOW")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text("\(week.phase) · \(week.startDate.formatted(.dateTime.day().month())) – \(week.endDate.formatted(.dateTime.day().month()))")
                    .font(.caption)
            }
            Spacer()
            Text(Formatters.distance(week.plannedDistance, units: units, fractionDigits: 0))
                .font(.subheadline.monospacedDigit())
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Planned vs completed distance per week.
struct WeeklySummaryChart: View {
    let weeks: [PlanWeekGroup]
    let currentWeek: Int
    let units: UnitSystem

    private struct Entry: Identifiable {
        var week: Int
        var kind: String
        var value: Double
        var id: String { "\(week)-\(kind)" }
    }

    private var entries: [Entry] {
        weeks.flatMap { week in
            [Entry(week: week.index, kind: "Planned", value: week.plannedDistance / units.metersPerUnit),
             Entry(week: week.index, kind: "Completed", value: week.completedDistance / units.metersPerUnit)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weekly distance").font(.headline)
                Spacer()
                let done = weeks.reduce(0) { $0 + $1.completedDistance }
                Text("\(Formatters.distance(done, units: units, fractionDigits: 0)) total")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Chart(entries) { entry in
                BarMark(x: .value("Week", entry.week), y: .value(units.distanceAbbreviation, entry.value))
                    .foregroundStyle(by: .value("Kind", entry.kind))
                    .position(by: .value("Kind", entry.kind))
                    .cornerRadius(3)
                    .opacity(entry.week > currentWeek ? 0.5 : 1)
            }
            .chartForegroundStyleScale(domain: ["Planned", "Completed"], range: [Color(.systemGray4), Theme.accent])
            .chartXAxis {
                AxisMarks(values: .stride(by: weeks.count > 12 ? 2 : 1)) { _ in AxisValueLabel() }
            }
            .frame(height: 160)
            .accessibilityLabel("Planned versus completed distance by week")
        }
    }
}

/// Swap / move / skip actions for a scheduled workout (used in context menus and the detail screen).
struct WorkoutActionsMenu: View {
    let workout: ScheduledWorkout
    let plan: ActivePlan
    let template: PlanTemplate

    var body: some View {
        if workout.status != .completed {
            let days = PlanManager.daysInWeek(of: workout, plan: plan)
            Menu {
                ForEach(days, id: \.self) { day in
                    Button(day.formatted(.dateTime.weekday(.wide).day())) {
                        withAnimation { PlanManager.move(workout, to: day, in: plan) }
                    }
                    .disabled(Calendar.current.isDate(day, inSameDayAs: workout.date))
                }
            } label: {
                Label("Move to…", systemImage: "calendar")
            }

            let others = plan.workouts.filter { other in
                other !== workout && other.status != .completed
                    && days.contains(where: { day in Calendar.current.isDate(day, inSameDayAs: other.date) })
            }
            if !others.isEmpty {
                Menu {
                    ForEach(others) { other in
                        Button("\(template.workout(id: other.templateWorkoutID)?.title ?? "Workout") · \(other.date.formatted(.dateTime.weekday()))") {
                            withAnimation { PlanManager.swap(workout, other) }
                        }
                    }
                } label: {
                    Label("Swap with…", systemImage: "arrow.left.arrow.right")
                }
            }

            if workout.status == .skipped {
                Button { PlanManager.restore(workout) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            } else {
                Button(role: .destructive) { PlanManager.skip(workout) } label: { Label("Skip", systemImage: "forward") }
            }
        }
    }
}

#Preview {
    ScheduleView(profile: PreviewData.profile, selectedTab: .constant(.plan))
        .previewEnvironment()
}
