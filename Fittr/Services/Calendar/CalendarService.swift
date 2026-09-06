import EventKit
import Foundation

protocol CalendarServicing: AnyObject {
    var isAuthorized: Bool { get }
    func requestWriteAccess() async -> Bool
    func upsertWorkoutEvent(
        identifier: String?,
        title: String,
        start: Date,
        durationMinutes: Int,
        notes: String,
        deepLink: URL?
    ) async throws -> String?
    func removeEvent(identifier: String) async
}

final class CalendarService: CalendarServicing {
    private let store = EKEventStore()
    private(set) var isAuthorized = false

    func requestWriteAccess() async -> Bool {
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    func upsertWorkoutEvent(
        identifier: String?,
        title: String,
        start: Date,
        durationMinutes: Int,
        notes: String,
        deepLink: URL?
    ) async throws -> String? {
        let authorized = isAuthorized ? true : await requestWriteAccess()
        guard authorized else { return nil }

        let event: EKEvent
        if let identifier, let existing = store.event(withIdentifier: identifier) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = store.defaultCalendarForNewEvents
        }

        event.title = "🏋️ \(title)"
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(max(durationMinutes, 15) * 60))
        var extra = notes
        if let deepLink {
            extra += "\n\nOpen in Fittr: \(deepLink.absoluteString)"
        }
        event.notes = extra
        event.url = deepLink
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    func removeEvent(identifier: String) async {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }
}

final class MockCalendarService: CalendarServicing {
    var isAuthorized = false
    var events: [String: String] = [:]

    func requestWriteAccess() async -> Bool {
        isAuthorized = true
        return true
    }

    func upsertWorkoutEvent(
        identifier: String?,
        title: String,
        start: Date,
        durationMinutes: Int,
        notes: String,
        deepLink: URL?
    ) async throws -> String? {
        let id = identifier ?? UUID().uuidString
        events[id] = title
        return id
    }

    func removeEvent(identifier: String) async {
        events[identifier] = nil
    }
}
