import Foundation

enum WorkoutMath {
    /// Volume uses the entered load as-is for bilateral work.
    /// For unilateral work the entered weight is treated as load per side.
    static func setVolumeKg(
        weightKg: Double?,
        reps: Int?,
        leftReps: Int?,
        rightReps: Int?,
        laterality: Laterality
    ) -> Double {
        guard let weightKg else { return 0 }
        switch laterality {
        case .bilateral:
            return weightKg * Double(reps ?? 0)
        case .unilateral:
            let totalReps = Double((leftReps ?? 0) + (rightReps ?? 0))
            if totalReps > 0 {
                return weightKg * totalReps
            }
            return weightKg * Double(reps ?? 0)
        }
    }

    static func sessionVolumeKg(sets: [SetVolumeInput]) -> Double {
        sets.reduce(0) { partial, set in
            partial + setVolumeKg(
                weightKg: set.weightKg,
                reps: set.reps,
                leftReps: set.leftReps,
                rightReps: set.rightReps,
                laterality: set.laterality
            )
        }
    }

    static func duration(from start: Date?, to end: Date?, now: Date = .now) -> TimeInterval {
        guard let start else { return 0 }
        let finish = end ?? now
        return max(0, finish.timeIntervalSince(start))
    }

    static func averageRestSeconds(rests: [RestDurationInput]) -> Double? {
        let completed = rests.compactMap { rest -> TimeInterval? in
            guard let endedAt = rest.endedAt else { return nil }
            return max(0, endedAt.timeIntervalSince(rest.startedAt))
        }
        guard !completed.isEmpty else { return nil }
        return completed.reduce(0, +) / Double(completed.count)
    }

    static func totalRestSeconds(rests: [RestDurationInput], now: Date = .now) -> TimeInterval {
        rests.reduce(0) { partial, rest in
            partial + duration(from: rest.startedAt, to: rest.endedAt, now: now)
        }
    }

    /// Epley estimate: `weight × (1 + reps / 30)`.
    /// Only valid for weighted sets with 1...12 reps. Not used for plank/cardio.
    static func estimatedOneRepMaxKg(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, (1...12).contains(reps) else { return nil }
        return weightKg * (1 + Double(reps) / 30.0)
    }

    static func movingAverage(values: [DatedValue], windowDays: Int = 7) -> [DatedValue] {
        guard windowDays > 0, !values.isEmpty else { return [] }
        let sorted = values.sorted { $0.date < $1.date }
        return sorted.map { point in
            let start = Calendar.current.date(byAdding: .day, value: -(windowDays - 1), to: point.date) ?? point.date
            let window = sorted.filter { $0.date >= start && $0.date <= point.date }
            let average = window.map(\.value).reduce(0, +) / Double(window.count)
            return DatedValue(date: point.date, value: average)
        }
    }

    static func weeklyAdherence(planned: Int, completed: Int) -> Double {
        guard planned > 0 else { return 0 }
        return min(1, Double(completed) / Double(planned))
    }

    static func percentChange(from previous: Double, to current: Double) -> Double? {
        guard previous != 0 else { return nil }
        return ((current - previous) / previous) * 100
    }
}

struct SetVolumeInput: Sendable, Hashable {
    var weightKg: Double?
    var reps: Int?
    var leftReps: Int?
    var rightReps: Int?
    var laterality: Laterality
}

struct RestDurationInput: Sendable, Hashable {
    var startedAt: Date
    var endedAt: Date?
}

struct DatedValue: Sendable, Hashable, Identifiable {
    var id: Date { date }
    var date: Date
    var value: Double
}

extension ExerciseSet {
    var volumeInput: SetVolumeInput {
        SetVolumeInput(
            weightKg: weightKg,
            reps: reps,
            leftReps: leftReps,
            rightReps: rightReps,
            laterality: laterality
        )
    }

    var volumeKg: Double {
        WorkoutMath.setVolumeKg(
            weightKg: weightKg,
            reps: reps,
            leftReps: leftReps,
            rightReps: rightReps,
            laterality: laterality
        )
    }
}

extension RestInterval {
    var durationInput: RestDurationInput {
        RestDurationInput(startedAt: startedAt, endedAt: endedAt)
    }

    func actualDuration(now: Date = .now) -> TimeInterval {
        WorkoutMath.duration(from: startedAt, to: endedAt, now: now)
    }
}

extension WorkoutSession {
    var completedSetCount: Int {
        exercises.flatMap(\.sets).filter { $0.status == .completed }.count
    }

    var completedReps: Int {
        exercises.flatMap(\.sets).filter { $0.status == .completed }.reduce(0) { partial, set in
            if set.laterality == .unilateral {
                return partial + (set.leftReps ?? 0) + (set.rightReps ?? 0)
            }
            return partial + (set.reps ?? 0)
        }
    }

    var trainingVolumeKg: Double {
        WorkoutMath.sessionVolumeKg(
            sets: exercises.flatMap(\.sets).filter { $0.status == .completed }.map(\.volumeInput)
        )
    }

    func elapsed(now: Date = .now) -> TimeInterval {
        WorkoutMath.duration(from: startedAt, to: endedAt, now: now)
    }

    var totalRestSeconds: TimeInterval {
        WorkoutMath.totalRestSeconds(rests: exercises.flatMap(\.rests).map(\.durationInput), now: endedAt ?? .now)
    }

    var averageRestSeconds: Double? {
        WorkoutMath.averageRestSeconds(rests: exercises.flatMap(\.rests).map(\.durationInput))
    }

    var totalActiveSeconds: TimeInterval {
        max(0, elapsed() - totalRestSeconds)
    }
}
