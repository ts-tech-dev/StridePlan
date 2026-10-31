import Charts
import MapKit
import SwiftData
import SwiftUI

struct RunSummaryView: View {
    @Bindable var run: RunRecord
    let profile: UserProfile
    let isNewRun: Bool
    var onDone: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.services) private var services
    @State private var confirmingDelete = false

    private var units: UnitSystem { profile.units }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsGrid
                if run.route.count > 1 { routeMap }
                if run.paceSamples.count > 2 { paceChart }
                if !run.splits.isEmpty { splitsTable }
                if !run.stepResults.isEmpty { compliance }
                feedback
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isNewRun ? "Nice work!" : run.workoutTitle)
        .navigationBarTitleDisplayMode(isNewRun ? .large : .inline)
        .toolbar {
            if isNewRun {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); onDone?() }
                        .bold()
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    optionsMenu
                }
            }
        }
        .confirmationDialog("Delete this run?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("It will be removed from your history. Runs saved to Apple Health stay there.")
        }
        .onDisappear(perform: save)
    }

    private var optionsMenu: some View {
        Menu {
            if profile.healthKitEnabled && run.healthKitUUID == nil {
                Button {
                    RunRecorder.syncHealth(run: run, profile: profile, health: services.health, context: context)
                } label: {
                    Label("Save to Apple Health", systemImage: "heart")
                }
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete run", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle").accessibilityLabel("Run options")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isNewRun { Text(run.workoutTitle).font(.title2.bold()) }
            Text(run.startDate.formatted(date: .complete, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if run.healthKitUUID != nil {
                Label("Saved to Apple Health", systemImage: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
            }
        }
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                StatTile(title: "Distance", value: Formatters.distanceValue(run.distanceMeters, units: units), unit: units.distanceAbbreviation, valueFont: Theme.numeral(34))
                StatTile(title: "Time", value: Formatters.duration(run.durationSeconds), valueFont: Theme.numeral(34))
            }
            GridRow {
                StatTile(title: "Avg pace", value: Formatters.pace(run.averagePaceSecondsPerKm, units: units), unit: units.paceSuffix)
                if let hr = run.averageHeartRate {
                    StatTile(title: "Avg heart rate", value: "\(Int(hr.rounded()))", unit: "bpm")
                } else {
                    StatTile(title: "Splits", value: "\(run.splits.count)")
                }
            }
        }
        .card()
    }

    private var routeMap: some View {
        let coordinates = run.route.map(\.coordinate)
        return Map(initialPosition: .automatic, interactionModes: [.zoom, .pan]) {
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            if let first = coordinates.first {
                Annotation("Start", coordinate: first) {
                    Circle().fill(.green).overlay(Circle().stroke(.white, lineWidth: 2)).frame(width: 14, height: 14)
                }
            }
            if let last = coordinates.last {
                Annotation("Finish", coordinate: last) {
                    Circle().fill(.red).overlay(Circle().stroke(.white, lineWidth: 2)).frame(width: 14, height: 14)
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityLabel("Map of your route")
    }

    private var paceChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pace").font(.headline)
            Chart(run.paceSamples) { sample in
                LineMark(x: .value("Distance", sample.distanceMeters / units.metersPerUnit),
                         y: .value("Pace", Formatters.paceValue(sample.paceSecondsPerKm, units: units) / 60))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.accent)
                if let average = run.averagePaceSecondsPerKm {
                    RuleMark(y: .value("Average", Formatters.paceValue(average, units: units) / 60))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(Formatters.pace(minutes * 60 * 1000 / units.metersPerUnit, units: units))
                        }
                    }
                }
            }
            .chartXAxisLabel(units.distanceAbbreviation)
            .frame(height: 180)
            .accessibilityLabel("Pace over distance chart")
        }
        .card()
    }

    private var splitsTable: some View {
        let fastest = run.splits.map(\.paceSecondsPerKm).min() ?? 0
        let slowest = run.splits.map(\.paceSecondsPerKm).max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("Splits").font(.headline)
            ForEach(run.splits) { split in
                HStack {
                    Text(split.distanceMeters < units.metersPerUnit * 0.98
                         ? Formatters.distanceValue(split.distanceMeters, units: units)
                         : "\(split.index)")
                        .frame(width: 44, alignment: .leading)
                    GeometryReader { proxy in
                        let range = max(slowest - fastest, 1)
                        let fraction = 1 - (split.paceSecondsPerKm - fastest) / range * 0.6
                        Capsule()
                            .fill(split.paceSecondsPerKm == fastest ? Theme.accent : Theme.accent.opacity(0.45))
                            .frame(width: proxy.size.width * fraction)
                    }
                    .frame(height: 10)
                    Text(Formatters.pace(split.paceSecondsPerKm, units: units))
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.subheadline.monospacedDigit())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Split \(split.index): \(Formatters.pace(split.paceSecondsPerKm, units: units)) \(units.paceSuffix)")
            }
        }
        .card()
    }

    private var compliance: some View {
        let scored = run.stepResults.compactMap(\.compliance)
        let hits = scored.filter { $0 == .hit }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Steps").font(.headline)
                Spacer()
                if !scored.isEmpty {
                    Text("\(hits)/\(scored.count) on target")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            ForEach(run.stepResults) { result in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(result.zone.color).frame(width: 4, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).font(.subheadline.weight(.semibold))
                        Text(result.skipped ? "Skipped" : "\(Formatters.duration(result.durationSeconds)) · \(Formatters.distance(result.distanceMeters, units: units))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Formatters.pace(result.paceSecondsPerKm, units: units)).font(.subheadline.monospacedDigit())
                        if let target = result.target {
                            Text(Formatters.paceRange(target, units: units)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    complianceIcon(result.compliance)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    @ViewBuilder
    private func complianceIcon(_ value: PaceRange.Compliance?) -> some View {
        switch value {
        case .hit: Image(systemName: "checkmark.circle.fill").foregroundStyle(ZonePalette.color(for: "easy")).accessibilityLabel("On target")
        case .under: Image(systemName: "tortoise.fill").foregroundStyle(.orange).accessibilityLabel("Slower than target")
        case .over: Image(systemName: "hare.fill").foregroundStyle(.red).accessibilityLabel("Faster than target")
        case nil: Image(systemName: "minus.circle").foregroundStyle(.tertiary).accessibilityHidden(true)
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How did it feel?").font(.headline)
            HStack(spacing: 4) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        run.rpe = run.rpe == value ? nil : value
                    } label: {
                        Text("\(value)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(run.rpe == value ? .white : .primary)
                            .background(run.rpe == value ? AnyShapeStyle(rpeColor(value)) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effort \(value) of 10")
                    .accessibilityAddTraits(run.rpe == value ? .isSelected : [])
                }
            }
            HStack {
                Text("Easy").font(.caption2)
                Spacer()
                Text("Max effort").font(.caption2)
            }
            .foregroundStyle(.secondary)
            TextField("Notes (how you felt, weather, shoes…)", text: $run.notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        }
        .card()
    }

    private func rpeColor(_ value: Int) -> Color {
        switch value {
        case ...3: ZonePalette.color(for: "easy")
        case 4...5: ZonePalette.color(for: "steady")
        case 6...7: ZonePalette.color(for: "tempo")
        case 8: ZonePalette.color(for: "threshold")
        default: ZonePalette.color(for: "interval")
        }
    }

    private func save() {
        try? context.save()
    }

    private func delete() {
        if let scheduled = run.scheduledWorkout {
            scheduled.run = nil
            PlanManager.restore(scheduled)
        }
        context.delete(run)
        try? context.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        RunSummaryView(run: PreviewData.run, profile: PreviewData.profile, isNewRun: true)
    }
    .previewEnvironment()
}
