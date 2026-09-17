import Foundation
import SwiftData
import Testing
@testable import Fittr

/// A single assigned track runs out long before a 30–40 minute cardio session does,
/// leaving silence for the rest of it. These cover assigning a whole playlist and
/// queueing every song in it.
@MainActor
struct MusicPlaylistTests {
    @Test func aPlaylistAssignmentQueuesEverySong() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.playlistSongs["ride"] = ["a", "b", "c"].map(track)
        assignPlaylist(id: "ride", songCount: 3, to: SeedID.indoorCycling, in: context)

        let controller = try makeController(music: music, in: context)
        try await settle(controller)

        #expect(music.queuedIDs == ["a", "b", "c"])
        #expect(music.didRepeat)
    }

    /// The point of the feature: what plays must outlast the session, so a playlist
    /// loops by default rather than stopping after its last song.
    @Test func playlistsRepeatByDefaultAndDoNotShuffle() throws {
        let assignment = MusicAssignment(
            scope: .exercise,
            musicItemID: "a",
            cachedTitle: "Ride",
            cachedArtist: "3 songs",
            playlistID: "ride"
        )
        #expect(assignment.isPlaylist)
        #expect(assignment.repeatPlaylist)
        #expect(assignment.shufflePlaylist == false)
    }

    @Test func aSingleTrackAssignmentIsNotTreatedAsAPlaylist() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("solo")]
        let assignment = MusicAssignment(
            scope: .exercise,
            musicItemID: "solo",
            cachedTitle: "Solo",
            cachedArtist: "Artist",
            exerciseId: SeedID.indoorCycling
        )
        #expect(assignment.isPlaylist == false)
        context.insert(assignment)
        try context.save()

        let controller = try makeController(music: music, in: context)
        try await settle(controller)

        #expect(music.queuedIDs == ["solo"])
        #expect(music.didRepeat == false)
    }

    /// A playlist emptied or deleted in the Music app should still play the song it
    /// was assigned from rather than falling silent.
    @Test func anEmptyPlaylistFallsBackToTheStoredTrack() async throws {
        let context = try makeContext()
        let music = MockMusicService()
        music.catalog = [track("a")]
        assignPlaylist(id: "gone", songCount: 0, to: SeedID.indoorCycling, in: context)

        let controller = try makeController(music: music, in: context)
        try await settle(controller)

        #expect(music.queuedIDs == ["a"])
    }
}

private extension MusicPlaylistTests {
    func makeContext() throws -> ModelContext {
        let container = try FittrSchema.container(inMemory: true)
        return ModelContext(container)
    }

    func track(_ id: String) -> MusicTrackInfo {
        MusicTrackInfo(id: id, title: "Song \(id)", artist: "Artist")
    }

    func assignPlaylist(id: String, songCount: Int, to exerciseId: UUID, in context: ModelContext) {
        context.insert(
            MusicAssignment(
                scope: .exercise,
                musicItemID: "a",
                cachedTitle: "Ride playlist",
                cachedArtist: "\(songCount) songs",
                playlistID: id,
                playlistName: "Ride playlist",
                exerciseId: exerciseId
            )
        )
        try? context.save()
    }

    /// Playback is kicked off from a `Task` during `init`, so give it a turn.
    func settle(_ controller: ActiveWorkoutController) async throws {
        _ = controller
        try await Task.sleep(for: .milliseconds(50))
    }

    func makeController(music: MockMusicService, in context: ModelContext) throws -> ActiveWorkoutController {
        let cycling = TemplateExerciseSnapshot(
            id: UUID(),
            exerciseId: SeedID.indoorCycling,
            exerciseName: "Indoor Cycling",
            category: .cardio,
            trackingMode: .distanceDuration,
            laterality: .bilateral,
            order: 0,
            targetSets: 1,
            minReps: nil,
            maxReps: nil,
            targetDurationSeconds: 2100,
            targetRestSeconds: 0,
            isOptional: false,
            equipment: .bike,
            slug: "indoor-cycling"
        )
        let snapshot = TemplateSnapshot(
            templateId: SeedID.tuesdayCardio,
            name: "Easy Cardio",
            type: .cardio,
            estimatedDurationMinutes: 35,
            notes: "",
            exercises: [cycling]
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
                exerciseId: cycling.exerciseId,
                exerciseName: cycling.exerciseName,
                order: 0,
                snapshotJSON: SnapshotCodec.encodeExercise(cycling),
                workout: session
            ),
        ]
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
}
