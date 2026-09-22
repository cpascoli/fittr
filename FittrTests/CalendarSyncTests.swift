import Foundation
import SwiftData
import Testing
@testable import Fittr

/// Reported from the field: duplicated workout events in Apple Calendar.
///
/// The old sync ran only from the "Connect Calendar" button and relied on
/// `store.event(withIdentifier:)` to find the event it had written before — a
/// read, while the app asked for write-only access. That branch could never
/// match, so every run created a fresh copy of every upcoming workout.
///
/// `MockCalendarService` now mirrors EventKit's identity rules: an identifier
/// that is not in the store cannot be updated. Without that these tests would
/// pass against the broken code.
@MainActor
struct CalendarSyncTests {
    @Test func syncingTwiceDoesNotDuplicateEvents() async throws {
        let context = try seededContext()
        let calendar = try enableSync(in: context)

        await CalendarSyncService.reconcile(in: context)
        let afterFirst = calendar.events.count
        await CalendarSyncService.reconcile(in: context)

        #expect(afterFirst > 0)
        #expect(calendar.events.count == afterFirst)
        #expect(calendar.createdCount == afterFirst)
    }

    /// The question that prompted this: moving a workout should move its event,
    /// not leave the old one behind.
    @Test func reschedulingMovesTheEventInsteadOfAddingOne() async throws {
        let context = try seededContext()
        let calendar = try enableSync(in: context)
        await CalendarSyncService.reconcile(in: context)
        let before = calendar.events.count

        let item = try #require(upcomingTrainable(in: context).first)
        let target = try #require(Calendar.current.date(byAdding: .day, value: 1, to: item.scheduledStart))
        try ScheduleService.reschedule(item, to: target, in: context)
        await CalendarSyncService.reconcile(in: context)

        #expect(calendar.events.count == before)
        let event = try #require(calendar.events[item.calendarEventIdentifier])
        #expect(event.start == target)
    }

    @Test func skippingAWorkoutRemovesItsEvent() async throws {
        let context = try seededContext()
        let calendar = try enableSync(in: context)
        await CalendarSyncService.reconcile(in: context)
        let before = calendar.events.count

        let item = try #require(upcomingTrainable(in: context).first)
        try ScheduleService.markSkipped(item, in: context)
        await CalendarSyncService.reconcile(in: context)

        #expect(calendar.events.count == before - 1)
        #expect(item.calendarEventIdentifier.isEmpty)
    }

    /// Removing a day used to orphan its event permanently: `removeEvent` was
    /// never called anywhere in the app, and the identifier went with the row.
    @Test func removingAScheduledWorkoutRemovesItsEvent() async throws {
        let context = try seededContext()
        let calendar = try enableSync(in: context)
        await CalendarSyncService.reconcile(in: context)
        let before = calendar.events.count

        let item = try #require(upcomingTrainable(in: context).first)
        await CalendarSyncService.removeEvent(for: item, in: context)
        try ScheduleService.remove(item, in: context)
        await CalendarSyncService.reconcile(in: context)

        #expect(calendar.events.count == before - 1)
    }

    /// A rest day is not an appointment.
    @Test func restDaysDoNotGetEvents() async throws {
        let context = try seededContext()
        let calendar = try enableSync(in: context)

        await CalendarSyncService.reconcile(in: context)

        let restCount = (try context.fetch(FetchDescriptor<ScheduledWorkout>()))
            .filter { $0.template?.type.isTrainable == false }
            .count
        #expect(restCount > 0)
        #expect(calendar.events.count == upcomingTrainable(in: context).count)
    }

    @Test func nothingIsWrittenWhileSyncIsOff() async throws {
        let context = try seededContext()
        let calendar = MockCalendarService()
        FittrDependencies.shared.calendar = calendar

        await CalendarSyncService.reconcile(in: context)

        #expect(calendar.events.isEmpty)
    }

    @Test func removeAllClearsEveryEventAndItsStoredIdentifier() async throws {
        let context = try seededContext()
        let calendar = try enableSync(in: context)
        await CalendarSyncService.reconcile(in: context)
        #expect(!calendar.events.isEmpty)

        let removed = await CalendarSyncService.removeAllEvents(in: context)

        #expect(removed > 0)
        #expect(calendar.events.isEmpty)
        let identifiers = (try context.fetch(FetchDescriptor<ScheduledWorkout>()))
            .map(\.calendarEventIdentifier)
        #expect(identifiers.allSatisfy { $0.isEmpty })
    }
}

private extension CalendarSyncTests {
    func seededContext() throws -> ModelContext {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        try SeedService.seedIfNeeded(in: context)
        return context
    }

    func enableSync(in context: ModelContext) throws -> MockCalendarService {
        let calendar = MockCalendarService()
        FittrDependencies.shared.calendar = calendar
        let settings = try #require(try ScheduleService.fetchSettings(in: context))
        settings.calendarSyncEnabled = true
        try context.save()
        return calendar
    }

    func upcomingTrainable(in context: ModelContext) -> [ScheduledWorkout] {
        ((try? context.fetch(FetchDescriptor<ScheduledWorkout>())) ?? [])
            .filter { $0.template?.type.isTrainable == true }
            .filter { $0.status == .upcoming || $0.status == .rescheduled }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }
}
