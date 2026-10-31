import SwiftUI

extension PaceZoneKind {
    var color: Color { ZonePalette.color(for: rawValue) }
}

extension WorkoutType {
    /// Representative zone for coloring cards and calendar dots.
    var primaryZone: PaceZoneKind {
        switch self {
        case .easy, .long: .easy
        case .recovery: .recovery
        case .tempo, .progression: .tempo
        case .intervals: .interval
        case .hills: .threshold
        case .fartlek: .steady
        case .race: .race
        case .crossTrain, .rest: .walk
        }
    }

    var color: Color { primaryZone.color }
}

extension WorkoutStatus {
    var symbolName: String {
        switch self {
        case .upcoming: "circle"
        case .completed: "checkmark.circle.fill"
        case .skipped: "arrow.uturn.forward.circle"
        case .missed: "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .upcoming: .secondary
        case .completed: ZonePalette.color(for: "easy")
        case .skipped: .orange
        case .missed: .red
        }
    }

    var label: String { rawValue.capitalized }
}

enum Theme {
    static let cornerRadius: CGFloat = 20
    static let spacing: CGFloat = 16
    static let accent = AppBrand.accent

    static let accentGradient = LinearGradient(
        colors: [AppBrand.accent, Color(red: 1.0, green: 0.56, blue: 0.20)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Large, rounded numerals for stats.
    static func numeral(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}

// MARK: - Modifiers & styles

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.spacing

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Theme.spacing) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accentGradient.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Dates

enum DateText {
    static func weekdayShort(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[(weekday - 1) % 7]
    }

    static func weekdayFull(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[(weekday - 1) % 7]
    }

    /// Weekdays ordered starting from the user's locale first weekday.
    static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
