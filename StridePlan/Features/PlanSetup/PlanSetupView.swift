import SwiftUI

@Observable
final class PlanSetupModel {
    enum Anchor: String, CaseIterable, Identifiable {
        case start = "Start date"
        case race = "Race date"
        var id: String { rawValue }
    }

    let plan: PlanTemplate
    var anchor: Anchor = .start
    var startDate: Date = Calendar.current.startOfDay(for: .now)
    var raceDate: Date
    var weekdays: Set<Int>
    var longRunWeekday = 1
    var useGoalTime = false
    var goalHours = 0
    var goalMinutes = 30
    var goalSeconds = 0

    init(plan: PlanTemplate) {
        self.plan = plan
        let calendar = Calendar.current
        let earliestRace = calendar.date(byAdding: .day, value: plan.weeks * 7 - 1, to: calendar.startOfDay(for: .now)) ?? .now
        // Default to the first Sunday on or after the earliest possible race day.
        let daysToSunday = (8 - calendar.component(.weekday, from: earliestRace)) % 7
        self.raceDate = calendar.date(byAdding: .day, value: daysToSunday, to: earliestRace) ?? earliestRace
        self.weekdays = Self.defaultWeekdays(count: plan.runsPerWeek.max)
        if let distance = plan.goal.raceDistanceMeters {
            let guess = PaceCalculator.riegel(timeSeconds: 30 * 60, fromMeters: 5_000, toMeters: distance)
            goalHours = Int(guess) / 3600
            goalMinutes = (Int(guess) % 3600) / 60
        }
    }

    static func defaultWeekdays(count: Int) -> Set<Int> {
        // Calendar weekdays: 1 Sun … 7 Sat. Long run on Sunday.
        switch count {
        case ...3: [3, 5, 1]
        case 4: [3, 5, 7, 1]
        case 5: [2, 3, 5, 7, 1]
        default: [2, 3, 4, 5, 7, 1]
        }
    }

    var supportsRaceDate: Bool { plan.raceWorkout != nil }
    var supportsGoalTime: Bool { plan.goal.isRaceGoal }

    var earliestRaceDate: Date {
        Calendar.current.date(byAdding: .day, value: plan.weeks * 7 - 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    var goalTimeSeconds: Double? {
        guard supportsGoalTime, useGoalTime else { return nil }
        let total = Double(goalHours * 3600 + goalMinutes * 60 + goalSeconds)
        return total > 0 ? total : nil
    }

    var isGoalTimeValid: Bool {
        guard let goalTimeSeconds, let distance = plan.goal.raceDistanceMeters else { return true }
        return PaceCalculator.vdot(distanceMeters: distance, timeSeconds: goalTimeSeconds) != nil
    }

    var request: ScheduleRequest {
        var days = weekdays
        days.insert(longRunWeekday)
        return ScheduleRequest(anchor: anchor == .race && supportsRaceDate ? .race(raceDate) : .start(startDate),
                               weekdays: days, longRunWeekday: longRunWeekday)
    }

    var preview: GeneratedSchedule {
        ScheduleGenerator().generate(template: plan, request: request)
    }

    var canContinue: Bool { !weekdays.isEmpty && isGoalTimeValid }

    func toggle(_ weekday: Int) {
        if weekdays.contains(weekday) {
            guard weekday != longRunWeekday else { return }
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
    }
}

struct PlanSetupView: View {
    let profile: UserProfile
    let existingPlan: ActivePlan?
    @State private var model: PlanSetupModel
    @Environment(\.dismiss) private var dismiss

    init(plan: PlanTemplate, profile: UserProfile, existingPlan: ActivePlan?) {
        self.profile = profile
        self.existingPlan = existingPlan
        _model = State(initialValue: PlanSetupModel(plan: plan))
    }

    var body: some View {
        NavigationStack {
            Form {
                whenSection
                daysSection
                if model.supportsGoalTime { goalSection }
            }
            .navigationTitle("Set up your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                NavigationLink("Review") {
                    PlanConfirmationView(model: model, profile: profile, existingPlan: existingPlan) { dismiss() }
                }
                .buttonStyle(.primary)
                .disabled(!model.canContinue)
                .padding()
                .background(.bar)
            }
        }
    }

    private var whenSection: some View {
        Section {
            if model.supportsRaceDate {
                Picker("Schedule by", selection: $model.anchor) {
                    ForEach(PlanSetupModel.Anchor.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if model.anchor == .race && model.supportsRaceDate {
                DatePicker("Race day", selection: $model.raceDate, in: model.earliestRaceDate..., displayedComponents: .date)
            } else {
                DatePicker("First day", selection: $model.startDate, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
            }
            LabeledContent("Plan runs", value: "\(model.preview.startDate.formatted(date: .abbreviated, time: .omitted)) – \(model.preview.endDate.formatted(date: .abbreviated, time: .omitted))")
        } header: {
            Text("When")
        } footer: {
            if model.anchor == .race && model.supportsRaceDate {
                Text("We'll count back \(model.plan.weeks) weeks so your race lands on the final day. Racing sooner? Pick a shorter plan.")
            }
        }
    }

    private var daysSection: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(DateText.orderedWeekdays, id: \.self) { weekday in
                    let selected = model.weekdays.contains(weekday)
                    Button {
                        model.toggle(weekday)
                    } label: {
                        Text(DateText.weekdayShort(weekday).prefix(2))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DateText.weekdayFull(weekday))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Picker("Long run day", selection: $model.longRunWeekday) {
                ForEach(DateText.orderedWeekdays.filter { model.weekdays.contains($0) }, id: \.self) { weekday in
                    Text(DateText.weekdayFull(weekday)).tag(weekday)
                }
            }
        } header: {
            Text("Run days")
        } footer: {
            let count = model.weekdays.count
            if count < model.plan.runsPerWeek.min {
                Text("This plan has \(model.plan.runsPerWeek.displayText) runs a week. With \(count) days some sessions will be left out — we keep the most important ones.")
                    .foregroundStyle(.orange)
            } else {
                Text("This plan has \(model.plan.runsPerWeek.displayText) runs a week. Hard sessions are spaced away from your long run.")
            }
        }
    }

    private var goalSection: some View {
        Section {
            Toggle("Set a goal time", isOn: $model.useGoalTime.animation())
            if model.useGoalTime {
                DurationPicker(hours: $model.goalHours, minutes: $model.goalMinutes, seconds: $model.goalSeconds)
                if !model.isGoalTimeValid {
                    Text("That goal looks out of range.").foregroundStyle(.red)
                }
            }
        } header: {
            Text("Goal")
        } footer: {
            if let predicted = predictedTime {
                Text("Based on your recent result you're on track for about \(Formatters.duration(predicted)). Race pace is set from your goal time.")
            } else {
                Text("Without a goal time or recent result, sessions are coached by effort.")
            }
        }
    }

    private var predictedTime: Double? {
        guard let reference = profile.referenceResult, let distance = model.plan.goal.raceDistanceMeters,
              let vdot = PaceCalculator.vdot(distanceMeters: reference.distanceMeters, timeSeconds: reference.timeSeconds) else { return nil }
        return PaceCalculator.predictedTime(vdot: vdot, distanceMeters: distance)
    }
}

#Preview {
    PlanSetupView(plan: PreviewData.template, profile: PreviewData.profile, existingPlan: nil)
        .previewEnvironment()
}
