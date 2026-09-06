import Foundation
import SwiftData

enum ScheduleService {
    static let horizonWeeks = 8

    static func ensureUpcomingSchedule(in context: ModelContext, now: Date = .now) throws {
        let settings = try fetchSettings(in: context)
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        guard !templates.isEmpty else { return }

        let existing = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let existingKeys = Set(existing.map { scheduleKey(templateID: $0.template?.id, date: $0.scheduledStart) })

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

    static func scheduled(on day: Date, in context: ModelContext) throws -> ScheduledWorkout? {
        let start = DateHelpers.startOfDay(day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        let descriptor = FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { item in
                item.scheduledStart >= start && item.scheduledStart < end
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        return try context.fetch(descriptor).first
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

    static func reschedule(_ item: ScheduledWorkout, to date: Date, in context: ModelContext) throws {
        item.scheduledStart = date
        if item.status == .upcoming || item.status == .rescheduled {
            item.status = .rescheduled
        }
        item.notes = "Rescheduled"
        try context.save()
    }

    static func markSkipped(_ item: ScheduledWorkout, in context: ModelContext) throws {
        item.status = .skipped
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
