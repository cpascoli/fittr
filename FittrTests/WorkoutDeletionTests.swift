import Foundation
import SwiftData
import Testing
@testable import Fittr

struct WorkoutDeletionTests {
    @Test func deleteRemovesSessionRecordsPlannedLoadAndResetsSchedule() throws {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = makeCompletedSession(
            startedAt: startedAt,
            weightKg: 12,
            in: context
        )
        let scheduled = ScheduledWorkout(
            scheduledStart: startedAt,
            status: .completed,
            completedSession: session
        )
        session.scheduled = scheduled
        context.insert(scheduled)
        PlannedLoadService.accept(exerciseId: SeedID.gobletSquat, weightKg: 14, in: context)
        try PersonalRecordService.evaluate(session: session, in: context)
        try context.save()

        try WorkoutSessionDeletionService.delete(session, in: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let records = try context.fetch(FetchDescriptor<PersonalRecord>())
        let loads = try context.fetch(FetchDescriptor<PlannedExerciseLoad>())
        let leftoverSets = try context.fetch(FetchDescriptor<ExerciseSet>())
        let leftoverScheduled = try context.fetch(FetchDescriptor<ScheduledWorkout>())

        #expect(sessions.isEmpty)
        #expect(records.isEmpty)
        #expect(loads.isEmpty)
        #expect(leftoverSets.isEmpty)
        #expect(leftoverScheduled.count == 1)
        #expect(leftoverScheduled[0].status == .upcoming)
        #expect(leftoverScheduled[0].completedSession == nil)
    }

    @Test func deleteLeavesOlderWorkoutAndItsRecords() throws {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        let older = makeCompletedSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            weightKg: 10,
            in: context
        )
        let newer = makeCompletedSession(
            startedAt: Date(timeIntervalSince1970: 1_700_100_000),
            weightKg: 14,
            in: context
        )
        try PersonalRecordService.evaluate(session: older, in: context)
        try PersonalRecordService.evaluate(session: newer, in: context)

        try WorkoutSessionDeletionService.delete(newer, in: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let records = try context.fetch(FetchDescriptor<PersonalRecord>())
        #expect(sessions.map(\.id) == [older.id])
        #expect(records.allSatisfy { $0.workoutSessionId == older.id })
        #expect(!records.isEmpty)
    }

    @Test func deleteDoesNotClearPlannedLoadOwnedByALaterSession() throws {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        let older = makeCompletedSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            weightKg: 10,
            in: context
        )
        _ = makeCompletedSession(
            startedAt: Date(timeIntervalSince1970: 1_700_100_000),
            weightKg: 12,
            in: context
        )
        PlannedLoadService.accept(exerciseId: SeedID.gobletSquat, weightKg: 14, in: context)

        try WorkoutSessionDeletionService.delete(older, in: context)

        #expect(PlannedLoadService.weight(for: SeedID.gobletSquat, in: context) == 14)
    }

    private func makeCompletedSession(
        startedAt: Date,
        weightKg: Double,
        in context: ModelContext
    ) -> WorkoutSession {
        let snapshot = TemplateExerciseSnapshot(
            id: UUID(),
            exerciseId: SeedID.gobletSquat,
            exerciseName: "Goblet Squat",
            category: .strength,
            trackingMode: .repsWeight,
            laterality: .bilateral,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 12,
            targetDurationSeconds: nil,
            targetRestSeconds: 90,
            isOptional: false,
            equipment: .dumbbell,
            slug: "goblet-squat"
        )
        let session = WorkoutSession(
            name: "Full Body Strength",
            type: .strength,
            source: .manual,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(2_400),
            templateSnapshotJSON: SnapshotCodec.encode(
                TemplateSnapshot(
                    templateId: SeedID.mondayStrength,
                    name: "Full Body Strength",
                    type: .strength,
                    estimatedDurationMinutes: 40,
                    notes: "",
                    exercises: [snapshot]
                )
            ),
            workoutTemplateId: SeedID.mondayStrength
        )
        let exercise = ExerciseSession(
            exerciseId: snapshot.exerciseId,
            exerciseName: snapshot.exerciseName,
            order: 0,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            status: .completed,
            snapshotJSON: SnapshotCodec.encodeExercise(snapshot),
            workout: session
        )
        exercise.sets = [
            ExerciseSet(
                setNumber: 1,
                weightKg: weightKg,
                reps: 12,
                completedAt: startedAt.addingTimeInterval(40),
                status: .completed,
                exercise: exercise
            ),
        ]
        session.exercises = [exercise]
        context.insert(session)
        return session
    }
}
