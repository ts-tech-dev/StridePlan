import SwiftUI

struct ZoneBadge: View {
    let zone: PaceZoneKind

    var body: some View {
        Text(zone.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(zone.color)
            .background(zone.color.opacity(0.15), in: Capsule())
            .accessibilityLabel("\(zone.displayName) zone")
    }
}

struct WorkoutTypeIcon: View {
    let type: WorkoutType
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: type.symbolName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(type.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var valueFont: Font = Theme.numeral(28)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(valueFont)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit ?? "")")
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

/// Horizontal bar showing a workout's steps proportionally, colored by zone.
struct StepStripView: View {
    let steps: [FlatStep]
    let zones: PaceZones
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let durations = steps.map(stepSeconds)
            let total = max(durations.reduce(0, +), 1)
            HStack(spacing: 1.5) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    step.zone.color
                        .frame(width: max(2, (proxy.size.width - CGFloat(steps.count) * 1.5) * durations[index] / total))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func stepSeconds(_ step: FlatStep) -> CGFloat {
        switch step.duration.type {
        case .time: step.duration.value
        case .distance: step.duration.value / 1000 * zones.estimatedPace(for: step.zone)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Target pace text for a zone: pace range when known, otherwise the effort cue.
struct TargetText: View {
    let zone: PaceZoneKind
    let zones: PaceZones
    let units: UnitSystem

    var body: some View {
        if let range = zones.range(for: zone) {
            Text(Formatters.paceRange(range, units: units)).monospacedDigit()
        } else {
            Text(zone.effortCue)
        }
    }
}
