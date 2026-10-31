import SwiftUI

/// Offered when 2+ workouts in a week were missed.
struct AdaptationSheet: View {
    let week: Int
    let plan: ActivePlan
    let template: PlanTemplate
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Missed a few runs?").font(.title2.bold())
            Text("You missed some sessions in week \(week). Life happens! You can repeat that week to rebuild consistency, or carry on with the plan.")
                .foregroundStyle(.secondary)
            if plan.raceDate != nil {
                Label("Repeating moves your final race day back by one week.", systemImage: "calendar.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            Button("Repeat the week") {
                PlanManager.repeatWeek(week, in: plan, template: template, context: context)
                dismiss()
            }
            .buttonStyle(.primary)
            Button("Continue the plan") {
                PlanManager.dismissAdaptation(week: week, in: plan)
                dismiss()
            }
            .buttonStyle(.secondary)
        }
        .padding(24)
    }
}

#Preview {
    if let plan = PreviewData.plan {
        AdaptationSheet(week: 2, plan: plan, template: PreviewData.template)
            .previewEnvironment()
    }
}
