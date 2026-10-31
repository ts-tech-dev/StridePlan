import Charts
import SwiftData
import SwiftUI

struct PlanDetailView: View {
    let plan: PlanTemplate
    let profile: UserProfile
    @Query(filter: #Predicate<ActivePlan> { $0.statusRaw == "active" }) private var activePlans: [ActivePlan]
    @State private var showingSetup = false

    private var zones: PaceZones { profile.paceZones }
    private var units: UnitSystem { profile.units }

    private struct WeekDistance: Identifiable {
        var week: Int
        var meters: Double
        var phase: String
        var id: Int { week }
    }

    private var weeklyDistances: [WeekDistance] {
        plan.schedule.map { week in
            let meters = week.scheduledWorkouts.reduce(0) { $0 + $1.estimate(zones: zones).distanceMeters }
            return WeekDistance(week: week.week, meters: meters, phase: plan.phase(forWeek: week.week))
        }
    }

    private static let phaseColors: [Color] = [
        ZonePalette.color(for: "easy"), ZonePalette.color(for: "steady"), ZonePalette.color(for: "threshold"),
        ZonePalette.color(for: "interval"), ZonePalette.color(for: "recovery"), ZonePalette.color(for: "repetition"),
    ]

    /// A representative mid-plan week for the preview card.
    private var sampleWeek: PlanWeek? {
        plan.week(max(1, plan.weeks / 2)) ?? plan.schedule.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stats
                mileageChart
                if let sampleWeek { sampleWeekCard(sampleWeek) }
                breakdown
            }
            .padding()
            .padding(.bottom, 80)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(activePlans.first?.planID == plan.id ? "Restart this plan" : "Start this plan") {
                showingSetup = true
            }
            .buttonStyle(.primary)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .sheet(isPresented: $showingSetup) {
            PlanSetupView(plan: plan, profile: profile, existingPlan: activePlans.first)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(plan.goal.displayName, systemImage: plan.goal.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(plan.title).font(.largeTitle.bold())
            Text(plan.description).foregroundStyle(.secondary)
        }
    }

    private var stats: some View {
        HStack {
            StatTile(title: "Weeks", value: "\(plan.weeks)")
            StatTile(title: "Runs / wk", value: plan.runsPerWeek.displayText)
            StatTile(title: "Peak week", value: Formatters.distanceValue(weeklyDistances.map(\.meters).max() ?? 0, units: units, fractionDigits: 0),
                     unit: units.distanceAbbreviation)
        }
        .card()
    }

    private var mileageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly distance").font(.headline)
            Chart(weeklyDistances) { item in
                BarMark(x: .value("Week", item.week),
                        y: .value("Distance", item.meters / units.metersPerUnit))
                    .foregroundStyle(by: .value("Phase", item.phase))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(domain: plan.phases.map(\.name),
                                       range: Array(Self.phaseColors.prefix(max(plan.phases.count, 1))))
            .chartYAxisLabel(units.distanceAbbreviation)
            .chartXAxis {
                AxisMarks(values: .stride(by: plan.weeks > 12 ? 2 : 1)) { _ in AxisValueLabel() }
            }
            .frame(height: 180)
            .accessibilityLabel("Weekly distance chart")
            .accessibilityValue("Peaks at \(Formatters.distance(weeklyDistances.map(\.meters).max() ?? 0, units: units, fractionDigits: 0))")
            Text("Estimated from your pace zones. Phases: \(plan.phases.map(\.name).joined(separator: " → "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func sampleWeekCard(_ week: PlanWeek) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sample week (week \(week.week))").font(.headline)
            ForEach(week.scheduledWorkouts) { workout in
                TemplateWorkoutRow(workout: workout, zones: zones, units: units)
            }
        }
        .card()
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week by week").font(.headline)
            ForEach(plan.schedule, id: \.week) { week in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(week.scheduledWorkouts) { workout in
                            TemplateWorkoutRow(workout: workout, zones: zones, units: units)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("Week \(week.week)").font(.subheadline.weight(.semibold))
                        Text(plan.phase(forWeek: week.week))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.distance(weeklyDistances.first { $0.week == week.week }?.meters ?? 0, units: units, fractionDigits: 0))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .tint(.primary)
                Divider()
            }
        }
        .card()
    }
}

struct TemplateWorkoutRow: View {
    let workout: WorkoutTemplate
    let zones: PaceZones
    let units: UnitSystem

    var body: some View {
        let estimate = workout.estimate(zones: zones)
        HStack(spacing: 12) {
            WorkoutTypeIcon(type: workout.type, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.title).font(.subheadline.weight(.semibold))
                if workout.type.isRun {
                    Text(workout.structureSummary(units: units))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    StepStripView(steps: workout.flatSteps, zones: zones, height: 5)
                }
            }
            Spacer(minLength: 4)
            if workout.type.isRun {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.distance(estimate.distanceMeters, units: units, fractionDigits: 1))
                    Text(Formatters.duration(estimate.durationSeconds, style: .compact))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        PlanDetailView(plan: PreviewData.template, profile: PreviewData.profile)
    }
    .previewEnvironment()
}
