import SwiftData
import SwiftUI

struct ExerciseHistoryView: View {
    let exercise: ExerciseDefinition
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        List {
            ForEach(rows, id: \.id) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                    Text(row.line)
                        .font(.body.monospacedDigit())
                    if row.volume > 0 {
                        Text("Volume \(NumberFormatting.volume(row.volume, units: .metric))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
    }

    private var rows: [Row] {
        sessions.flatMap { session in
            session.orderedExercises
                .filter { $0.exerciseId == exercise.id }
                .flatMap { exerciseSession in
                    exerciseSession.completedSets.map { set in
                        Row(
                            id: set.id,
                            date: set.completedAt ?? session.startedAt,
                            line: line(set),
                            volume: set.volumeKg
                        )
                    }
                }
        }
    }

    private func line(_ set: ExerciseSet) -> String {
        if let weight = set.weightKg, let reps = set.reps {
            return "Set \(set.setNumber) · \(NumberFormatting.weight(weight, units: .metric)) × \(reps)"
        }
        if let duration = set.durationSeconds {
            return "Set \(set.setNumber) · \(DurationFormatting.compact(seconds: duration))"
        }
        return "Set \(set.setNumber)"
    }

    private struct Row: Identifiable {
        var id: UUID
        var date: Date
        var line: String
        var volume: Double
    }
}
