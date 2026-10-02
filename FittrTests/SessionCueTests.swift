import Foundation
import Testing
@testable import Fittr

struct SessionCueTests {
    private let squat = UUID()
    private let press = UUID()

    @Test func aLiftThatToppedItsRangeSaysTheNextWeightIsWaiting() throws {
        let cue = try #require(
            SessionCueBuilder.cue(
                lifts: [lift(id: squat, name: "Goblet Squat", reps: [12, 12, 12], weight: 20)],
                plannedWeightKg: [:],
                incrementKg: 2,
                formatWeight: format
            )
        )
        #expect(cue.readyToProgress)
        #expect(cue.exerciseName == "Goblet Squat")
        #expect(cue.headline == "Goblet Squat · 20 kg × 12 last time. 22 kg is waiting.")
    }

    @Test func anAcceptedPlanBeatsAFreshSuggestion() {
        let cue = SessionCueBuilder.cue(
            lifts: [lift(id: squat, name: "Goblet Squat", reps: [12, 12, 12], weight: 20)],
            plannedWeightKg: [squat: 24],
            incrementKg: 2,
            formatWeight: format
        )
        #expect(cue?.headline == "Goblet Squat · 24 kg is the plan.")
        #expect(cue?.readyToProgress == true)
    }

    @Test func aLiftStillInsideTheRangeShowsLastTime() {
        let cue = SessionCueBuilder.cue(
            lifts: [lift(id: squat, name: "Goblet Squat", reps: [8, 8, 8], weight: 20)],
            plannedWeightKg: [:],
            incrementKg: 2,
            formatWeight: format
        )
        #expect(cue?.readyToProgress == false)
        #expect(cue?.headline == "Last time · Goblet Squat 20 kg × 8")
    }

    /// The cue follows exercise order, and a later lift only speaks when nothing
    /// earlier has anything to say.
    @Test func theFirstLiftThatCanProgressWins() {
        let cue = SessionCueBuilder.cue(
            lifts: [
                lift(id: squat, name: "Goblet Squat", reps: [8, 8], weight: 20),
                lift(id: press, name: "Shoulder Press", reps: [12, 12], weight: 10, targetSets: 2),
            ],
            plannedWeightKg: [:],
            incrementKg: 2,
            formatWeight: format
        )
        #expect(cue?.exerciseId == press)
        #expect(cue?.headline == "Shoulder Press · 10 kg × 12 last time. 12 kg is waiting.")
    }

    private func format(_ kg: Double) -> String { "\(Int(kg)) kg" }

    private func lift(
        id: UUID,
        name: String,
        reps: [Int],
        weight: Double,
        targetSets: Int? = nil
    ) -> LiftSnapshot {
        LiftSnapshot(
            exerciseId: id,
            exerciseName: name,
            targetSets: targetSets ?? reps.count,
            maxReps: 12,
            sets: reps.enumerated().map { index, reps in
                CompletedSetSummary(
                    setNumber: index + 1,
                    weightKg: weight,
                    reps: reps,
                    rir: nil,
                    status: .completed
                )
            }
        )
    }
}
