import Foundation

struct LiftSnapshot: Equatable, Sendable {
    var exerciseId: UUID
    var exerciseName: String
    var targetSets: Int
    var maxReps: Int?
    var sets: [CompletedSetSummary]
}

/// What Today, and the reminder, can say about the next session before it starts.
struct SessionCue: Equatable, Sendable {
    var exerciseId: UUID
    var exerciseName: String
    var headline: String
    /// True when the last session already earned a heavier load.
    var readyToProgress: Bool
}

enum SessionCueBuilder {
    /// Picks one lift to talk about. An accepted plan wins, then a lift that has
    /// earned the next increase, then the first lift that simply has a number
    /// from last time. Earlier exercises win ties, so the cue matches the order
    /// you will actually lift in.
    static func cue(
        lifts: [LiftSnapshot],
        plannedWeightKg: [UUID: Double],
        incrementKg: Double,
        formatWeight: (Double) -> String
    ) -> SessionCue? {
        var best: (rank: Int, index: Int, cue: SessionCue)?
        for (index, lift) in lifts.enumerated() {
            guard let candidate = candidate(
                for: lift,
                plannedWeightKg: plannedWeightKg[lift.exerciseId],
                incrementKg: incrementKg,
                formatWeight: formatWeight
            ) else { continue }
            if let best, (candidate.rank, index) >= (best.rank, best.index) { continue }
            best = (candidate.rank, index, candidate.cue)
        }
        return best?.cue
    }

    private static func candidate(
        for lift: LiftSnapshot,
        plannedWeightKg: Double?,
        incrementKg: Double,
        formatWeight: (Double) -> String
    ) -> (rank: Int, cue: SessionCue)? {
        if let plannedWeightKg, plannedWeightKg > 0 {
            return (
                0,
                SessionCue(
                    exerciseId: lift.exerciseId,
                    exerciseName: lift.exerciseName,
                    headline: "\(lift.exerciseName) · \(formatWeight(plannedWeightKg)) is the plan.",
                    readyToProgress: true
                )
            )
        }

        if let suggestion = ProgressionEngine.suggestion(
            exerciseId: lift.exerciseId,
            exerciseName: lift.exerciseName,
            targetMinReps: nil,
            targetMaxReps: lift.maxReps,
            targetSets: lift.targetSets,
            completedSets: lift.sets,
            incrementKg: incrementKg
        ) {
            let reps = reps(at: suggestion.lastWeightKg, in: lift.sets)
            let last = loadPhrase(formatWeight(suggestion.lastWeightKg), reps: reps)
            let next = formatWeight(suggestion.suggestedWeightKg)
            return (
                1,
                SessionCue(
                    exerciseId: lift.exerciseId,
                    exerciseName: lift.exerciseName,
                    headline: "\(lift.exerciseName) · \(last) last time. \(next) is waiting.",
                    readyToProgress: true
                )
            )
        }

        guard let heaviest = lift.sets
            .filter({ $0.status == .completed && ($0.weightKg ?? 0) > 0 })
            .max(by: { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }),
            let weight = heaviest.weightKg
        else { return nil }

        let phrase = loadPhrase(formatWeight(weight), reps: heaviest.reps)
        return (
            2,
            SessionCue(
                exerciseId: lift.exerciseId,
                exerciseName: lift.exerciseName,
                headline: "Last time · \(lift.exerciseName) \(phrase)",
                readyToProgress: false
            )
        )
    }

    private static func reps(at weight: Double, in sets: [CompletedSetSummary]) -> Int? {
        sets
            .filter { abs(($0.weightKg ?? 0) - weight) < 0.05 }
            .compactMap(\.reps)
            .max()
    }

    private static func loadPhrase(_ weight: String, reps: Int?) -> String {
        guard let reps, reps > 0 else { return weight }
        return "\(weight) × \(reps)"
    }
}
