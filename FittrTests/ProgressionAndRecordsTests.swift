import Foundation
import SwiftData
import Testing
@testable import Fittr

struct ProgressionAndRecordsTests {
    @Test func progressionRequiresTopOfRangeOnAllSets() {
        let sets = [
            CompletedSetSummary(setNumber: 1, weightKg: 10, reps: 12, rir: 3, status: .completed),
            CompletedSetSummary(setNumber: 2, weightKg: 10, reps: 12, rir: 3, status: .completed),
        ]
        let suggestion = ProgressionEngine.suggestion(
            exerciseId: SeedID.gobletSquat,
            exerciseName: "Goblet Squat",
            targetMinReps: 8,
            targetMaxReps: 12,
            targetSets: 2,
            completedSets: sets,
            incrementKg: 2
        )
        #expect(suggestion?.suggestedWeightKg == 12)
    }

    @Test func progressionDoesNotFireWhenRepsStayInMiddleOfRange() {
        let sets = [
            CompletedSetSummary(setNumber: 1, weightKg: 10, reps: 10, rir: 3, status: .completed),
            CompletedSetSummary(setNumber: 2, weightKg: 10, reps: 11, rir: 3, status: .completed),
        ]
        let suggestion = ProgressionEngine.suggestion(
            exerciseId: SeedID.gobletSquat,
            exerciseName: "Goblet Squat",
            targetMinReps: 8,
            targetMaxReps: 12,
            targetSets: 2,
            completedSets: sets,
            incrementKg: 2
        )
        #expect(suggestion == nil)
    }

    @Test func snapshotSurvivesTemplateChange() {
        let original = TemplateExerciseSnapshot(
            id: UUID(),
            exerciseId: SeedID.gobletSquat,
            exerciseName: "Goblet Squat",
            category: .strength,
            trackingMode: .repsWeight,
            laterality: .bilateral,
            order: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 12,
            targetDurationSeconds: nil,
            targetRestSeconds: 90,
            isOptional: false,
            equipment: .dumbbell,
            slug: "goblet-squat"
        )
        let snapshot = TemplateSnapshot(
            templateId: SeedID.mondayStrength,
            name: "Full Body Strength",
            type: .strength,
            estimatedDurationMinutes: 40,
            notes: "",
            exercises: [original]
        )
        let json = SnapshotCodec.encode(snapshot)
        let decoded = SnapshotCodec.decode(json)
        #expect(decoded?.exercises.first?.targetSets == 2)
        #expect(decoded?.exercises.first?.maxReps == 12)
    }

    @Test func movingAverageIsSevenDayWindow() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let values = (0..<7).map { offset in
            DatedValue(date: Calendar.current.date(byAdding: .day, value: offset, to: day)!, value: Double(offset + 1))
        }
        let averages = WorkoutMath.movingAverage(values: values, windowDays: 7)
        #expect(averages.last != nil)
        #expect(averages.first?.value == 1)
    }

    @Test func adherencePercentage() {
        #expect(WorkoutMath.weeklyAdherence(planned: 4, completed: 3) == 0.75)
        #expect(WorkoutMath.weeklyAdherence(planned: 0, completed: 1) == 0)
    }

    @Test func acceptedProgressionPrefillsNextWeight() throws {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        PlannedLoadService.accept(exerciseId: SeedID.gobletSquat, weightKg: 12, in: context)
        #expect(PlannedLoadService.weight(for: SeedID.gobletSquat, in: context) == 12)
        PlannedLoadService.consume(exerciseId: SeedID.gobletSquat, in: context)
        #expect(PlannedLoadService.weight(for: SeedID.gobletSquat, in: context) == nil)
    }

    @Test @MainActor func lastSetRestsBeforeNextExerciseAndPausesMusic() throws {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        let first = exerciseSnapshot(id: SeedID.gobletSquat, name: "Goblet Squat", order: 0)
        let second = exerciseSnapshot(id: SeedID.romanianDeadlift, name: "Romanian Deadlift", order: 1)
        let snapshot = TemplateSnapshot(
            templateId: SeedID.mondayStrength,
            name: "Full Body Strength",
            type: .strength,
            estimatedDurationMinutes: 40,
            notes: "",
            exercises: [first, second]
        )
        let session = WorkoutSession(
            name: snapshot.name,
            type: snapshot.type,
            source: .manual,
            templateSnapshotJSON: SnapshotCodec.encode(snapshot),
            workoutTemplateId: snapshot.templateId
        )
        session.exercises = [
            ExerciseSession(
                exerciseId: first.exerciseId,
                exerciseName: first.exerciseName,
                order: 0,
                snapshotJSON: SnapshotCodec.encodeExercise(first),
                workout: session
            ),
            ExerciseSession(
                exerciseId: second.exerciseId,
                exerciseName: second.exerciseName,
                order: 1,
                snapshotJSON: SnapshotCodec.encodeExercise(second),
                workout: session
            ),
        ]
        context.insert(session)
        try context.save()

        let music = MockMusicService()
        music.isPlaying = true
        music.nowPlaying = MusicTrackInfo(id: "1", title: "Track", artist: "Artist")
        let controller = ActiveWorkoutController(
            session: session,
            modelContext: context,
            haptics: MockHapticService(),
            notifications: MockNotificationService(),
            music: music,
            settings: nil,
            profile: nil
        )

        controller.completeSet()
        #expect(controller.isResting)
        #expect(controller.isRestingBeforeNextExercise)
        #expect(controller.currentExerciseIndex == 0)
        #expect(controller.nextExerciseName == "Romanian Deadlift")
        #expect(music.isPlaying == false)

        controller.stopMusic()
        #expect(music.nowPlaying == nil)

        controller.startNextSet()
        #expect(controller.currentExerciseIndex == 1)
        #expect(controller.currentExercise?.exerciseName == "Romanian Deadlift")
        #expect(controller.isResting == false)
    }

    @Test @MainActor func secondPrescribedSetRestsThenAdvancesInsteadOfStartingSetThree() throws {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        let first = exerciseSnapshot(id: SeedID.gobletSquat, name: "Goblet Squat", order: 0, targetSets: 2)
        let second = exerciseSnapshot(id: SeedID.romanianDeadlift, name: "Romanian Deadlift", order: 1, targetSets: 2)
        let snapshot = TemplateSnapshot(
            templateId: SeedID.mondayStrength,
            name: "Full Body Strength",
            type: .strength,
            estimatedDurationMinutes: 40,
            notes: "",
            exercises: [first, second]
        )
        let session = WorkoutSession(
            name: snapshot.name,
            type: snapshot.type,
            source: .manual,
            templateSnapshotJSON: SnapshotCodec.encode(snapshot),
            workoutTemplateId: snapshot.templateId
        )
        session.exercises = [
            ExerciseSession(
                exerciseId: first.exerciseId,
                exerciseName: first.exerciseName,
                order: 0,
                snapshotJSON: SnapshotCodec.encodeExercise(first),
                workout: session
            ),
            ExerciseSession(
                exerciseId: second.exerciseId,
                exerciseName: second.exerciseName,
                order: 1,
                snapshotJSON: SnapshotCodec.encodeExercise(second),
                workout: session
            ),
        ]
        context.insert(session)
        try context.save()

        let controller = ActiveWorkoutController(
            session: session,
            modelContext: context,
            haptics: MockHapticService(),
            notifications: MockNotificationService(),
            music: MockMusicService(),
            settings: nil,
            profile: nil
        )

        controller.completeSet()
        #expect(controller.isResting)
        #expect(controller.isRestingBeforeNextExercise == false)
        #expect(controller.currentSetNumber == 2)

        controller.startNextSet()
        controller.completeSet()
        #expect(controller.isRestingBeforeNextExercise)
        #expect(controller.currentExerciseIndex == 0)
        #expect(controller.currentSetNumber == 3)

        controller.startNextSet()
        #expect(controller.currentExerciseIndex == 1)
        #expect(controller.currentExercise?.exerciseName == "Romanian Deadlift")
        #expect(controller.currentSetNumber == 1)
        #expect(controller.isResting == false)
    }

    private func exerciseSnapshot(id: UUID, name: String, order: Int, targetSets: Int = 1) -> TemplateExerciseSnapshot {
        TemplateExerciseSnapshot(
            id: UUID(),
            exerciseId: id,
            exerciseName: name,
            category: .strength,
            trackingMode: .repsWeight,
            laterality: .bilateral,
            order: order,
            targetSets: targetSets,
            minReps: 8,
            maxReps: 12,
            targetDurationSeconds: nil,
            targetRestSeconds: 90,
            isOptional: false,
            equipment: .dumbbell,
            slug: name
        )
    }
}
