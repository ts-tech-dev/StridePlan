import SwiftUI

struct CatalogFilter: Equatable {
    var goal: PlanGoal?
    var levels: Set<PlanLevel> = []
    var maxWeeks: Int = 20
    var runsPerWeek: ClosedRange<Int> = 2...6

    var isDefault: Bool { levels.isEmpty && maxWeeks == 20 && runsPerWeek == 2...6 }

    func matches(_ plan: PlanTemplate) -> Bool {
        (goal == nil || plan.goal == goal)
            && (levels.isEmpty || levels.contains(plan.level))
            && plan.weeks <= maxWeeks
            && plan.runsPerWeek.overlaps(runsPerWeek)
    }
}

struct CatalogView: View {
    let profile: UserProfile
    @Environment(\.services) private var services
    @State private var filter = CatalogFilter()
    @State private var showingFilters = false

    private var plans: [PlanTemplate] { services.plans.allPlans().filter(filter.matches) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    goalChips
                    if plans.isEmpty {
                        EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: "No matching plans",
                                       message: "Try widening your filters.", actionTitle: "Reset filters") {
                            filter = CatalogFilter()
                        }
                    }
                    ForEach(PlanGoal.allCases) { goal in
                        let group = plans.filter { $0.goal == goal }
                        if !group.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(goal.displayName, systemImage: goal.symbolName)
                                    .font(.title3.bold())
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group) { plan in
                                    NavigationLink(value: plan) {
                                        PlanCard(plan: plan, recommended: plan.level == profile.level.suggestedPlanLevel)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Training Plans")
            .navigationDestination(for: PlanTemplate.self) { plan in
                PlanDetailView(plan: plan, profile: profile)
            }
            .toolbar {
                Button {
                    showingFilters = true
                } label: {
                    Label("Filters", systemImage: filter.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(filter: $filter)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var goalChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: filter.goal == nil) { filter.goal = nil }
                ForEach(PlanGoal.allCases) { goal in
                    chip(goal.displayName, selected: filter.goal == goal) { filter.goal = goal }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? .white : .primary)
                .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PlanCard: View {
    let plan: PlanTemplate
    var recommended = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.headline)
                    Text(plan.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 12) {
                Label("\(plan.weeks) wks", systemImage: "calendar")
                Label("\(plan.runsPerWeek.displayText)/wk", systemImage: "figure.run")
                Text(plan.level.displayName)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(levelColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(levelColor)
                if recommended {
                    Label("For you", systemImage: "star.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows plan details")
    }

    private var levelColor: Color {
        switch plan.level {
        case .beginner: ZonePalette.color(for: "easy")
        case .intermediate: ZonePalette.color(for: "tempo")
        case .advanced: ZonePalette.color(for: "interval")
        }
    }
}

private struct FilterSheet: View {
    @Binding var filter: CatalogFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Level") {
                    ForEach(PlanLevel.allCases) { level in
                        Toggle(level.displayName, isOn: Binding(
                            get: { filter.levels.contains(level) },
                            set: { isOn in
                                if isOn { filter.levels.insert(level) } else { filter.levels.remove(level) }
                            }))
                    }
                }
                Section("Duration") {
                    Stepper("Up to \(filter.maxWeeks) weeks", value: $filter.maxWeeks, in: 4...20)
                }
                Section("Runs per week") {
                    Stepper("At least \(filter.runsPerWeek.lowerBound)", value: Binding(
                        get: { filter.runsPerWeek.lowerBound },
                        set: { filter.runsPerWeek = $0...max($0, filter.runsPerWeek.upperBound) }), in: 2...6)
                    Stepper("At most \(filter.runsPerWeek.upperBound)", value: Binding(
                        get: { filter.runsPerWeek.upperBound },
                        set: { filter.runsPerWeek = min($0, filter.runsPerWeek.lowerBound)...$0 }), in: 2...6)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter = CatalogFilter(goal: filter.goal) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CatalogView(profile: PreviewData.profile)
        .previewEnvironment()
}
