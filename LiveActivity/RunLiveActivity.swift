import ActivityKit
import SwiftUI
import WidgetKit

@main
struct StridePlanWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let zoneColor = ZonePalette.color(for: state.zoneRaw)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.stepTitle)
                            .font(.headline)
                            .foregroundStyle(zoneColor)
                            .lineLimit(1)
                        Text(state.targetPace)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(state.currentPace)
                            .font(.title2.bold().monospacedDigit())
                        Text(context.attributes.paceUnit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        ElapsedText(state: state)
                            .font(.title3.monospacedDigit())
                        Spacer()
                        Text("\(state.distance) \(context.attributes.distanceUnit)")
                            .font(.title3.monospacedDigit())
                        if !state.stepRemaining.isEmpty {
                            Spacer()
                            Label(state.stepRemaining, systemImage: "hourglass")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(zoneColor)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.isPaused ? "pause.fill" : "figure.run")
                    .foregroundStyle(zoneColor)
            } compactTrailing: {
                Text(state.currentPace)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(zoneColor)
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundStyle(zoneColor)
            }
            .keylineTint(zoneColor)
        }
    }
}

private struct LockScreenView: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState

    var body: some View {
        let zoneColor = ZonePalette.color(for: state.zoneRaw)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.workoutTitle, systemImage: "figure.run")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if state.isPaused {
                    Text("PAUSED")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.yellow)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.stepTitle)
                        .font(.headline)
                        .foregroundStyle(zoneColor)
                    Text(state.targetPace)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
                if !state.stepRemaining.isEmpty {
                    Text(state.stepRemaining)
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(zoneColor)
                }
            }
            HStack {
                metric("Pace", state.currentPace, attributes.paceUnit)
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Time").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    ElapsedText(state: state).font(.title3.bold().monospacedDigit())
                }
                Spacer()
                metric("Distance", state.distance, attributes.distanceUnit)
            }
            .foregroundStyle(.white)
        }
        .padding()
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title3.bold().monospacedDigit())
                Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Ticks on its own while running; frozen while paused.
private struct ElapsedText: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(state.elapsedWhenPaused)
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
        }
    }
}

#Preview("Lock Screen", as: .content, using: RunActivityAttributes(workoutTitle: "6 × 400 m", paceUnit: "/km", distanceUnit: "km")) {
    RunLiveActivity()
} contentStates: {
    RunActivityAttributes.ContentState(stepTitle: "Run 3/6", zoneRaw: "interval", targetPace: "4:40–4:52/km", currentPace: "4:45",
                                       distance: "3.42", stepRemaining: "180 m", timerStart: .now.addingTimeInterval(-1260),
                                       isPaused: false, elapsedWhenPaused: "21:00")
}
