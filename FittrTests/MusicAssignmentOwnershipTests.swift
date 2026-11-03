import Foundation
import SwiftData
import Testing
@testable import Fittr

/// An exercise's track applies in every workout and is found by exercise alone,
/// so a template must not own it: a template's assignments go when it does.
@MainActor
struct MusicAssignmentOwnershipTests {
    @Test func repairDetachesExerciseTracksFromTheirTemplate() throws {
        let context = try makeContext()
        let template = makeTemplate(in: context)
        let exerciseTrack = MusicAssignment(
            scope: .exercise,
            musicItemID: "squat-song",
            cachedTitle: "Squat",
            cachedArtist: "Artist",
            template: template,
            exerciseId: SeedID.gobletSquat
        )
        let workoutTrack = MusicAssignment(
            scope: .workout,
            musicItemID: "workout-song",
            cachedTitle: "Workout",
            cachedArtist: "Artist",
            template: template
        )
        context.insert(exerciseTrack)
        context.insert(workoutTrack)
        try context.save()

        let changed = try MusicAssignmentRepair.detachExerciseTracksFromTemplates(in: context)

        #expect(changed == 1)
        #expect(exerciseTrack.template == nil)
        #expect(workoutTrack.template?.id == template.id)
        #expect(try MusicAssignmentRepair.detachExerciseTracksFromTemplates(in: context) == 0)
    }

    @Test func deletingATemplateKeepsADetachedExerciseTrack() throws {
        let context = try makeContext()
        let template = makeTemplate(in: context)
        context.insert(
            MusicAssignment(
                scope: .exercise,
                musicItemID: "squat-song",
                cachedTitle: "Squat",
                cachedArtist: "Artist",
                template: template,
                exerciseId: SeedID.gobletSquat
            )
        )
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
        try MusicAssignmentRepair.detachExerciseTracksFromTemplates(in: context)

        context.delete(template)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<MusicAssignment>())
        #expect(remaining.map(\.musicItemID) == ["squat-song"])
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try FittrSchema.container(inMemory: true))
    }

    private func makeTemplate(in context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(
            id: SeedID.mondayStrength,
            name: "Full Body Strength",
            type: .strength,
            estimatedDurationMinutes: 40,
            weekday: .monday
        )
        context.insert(template)
        return template
    }
}
