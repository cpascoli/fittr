import Foundation
import SwiftData

enum WorkoutSessionDeletionService {
    /// Removes a workout and every derived effect so later sessions behave as if it never existed.
    static func delete(_ session: WorkoutSession, in context: ModelContext) throws {
        let sessionID = session.id
        let exerciseIDs = Set(session.exercises.map(\.exerciseId))
        let remainingSessions = ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? [])
            .filter { $0.id != sessionID }

        resetSchedule(for: session, sessionID: sessionID, in: context)
        deleteRecords(for: sessionID, in: context)
        clearPlannedLoads(
            exerciseIDs: exerciseIDs,
            deletedStartedAt: session.startedAt,
            remainingSessions: remainingSessions,
            in: context
        )

        context.delete(session)
        try context.save()
    }

    private static func resetSchedule(
        for session: WorkoutSession,
        sessionID: UUID,
        in context: ModelContext
    ) {
        var items: [ScheduledWorkout] = []
        if let scheduled = session.scheduled {
            items.append(scheduled)
        }
        let linked = ((try? context.fetch(FetchDescriptor<ScheduledWorkout>())) ?? [])
            .filter { $0.completedSession?.id == sessionID }
        items.append(contentsOf: linked)

        session.scheduled = nil

        var seen = Set<UUID>()
        for item in items where seen.insert(item.id).inserted {
            item.completedSession = nil
            // Re-derive rather than assume the day is now undone: another
            // finished session may still satisfy this slot.
            ScheduleService.refreshCompletion(for: item, in: context, excluding: sessionID)
        }
    }

    private static func deleteRecords(for sessionID: UUID, in context: ModelContext) {
        let records = ((try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? [])
            .filter { $0.workoutSessionId == sessionID }
        for record in records {
            context.delete(record)
        }
    }

    private static func clearPlannedLoads(
        exerciseIDs: Set<UUID>,
        deletedStartedAt: Date,
        remainingSessions: [WorkoutSession],
        in context: ModelContext
    ) {
        let loads = ((try? context.fetch(FetchDescriptor<PlannedExerciseLoad>())) ?? [])
            .filter { exerciseIDs.contains($0.exerciseId) }
        for load in loads {
            let laterSessionExists = remainingSessions.contains { other in
                other.endedAt != nil
                    && other.startedAt > deletedStartedAt
                    && other.exercises.contains { exercise in
                        exercise.exerciseId == load.exerciseId && !exercise.completedSets.isEmpty
                    }
            }
            if !laterSessionExists {
                context.delete(load)
            }
        }
    }
}
