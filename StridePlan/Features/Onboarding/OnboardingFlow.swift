import SwiftUI

struct OnboardingFlow: View {
    @Bindable var profile: UserProfile
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var context
    @State private var model = OnboardingModel()

    var body: some View {
        VStack(spacing: 0) {
            if model.step != .welcome {
                header
            }
            Group {
                switch model.step {
                case .welcome: WelcomePage()
                case .name: NamePage(name: $model.name)
                case .experience: ExperiencePage(level: $model.level)
                case .volume: VolumePage(weeklyKm: $model.weeklyKm, units: model.units)
                case .result: ResultPage(model: model)
                case .units: UnitsPage(units: $model.units)
                case .health: HealthPage(connected: $model.healthConnected, connect: connectHealth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(model.step)

            footer
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack {
            Button {
                withAnimation { model.back() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            ProgressView(value: model.progress)
                .tint(Theme.accent)
            Spacer().frame(width: 44)
        }
        .padding(.horizontal)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(model.step == .health ? "Get started" : (model.step == .welcome ? "Let's go" : "Continue")) {
                if model.step == .health {
                    finish()
                } else {
                    withAnimation { model.next() }
                }
            }
            .buttonStyle(.primary)
            .disabled(!model.canContinue)

            if model.step.isSkippable {
                Button("Skip") { withAnimation { model.skip() } }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            }
        }
        .padding()
    }

    private func connectHealth() {
        Task {
            do {
                try await services.health.requestAuthorization()
                model.healthConnected = true
            } catch {
                model.healthConnected = false
            }
        }
    }

    private func finish() {
        model.apply(to: profile)
        try? context.save()
    }
}

@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, name, experience, volume, result, units, health

        var isSkippable: Bool { self == .name || self == .result }
    }

    var step: Step = .welcome
    var name = ""
    var level: ExperienceLevel = .regular
    var weeklyKm: Double = 15
    var units: UnitSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial
    var hasResult = false
    var resultDistance: Double = 5_000
    var resultMinutes = 28
    var resultSeconds = 0
    var resultHours = 0
    var healthConnected = false

    var progress: Double { Double(step.rawValue) / Double(Step.allCases.count - 1) }

    var resultTime: Double { Double(resultHours * 3600 + resultMinutes * 60 + resultSeconds) }

    var canContinue: Bool {
        guard step == .result, hasResult else { return true }
        return PaceCalculator.vdot(distanceMeters: resultDistance, timeSeconds: resultTime) != nil
    }

    func next() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    func skip() {
        if step == .name { name = "" }
        if step == .result { hasResult = false }
        next()
    }

    func apply(to profile: UserProfile) {
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.level = level
        profile.units = units
        profile.weeklyVolumeMeters = weeklyKm * 1000
        profile.referenceResult = hasResult && canContinue
            ? RaceResult(distanceMeters: resultDistance, timeSeconds: resultTime, date: .now)
            : nil
        profile.healthKitEnabled = healthConnected
        profile.recalculateZones(activePlan: nil, template: nil)
        profile.hasCompletedOnboarding = true
    }
}

// MARK: - Pages

private struct PageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

private struct WelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(Theme.accentGradient)
                    .padding(.top, 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppBrand.name).font(.system(size: 44, weight: .heavy, design: .rounded))
                    Text(AppBrand.tagline).font(.title3).foregroundStyle(.secondary)
                }
                feature("list.bullet.clipboard", "Structured plans", "From Couch to 5K through the marathon, built on proven training principles.")
                feature("gauge.with.dots.needle.67percent", "Your paces", "Personal pace zones from a recent race, so every run has a clear target.")
                feature("waveform", "Coached in your ear", "Voice cues for every step, split and pace drift, even with the screen locked.")
            }
            .padding(24)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NamePage: View {
    @Binding var name: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "What should we call you?", subtitle: "Optional — used to personalise your daily plan.")
            TextField("First name", text: $name)
                .textContentType(.givenName)
                .font(.title2)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .focused($focused)
                .submitLabel(.continue)
        }
        .padding(24)
        .onAppear { focused = true }
    }
}

private struct ExperiencePage: View {
    @Binding var level: ExperienceLevel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(title: "Your running experience", subtitle: "We'll suggest plans that match where you are now.")
                ForEach(ExperienceLevel.allCases) { option in
                    Button {
                        level = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.displayName).font(.headline)
                                Text(option.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: level == option ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(level == option ? Theme.accent : .secondary)
                        }
                        .card()
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(level == option ? Theme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(level == option ? .isSelected : [])
                }
            }
            .padding(24)
        }
    }
}

private struct VolumePage: View {
    @Binding var weeklyKm: Double
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageTitle(title: "How much do you run?", subtitle: "Your typical weekly distance over the last month.")
            HStack(alignment: .firstTextBaseline) {
                Text(Formatters.distanceValue(weeklyKm * 1000, units: units, fractionDigits: 0))
                    .font(Theme.numeral(64))
                Text("\(units.distanceAbbreviation) / week")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Slider(value: $weeklyKm, in: 0...120, step: units == .metric ? 1 : 1.609344) {
                Text("Weekly distance")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("\(Int(120 / units.metersPerUnit * 1000))+")
            }
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var hint: String {
        switch weeklyKm {
        case ..<5: "Starting fresh? Couch to 5K is a great first plan."
        case ..<20: "A solid base for 5K and 10K plans."
        case ..<40: "Ready for half-marathon training."
        default: "Plenty of volume for marathon training."
        }
    }
}

private struct ResultPage: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(title: "A recent race or time trial?",
                          subtitle: "We use it to calculate your personal pace zones. No result? We'll coach by effort instead.")
                Toggle("I have a recent result", isOn: $model.hasResult.animation())
                    .font(.headline)
                    .card()
                if model.hasResult {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Distance", selection: $model.resultDistance) {
                            ForEach(RaceResult.commonDistances) { item in
                                Text(item.name).tag(item.meters)
                            }
                        }
                        .pickerStyle(.segmented)
                        DurationPicker(hours: $model.resultHours, minutes: $model.resultMinutes, seconds: $model.resultSeconds)
                        if let vdot = PaceCalculator.vdot(distanceMeters: model.resultDistance, timeSeconds: model.resultTime) {
                            let zones = PaceCalculator.zones(reference: RaceResult(distanceMeters: model.resultDistance, timeSeconds: model.resultTime, date: .now), level: model.level)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Fitness score \(Int(vdot.rounded()))").font(.headline)
                                if let easy = zones.range(for: .easy) {
                                    Text("Easy pace \(Formatters.paceRange(easy, units: model.units))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("That time looks unusual — please double-check it.")
                                .foregroundStyle(.red)
                        }
                    }
                    .card()
                }
            }
            .padding(24)
        }
    }
}

struct DurationPicker: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int

    var body: some View {
        HStack(spacing: 0) {
            wheel("h", selection: $hours, range: 0...9)
            wheel("min", selection: $minutes, range: 0...59)
            wheel("s", selection: $seconds, range: 0...59)
        }
        .frame(height: 140)
    }

    private func wheel(_ label: String, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach(Array(range), id: \.self) { value in
                Text("\(value) \(label)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

private struct UnitsPage: View {
    @Binding var units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Kilometers or miles?", subtitle: "You can change this anytime in Settings.")
            Picker("Units", selection: $units) {
                ForEach(UnitSystem.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
        }
        .padding(24)
    }
}

private struct HealthPage: View {
    @Binding var connected: Bool
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Connect Apple Health",
                      subtitle: "Optional. Save your runs as workouts with routes, and see your heart rate in run summaries.")
            Image(systemName: connected ? "heart.circle.fill" : "heart.circle")
                .font(.system(size: 80))
                .foregroundStyle(.pink)
                .frame(maxWidth: .infinity)
                .padding(.vertical)
                .accessibilityHidden(true)
            Button(connected ? "Connected" : "Connect Apple Health", action: connect)
                .buttonStyle(.secondary)
                .disabled(connected)
            Text("We'll ask for location access when you start your first run, and notification access when you start a plan.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

#Preview {
    OnboardingFlow(profile: UserProfile())
        .previewEnvironment()
}
