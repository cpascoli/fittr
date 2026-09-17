import Foundation
import SwiftData
import Testing
@testable import Fittr

/// Covers the 16 September incident: tapping "Tomorrow" moved a workout onto a day
/// that already had one, and because every surface rendered a single item per day
/// the moved workout became invisible — and so could not be moved back, skipped or
/// removed, since all of those live on its row.
struct ScheduleReschedulingTests {
    @Test func movingOntoAnOccupiedDayKeepsBothWorkoutsReachable() throws {
        let context = try seededContext()
        let (thursday, friday) = try twoAdjacentDays(in: context)
        let strength = try #require(try firstItem(on: thursday, in: context))

        try ScheduleService.reschedule(strength, to: dayAfter(strength.scheduledStart), in: context)

        let onFriday = try ScheduleService.items(on: friday, in: context)
        #expect(onFriday.count == 2)
        #expect(onFriday.contains { $0.id == strength.id })
    }

    @Test func undoReturnsTheWorkoutToTheDayItCameFrom() throws {
        let context = try seededContext()
        let (thursday, _) = try twoAdjacentDays(in: context)
        let strength = try #require(try firstItem(on: thursday, in: context))
        let original = strength.scheduledStart

        try ScheduleService.reschedule(strength, to: dayAfter(original), in: context)
        #expect(strength.status == .rescheduled)
        #expect(strength.rescheduledFrom == original)

        try ScheduleService.undoReschedule(strength, in: context)

        #expect(strength.scheduledStart == original)
        #expect(strength.rescheduledFrom == nil)
        #expect(strength.status == .upcoming)
    }

    /// After Thu → Fri → Sat, undo goes back to Thursday. Stepping back one day at
    /// a time would strand the workout on Friday, which nobody asked for.
    @Test func undoSurvivesRepeatedMoves() throws {
        let context = try seededContext()
        let (thursday, _) = try twoAdjacentDays(in: context)
        let strength = try #require(try firstItem(on: thursday, in: context))
        let original = strength.scheduledStart

        try ScheduleService.reschedule(strength, to: dayAfter(original), in: context)
        try ScheduleService.reschedule(strength, to: dayAfter(dayAfter(original)), in: context)
        try ScheduleService.undoReschedule(strength, in: context)

        #expect(strength.scheduledStart == original)
    }

    @Test func movingBackOntoTheOriginalDayClearsTheRescheduledFlag() throws {
        let context = try seededContext()
        let (thursday, _) = try twoAdjacentDays(in: context)
        let strength = try #require(try firstItem(on: thursday, in: context))
        let original = strength.scheduledStart

        try ScheduleService.reschedule(strength, to: dayAfter(original), in: context)
        try ScheduleService.reschedule(strength, to: original, in: context)

        #expect(strength.status == .upcoming)
        #expect(strength.rescheduledFrom == nil)
    }

    @Test func rescheduleLeavesUserNotesAlone() throws {
        let context = try seededContext()
        let (thursday, _) = try twoAdjacentDays(in: context)
        let strength = try #require(try firstItem(on: thursday, in: context))
        strength.notes = "Bring the lifting belt"

        try ScheduleService.reschedule(strength, to: dayAfter(strength.scheduledStart), in: context)

        #expect(strength.notes == "Bring the lifting belt")
    }

    /// The launch backfill used to see the vacated day as missing and recreate the
    /// workout there, leaving a duplicate the user never asked for.
    @Test func backfillDoesNotRefillADayAWorkoutWasMovedOffOf() throws {
        let context = try seededContext()
        let (thursday, _) = try twoAdjacentDays(in: context)
        let strength = try #require(try firstItem(on: thursday, in: context))
        let templateID = try #require(strength.template?.id)

        try ScheduleService.reschedule(strength, to: dayAfter(strength.scheduledStart), in: context)
        try ScheduleService.ensureUpcomingSchedule(in: context)

        let sameTemplateThisWeek = try ScheduleService.weekItems(containing: .now, in: context)
            .filter { $0.template?.id == templateID }
        #expect(sameTemplateThisWeek.count == 1)
        #expect(try firstItem(on: thursday, in: context) == nil)
    }

    @Test func moveToTodayBringsAWorkoutForwardKeepingItsTime() throws {
        let context = try seededContext()
        let (thursday, _) = try twoAdjacentDays(in: context)
        let strength = try #require(try firstItem(on: thursday, in: context))
        try ScheduleService.reschedule(strength, to: dayAfter(strength.scheduledStart), in: context)
        let hour = Calendar.current.component(.hour, from: strength.scheduledStart)

        try ScheduleService.moveToToday(strength, in: context)

        #expect(DateHelpers.isSameDay(strength.scheduledStart, .now))
        #expect(Calendar.current.component(.hour, from: strength.scheduledStart) == hour)
    }

    @Test func aWorkoutCanBePutOnAnEmptyDay() throws {
        let context = try seededContext()
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let template = try #require(templates.first)
        // The seeded plan covers every weekday, so vacate one the way a user would.
        let emptyDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        for item in try ScheduleService.items(on: emptyDay, in: context) {
            try ScheduleService.remove(item, in: context)
        }
        #expect(try ScheduleService.items(on: emptyDay, in: context).isEmpty)

        try ScheduleService.schedule(template: template, on: emptyDay, in: context)

        let items = try ScheduleService.items(on: emptyDay, in: context)
        #expect(items.count == 1)
        #expect(items.first?.template?.id == template.id)
    }

    @Test func removeTakesAStrayWorkoutOffTheCalendar() throws {
        let context = try seededContext()
        let (thursday, _) = try twoAdjacentDays(in: context)
        let strength = try #require(try firstItem(on: thursday, in: context))

        try ScheduleService.remove(strength, in: context)

        #expect(try firstItem(on: thursday, in: context) == nil)
    }
}

private extension ScheduleReschedulingTests {
    func seededContext() throws -> ModelContext {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        try SeedService.seedIfNeeded(in: context)
        return context
    }

    /// The first upcoming day this week that already has a workout, plus the day
    /// after it. Picking these by inspection rather than by weekday name keeps the
    /// tests from depending on which day they happen to run.
    func twoAdjacentDays(in context: ModelContext) throws -> (Date, Date) {
        let candidates = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
        for day in candidates {
            let next = try #require(Calendar.current.date(byAdding: .day, value: 1, to: day))
            let hasOne = try !ScheduleService.items(on: day, in: context).isEmpty
            let nextHasOne = try !ScheduleService.items(on: next, in: context).isEmpty
            if hasOne && nextHasOne { return (day, next) }
        }
        Issue.record("The seeded plan should contain two consecutive scheduled days")
        return (.now, .now)
    }

    func firstItem(on day: Date, in context: ModelContext) throws -> ScheduledWorkout? {
        try ScheduleService.items(on: day, in: context).first
    }

    func dayAfter(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }
}
