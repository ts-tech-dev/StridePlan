import Foundation

enum Formatters {
    enum DurationStyle {
        /// `1:05:09`, `5:09`
        case clock
        /// `1h 05m`, `25 min`, `90 s`
        case compact
    }

    static func duration(_ seconds: Double, style: DurationStyle = .clock) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        switch style {
        case .clock:
            return h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%d:%02d", m, s)
        case .compact:
            if h > 0 { return m > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(h)h" }
            if m > 0 { return s > 0 ? "\(m):\(String(format: "%02d", s)) min" : "\(m) min" }
            return "\(s) s"
        }
    }

    /// Converts seconds per kilometer into seconds per display unit.
    static func paceValue(_ secondsPerKm: Double, units: UnitSystem) -> Double {
        secondsPerKm * units.metersPerUnit / 1000
    }

    /// `5:12` (no suffix). Returns `--:--` for invalid paces.
    static func pace(_ secondsPerKm: Double?, units: UnitSystem) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0, secondsPerKm < 3600 else { return "--:--" }
        let value = Int(paceValue(secondsPerKm, units: units).rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func paceWithUnit(_ secondsPerKm: Double?, units: UnitSystem) -> String {
        "\(pace(secondsPerKm, units: units))\(units.paceSuffix)"
    }

    static func paceRange(_ range: PaceRange, units: UnitSystem) -> String {
        "\(pace(range.fast, units: units))–\(pace(range.slow, units: units))\(units.paceSuffix)"
    }

    /// Distance value in display units, e.g. `5.24`.
    static func distanceValue(_ meters: Double, units: UnitSystem, fractionDigits: Int = 2) -> String {
        String(format: "%.\(fractionDigits)f", max(0, meters) / units.metersPerUnit)
    }

    static func distance(_ meters: Double, units: UnitSystem, fractionDigits: Int = 2) -> String {
        "\(distanceValue(meters, units: units, fractionDigits: fractionDigits)) \(units.distanceAbbreviation)"
    }

    /// Track-style distances stay in meters (`400 m`); longer ones use display units.
    static func stepDistance(_ meters: Double, units: UnitSystem) -> String {
        if meters < 2_000, meters.truncatingRemainder(dividingBy: 100) == 0 {
            return "\(Int(meters)) m"
        }
        let value = meters / units.metersPerUnit
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
        return "\(text) \(units.distanceAbbreviation)"
    }

    /// Words suitable for speech, e.g. "5 minutes 12 seconds per kilometer".
    static func spokenPace(_ secondsPerKm: Double, units: UnitSystem) -> String {
        let value = Int(paceValue(secondsPerKm, units: units).rounded())
        let m = value / 60
        let s = value % 60
        let minutes = m == 1 ? "1 minute" : "\(m) minutes"
        let seconds = s == 0 ? "" : " \(s) second\(s == 1 ? "" : "s")"
        return "\(minutes)\(seconds) per \(units.splitName)"
    }

    static func spokenDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if s > 0 && h == 0 { parts.append("\(s) second\(s == 1 ? "" : "s")") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    static func spokenDistance(_ meters: Double, units: UnitSystem) -> String {
        if meters < 1_000 { return "\(Int(meters.rounded())) meters" }
        let value = meters / units.metersPerUnit
        let text = String(format: "%.2f", value)
        return "\(text) \(units == .metric ? "kilometers" : "miles")"
    }

    /// Parses `mm:ss` or `h:mm:ss` into seconds.
    static func parseDuration(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let values = parts.compactMap { $0 }
        let seconds = values.reduce(0) { $0 * 60 + $1 }
        return seconds > 0 ? Double(seconds) : nil
    }
}
