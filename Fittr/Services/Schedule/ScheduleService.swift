import Foundation
import SwiftData

enum ScheduleService {
    static let horizonWeeks = 8

    static func ensureUpcomingSchedule(in context: ModelContext, now: Date = .now) throws {
        let settings = try fetchSettings(in: context)
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        guard !templates.isEmpty else { return }

        // A moved workout occupies both the day it is on and the day it came from.
        // Without the second key, backfilling would refill the vacated slot and the
        // week would end up holding two copies of the same workout — one of which
        // the user never asked for and could not see.
        let existing = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        var existingKeys = Set(existing.map { scheduleKey(templateID: $0.template?.id, date: $0.scheduledStart) })
        for item in existing {
            guard let origin = item.rescheduledFrom else { continue }
            existingKeys.insert(scheduleKey(templateID: item.template?.id, date: origin))
        }

        let weekStart = DateHelpers.isoWeekStart(for: now)
        for weekOffset in 0..<horizonWeeks {
            guard let thisWeek = Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart) else { continue }
            for template in templates {
                let date = DateHelpers.dateOnISOWeekday(
                    template.weekday,
                    weekStart: thisWeek,
                    hour: template.preferredHour ?? settings?.preferredWorkoutHour,
                    minute: template.preferredMinute ?? settings?.preferredWorkoutMinute
                )
                if date < DateHelpers.startOfDay(now) { continue }
                let key = scheduleKey(templateID: template.id, date: date)
                if existingKeys.contains(key) { continue }
                let scheduled = ScheduledWorkout(
                    scheduledStart: date,
                    recurrenceGroupId: SeedID.recurrenceGroup,
                    template: template
                )
                context.insert(scheduled)
            }
        }
        try context.save()
    }

    static func nextScheduled(in context: ModelContext, now: Date = .now) throws -> ScheduledWorkout? {
        var descriptor = FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { item in
                item.statusRaw == "upcoming"
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        descriptor.fetchLimit = 20
        let upcoming = try context.fetch(descriptor)
        return upcoming.first { $0.scheduledStart >= DateHelpers.startOfDay(now) }
            ?? upcoming.first
    }

    /// Every workout on a day, not just the first. A day can legitimately hold
    /// more than one once anything has been moved onto it, and returning a single
    /// item here is how a rescheduled workout used to become unreachable.
    static func items(on day: Date, in context: ModelContext) throws -> [ScheduledWorkout] {
        let start = DateHelpers.startOfDay(day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        let descriptor = FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { item in
                item.scheduledStart >= start && item.scheduledStart < end
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        return try context.fetch(descriptor)
    }

    @discardableResult
    static func schedule(
        template: WorkoutTemplate,
        on day: Date,
        in context: ModelContext
    ) throws -> ScheduledWorkout {
        let settings = try fetchSettings(in: context)
        let start = DateHelpers.applying(
            hour: template.preferredHour ?? settings?.preferredWorkoutHour,
            minute: template.preferredMinute ?? settings?.preferredWorkoutMinute,
            to: day
        )
        let item = ScheduledWorkout(
            scheduledStart: start,
            recurrenceGroupId: SeedID.recurrenceGroup,
            template: template
        )
        context.insert(item)
        try context.save()
        return item
    }

    static func weekItems(containing date: Date, in context: ModelContext) throws -> [ScheduledWorkout] {
        let start = DateHelpers.isoWeekStart(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? date
        let descriptor = FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { item in
                item.scheduledStart >= start && item.scheduledStart < end
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        return try context.fetch(descriptor)
    }

    /// Moves a workout, remembering the day it came from so the move can be undone
    /// exactly. Moving it back onto its original day clears the marker rather than
    /// leaving it flagged as "rescheduled" forever.
    ///
    /// This deliberately does not touch `notes`: it used to overwrite whatever you
    /// had written there with the literal string "Rescheduled".
    static func reschedule(_ item: ScheduledWorkout, to date: Date, in context: ModelContext) throws {
        let origin = item.rescheduledFrom ?? item.scheduledStart
        item.scheduledStart = date

        if DateHelpers.isSameDay(origin, date) {
            item.rescheduledFrom = nil
            if item.status == .rescheduled {
                item.status = .upcoming
            }
        } else {
            item.rescheduledFrom = origin
            if item.status == .upcoming || item.status == .rescheduled {
                item.status = .rescheduled
            }
        }
        try context.save()
    }

    /// Puts a moved workout back where it started. No-op if it was never moved.
    static func undoReschedule(_ item: ScheduledWorkout, in context: ModelContext) throws {
        guard let origin = item.rescheduledFrom else { return }
        try reschedule(item, to: origin, in: context)
    }

    /// Brings a workout to today, keeping its time of day.
    static func moveToToday(_ item: ScheduledWorkout, in context: ModelContext, now: Date = .now) throws {
        let components = Calendar.current.dateComponents([.hour, .minute], from: item.scheduledStart)
        let target = DateHelpers.applying(hour: components.hour, minute: components.minute, to: now)
        try reschedule(item, to: target, in: context)
    }

    static func markSkipped(_ item: ScheduledWorkout, in context: ModelContext) throws {
        item.status = .skipped
        try context.save()
    }

    /// Takes a planned workout off the calendar entirely. Needed as an escape hatch
    /// for stray entries — a duplicate left behind by a move made before moves were
    /// tracked, say — which nothing else can clear.
    static func remove(_ item: ScheduledWorkout, in context: ModelContext) throws {
        context.delete(item)
        try context.save()
    }

    static func markCompleted(_ item: ScheduledWorkout, session: WorkoutSession, in context: ModelContext) throws {
        item.status = .completed
        item.completedSession = session
        try context.save()
    }

    static func syncUpcomingTimes(for template: WorkoutTemplate, in context: ModelContext) throws {
        let settings = try fetchSettings(in: context)
        let hour = template.preferredHour ?? settings?.preferredWorkoutHour
        let minute = template.preferredMinute ?? settings?.preferredWorkoutMinute
        let upcoming = try context.fetch(
            FetchDescriptor<ScheduledWorkout>(
                predicate: #Predicate { $0.statusRaw == "upcoming" }
            )
        )
        for item in upcoming where item.template?.id == template.id {
            item.scheduledStart = DateHelpers.applying(hour: hour, minute: minute, to: item.scheduledStart)
        }
        try context.save()
    }

    static func fetchSettings(in context: ModelContext) throws -> AppSettings? {
        try context.fetch(FetchDescriptor<AppSettings>()).first
    }

    private static func scheduleKey(templateID: UUID?, date: Date) -> String {
        let day = ISO8601DateFormatter.stringDay(from: date)
        return "\(templateID?.uuidString ?? "none")-\(day)"
    }
}

extension ISO8601DateFormatter {
    static func stringDay(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
