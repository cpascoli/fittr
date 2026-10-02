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

    /// The bug this guards: Monday and Thursday are separate templates with the
    /// same lifts. "Last time" was keyed on the template, so Thursday showed the
    /// previous Thursday's numbers and ignored what was lifted on Monday.
    @Test func lastTimeIsTheLatestSessionOfAnyTemplate() throws {
        let context = try makeContext()
        let controller = try makeController(
            in: context,
            previous: [
                .init(templateId: SeedID.mondayStrength, daysAgo: 7, weights: [20, 20], reps: 10),
                .init(templateId: SeedID.thursdayStrength, daysAgo: 3, weights: [24, 24], reps: 11),
            ]
        )

        controller.completeSet()

        let plan = try #require(controller.nextExercisePlan)
        #expect(plan.weightKg == 24)
        #expect(plan.reps == 11)
        #expect(plan.basis == .lastTime)
    }

    @Test func anExerciseSkippedLastTimeFallsBackToTheTimeBefore() throws {
        let context = try makeContext()
        let controller = try makeController(
            in: context,
            previous: [
                .init(templateId: SeedID.mondayStrength, daysAgo: 7, weights: [22], reps: 9),
                .init(templateId: SeedID.thursdayStrength, daysAgo: 3, weights: [], reps: 0),
            ]
        )

        controller.completeSet()

        let plan = try #require(controller.nextExercisePlan)
        #expect(plan.weightKg == 22)
        #expect(plan.reps == 9)
    }

    /// What the rest card promises is what the logger opens with.
    @Test func theRestCardAgreesWithTheLoggerOnWeightAndReps() throws {
        let context = try makeContext()
        let controller = try makeController(in: context, previousWeights: [24, 20], previousReps: 11)

        controller.completeSet()
        let plan = try #require(controller.nextExercisePlan)
        controller.startNextSet()

        #expect(controller.draftWeightKg == plan.weightKg)
        #expect(controller.draftReps == plan.reps)
    }

    @Test func anAcceptedProgressionReachesBothTheRestCardAndTheLogger() throws {
        let context = try makeContext()
        let controller = try makeController(in: context, previousWeights: [24, 24], previousReps: 14)
        PlannedLoadService.accept(exerciseId: SeedID.romanianDeadlift, weightKg: 26, in: context)

        controller.completeSet()
        let plan = try #require(controller.nextExercisePlan)
        controller.startNextSet()

        #expect(plan.weightKg == 26)
        #expect(plan.reps == 12, "a heavier load starts back inside the 8–12 range")
        #expect(controller.draftWeightKg == 26)
        #expect(controller.draftReps == 12)
    }

    /// What was edited and logged today is what the next session starts from.
    @Test func editedValuesBecomeNextSessionsStartingPoint() throws {
        let context = try makeContext()
        let today = try makeController(in: context, previousWeights: [20], previousReps: 10)
        today.completeSet()
        today.startNextSet()
        today.draftWeightKg = 27.5
        today.draftReps = 9
        today.completeSet()
        #expect(today.session.endedAt != nil)

        let nextTime = try makeController(in: context, startedAt: .now.addingTimeInterval(3600))
        nextTime.completeSet()
        let plan = try #require(nextTime.nextExercisePlan)

        #expect(plan.weightKg == 27.5)
        #expect(plan.reps == 9)
    }

    /// Reopening the app mid-exercise must not snap the logger back to last
    /// session's numbers after a set has already been logged differently today.
    @Test func resumingMidExerciseKeepsTodaysValues() throws {
        let context = try makeContext()
        let first = try makeController(in: context, previousWeights: [20, 20], previousReps: 10, secondTargetSets: 2)
        first.completeSet()
        first.startNextSet()
        first.draftWeightKg = 26
        first.draftReps = 8
        first.completeSet()

        let resumed = ActiveWorkoutController(
            session: first.session,
            modelContext: context,
            haptics: MockHapticService(),
            notifications: MockNotificationService(),
            music: MockMusicService(),
            settings: nil,
            profile: nil
        )

        #expect(resumed.currentExercise?.exerciseId == SeedID.romanianDeadlift)
        #expect(resumed.draftWeightKg == 26)
        #expect(resumed.draftReps == 8)
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

    struct PreviousSession {
        var templateId: UUID
        var daysAgo: Double
        var weights: [Double]
        var reps: Int
    }

    func makeController(
        in context: ModelContext,
        nextTrackingMode: TrackingMode = .repsWeight,
        previousWeights: [Double] = [],
        previousReps: Int = 10,
        previous: [PreviousSession] = [],
        secondTargetSets: Int = 1,
        startedAt: Date = .now
    ) throws -> ActiveWorkoutController {
        let first = snapshot(id: SeedID.gobletSquat, name: "Goblet Squat", order: 0)
        let second = snapshot(
            id: SeedID.romanianDeadlift,
            name: "Romanian Deadlift",
            order: 1,
            trackingMode: nextTrackingMode,
            targetSets: secondTargetSets
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
            insertPreviousSession(template: template, second: second, weights: previousWeights, reps: previousReps, in: context)
        }
        for item in previous {
            insertPreviousSession(
                template: template,
                second: second,
                weights: item.weights,
                reps: item.reps,
                templateId: item.templateId,
                daysAgo: item.daysAgo,
                in: context
            )
        }

        let session = WorkoutSession(
            name: template.name,
            type: template.type,
            source: .manual,
            templateSnapshotJSON: SnapshotCodec.encode(template),
            workoutTemplateId: template.templateId
        )
        session.startedAt = startedAt
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

        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? {
            let created = AppSettings(id: SeedID.settings)
            context.insert(created)
            return created
        }()
        settings.autoPlayExerciseTrack = false
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
        reps: Int,
        templateId: UUID? = nil,
        daysAgo: Double = 7,
        in context: ModelContext
    ) {
        let previous = WorkoutSession(
            name: template.name,
            type: template.type,
            source: .manual,
            templateSnapshotJSON: SnapshotCodec.encode(template),
            workoutTemplateId: templateId ?? template.templateId
        )
        previous.startedAt = .now.addingTimeInterval(-daysAgo * 24 * 3600)
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
                reps: reps,
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
        trackingMode: TrackingMode = .repsWeight,
        targetSets: Int = 1
    ) -> TemplateExerciseSnapshot {
        TemplateExerciseSnapshot(
            id: UUID(),
            exerciseId: id,
            exerciseName: name,
            category: .strength,
            trackingMode: trackingMode,
            laterality: .bilateral,
            order: order,
            targetSets: targetSets,
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
