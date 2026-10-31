import ActivityKit
import Foundation

protocol RunActivityControlling: AnyObject {
    func start(attributes: RunActivityAttributes, state: RunActivityAttributes.ContentState)
    func update(_ state: RunActivityAttributes.ContentState)
    func end(_ state: RunActivityAttributes.ContentState)
}

/// Lock Screen + Dynamic Island run activity.
final class LiveActivityService: RunActivityControlling {
    private var activity: Activity<RunActivityAttributes>?

    func start(attributes: RunActivityAttributes, state: RunActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endStaleActivities()
        do {
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        } catch {
            print("[LiveActivity] request failed: \(error)")
        }
    }

    func update(_ state: RunActivityAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(5 * 60)))
        }
    }

    func end(_ state: RunActivityAttributes.ContentState) {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(10 * 60)))
        }
    }

    /// Cleans up activities left behind if the app was killed mid-run.
    private func endStaleActivities() {
        for stale in Activity<RunActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

final class MockLiveActivityService: RunActivityControlling {
    private(set) var lastState: RunActivityAttributes.ContentState?
    func start(attributes: RunActivityAttributes, state: RunActivityAttributes.ContentState) { lastState = state }
    func update(_ state: RunActivityAttributes.ContentState) { lastState = state }
    func end(_ state: RunActivityAttributes.ContentState) { lastState = nil }
}
