import Foundation
import SwiftData
import Testing
@testable import Fittr

/// The rest screen named the next exercise but not its load, so the walk to the
/// rack happened before the number was visible. The plan has to agree with what
/// `prefillFromHistory` will put in the logger once the rest ends — a rest card
/// that says 20 kg and a logger that then says 22.5 kg is worse than silence.
@MainActor
struct NextExercisePlanTests {
    @Test func restBeforeTheNextExerciseCarriesItsTargetAndLoad() throws {
        let context = try makeContext()
        let controller = try makeController(in: context)

        controller.completeSet()

        let plan = try #require(controller.nextExercisePlan)
        #expect(controller.isRestingBeforeNextExercise)
        #expect(plan.name == "Romanian Deadlift")
        #expect(plan.targetLabel == "1 × 8–12")
        #expect(plan.equipmentLabel == "Dumbbell")
        #expect(plan.isPerSide == false)
    }

    @Test func anAcceptedProgressionWinsOverLastTime() throws {
        let context = try makeContext()
        PlannedLoadService.accept(exerciseId: SeedID.romanianDeadlift, weightKg: 32.5, in: context)
        let controller = try makeController(in: context)

        controller.completeSet()

        let plan = try #require(controller.nextExercisePlan)
        #expect(plan.weightKg == 32.5)
        #expect(plan.basis == .planned)
    }

    /// Without a planned load the number should be the one actually lifted last
    /// time, taken from the first set rather than the last: that is the weight
    /// to walk over and load.
    @Test func withoutAPlannedLoadTheWeightComesFromTheFirstSetLastTime() throws {
        let context = try makeContext()
        let controller = try makeController(in: context, previousWeights: [24, 20])

        controller.completeSet()

        let plan = try #require(controller.nextExercisePlan)
        #expect(plan.weightKg == 24)
        #expect(plan.basis == .lastTime)
    }

    @Test func anExerciseThatCarriesNoWeightShowsNoWeight() throws {
        let context = try makeContext()
        let controller = try makeController(in: context, nextTrackingMode: .duration)

        controller.completeSet()

        let plan = try #require(controller.nextExercisePlan)
        #expect(plan.weightKg == nil)
        #expect(plan.basis == nil)
    }

    /// Resolved once when the rest starts, then cleared on advance, because the
    /// lookup fetches every exercise definition and the card re-renders on tick.
    @Test func thePlanIsClearedOnceTheNextExerciseIsUnderWay() throws {
        let context = try makeContext()
        let controller = try makeController(in: context)

        controller.completeSet()
        #expect(controller.nextExercisePlan != nil)

        controller.startNextSet()
        #expect(controller.nextExercisePlan == nil)
        #expect(controller.currentExercise?.exerciseId == SeedID.romanianDeadlift)
    }
}

private extension NextExercisePlanTests {
    func makeContext() throws -> ModelContext {
        let container = try FittrSchema.container(inMemory: true)
        return ModelContext(container)
    }

    func makeController(
        in context: ModelContext,
        nextTrackingMode: TrackingMode = .repsWeight,
        previousWeights: [Double] = []
    ) throws -> ActiveWorkoutController {
        let first = snapshot(id: SeedID.gobletSquat, name: "Goblet Squat", order: 0)
        let second = snapshot(
            id: SeedID.romanianDeadlift,
            name: "Romanian Deadlift",
            order: 1,
            trackingMode: nextTrackingMode
        )
        let template = TemplateSnapshot(
            templateId: SeedID.mondayStrength,
            name: "Full Body Strength",
            type: .strength,
            estimatedDurationMinutes: 40,
            notes: "",
            exercises: [first, second]
        )
        if !previousWeights.isEmpty {
            insertPreviousSession(template: template, second: second, weights: previousWeights, in: context)
        }

        let session = WorkoutSession(
            name: template.name,
            type: template.type,
            source: .manual,
            templateSnapshotJSON: SnapshotCodec.encode(template),
            workoutTemplateId: template.templateId
        )
        session.exercises = [first, second].map { item in
            ExerciseSession(
                exerciseId: item.exerciseId,
                exerciseName: item.exerciseName,
                order: item.order,
                snapshotJSON: SnapshotCodec.encodeExercise(item),
                workout: session
            )
        }
        context.insert(session)

        let settings = AppSettings(id: SeedID.settings)
        settings.autoPlayExerciseTrack = false
        context.insert(settings)
        try context.save()

        return ActiveWorkoutController(
            session: session,
            modelContext: context,
            haptics: MockHapticService(),
            notifications: MockNotificationService(),
            music: MockMusicService(),
            settings: settings,
            profile: nil
        )
    }

    func insertPreviousSession(
        template: TemplateSnapshot,
        second: TemplateExerciseSnapshot,
        weights: [Double],
        in context: ModelContext
    ) {
        let previous = WorkoutSession(
            name: template.name,
            type: template.type,
            source: .manual,
            templateSnapshotJSON: SnapshotCodec.encode(template),
            workoutTemplateId: template.templateId
        )
        previous.startedAt = .now.addingTimeInterval(-7 * 24 * 3600)
        previous.endedAt = previous.startedAt.addingTimeInterval(3000)
        let exercise = ExerciseSession(
            exerciseId: second.exerciseId,
            exerciseName: second.exerciseName,
            order: second.order,
            snapshotJSON: SnapshotCodec.encodeExercise(second),
            workout: previous
        )
        exercise.sets = weights.enumerated().map { index, weight in
            ExerciseSet(
                setNumber: index + 1,
                weightKg: weight,
                reps: 10,
                status: .completed,
                laterality: .bilateral,
                exercise: exercise
            )
        }
        previous.exercises = [exercise]
        context.insert(previous)
        try? context.save()
    }

    func snapshot(
        id: UUID,
        name: String,
        order: Int,
        trackingMode: TrackingMode = .repsWeight
    ) -> TemplateExerciseSnapshot {
        TemplateExerciseSnapshot(
            id: UUID(),
            exerciseId: id,
            exerciseName: name,
            category: .strength,
            trackingMode: trackingMode,
            laterality: .bilateral,
            order: order,
            targetSets: 1,
            minReps: 8,
            maxReps: 12,
            targetDurationSeconds: trackingMode == .duration ? 45 : nil,
            targetRestSeconds: 90,
            isOptional: false,
            equipment: .dumbbell,
            slug: name
        )
    }
}
