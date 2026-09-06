import Foundation

struct WorkoutComparison: Equatable, Sendable {
    var previousDate: Date
    var previousVolumeKg: Double
    var currentVolumeKg: Double
    var volumeDeltaPercent: Double?
    var heavierExercises: [String]
    var higherRepExercises: [String]

    var volumeLine: String {
        let previous = previousVolumeKg.formatted(.number.precision(.fractionLength(0)))
        let current = currentVolumeKg.formatted(.number.precision(.fractionLength(0)))
        var line = "Volume: \(previous) → \(current) kg"
        if let volumeDeltaPercent {
            let sign = volumeDeltaPercent >= 0 ? "+" : ""
            line += String(format: "  %@%.1f%%", sign, volumeDeltaPercent)
        }
        return line
    }
}

enum AnalyticsEngine {
    static func compare(current: WorkoutSession, previous: WorkoutSession?) -> WorkoutComparison? {
        guard let previous else { return nil }
        let currentVolume = current.trainingVolumeKg
        let previousVolume = previous.trainingVolumeKg
        var heavier: [String] = []
        var moreReps: [String] = []

        for exercise in current.orderedExercises {
            let prior = previous.orderedExercises.first { $0.exerciseId == exercise.exerciseId }
            guard let prior else { continue }
            let currentWeight = exercise.completedSets.compactMap(\.weightKg).max() ?? 0
            let priorWeight = prior.completedSets.compactMap(\.weightKg).max() ?? 0
            if currentWeight > priorWeight, currentWeight > 0 {
                heavier.append(exercise.exerciseName)
            }
            let currentReps = exercise.completedSets.compactMap(\.reps).max() ?? 0
            let priorReps = prior.completedSets.compactMap(\.reps).max() ?? 0
            if currentReps > priorReps, currentReps > 0 {
                moreReps.append(exercise.exerciseName)
            }
        }

        return WorkoutComparison(
            previousDate: previous.startedAt,
            previousVolumeKg: previousVolume,
            currentVolumeKg: currentVolume,
            volumeDeltaPercent: WorkoutMath.percentChange(from: previousVolume, to: currentVolume),
            heavierExercises: heavier,
            higherRepExercises: moreReps
        )
    }

    static func previousComparableSession(
        for templateId: UUID,
        type: WorkoutType,
        before sessionID: UUID,
        startedAt: Date,
        in sessions: [WorkoutSession]
    ) -> WorkoutSession? {
        sessions
            .filter { session in
                session.id != sessionID
                    && session.endedAt != nil
                    && session.workoutTemplateId == templateId
                    && session.type == type
                    && session.startedAt < startedAt
            }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    static func previousSets(for exerciseId: UUID, in session: WorkoutSession?) -> [ExerciseSet] {
        session?.orderedExercises.first { $0.exerciseId == exerciseId }?.completedSets ?? []
    }

    static func weeklyVolume(sessions: [WorkoutSession], in range: DateInterval) -> Double {
        sessions
            .filter { $0.endedAt != nil && range.contains($0.startedAt) && $0.type == .strength }
            .reduce(0) { $0 + $1.trainingVolumeKg }
    }

    static func adherence(planned: [ScheduledWorkout], now: Date = .now) -> (planned: Int, completed: Int, skipped: Int, percent: Double) {
        let considered = planned.filter { $0.scheduledStart <= now || $0.status == .completed }
        let plannedCount = considered.filter { item in
            guard let template = item.template else { return false }
            return !template.isOptionalDay && template.type != .rest
        }.count
        let completed = considered.filter { $0.status == .completed }.count
        let skipped = considered.filter { $0.status == .skipped }.count
        return (plannedCount, completed, skipped, WorkoutMath.weeklyAdherence(planned: plannedCount, completed: completed))
    }
}

struct ChartPoint: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var value: Double
    var label: String = ""
}
