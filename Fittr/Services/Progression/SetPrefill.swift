import Foundation

/// The numbers a set starts from. The rest card before an exercise and the
/// logger once it begins both read this, so the weight carried to the rack and
/// the weight on the first set cannot disagree.
struct SetPrefill: Equatable, Sendable {
    enum Basis: Equatable, Sendable {
        /// An earlier set of the same exercise in this session.
        case thisSession
        /// A load accepted on a previous summary.
        case planned
        /// The most recent session, of any workout, that logged this exercise.
        case lastTime
        /// No history at all: the library's starting weight.
        case starting
    }

    var weightKg: Double?
    var reps: Int?
    var leftReps: Int?
    var rightReps: Int?
    var basis: Basis?
}

enum SetPrefillResolver {
    /// - Parameters:
    ///   - setNumber: the set about to be logged.
    ///   - sessionSets: completed sets of this exercise already logged today. When
    ///     present they win, so resuming mid-exercise keeps today's edits instead
    ///     of snapping back to last time's numbers.
    ///   - plannedWeightKg: an accepted progression, which replaces last time's
    ///     weight but not its reps.
    ///   - previousSets: completed sets from the last time this exercise was done.
    static func resolve(
        setNumber: Int,
        sessionSets: [ExerciseSet],
        plannedWeightKg: Double?,
        previousSets: [ExerciseSet],
        startingWeightKg: Double?,
        maxReps: Int?
    ) -> SetPrefill {
        if let last = sessionSets.last {
            return SetPrefill(
                weightKg: last.weightKg,
                reps: last.leftReps == nil ? last.reps : nil,
                leftReps: last.leftReps,
                rightReps: last.rightReps,
                basis: .thisSession
            )
        }

        let matching = previousSets.first { $0.setNumber == setNumber } ?? previousSets.last
        let defaultReps = maxReps.flatMap { $0 > 0 ? min(10, $0) : nil }
        var reps = matching?.reps ?? defaultReps
        if plannedWeightKg != nil, let value = reps, let maxReps, maxReps > 0 {
            // A heavier load starts back inside the range, not above it.
            reps = min(value, maxReps)
        }
        let lastWeight = matching?.weightKg ?? previousSets.compactMap(\.weightKg).first

        let weight: Double?
        let basis: SetPrefill.Basis?
        if let plannedWeightKg {
            (weight, basis) = (plannedWeightKg, .planned)
        } else if let lastWeight {
            (weight, basis) = (lastWeight, .lastTime)
        } else if let startingWeightKg {
            (weight, basis) = (startingWeightKg, .starting)
        } else {
            (weight, basis) = (nil, nil)
        }

        return SetPrefill(
            weightKg: weight,
            reps: matching?.leftReps == nil ? reps : nil,
            leftReps: matching?.leftReps ?? reps,
            rightReps: matching?.rightReps ?? reps,
            basis: basis
        )
    }
}
