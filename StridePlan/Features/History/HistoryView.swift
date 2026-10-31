import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    let profile: UserProfile
    @Query(sort: \RunRecord.startDate, order: .reverse) private var runs: [RunRecord]
    @State private var period: Period = .threeMonths
    @State private var source: Source = .all

    enum Period: String, CaseIterable, Identifiable {
        case month = "4 wks", threeMonths = "3 mo", year = "Year", all = "All"
        var id: String { rawValue }

        var startDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .month: return calendar.date(byAdding: .day, value: -28, to: .now)
            case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: .now)
            case .year: return calendar.date(byAdding: .year, value: -1, to: .now)
            case .all: return nil
            }
        }
    }

    enum Source: String, CaseIterable, Identifiable {
        case all = "All runs", plan = "Plan workouts", other = "Free & manual"
        var id: String { rawValue }
    }

    private var filtered: [RunRecord] {
        runs.filter { run in
            (period.startDate.map { run.startDate >= $0 } ?? true)
                && (source == .all || (source == .plan) == (run.scheduledWorkout != nil))
        }
    }

    private var units: UnitSystem { profile.units }

    var body: some View {
        NavigationStack {
            List {
                if runs.isEmpty {
                    EmptyStateView(symbol: "figure.run", title: "No runs yet", message: "Your completed runs will appear here.")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        HistoryStats(runs: filtered, units: units)
                        WeeklyDistanceChart(runs: filtered, units: units)
                    }
                    Section {
                        Picker("Period", selection: $period) {
                            ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Show", selection: $source) {
                            ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Section("\(filtered.count) runs") {
                        ForEach(filtered) { run in
                            NavigationLink(value: run) {
                                RunRow(run: run, units: units)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: RunRecord.self) { run in
                RunSummaryView(run: run, profile: profile, isNewRun: false)
            }
        }
    }
}

private struct HistoryStats: View {
    let runs: [RunRecord]
    let units: UnitSystem

    private var thisWeek: Double {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return runs.filter { $0.startDate >= start }.reduce(0) { $0 + $1.distanceMeters }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "This week", value: Formatters.distanceValue(thisWeek, units: units, fractionDigits: 1), unit: units.distanceAbbreviation)
                StatTile(title: "Total runs", value: "\(runs.count)")
            }
            GridRow {
                StatTile(title: "Longest", value: Formatters.distanceValue(runs.map(\.distanceMeters).max() ?? 0, units: units, fractionDigits: 1), unit: units.distanceAbbreviation)
                StatTile(title: "Total", value: Formatters.distanceValue(runs.reduce(0) { $0 + $1.distanceMeters }, units: units, fractionDigits: 0), unit: units.distanceAbbreviation)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct WeeklyDistanceChart: View {
    let runs: [RunRecord]
    let units: UnitSystem

    private struct WeekTotal: Identifiable {
        var weekStart: Date
        var meters: Double
        var id: Date { weekStart }
    }

    private var totals: [WeekTotal] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: runs) { calendar.dateInterval(of: .weekOfYear, for: $0.startDate)?.start ?? $0.startDate }
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<8).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek) else { return nil }
            return WeekTotal(weekStart: start, meters: grouped[start]?.reduce(0) { $0 + $1.distanceMeters } ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 8 weeks").font(.subheadline.weight(.semibold))
            Chart(totals) { week in
                BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value(units.distanceAbbreviation, week.meters / units.metersPerUnit))
                    .foregroundStyle(Theme.accent.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 140)
            .accessibilityLabel("Weekly distance for the last eight weeks")
        }
        .padding(.vertical, 6)
    }
}

private struct RunRow: View {
    let run: RunRecord
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            WorkoutTypeIcon(type: run.workoutType, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.workoutTitle).font(.subheadline.weight(.semibold))
                Text(run.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.distance(run.distanceMeters, units: units)).font(.subheadline.weight(.semibold))
                Text("\(Formatters.duration(run.durationSeconds)) · \(Formatters.paceWithUnit(run.averagePaceSecondsPerKm, units: units))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            if run.isManual {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Logged manually")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HistoryView(profile: PreviewData.profile)
        .previewEnvironment()
}
