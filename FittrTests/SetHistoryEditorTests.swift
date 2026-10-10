import Foundation
import SwiftData
import Testing
@testable import Fittr

/// Editing a finished workout from History: a timed set's duration is part of
/// the workout's, and a deleted set must not leave its time, its number or its
/// records behind.
@MainActor
struct SetHistoryEditorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aRideLoggedWithoutAStoredDurationIsTimedFromTheExerciseStart() throws {
        let context = try makeContext()
        let (_, ride) = makeCardio(minutes: 35, in: context)

        #expect(SetHistoryEditor.duration(of: ride) == TimeInterval(35 * 60))
    }

    @Test func lengtheningARideLengthensTheWorkout() throws {
        let context = try makeContext()
        let (session, ride) = makeCardio(minutes: 35, in: context)
        let before = session.elapsed()

        SetHistoryEditor.setDuration(45 * 60, for: ride, in: context)

        #expect(ride.durationSeconds == TimeInterval(45 * 60))
        #expect(session.elapsed() == before + 10 * 60)
        #expect(SetHistoryEditor.duration(of: ride) == TimeInterval(45 * 60))
    }

    @Test func shorteningARideShortensTheWorkout() throws {
        let context = try makeContext()
        let (session, ride) = makeCardio(minutes: 35, in: context)
        let before = session.elapsed()

        SetHistoryEditor.setDuration(20 * 60, for: ride, in: context)

        #expect(session.elapsed() == before - 15 * 60)
    }

    @Test func deletingATimedSetTakesItsTimeOutOfTheWorkout() throws {
        let context = try makeContext()
        let (session, ride) = makeCardio(minutes: 35, in: context)
        let exercise = try #require(ride.exercise)
        let before = session.elapsed()

        SetHistoryEditor.delete(ride, in: context)

        #expect(exercise.sets.isEmpty)
        #expect(exercise.status == .skipped)
        #expect(session.elapsed() == before - 35 * 60)
    }

    @Test func deletingAStrengthSetRenumbersAndLeavesTheClockAlone() throws {
        let context = try makeContext()
        let session = makeStrength(weights: [20, 22, 24], startedAt: start, in: context)
        let exercise = try #require(session.exercises.first)
        let before = session.elapsed()

        SetHistoryEditor.delete(exercise.orderedSets[0], in: context)

        #expect(exercise.orderedSets.map(\.setNumber) == [1, 2])
        #expect(exercise.orderedSets.map(\.weightKg) == [22, 24])
        #expect(exercise.status == .completed)
        #expect(session.elapsed() == before)
    }

    /// A mistyped 200 kg blocked every later session from a heaviest-weight
    /// record. Deleting it has to hand that record back to the session that
    /// actually earned it.
    @Test func deletingAMistypedSetReDerivesRecords() throws {
        let context = try makeContext()
        let first = makeStrength(weights: [20, 200], startedAt: start, in: context)
        let second = makeStrength(weights: [24], startedAt: start.addingTimeInterval(86_400), in: context)
        try PersonalRecordService.rebuildAll(in: context)
        #expect(try heaviest(in: context) == [200])

        let mistake = try #require(first.exercises.first?.orderedSets.last)
        SetHistoryEditor.delete(mistake, in: context)
        try PersonalRecordService.rebuildAll(in: context)

        let records = try context.fetch(FetchDescriptor<PersonalRecord>())
            .filter { $0.kind == .heaviestWeight }
        #expect(records.map(\.value).sorted() == [20, 24])
        #expect(records.contains { $0.workoutSessionId == second.id && $0.value == 24 })
    }
}

private extension SetHistoryEditorTests {
    func makeContext() throws -> ModelContext {
        ModelContext(try FittrSchema.container(inMemory: true))
    }

    func heaviest(in context: ModelContext) throws -> [Double] {
        try context.fetch(FetchDescriptor<PersonalRecord>())
            .filter { $0.kind == .heaviestWeight }
            .map(\.value)
            .sorted()
    }

    func makeCardio(minutes: Double, in context: ModelContext) -> (WorkoutSession, ExerciseSet) {
        let item = snapshot(id: SeedID.indoorCycling, name: "Indoor Cycling", mode: .distanceDuration)
        let session = makeSession(name: "Easy Cardio", type: .cardio, item: item, startedAt: start)
        let exercise = session.exercises[0]
        let finished = start.addingTimeInterval(minutes * 60)
        let ride = ExerciseSet(
            setNumber: 1,
            startedAt: start,
            completedAt: finished,
            status: .completed,
            laterality: .bilateral,
            exercise: exercise
        )
        exercise.sets = [ride]
        exercise.endedAt = finished.addingTimeInterval(5)
        session.endedAt = finished.addingTimeInterval(10)
        context.insert(session)
        try? context.save()
        return (session, ride)
    }

    func makeStrength(weights: [Double], startedAt: Date, in context: ModelContext) -> WorkoutSession {
        let item = snapshot(id: SeedID.gobletSquat, name: "Goblet Squat", mode: .repsWeight)
        let session = makeSession(name: "Full Body Strength", type: .strength, item: item, startedAt: startedAt)
        let exercise = session.exercises[0]
        exercise.sets = weights.enumerated().map { index, weight in
            ExerciseSet(
                setNumber: index + 1,
                weightKg: weight,
                reps: 10,
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(Double(index + 1) * 120),
                status: .completed,
                laterality: .bilateral,
                exercise: exercise
            )
        }
        session.endedAt = startedAt.addingTimeInterval(1800)
        context.insert(session)
        try? context.save()
        return session
    }

    func makeSession(
        name: String,
        type: WorkoutType,
        item: TemplateExerciseSnapshot,
        startedAt: Date
    ) -> WorkoutSession {
        let template = TemplateSnapshot(
            templateId: UUID(),
            name: name,
            type: type,
            estimatedDurationMinutes: 40,
            notes: "",
            exercises: [item]
        )
        let session = WorkoutSession(
            name: name,
            type: type,
            source: .manual,
            startedAt: startedAt,
            templateSnapshotJSON: SnapshotCodec.encode(template),
            workoutTemplateId: template.templateId
        )
        let exercise = ExerciseSession(
            exerciseId: item.exerciseId,
            exerciseName: item.exerciseName,
            order: 0,
            startedAt: startedAt,
            snapshotJSON: SnapshotCodec.encodeExercise(item),
            workout: session
        )
        exercise.status = .completed
        session.exercises = [exercise]
        return session
    }

    func snapshot(id: UUID, name: String, mode: TrackingMode) -> TemplateExerciseSnapshot {
        TemplateExerciseSnapshot(
            id: UUID(),
            exerciseId: id,
            exerciseName: name,
            category: mode == .repsWeight ? .strength : .cardio,
            trackingMode: mode,
            laterality: .bilateral,
            order: 0,
            targetSets: 1,
            minReps: mode == .repsWeight ? 8 : nil,
            maxReps: mode == .repsWeight ? 12 : nil,
            targetDurationSeconds: mode == .repsWeight ? nil : 2100,
            targetRestSeconds: 0,
            isOptional: false,
            equipment: .none,
            slug: name
        )
    }
}
