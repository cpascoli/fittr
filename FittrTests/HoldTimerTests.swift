import Foundation
import SwiftData
import Testing
@testable import Fittr

/// Covers the plank hold timer. `tick` is injected rather than slept on, so these
/// stay deterministic and fast.
@MainActor
struct HoldTimerTests {
    @Test func holdingTheFullTargetRecordsTheTarget() throws {
        let controller = try makeController()
        #expect(controller.usesDuration)
        #expect(controller.holdTargetSeconds == 30)
        #expect(controller.isHolding == false)

        controller.startHold()
        #expect(controller.isHolding)

        let started = try #require(controller.holdStartedAt)
        controller.tick = started.addingTimeInterval(30)
        #expect(controller.holdRemaining == 0)
        #expect(controller.holdProgress == 1)

        controller.stopHold()
        #expect(controller.isHolding == false)
        #expect(controller.measuredHoldSeconds == 30)
    }

    @Test func stoppingEarlyRecordsWhatWasActuallyHeld() throws {
        let controller = try makeController()
        controller.startHold()
        let started = try #require(controller.holdStartedAt)

        controller.tick = started.addingTimeInterval(22)
        controller.stopHold()

        #expect(controller.measuredHoldSeconds == 22)
        #expect(controller.holdIsFinished == false)
        #expect(controller.holdRemaining == 8)
    }

    @Test func completedSetLogsTheMeasuredHoldNotTheTarget() throws {
        let controller = try makeController()
        controller.startHold()
        let started = try #require(controller.holdStartedAt)
        controller.tick = started.addingTimeInterval(18)
        controller.stopHold()

        controller.completeSet()

        let set = try #require(controller.currentExercise?.completedSets.first)
        #expect(set.durationSeconds == 18)
        #expect(set.reps == nil)
        #expect(set.weightKg == nil)
    }

    @Test func withoutUsingTheTimerTheConfiguredTargetIsLogged() throws {
        let controller = try makeController()
        controller.draftDurationSeconds = 45

        controller.completeSet()

        let set = try #require(controller.currentExercise?.completedSets.first)
        #expect(set.durationSeconds == 45)
    }

    @Test func completingASetClearsTheTimerForTheNextOne() throws {
        let controller = try makeController()
        controller.startHold()
        let started = try #require(controller.holdStartedAt)
        controller.tick = started.addingTimeInterval(30)
        controller.stopHold()
        #expect(controller.measuredHoldSeconds == 30)

        controller.completeSet()

        #expect(controller.measuredHoldSeconds == nil)
        #expect(controller.isHolding == false)
        #expect(controller.holdIsFinished == false)
        #expect(controller.holdProgress == 0)
    }

    @Test func resetReturnsTheTimerToTheTarget() throws {
        let controller = try makeController()
        controller.startHold()
        let started = try #require(controller.holdStartedAt)
        controller.tick = started.addingTimeInterval(12)
        controller.stopHold()

        controller.resetHold()

        #expect(controller.measuredHoldSeconds == nil)
        #expect(controller.holdElapsed == 0)
        #expect(controller.holdRemaining == 30)
    }

    // MARK: - Fixture

    private func makeController() throws -> ActiveWorkoutController {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        let plank = TemplateExerciseSnapshot(
            id: UUID(),
            exerciseId: SeedID.plank,
            exerciseName: "Plank",
            category: .strength,
            trackingMode: .duration,
            laterality: .bilateral,
            order: 0,
            targetSets: 2,
            minReps: nil,
            maxReps: nil,
            targetDurationSeconds: 30,
            targetRestSeconds: 60,
            isOptional: false,
            equipment: .none,
            slug: "plank"
        )
        let session = WorkoutSession(
            name: "Full Body Strength",
            type: .strength,
            source: .manual,
            templateSnapshotJSON: SnapshotCodec.encode(
                TemplateSnapshot(
                    templateId: SeedID.mondayStrength,
                    name: "Full Body Strength",
                    type: .strength,
                    estimatedDurationMinutes: 40,
                    notes: "",
                    exercises: [plank]
                )
            ),
            workoutTemplateId: SeedID.mondayStrength
        )
        session.exercises = [
            ExerciseSession(
                exerciseId: plank.exerciseId,
                exerciseName: plank.exerciseName,
                order: 0,
                snapshotJSON: SnapshotCodec.encodeExercise(plank),
                workout: session
            ),
        ]
        context.insert(session)
        try context.save()

        return ActiveWorkoutController(
            session: session,
            modelContext: context,
            haptics: MockHapticService(),
            notifications: MockNotificationService(),
            music: MockMusicService(),
            settings: nil,
            profile: nil
        )
    }
}
