import SwiftData
import SwiftUI

/// Log a run without GPS (treadmill, forgot phone, etc.).
struct ManualRunView: View {
    let request: ManualLogRequest
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var distanceText = ""
    @State private var hours = 0
    @State private var minutes = 30
    @State private var seconds = 0
    @State private var rpe = 5
    @State private var notes = ""

    private var units: UnitSystem { profile.units }
    private var distanceMeters: Double? {
        Double(distanceText.replacingOccurrences(of: ",", with: ".")).map { $0 * units.metersPerUnit }
    }
    private var duration: Double { Double(hours * 3600 + minutes * 60 + seconds) }
    private var isValid: Bool { (distanceMeters ?? 0) > 0 && duration > 0 }

    var body: some View {
        NavigationStack {
            Form {
                if let template = request.template {
                    Section("Workout") {
                        Label(template.title, systemImage: template.type.symbolName)
                    }
                }
                Section {
                    DatePicker("Started", selection: $date, in: ...Date())
                    HStack {
                        Text("Distance")
                        Spacer()
                        TextField("0.0", text: $distanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text(units.distanceAbbreviation).foregroundStyle(.secondary)
                    }
                    DurationPicker(hours: $hours, minutes: $minutes, seconds: $seconds)
                    if let distanceMeters, distanceMeters > 0, duration > 0 {
                        LabeledContent("Average pace", value: Formatters.paceWithUnit(duration / distanceMeters * 1000, units: units))
                    }
                }
                Section("Effort") {
                    Stepper("RPE \(rpe) / 10", value: $rpe, in: 1...10)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Log a run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
            .onAppear {
                if let scheduled = request.scheduled, Calendar.current.isDateInToday(scheduled.date) == false, scheduled.date < .now {
                    date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: scheduled.date) ?? date
                }
                if let template = request.template {
                    let estimate = template.estimate(zones: profile.paceZones)
                    distanceText = Formatters.distanceValue(estimate.distanceMeters, units: units, fractionDigits: 1)
                    let total = Int(estimate.durationSeconds)
                    hours = total / 3600
                    minutes = (total % 3600) / 60
                }
            }
        }
    }

    private func save() {
        guard let distanceMeters else { return }
        let run = RunRecord(startDate: date, endDate: date.addingTimeInterval(duration), distanceMeters: distanceMeters,
                            durationSeconds: duration, workoutTitle: request.template?.title ?? "Manual Run",
                            workoutType: request.template?.type ?? .easy, isManual: true, notes: notes)
        run.rpe = rpe
        context.insert(run)
        if let scheduled = request.scheduled {
            PlanManager.complete(scheduled, with: run)
        }
        try? context.save()
        RunRecorder.syncHealth(run: run, profile: profile, health: services.health, context: context)
        dismiss()
    }
}

#Preview {
    ManualRunView(request: ManualLogRequest(template: PreviewData.intervalWorkout, scheduled: nil), profile: PreviewData.profile)
        .previewEnvironment()
}
