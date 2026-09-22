import Foundation
import SwiftData
import Testing
@testable import Fittr

/// `AppSettings.preferredWorkoutHour` drives the time of every seeded workout,
/// since none of them carry one of their own — and it was written once during
/// onboarding and never again. Settings can now change it, which is only useful
/// if the change reaches the eight weeks already on the calendar.
struct DefaultStartTimeTests {
    @Test func changingTheDefaultMovesWorkoutsAlreadyScheduled() throws {
        let context = try makeContext()
        let settings = makeSettings(hour: 7, in: context)
        let template = makeTemplate(preferredHour: nil, in: context)
        let item = makeScheduled(template: template, hour: 7, in: context)

        settings.preferredWorkoutHour = 18
        settings.preferredWorkoutMinute = 30
        try ScheduleService.syncUpcomingTimesToDefault(in: context)

        #expect(hourMinute(of: item.scheduledStart) == [18, 30])
    }

    /// A workout with its own time set in the template editor keeps it: the
    /// per-workout value is an override, not a copy of the default.
    @Test func aWorkoutWithItsOwnTimeIsNotOverwritten() throws {
        let context = try makeContext()
        let settings = makeSettings(hour: 7, in: context)
        let template = makeTemplate(preferredHour: 6, in: context)
        let item = makeScheduled(template: template, hour: 6, in: context)

        settings.preferredWorkoutHour = 18
        settings.preferredWorkoutMinute = 30
        try ScheduleService.syncUpcomingTimesToDefault(in: context)

        #expect(hourMinute(of: item.scheduledStart) == [6, 0])
    }

    /// Moving a workout you have already finished would rewrite history.
    @Test func completedWorkoutsAreLeftWhereTheyAre() throws {
        let context = try makeContext()
        let settings = makeSettings(hour: 7, in: context)
        let template = makeTemplate(preferredHour: nil, in: context)
        let item = makeScheduled(template: template, hour: 7, in: context)
        item.status = .completed

        settings.preferredWorkoutHour = 18
        try ScheduleService.syncUpcomingTimesToDefault(in: context)

        #expect(hourMinute(of: item.scheduledStart) == [7, 0])
    }

    /// Clearing the toggle falls back to the same midday default the scheduler
    /// uses everywhere else, rather than leaving a half-applied time.
    @Test func clearingTheDefaultFallsBackToMidday() throws {
        let context = try makeContext()
        let settings = makeSettings(hour: 7, in: context)
        let template = makeTemplate(preferredHour: nil, in: context)
        let item = makeScheduled(template: template, hour: 7, in: context)

        settings.preferredWorkoutHour = nil
        settings.preferredWorkoutMinute = nil
        try ScheduleService.syncUpcomingTimesToDefault(in: context)

        #expect(hourMinute(of: item.scheduledStart) == [12, 0])
    }

    /// The day must not drift when only the time of day changes.
    @Test func theScheduledDayIsUnchanged() throws {
        let context = try makeContext()
        let settings = makeSettings(hour: 7, in: context)
        let template = makeTemplate(preferredHour: nil, in: context)
        let item = makeScheduled(template: template, hour: 7, in: context)
        let day = DateHelpers.startOfDay(item.scheduledStart)

        settings.preferredWorkoutHour = 23
        try ScheduleService.syncUpcomingTimesToDefault(in: context)

        #expect(DateHelpers.startOfDay(item.scheduledStart) == day)
    }
}

private extension DefaultStartTimeTests {
    func makeContext() throws -> ModelContext {
        let container = try FittrSchema.container(inMemory: true)
        return ModelContext(container)
    }

    func makeSettings(hour: Int, in context: ModelContext) -> AppSettings {
        let settings = AppSettings(id: SeedID.settings)
        settings.preferredWorkoutHour = hour
        settings.preferredWorkoutMinute = 0
        context.insert(settings)
        return settings
    }

    func makeTemplate(preferredHour: Int?, in context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(
            id: SeedID.mondayStrength,
            name: "Full Body Strength",
            type: .strength,
            estimatedDurationMinutes: 40,
            weekday: .monday,
            preferredHour: preferredHour,
            preferredMinute: preferredHour == nil ? nil : 0
        )
        context.insert(template)
        return template
    }

    func makeScheduled(template: WorkoutTemplate, hour: Int, in context: ModelContext) -> ScheduledWorkout {
        let start = DateHelpers.applying(
            hour: hour,
            minute: 0,
            to: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let item = ScheduledWorkout(scheduledStart: start, template: template)
        context.insert(item)
        try? context.save()
        return item
    }

    func hourMinute(of date: Date) -> [Int] {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return [components.hour ?? -1, components.minute ?? -1]
    }
}
