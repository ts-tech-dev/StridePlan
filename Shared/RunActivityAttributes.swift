import ActivityKit
import Foundation

/// Shared between the app and the widget extension. Values are pre-formatted so the widget stays dumb.
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stepTitle: String
        var zoneRaw: String
        var targetPace: String
        var currentPace: String
        var distance: String
        var stepRemaining: String
        /// `now - movingTime`, so `Text(timerInterval:)` ticks without updates.
        var timerStart: Date
        var isPaused: Bool
        var elapsedWhenPaused: String
    }

    var workoutTitle: String
    var paceUnit: String
    var distanceUnit: String
}
