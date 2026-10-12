import CoffeeCore
import Foundation
import UserNotifications

extension Reminder.Kind {
    /// Where the kind's switch in Settings is kept. On this device only:
    /// permission to notify is per device too.
    var defaultsKey: String { "reminder.\(rawValue)" }
}

/// Sends the schedule's reminders as local notifications, which need no
/// entitlement. They are set each time the schedule changes, so they are as
/// current as the last time the app was open.
@MainActor
enum ReminderScheduler {
    /// The hour of the morning a reminder is sent, in the device's time zone.
    static let hour = 8
    /// iOS keeps 64 pending notifications for an app at most.
    private static let limit = 40

    private static var work: Task<Void, Never>?

    static func isOn(_ kind: Reminder.Kind) -> Bool {
        UserDefaults.standard.bool(forKey: kind.defaultsKey)
    }

    /// Ask to send notifications, once; later calls answer what was chosen.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replace what is pending with `reminders`, for the kinds switched on.
    /// One still pending for today is left to be sent: the plan only covers
    /// later days, and a thaw is gone from it once the app has thawed the bag.
    static func schedule(_ reminders: [Reminder], today: String) {
        let wanted = reminders.filter { isOn($0.kind) && $0.date > today }.prefix(limit)
        let off = Set(Reminder.Kind.allCases.filter { !isOn($0) }.map(\.rawValue))
        // One at a time, so an earlier call can't add back what a later one removed
        let previous = work
        work = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { isStale($0, today: today, off: off) })
            for reminder in wanted {
                guard let request = request(reminder) else { continue }
                try? await center.add(request)
            }
        }
    }

    /// An identifier is a `Reminder.id`: "2026-10-27|thaw|bean".
    private static func isStale(_ identifier: String, today: String, off: Set<String>) -> Bool {
        let parts = identifier.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return true }
        return parts[0] > today || off.contains(String(parts[1]))
    }

    private static func request(_ reminder: Reminder) -> UNNotificationRequest? {
        // The day's own numbers at a wall-clock hour: no time zone arithmetic
        let parts = reminder.date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        let when = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour)
        return UNNotificationRequest(
            identifier: reminder.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        )
    }
}
