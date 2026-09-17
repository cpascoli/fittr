import Foundation
import SwiftData
import Testing
@testable import Fittr

/// Reported from the field: a real Easy Cardio session on Wed 15 Sept, then an
/// accidental second start that ran 39 seconds. Deleting the 39-second one from
/// History took the green tick off Wednesday and put the day back to "upcoming",
/// even though the real session was still in History.
///
/// The green tick, the weekly count and adherence all read `ScheduledWorkout
/// .status`, so a stale link there is the whole story — nothing cross-checks the
/// sessions that actually exist.
struct ScheduleCompletionTests {
    @Test func deletingAnAccidentalDuplicateLeavesTheDayCompleted() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let template = makeTemplate(in: context)
        let scheduled = ScheduledWorkout(scheduledStart: day, template: template)
        context.insert(scheduled)

        let real = makeSession(startedAt: day, seconds: 2_400, in: context)
        try ScheduleService.markCompleted(scheduled, session: real, in: context)

        let duplicate = makeSession(startedAt: day.addingTimeInterval(3_000), seconds: 39, in: context)
        try ScheduleService.markCompleted(scheduled, session: duplicate, in: context)

        try WorkoutSessionDeletionService.delete(duplicate, in: context)

        #expect(scheduled.status == .completed)
        #expect(scheduled.completedSession?.id == real.id)
    }

    /// The same misfire should not take over the row while both still exist.
    @Test func aThirtyNineSecondMisfireDoesNotRepresentTheDay() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let template = makeTemplate(in: context)
        let scheduled = ScheduledWorkout(scheduledStart: day, template: template)
        context.insert(scheduled)

        let real = makeSession(startedAt: day, seconds: 2_400, in: context)
        try ScheduleService.markCompleted(scheduled, session: real, in: context)
        let duplicate = makeSession(startedAt: day.addingTimeInterval(3_000), seconds: 39, in: context)
        try ScheduleService.markCompleted(scheduled, session: duplicate, in: context)

        #expect(scheduled.completedSession?.id == real.id)
    }

    /// Deleting the last finished session really does undo the day.
    @Test func deletingTheOnlySessionReturnsTheDayToUpcoming() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let template = makeTemplate(in: context)
        let scheduled = ScheduledWorkout(scheduledStart: day, template: template)
        context.insert(scheduled)

        let only = makeSession(startedAt: day, seconds: 2_400, in: context)
        try ScheduleService.markCompleted(scheduled, session: only, in: context)

        try WorkoutSessionDeletionService.delete(only, in: context)

        #expect(scheduled.status == .upcoming)
        #expect(scheduled.completedSession == nil)
    }

    /// A workout done a day late is linked explicitly, and day matching alone
    /// would throw that link away on the next delete elsewhere.
    @Test func aWorkoutDoneLateKeepsItsSlot() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let template = makeTemplate(in: context)
        let scheduled = ScheduledWorkout(scheduledStart: day, template: template)
        context.insert(scheduled)

        let late = makeSession(startedAt: day.addingTimeInterval(36 * 3_600), seconds: 2_400, in: context)
        try ScheduleService.markCompleted(scheduled, session: late, in: context)

        let unrelated = makeSession(startedAt: day.addingTimeInterval(-48 * 3_600), seconds: 1_200, in: context)
        try WorkoutSessionDeletionService.delete(unrelated, in: context)

        #expect(scheduled.status == .completed)
        #expect(scheduled.completedSession?.id == late.id)
    }

    /// The fix above only helps deletions made from now on. A day already left
    /// orphaned reads "upcoming" forever unless launch repairs it.
    @Test func launchRepairsADayLeftOrphanedByAnEarlierDelete() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let template = makeTemplate(in: context)
        let scheduled = ScheduledWorkout(scheduledStart: day, template: template)
        context.insert(scheduled)
        let real = makeSession(startedAt: day, seconds: 2_400, in: context)
        try context.save()

        try ScheduleService.reconcileCompletions(in: context)

        #expect(scheduled.status == .completed)
        #expect(scheduled.completedSession?.id == real.id)
    }

    /// Repair must never invent a completion for a day that was genuinely missed.
    @Test func launchRepairLeavesAGenuinelyMissedDayAlone() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let template = makeTemplate(in: context)
        let scheduled = ScheduledWorkout(scheduledStart: day, template: template)
        context.insert(scheduled)
        _ = makeSession(startedAt: day.addingTimeInterval(-7 * 24 * 3_600), seconds: 2_400, in: context)
        try context.save()

        try ScheduleService.reconcileCompletions(in: context)

        #expect(scheduled.status == .upcoming)
        #expect(scheduled.completedSession == nil)
    }

    /// Two slots must not both claim the same workout.
    @Test func launchRepairDoesNotLetTwoDaysShareOneSession() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let template = makeTemplate(in: context)
        let first = ScheduledWorkout(scheduledStart: day, template: template)
        let second = ScheduledWorkout(scheduledStart: day.addingTimeInterval(3_600), template: template)
        context.insert(first)
        context.insert(second)
        _ = makeSession(startedAt: day, seconds: 2_400, in: context)
        try context.save()

        try ScheduleService.reconcileCompletions(in: context)

        let completed = [first, second].filter { $0.status == .completed }
        #expect(completed.count == 1)
    }

    /// A completed day must not be able to claim a session from another week.
    @Test func aSessionFromAnotherDayDoesNotSatisfyTheSlot() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let template = makeTemplate(in: context)
        let scheduled = ScheduledWorkout(scheduledStart: day, template: template)
        context.insert(scheduled)

        let thisWeek = makeSession(startedAt: day, seconds: 2_400, in: context)
        try ScheduleService.markCompleted(scheduled, session: thisWeek, in: context)
        _ = makeSession(startedAt: day.addingTimeInterval(-7 * 24 * 3_600), seconds: 3_000, in: context)

        try WorkoutSessionDeletionService.delete(thisWeek, in: context)

        #expect(scheduled.status == .upcoming)
        #expect(scheduled.completedSession == nil)
    }
}

private extension ScheduleCompletionTests {
    func makeContext() throws -> ModelContext {
        let container = try FittrSchema.container(inMemory: true)
        return ModelContext(container)
    }

    func makeTemplate(in context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(
            id: SeedID.wednesdayRecovery,
            name: "Easy Cardio",
            type: .cardio,
            estimatedDurationMinutes: 40,
            weekday: .wednesday
        )
        context.insert(template)
        return template
    }

    func makeSession(startedAt: Date, seconds: TimeInterval, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(
            name: "Easy Cardio",
            type: .cardio,
            source: .manual,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(seconds),
            templateSnapshotJSON: SnapshotCodec.encode(
                TemplateSnapshot(
                    templateId: SeedID.wednesdayRecovery,
                    name: "Easy Cardio",
                    type: .cardio,
                    estimatedDurationMinutes: 40,
                    notes: "",
                    exercises: []
                )
            ),
            workoutTemplateId: SeedID.wednesdayRecovery
        )
        context.insert(session)
        try? context.save()
        return session
    }
}
