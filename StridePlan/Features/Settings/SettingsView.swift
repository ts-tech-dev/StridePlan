import SwiftData
import SwiftUI

struct SettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ActivePlan> { $0.statusRaw == "active" }) private var activePlans: [ActivePlan]
    @State private var showingResultSheet = false
    @State private var confirmingEnd = false
    @State private var confirmingRestart = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var garminNote: String?
    @State private var isSendingToWatch = false

    private var plan: ActivePlan? { activePlans.first }
    private var template: PlanTemplate? { plan.flatMap { services.plans.plan(id: $0.planID) } }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                zonesSection
                voiceSection
                remindersSection
                healthSection
                garminSection
                planSection
                dataSection
                developerSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingResultSheet) {
                RaceResultSheet(profile: profile, plan: plan, template: template)
            }
            .onChange(of: profile.units) { _, _ in try? context.save() }
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            TextField("Name", text: $profile.name)
                .textContentType(.givenName)
            Picker("Experience", selection: $profile.level) {
                ForEach(ExperienceLevel.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Units", selection: $profile.units) {
                ForEach(UnitSystem.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var zonesSection: some View {
        Section {
            PaceZonesList(zones: profile.paceZones, units: profile.units)
            Button(profile.referenceResult == nil ? "Add a race result" : "Log a new race or time trial") {
                showingResultSheet = true
            }
        } header: {
            Text("Pace zones")
        } footer: {
            if let result = profile.referenceResult {
                Text("Based on \(RaceResult.name(forDistance: result.distanceMeters)) in \(Formatters.duration(result.timeSeconds)) (\(result.date.formatted(date: .abbreviated, time: .omitted))). New results update every remaining workout.")
            } else {
                Text("No result yet, so workouts use effort-based targets.")
            }
        }
    }

    private var voiceSection: some View {
        Section {
            Toggle("Voice coaching", isOn: $profile.voiceCuesEnabled)
            Group {
                Toggle("Step changes", isOn: $profile.voiceStepChanges)
                Toggle("Splits every \(profile.units.splitName)", isOn: $profile.voiceSplits)
                Toggle("Pace alerts", isOn: $profile.voicePaceAlerts)
                if profile.voicePaceAlerts {
                    Stepper("Alert tolerance ±\(Int(profile.paceAlertToleranceSeconds)) s", value: $profile.paceAlertToleranceSeconds, in: 0...30, step: 5)
                }
            }
            .disabled(!profile.voiceCuesEnabled)
        } header: {
            Text("Voice cues")
        } footer: {
            Text("Cues briefly lower your music instead of pausing it.")
        }
    }

    private var remindersSection: some View {
        Section("Reminders") {
            Toggle("Workout-day reminders", isOn: $profile.remindersEnabled)
            if profile.remindersEnabled {
                DatePicker("Time", selection: reminderBinding, displayedComponents: .hourAndMinute)
            }
        }
        .onChange(of: profile.remindersEnabled) { _, enabled in
            Task {
                if enabled { _ = await services.notifications.requestAuthorization() }
                await refreshReminders()
            }
        }
        .onChange(of: profile.reminderMinutes) { _, _ in
            Task { await refreshReminders() }
        }
    }

    private var reminderBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: profile.reminderMinutes / 60, minute: profile.reminderMinutes % 60, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                profile.reminderMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
            })
    }

    private var healthSection: some View {
        Section {
            Toggle("Save runs to Apple Health", isOn: Binding(
                get: { profile.healthKitEnabled },
                set: { enabled in
                    if enabled {
                        Task {
                            do {
                                try await services.health.requestAuthorization()
                                profile.healthKitEnabled = true
                            } catch {
                                profile.healthKitEnabled = false
                            }
                        }
                    } else {
                        profile.healthKitEnabled = false
                    }
                }))
            .disabled(!services.health.isAvailable)
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Completed runs are saved as running workouts with their route. Heart rate is read to show averages in summaries.")
        }
    }

    private var garmin: GarminConnecting { services.garmin }

    private var garminSection: some View {
        Section {
            if let name = garmin.status.watchName {
                LabeledContent("Watch", value: name)
                LabeledContent("Status") {
                    Label(garminStatusText, systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .imageScale(.small)
                        .foregroundStyle(garmin.status.isReady ? .green : .secondary)
                }
                if case .connected(_, false) = garmin.status {
                    Button {
                        garmin.showWatchAppInStore()
                    } label: {
                        Label("Install \(AppBrand.name) on the watch", systemImage: "arrow.down.circle")
                    }
                }
                Button {
                    sendWorkoutsToWatch()
                } label: {
                    if isSendingToWatch {
                        ProgressView()
                    } else {
                        Label("Send upcoming workouts", systemImage: "arrow.up.forward.app")
                    }
                }
                .disabled(!garmin.status.isReady || isSendingToWatch)
                if let garminNote {
                    Text(garminNote).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Choose a different watch") { garmin.pairWatch() }
                Button("Disconnect watch", role: .destructive) {
                    garmin.forgetWatch()
                    garminNote = nil
                }
            } else {
                Button {
                    garmin.pairWatch()
                } label: {
                    Label("Connect a Garmin watch", systemImage: "applewatch.radiowaves.left.and.right")
                }
            }
        } header: {
            Text("Garmin")
        } footer: {
            Text("Connects through the Garmin Connect app. Open \(AppBrand.name) on your watch to get the next \(GarminSync.daysAhead) days of workouts. Runs you record there are saved to Garmin Connect and appear in History here.")
        }
    }

    private var garminStatusText: String {
        switch garmin.status {
        case .noWatch: "Not connected"
        case .bluetoothOff: "Bluetooth is off"
        case .disconnected: "Not in range"
        case .connected(_, nil): "Connected"
        case .connected(_, true?): "Connected · app installed"
        case .connected(_, false?): "Connected · app not installed"
        }
    }

    private func sendWorkoutsToWatch() {
        isSendingToWatch = true
        garminNote = nil
        Task {
            do {
                try await GarminSync.sendUpcoming(profile: profile, services: services, context: context)
                garminNote = "Sent. Open \(AppBrand.name) on your watch to see them."
            } catch {
                garminNote = error.localizedDescription
            }
            isSendingToWatch = false
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if let plan, let template {
            Section("Current plan") {
                LabeledContent("Plan", value: plan.planTitle)
                LabeledContent("Started", value: plan.startDate.formatted(date: .abbreviated, time: .omitted))
                if let race = plan.raceDate {
                    LabeledContent("Race day", value: race.formatted(date: .abbreviated, time: .omitted))
                }
                Button("Restart plan from today") { confirmingRestart = true }
                    .confirmationDialog("Restart \(plan.planTitle)?", isPresented: $confirmingRestart, titleVisibility: .visible) {
                        Button("Restart") {
                            PlanManager.restart(plan, template: template, profile: profile, context: context)
                            Task { await refreshReminders() }
                        }
                    } message: {
                        Text("Your schedule is rebuilt from week 1 starting today. Completed runs stay in your history.")
                    }
                Button("End plan", role: .destructive) { confirmingEnd = true }
                    .confirmationDialog("End \(plan.planTitle)?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                        Button("End plan", role: .destructive) {
                            PlanManager.end(plan, context: context)
                            services.notifications.cancelAll()
                        }
                    }
            }
        }
    }

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share export file", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                do {
                    exportURL = try DataExporter.writeExportFile(context: context)
                    exportError = nil
                } catch {
                    exportError = error.localizedDescription
                }
            } label: {
                Label(exportURL == nil ? "Export data (JSON)" : "Refresh export", systemImage: "doc.badge.arrow.up")
            }
            if let exportError {
                Text(exportError).foregroundStyle(.red).font(.footnote)
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Includes your profile, plans, scheduled workouts and every run with splits and route.")
        }
    }

    private var developerSection: some View {
        Section {
            Toggle("Simulate GPS (replay sample route)", isOn: $profile.simulateGPS)
        } header: {
            Text("Testing")
        } footer: {
            Text("Replays a bundled GPX run instead of using real GPS. The Simulator always uses the replay.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        } footer: {
            Text("\(AppBrand.name) — \(AppBrand.tagline)")
        }
    }

    private func refreshReminders() async {
        await PlanManager.refreshReminders(plan: plan, template: template, profile: profile, notifications: services.notifications)
    }
}

/// Logs a new race/time-trial result and recalculates pace zones for all remaining workouts.
struct RaceResultSheet: View {
    let profile: UserProfile
    let plan: ActivePlan?
    let template: PlanTemplate?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var distance: Double = 5_000
    @State private var hours = 0
    @State private var minutes = 25
    @State private var seconds = 0
    @State private var date = Date()

    private var time: Double { Double(hours * 3600 + minutes * 60 + seconds) }
    private var result: RaceResult { RaceResult(distanceMeters: distance, timeSeconds: time, date: date) }
    private var newZones: PaceZones {
        PaceCalculator.zones(reference: result, goalTimeSeconds: plan?.goalTimeSeconds,
                             raceDistanceMeters: template?.goal.raceDistanceMeters, level: profile.level)
    }
    private var isValid: Bool { PaceCalculator.vdot(distanceMeters: distance, timeSeconds: time) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Result") {
                    Picker("Distance", selection: $distance) {
                        ForEach(RaceResult.commonDistances) { Text($0.name).tag($0.meters) }
                    }
                    DurationPicker(hours: $hours, minutes: $minutes, seconds: $seconds)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                if isValid {
                    Section("New pace zones") {
                        PaceZonesList(zones: newZones, units: profile.units)
                    }
                } else {
                    Text("That time looks out of range.").foregroundStyle(.red)
                }
            }
            .navigationTitle("Race result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.referenceResult = result
                        profile.recalculateZones(activePlan: plan, template: template)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

#Preview {
    SettingsView(profile: PreviewData.profile)
        .previewEnvironment()
}
