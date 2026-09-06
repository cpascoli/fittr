import Foundation
import SwiftData

enum PersonalRecordService {
    @discardableResult
    static func evaluate(session: WorkoutSession, in context: ModelContext) throws -> [PersonalRecord] {
        var created: [PersonalRecord] = []
        let existing = try context.fetch(FetchDescriptor<PersonalRecord>())

        for exercise in session.orderedExercises {
            let completed = exercise.completedSets
            if let heaviest = completed.compactMap(\.weightKg).max(), heaviest > 0 {
                if isNewBest(existing: existing, kind: .heaviestWeight, exerciseId: exercise.exerciseId, value: heaviest) {
                    created.append(
                        insert(
                            kind: .heaviestWeight,
                            exercise: exercise,
                            session: session,
                            value: heaviest,
                            unit: "kg",
                            in: context
                        )
                    )
                }
            }

            for set in completed {
                guard let weight = set.weightKg, let reps = set.reps, weight > 0, reps > 0 else { continue }
                let keyBest = existing.filter {
                    $0.kind == .mostRepsAtWeight
                        && $0.exerciseId == exercise.exerciseId
                        && abs(($0.secondaryValue ?? 0) - weight) < 0.05
                }.map(\.value).max() ?? 0
                if Double(reps) > keyBest {
                    created.append(
                        insert(
                            kind: .mostRepsAtWeight,
                            exercise: exercise,
                            session: session,
                            value: Double(reps),
                            secondary: weight,
                            unit: "reps",
                            notes: "\(Int(weight)) kg",
                            in: context
                        )
                    )
                }
            }

            if exercise.exerciseId == SeedID.plank {
                let longest = completed.compactMap(\.durationSeconds).max() ?? 0
                if longest > 0, isNewBest(existing: existing, kind: .longestPlank, exerciseId: exercise.exerciseId, value: longest) {
                    created.append(
                        insert(
                            kind: .longestPlank,
                            exercise: exercise,
                            session: session,
                            value: longest,
                            unit: "sec",
                            in: context
                        )
                    )
                }
            }
        }

        let volume = session.trainingVolumeKg
        if session.type == .strength, volume > 0,
           isNewBest(existing: existing, kind: .highestSessionVolume, exerciseId: nil, value: volume) {
            let record = PersonalRecord(
                kind: .highestSessionVolume,
                exerciseName: session.name,
                achievedAt: session.endedAt ?? session.startedAt,
                workoutSessionId: session.id,
                value: volume,
                unitLabel: "kg"
            )
            context.insert(record)
            created.append(record)
        }

        if session.type == .cardio || session.type == .recovery {
            let duration = session.elapsed()
            if duration > 0, isNewBest(existing: existing, kind: .longestCardio, exerciseId: nil, value: duration) {
                let record = PersonalRecord(
                    kind: .longestCardio,
                    exerciseName: session.name,
                    achievedAt: session.endedAt ?? session.startedAt,
                    workoutSessionId: session.id,
                    value: duration,
                    unitLabel: "sec"
                )
                context.insert(record)
                created.append(record)
            }
        }

        if session.type == .swimming {
            let duration = session.swim?.swimDurationSeconds ?? session.elapsed()
            if duration > 0, isNewBest(existing: existing, kind: .longestSwim, exerciseId: nil, value: duration) {
                let record = PersonalRecord(
                    kind: .longestSwim,
                    exerciseName: session.name,
                    achievedAt: session.endedAt ?? session.startedAt,
                    workoutSessionId: session.id,
                    value: duration,
                    unitLabel: "sec"
                )
                context.insert(record)
                created.append(record)
            }
        }

        try context.save()
        return created
    }

    private static func isNewBest(
        existing: [PersonalRecord],
        kind: PersonalRecordKind,
        exerciseId: UUID?,
        value: Double
    ) -> Bool {
        let matches = existing.filter { record in
            record.kind == kind && record.exerciseId == exerciseId
        }
        let best = matches.map(\.value).max() ?? 0
        return value > best
    }

    private static func insert(
        kind: PersonalRecordKind,
        exercise: ExerciseSession,
        session: WorkoutSession,
        value: Double,
        secondary: Double? = nil,
        unit: String,
        notes: String = "",
        in context: ModelContext
    ) -> PersonalRecord {
        let record = PersonalRecord(
            kind: kind,
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.exerciseName,
            achievedAt: session.endedAt ?? session.startedAt,
            workoutSessionId: session.id,
            value: value,
            secondaryValue: secondary,
            unitLabel: unit,
            notes: notes
        )
        context.insert(record)
        return record
    }
}
