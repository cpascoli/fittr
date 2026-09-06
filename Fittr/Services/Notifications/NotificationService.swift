import Foundation
import UserNotifications

protocol NotificationServicing: AnyObject {
    func requestAuthorizationIfNeeded() async -> Bool
    func scheduleWorkoutReminder(id: UUID, title: String, fireAt: Date)
    func cancelWorkoutReminder(id: UUID)
    func scheduleRestComplete(after seconds: TimeInterval)
    func cancelRestComplete()
}

final class NotificationService: NotificationServicing {
    private let center = UNUserNotificationCenter.current()
    private let restIdentifier = "fittr.rest.complete"

    func requestAuthorizationIfNeeded() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleWorkoutReminder(id: UUID, title: String, fireAt: Date) {
        guard fireAt > Date.now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(title) in 30 minutes"
        content.sound = .default
        let interval = max(1, fireAt.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: "fittr.workout.\(id.uuidString)", content: content, trigger: trigger)
        center.add(request)
    }

    func cancelWorkoutReminder(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["fittr.workout.\(id.uuidString)"])
    }

    func scheduleRestComplete(after seconds: TimeInterval) {
        center.removePendingNotificationRequests(withIdentifiers: [restIdentifier])
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Next set ready"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: restIdentifier, content: content, trigger: trigger))
    }

    func cancelRestComplete() {
        center.removePendingNotificationRequests(withIdentifiers: [restIdentifier])
    }
}

final class MockNotificationService: NotificationServicing {
    var authorized = true
    var reminders: [UUID: Date] = [:]
    var restScheduled = false

    func requestAuthorizationIfNeeded() async -> Bool { authorized }

    func scheduleWorkoutReminder(id: UUID, title: String, fireAt: Date) {
        reminders[id] = fireAt
    }

    func cancelWorkoutReminder(id: UUID) {
        reminders[id] = nil
    }

    func scheduleRestComplete(after seconds: TimeInterval) {
        restScheduled = seconds > 0
    }

    func cancelRestComplete() {
        restScheduled = false
    }
}
