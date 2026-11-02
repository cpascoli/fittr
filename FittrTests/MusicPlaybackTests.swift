import Foundation
import SwiftData
import Testing
@testable import Fittr

/// Covers §1.4: the new exercise's track used to be requested twice on every
/// advance — once by `activateCurrentIfNeeded` and once by `moveToNextExercise` —
/// and the two requests raced, which is how the previous exercise's song could
/// still be playing while the UI named the new one.
@MainActor
struct MusicPlaybackTests {
    @Test func advancingAnExerciseRequestsItsTrackExactlyOnce() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("squat-song"), track("deadlift-song")]
        assign(itemID: "squat-song", to: SeedID.gobletSquat, in: context)
        assign(itemID: "deadlift-song", to: SeedID.romanianDeadlift, in: context)

        let controller = try makeController(music: music, in: context)
        try await tick()
        #expect(music.playedIDs == ["squat-song"])

        controller.completeSet()
        controller.startNextSet()
        try await tick()

        #expect(controller.currentExercise?.exerciseId == SeedID.romanianDeadlift)
        #expect(music.playedIDs == ["squat-song", "deadlift-song"])
    }

    @Test func startingAWorkoutRequestsTheFirstTrackOnce() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("squat-song")]
        assign(itemID: "squat-song", to: SeedID.gobletSquat, in: context)

        _ = try makeController(music: music, in: context)
        try await tick()

        #expect(music.playedIDs == ["squat-song"])
    }

    /// An exercise with no track of its own falls through to the workout track.
    /// This is the case §1.1 broke every single time.
    @Test func anExerciseWithoutATrackFallsBackToTheWorkoutTrack() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("squat-song"), track("workout-song")]
        assign(itemID: "squat-song", to: SeedID.gobletSquat, in: context)
        let template = WorkoutTemplate(
            id: SeedID.mondayStrength,
            name: "Full Body Strength",
            type: .strength,
            estimatedDurationMinutes: 40,
            weekday: .monday
        )
        context.insert(template)
        context.insert(
            MusicAssignment(
                scope: .workout,
                musicItemID: "workout-song",
                cachedTitle: "Workout",
                cachedArtist: "Artist",
                template: template
            )
        )
        try context.save()

        let controller = try makeController(music: music, in: context)
        try await tick()
        controller.completeSet()
        controller.startNextSet()
        try await tick()

        #expect(music.playedIDs == ["squat-song", "workout-song"])
    }

    /// Rest between sets of the same exercise keeps the track going, and a single
    /// assigned song is set to restart when it ends. Silence starts only once the
    /// exercise is finished and the rest before the next one begins.
    @Test func musicContinuesThroughSetRestAndStopsBetweenExercises() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("squat-song"), track("deadlift-song")]
        assign(itemID: "squat-song", to: SeedID.gobletSquat, in: context)
        assign(itemID: "deadlift-song", to: SeedID.romanianDeadlift, in: context)

        let controller = try makeController(music: music, in: context, targetSets: 2)
        try await tick()
        #expect(music.isPlaying)
        #expect(music.loopsCurrentSong)
        #expect(music.playedIDs == ["squat-song"])

        controller.completeSet()
        #expect(controller.isResting)
        #expect(controller.isRestingBeforeNextExercise == false)
        #expect(music.isPlaying)
        #expect(music.playedIDs == ["squat-song"])

        controller.startNextSet()
        #expect(music.isPlaying)
        #expect(music.playedIDs == ["squat-song"])

        controller.completeSet()
        #expect(controller.isRestingBeforeNextExercise)
        #expect(music.isPlaying == false)

        controller.startNextSet()
        try await tick()
        #expect(controller.currentExercise?.exerciseId == SeedID.romanianDeadlift)
        #expect(music.isPlaying)
        #expect(music.playedIDs == ["squat-song", "deadlift-song"])
        #expect(music.loopsCurrentSong)
    }

    /// Choosing a track from the workout screen used to save it and do nothing
    /// else: the old song played on and the row kept naming it, so the choice looked
    /// lost until the next session.
    @Test func changingTheTrackMidExercisePlaysTheNewOneAtOnce() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("squat-song"), track("new-squat-song")]
        assign(itemID: "squat-song", to: SeedID.gobletSquat, in: context)

        let controller = try makeController(music: music, in: context)
        try await tick()
        #expect(music.playedIDs == ["squat-song"])

        assign(itemID: "new-squat-song", to: SeedID.gobletSquat, in: context)
        controller.assignedMusicDidChange()
        try await tick()

        #expect(music.playedIDs == ["squat-song", "new-squat-song"])
        #expect(music.nowPlaying?.id == "new-squat-song")
        #expect(music.isPlaying)
        #expect(controller.isMusicPlaying)
    }

    /// Picking a song is asking to hear it, even after Stop was pressed earlier.
    @Test func changingTheTrackAfterStoppingMusicStillPlaysIt() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("squat-song"), track("new-squat-song")]
        assign(itemID: "squat-song", to: SeedID.gobletSquat, in: context)

        let controller = try makeController(music: music, in: context)
        try await tick()
        controller.stopMusic()
        #expect(music.isPlaying == false)

        assign(itemID: "new-squat-song", to: SeedID.gobletSquat, in: context)
        controller.assignedMusicDidChange()
        try await tick()

        #expect(music.playedIDs == ["squat-song", "new-squat-song"])
        #expect(music.isPlaying)
    }

    /// Choosing a track replaces the old assignment rather than sitting beside it,
    /// and the next session of the same exercise starts with the new one.
    @Test func aTrackChosenMidWorkoutIsUsedByTheNextSession() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("squat-song"), track("new-squat-song")]
        assign(itemID: "squat-song", to: SeedID.gobletSquat, in: context)

        let controller = try makeController(music: music, in: context)
        try await tick()
        assign(itemID: "new-squat-song", to: SeedID.gobletSquat, in: context)
        controller.assignedMusicDidChange()
        try await tick()

        let stored = try context.fetch(FetchDescriptor<MusicAssignment>())
            .filter { $0.exerciseId == SeedID.gobletSquat }
        #expect(stored.map(\.musicItemID) == ["new-squat-song"])

        let nextMusic = MockMusicService()
        nextMusic.catalog = music.catalog
        _ = try makeController(music: nextMusic, in: context)
        try await tick()
        #expect(nextMusic.playedIDs == ["new-squat-song"])
    }
}

private extension MusicPlaybackTests {
    func makeContext() throws -> ModelContext {
        let container = try FittrSchema.container(inMemory: true)
        return ModelContext(container)
    }

    func track(_ id: String) -> MusicTrackInfo {
        MusicTrackInfo(id: id, title: "Song \(id)", artist: "Artist")
    }

    /// Mirrors the picker: one assignment per exercise, the newest replacing the old.
    func assign(itemID: String, to exerciseId: UUID, in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<MusicAssignment>())) ?? []
        for old in existing where old.exerciseId == exerciseId {
            context.delete(old)
        }
        context.insert(
            MusicAssignment(
                scope: .exercise,
                musicItemID: itemID,
                cachedTitle: itemID,
                cachedArtist: "Artist",
                exerciseId: exerciseId
            )
        )
        try? context.save()
    }

    /// Playback is kicked off from a `Task`, so let the main actor drain.
    func tick() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    func makeController(
        music: MockMusicService,
        in context: ModelContext,
        targetSets: Int = 1
    ) throws -> ActiveWorkoutController {
        let first = snapshot(id: SeedID.gobletSquat, name: "Goblet Squat", order: 0, targetSets: targetSets)
        let second = snapshot(id: SeedID.romanianDeadlift, name: "Romanian Deadlift", order: 1, targetSets: targetSets)
        let template = TemplateSnapshot(
            templateId: SeedID.mondayStrength,
            name: "Full Body Strength",
            type: .strength,
            estimatedDurationMinutes: 40,
            notes: "",
            exercises: [first, second]
        )
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
        settings.autoPlayExerciseTrack = true
        context.insert(settings)
        try context.save()

        return ActiveWorkoutController(
            session: session,
            modelContext: context,
            haptics: MockHapticService(),
            notifications: MockNotificationService(),
            music: music,
            settings: settings,
            profile: nil
        )
    }

    func snapshot(id: UUID, name: String, order: Int, targetSets: Int = 1) -> TemplateExerciseSnapshot {
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
