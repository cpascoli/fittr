import Foundation
import SwiftData

/// Corrections to a finished workout's sets from History.
///
/// A workout's duration is its start-to-end span, so a timed set — a ride, a
/// swim, a hold — cannot change length on its own: everything logged after it
/// moves with it. Lengthening a 35-minute ride to 45 pushes the workout's end
/// out by ten minutes; deleting it takes its time out of the workout.
/// Strength sets carry no duration, so deleting one leaves the clock alone.
enum SetHistoryEditor {
    static func isTimed(_ set: ExerciseSet) -> Bool {
        set.durationSeconds != nil || (set.exercise?.prescription?.trackingMode.usesDuration ?? false)
    }

    /// The stored duration, or — for rides and swims, which are timed from the
    /// clock rather than a counter — the span since the previous set finished,
    /// or since the exercise began for the first one.
    static func duration(of set: ExerciseSet) -> TimeInterval? {
        if let stored = set.durationSeconds { return stored }
        guard isTimed(set), let end = set.completedAt else { return nil }
        let start = previousCompletion(before: set) ?? set.exercise?.startedAt ?? set.startedAt
        guard let start else { return nil }
        return max(0, end.timeIntervalSince(start))
    }

    static func setDuration(_ seconds: TimeInterval, for set: ExerciseSet, in context: ModelContext) {
        let updated = max(0, seconds.rounded())
        let current = duration(of: set) ?? 0
        set.durationSeconds = updated
        shiftTimeline(from: set, by: updated - current)
        try? context.save()
    }

    static func delete(_ set: ExerciseSet, in context: ModelContext) {
        if isTimed(set), let removed = duration(of: set) {
            shiftTimeline(from: set, by: -removed)
        }
        let exercise = set.exercise
        exercise?.sets.removeAll { $0.id == set.id }
        context.delete(set)
        if let exercise {
            // Keep "Set 1, Set 2…" contiguous so set-matched prefills still line up.
            for (index, remaining) in exercise.orderedSets.enumerated() {
                remaining.setNumber = index + 1
            }
            if exercise.completedSets.isEmpty, exercise.status == .completed {
                exercise.status = .skipped
            }
        }
        try? context.save()
    }

    private static func previousCompletion(before set: ExerciseSet) -> Date? {
        set.exercise?.orderedSets
            .filter { $0.setNumber < set.setNumber && $0.status == .completed }
            .compactMap(\.completedAt)
            .max()
    }

    /// Moves every timestamp from the set's completion onwards by `delta`. The
    /// set's own start stays put, so only its end — and what followed — moves.
    private static func shiftTimeline(from set: ExerciseSet, by delta: TimeInterval) {
        guard delta != 0, let session = set.exercise?.workout else { return }
        guard let pivot = set.completedAt ?? session.endedAt else { return }
        func shifted(_ date: Date) -> Date { date >= pivot ? date.addingTimeInterval(delta) : date }
        func shifted(_ date: Date?) -> Date? { date.map { shifted($0) } }

        for exercise in session.exercises {
            exercise.startedAt = shifted(exercise.startedAt)
            exercise.endedAt = shifted(exercise.endedAt)
            for item in exercise.sets {
                item.startedAt = shifted(item.startedAt)
                item.completedAt = shifted(item.completedAt)
            }
            for rest in exercise.rests {
                rest.startedAt = shifted(rest.startedAt)
                rest.endedAt = shifted(rest.endedAt)
            }
        }
        if let end = shifted(session.endedAt) {
            session.endedAt = max(end, session.startedAt)
        }
    }
}
