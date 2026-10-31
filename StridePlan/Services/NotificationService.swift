import Foundation
import UserNotifications

struct WorkoutReminder: Hashable {
    var id: String
    var date: Date
    var title: String
    var body: String
}

protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func scheduleReminders(_ reminders: [WorkoutReminder], at time: DateComponents) async
    func cancelAll()
}

final class NotificationService: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "workout-reminder-"
    /// iOS keeps at most 64 pending requests per app; leave headroom.
    private let maxScheduled = 40

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleReminders(_ reminders: [WorkoutReminder], at time: DateComponents) async {
        cancelAll()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        let now = Date()
        var scheduled = 0
        for reminder in reminders.sorted(by: { $0.date < $1.date }) {
            var components = calendar.dateComponents([.year, .month, .day], from: reminder.date)
            components.hour = time.hour
            components.minute = time.minute
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifierPrefix + reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
            scheduled += 1
            if scheduled >= maxScheduled { break }
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}

final class MockNotificationService: NotificationScheduling {
    private(set) var scheduled: [WorkoutReminder] = []
    func requestAuthorization() async -> Bool { true }
    func scheduleReminders(_ reminders: [WorkoutReminder], at time: DateComponents) async { scheduled = reminders }
    func cancelAll() { scheduled = [] }
}
