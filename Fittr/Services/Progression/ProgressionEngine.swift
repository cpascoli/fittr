import Foundation

struct ProgressionSuggestion: Equatable, Sendable {
    var exerciseId: UUID
    var exerciseName: String
    var lastWeightKg: Double
    /// The sets that earned the suggestion, left as numbers so the summary can
    /// show them in the lifter's units.
    var workingSets: [CompletedSetSummary]
    var suggestedWeightKg: Double
    var incrementKg: Double
    var reason: String
}

enum ProgressionEngine {
    /// Conservative: every prescribed set must reach the top of the rep range.
    /// If RIR was logged, the easiest set must still have at least 2 RIR.
    /// Suggestions never mutate stored weights.
    static func suggestion(
        exerciseId: UUID,
        exerciseName: String,
        targetMinReps: Int?,
        targetMaxReps: Int?,
        targetSets: Int,
        completedSets: [CompletedSetSummary],
        incrementKg: Double
    ) -> ProgressionSuggestion? {
        guard let targetMaxReps, targetMaxReps > 0 else { return nil }
        let working = completedSets.filter { $0.status == .completed && ($0.weightKg ?? 0) > 0 }
        guard working.count >= targetSets, !working.isEmpty else { return nil }
        guard working.allSatisfy({ ($0.reps ?? 0) >= targetMaxReps }) else { return nil }

        let rirValues = working.compactMap(\.rir)
        if !rirValues.isEmpty, (rirValues.min() ?? 0) < 2 {
            return nil
        }

        let lastWeight = working.compactMap(\.weightKg).max() ?? 0
        guard lastWeight > 0 else { return nil }
        let suggested = lastWeight + incrementKg

        return ProgressionSuggestion(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            lastWeightKg: lastWeight,
            workingSets: working.sorted { $0.setNumber < $1.setNumber },
            suggestedWeightKg: suggested,
            incrementKg: incrementKg,
            reason: "All \(targetSets) sets reached \(targetMaxReps) reps with room to spare. Consider a modest increase next time."
        )
    }

    static func suggestions(
        from session: WorkoutSessionSummary,
        incrementKg: Double
    ) -> [ProgressionSuggestion] {
        session.exercises.compactMap { exercise in
            ProgressionEngine.suggestion(
                exerciseId: exercise.exerciseId,
                exerciseName: exercise.exerciseName,
                targetMinReps: exercise.minReps,
                targetMaxReps: exercise.maxReps,
                targetSets: exercise.targetSets,
                completedSets: exercise.sets,
                incrementKg: incrementKg
            )
        }
    }
}

struct CompletedSetSummary: Equatable, Sendable {
    var setNumber: Int
    var weightKg: Double?
    var reps: Int?
    var rir: Double?
    var status: SetStatus
}

struct ExerciseSessionSummary: Equatable, Sendable {
    var exerciseId: UUID
    var exerciseName: String
    var minReps: Int?
    var maxReps: Int?
    var targetSets: Int
    var sets: [CompletedSetSummary]
}

struct WorkoutSessionSummary: Equatable, Sendable {
    var exercises: [ExerciseSessionSummary]
}

extension WorkoutSession {
    var progressionSummary: WorkoutSessionSummary {
        WorkoutSessionSummary(
            exercises: orderedExercises.map { exercise in
                ExerciseSessionSummary(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseName,
                    minReps: exercise.prescription?.minReps,
                    maxReps: exercise.prescription?.maxReps,
                    targetSets: exercise.prescription?.targetSets ?? exercise.completedSets.count,
                    sets: exercise.orderedSets.map {
                        CompletedSetSummary(
                            setNumber: $0.setNumber,
                            weightKg: $0.weightKg,
                            reps: $0.reps,
                            rir: $0.rir,
                            status: $0.status
                        )
                    }
                )
            }
        )
    }
}
