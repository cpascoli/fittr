import EventKit
import Foundation

protocol CalendarServicing: AnyObject {
    var isAuthorized: Bool { get }
    func requestAccess() async -> Bool
    func upsertWorkoutEvent(
        identifier: String?,
        title: String,
        start: Date,
        durationMinutes: Int,
        notes: String,
        deepLink: URL?
    ) async throws -> String?
    func removeEvent(identifier: String) async
    /// Removes every event Fittr wrote in the window, recognised by its deep link
    /// rather than by a stored identifier, so copies orphaned by earlier versions
    /// are cleaned up too.
    func removeAllWorkoutEvents(from start: Date, to end: Date) async -> Int
}

final class CalendarService: CalendarServicing {
    private let store = EKEventStore()
    private(set) var isAuthorized = false

    /// Full access rather than write-only. Updating or deleting an event means
    /// finding it first, and a write-only store cannot read one back — so the
    /// "update the existing event" branch below could never match and every sync
    /// wrote a fresh copy. That is where the duplicate workout events came from.
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
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
        guard await ensureAuthorized() else { return nil }

        let event: EKEvent
        if let identifier, let existing = store.event(withIdentifier: identifier) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = store.defaultCalendarForNewEvents
        }

        event.title = "\(Self.titlePrefix)\(title)"
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
        guard await ensureAuthorized() else { return }
        guard let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    func removeAllWorkoutEvents(from start: Date, to end: Date) async -> Int {
        guard await ensureAuthorized() else { return 0 }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var removed = 0
        for event in store.events(matching: predicate) where Self.isWorkoutEvent(event) {
            do {
                try store.remove(event, span: .thisEvent, commit: false)
                removed += 1
            } catch {
                continue
            }
        }
        try? store.commit()
        return removed
    }

    private func ensureAuthorized() async -> Bool {
        if isAuthorized { return true }
        return await requestAccess()
    }

    static let titlePrefix = "🏋️ "

    /// The deep link is the reliable marker. Events written before it was attached
    /// carry only the title prefix, so both count — nothing else on the calendar
    /// is titled this way.
    private static func isWorkoutEvent(_ event: EKEvent) -> Bool {
        if event.url?.scheme == "fittr" { return true }
        return event.title?.hasPrefix(titlePrefix) == true
    }
}

final class MockCalendarService: CalendarServicing {
    struct Event: Equatable {
        var title: String
        var start: Date
    }

    var isAuthorized = false
    /// Every event ever written, so a test can tell "moved the existing one" from
    /// "left the old one and added another".
    private(set) var events: [String: Event] = [:]
    private(set) var createdCount = 0
    private(set) var removedCount = 0

    func requestAccess() async -> Bool {
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
        // Mirrors EventKit: an identifier that is not in the store cannot be
        // updated, so a stale one yields a brand new event. Reusing the passed
        // identifier here would have hidden the duplicate bug entirely.
        if let identifier, events[identifier] != nil {
            events[identifier] = Event(title: title, start: start)
            return identifier
        }
        let id = UUID().uuidString
        events[id] = Event(title: title, start: start)
        createdCount += 1
        return id
    }

    func removeEvent(identifier: String) async {
        guard events.removeValue(forKey: identifier) != nil else { return }
        removedCount += 1
    }

    func removeAllWorkoutEvents(from start: Date, to end: Date) async -> Int {
        let matching = events.filter { $0.value.start >= start && $0.value.start <= end }
        for key in matching.keys {
            events[key] = nil
        }
        removedCount += matching.count
        return matching.count
    }
}
