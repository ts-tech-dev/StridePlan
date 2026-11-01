import SwiftUI

/// Single place to rename/rebrand the app (also update PRODUCT_NAME / display name in the project).
enum AppBrand {
    static let name = "Kadence"
    static let tagline = "Plans that run with you."

    /// Bold accent used across the app (also defined as the AccentColor asset).
    static let accent = Color(red: 1.0, green: 0.36, blue: 0.16)
}

/// Pace zone colors, shared by the app and the Live Activity. Keyed by `PaceZoneKind.rawValue`.
enum ZonePalette {
    static func color(for zoneRaw: String) -> Color {
        switch zoneRaw {
        case "walk": Color(red: 0.56, green: 0.60, blue: 0.66)
        case "recovery": Color(red: 0.42, green: 0.66, blue: 0.86)
        case "easy": Color(red: 0.20, green: 0.74, blue: 0.48)
        case "steady": Color(red: 0.10, green: 0.68, blue: 0.70)
        case "tempo": Color(red: 0.98, green: 0.74, blue: 0.10)
        case "threshold": Color(red: 1.00, green: 0.52, blue: 0.12)
        case "interval": Color(red: 0.94, green: 0.26, blue: 0.30)
        case "repetition": Color(red: 0.64, green: 0.36, blue: 0.94)
        case "race": Color(red: 0.92, green: 0.20, blue: 0.56)
        default: AppBrand.accent
        }
    }
}
