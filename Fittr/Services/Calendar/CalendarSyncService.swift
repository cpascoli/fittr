import Foundation
import SwiftData

/// Keeps Apple Calendar mirroring the schedule.
///
/// Before this existed, the only thing that ever wrote to the calendar was the
/// "Connect Calendar" button in Settings. Rescheduling, skipping, removing and
/// completing a workout all left the calendar untouched, and `removeEvent` was
/// never called from anywhere in the app — so a vacated day kept its event for
/// good, and the launch backfill then recreated the day as a fresh row with no
/// identifier, which the next sync turned into a second event.
@MainActor
enum CalendarSyncService {
    /// Brings the calendar in line with every scheduled workout. Safe to call
    /// repeatedly — that is the point, since the old sync duplicated its whole
    /// output each time it ran.
    static func reconcile(in context: ModelContext) async {
        guard let settings = try? ScheduleService.fetchSettings(in: context),
              settings.calendarSyncEnabled else { return }
        guard await authorizedCalendar() != nil else { return }

        let items = (try? context.fetch(FetchDescriptor<ScheduledWorkout>())) ?? []
        for item in items {
            if shouldHaveEvent(item) {
                await upsert(item, in: context)
            } else {
                await removeEvent(for: item, in: context)
            }
        }
        try? context.save()
    }

    /// Deletes the event for a workout that is about to be taken off the
    /// calendar. Must run *before* the row goes, because the identifier is the
    /// only handle on the event and it disappears with the row.
    static func removeEvent(for item: ScheduledWorkout, in context: ModelContext) async {
        guard !item.calendarEventIdentifier.isEmpty else { return }
        await FittrDependencies.shared.calendar.removeEvent(identifier: item.calendarEventIdentifier)
        item.calendarEventIdentifier = ""
        try? context.save()
    }

    /// Clears out everything Fittr has put on the calendar, including copies it
    /// has lost track of. Matches on Fittr's own events only.
    @discardableResult
    static func removeAllEvents(in context: ModelContext) async -> Int {
        guard let calendar = await authorizedCalendar() else { return 0 }

        let items = (try? context.fetch(FetchDescriptor<ScheduledWorkout>())) ?? []
        let start = items.map(\.scheduledStart).min() ?? .now
        let end = items.map(\.scheduledStart).max() ?? .now
        let window = DateHelpers.startOfDay(min(start, .now)).addingTimeInterval(-365 * 24 * 3_600)
        let removed = await calendar.removeAllWorkoutEvents(
            from: window,
            to: max(end, .now).addingTimeInterval(365 * 24 * 3_600)
        )
        for item in items {
            item.calendarEventIdentifier = ""
        }
        try? context.save()
        return removed
    }

    private static func authorizedCalendar() async -> (any CalendarServicing)? {
        let calendar = FittrDependencies.shared.calendar
        if calendar.isAuthorized { return calendar }
        return await calendar.requestAccess() ? calendar : nil
    }

    /// A rest day is not an appointment, and a workout already finished or
    /// written off is not something to be reminded about.
    private static func shouldHaveEvent(_ item: ScheduledWorkout) -> Bool {
        guard item.template?.type.isTrainable == true else { return false }
        switch item.status {
        case .upcoming, .rescheduled: return true
        case .completed, .skipped: return false
        }
    }

    private static func upsert(_ item: ScheduledWorkout, in context: ModelContext) async {
        guard let template = item.template else { return }
        let exercises = template.orderedExercises.compactMap { $0.exercise?.name }.joined(separator: ", ")
        let identifier = try? await FittrDependencies.shared.calendar.upsertWorkoutEvent(
            identifier: item.calendarEventIdentifier.isEmpty ? nil : item.calendarEventIdentifier,
            title: template.name,
            start: item.scheduledStart,
            durationMinutes: template.estimatedDurationMinutes,
            notes: "Expected duration: \(template.estimatedDurationMinutes) min\n\(exercises)",
            deepLink: URL(string: "fittr://workout/\(item.id.uuidString)")
        )
        if let identifier = identifier ?? nil {
            item.calendarEventIdentifier = identifier
        }
    }
}
