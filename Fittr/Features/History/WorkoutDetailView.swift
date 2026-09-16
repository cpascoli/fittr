import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var units: UnitSystem { profiles.first?.liftingUnits ?? .metric }

    var body: some View {
        List {
            sessionSection
            ForEach(session.orderedExercises, id: \.id) { exercise in
                ExerciseHistorySection(exercise: exercise)
            }
            if let cardio = session.cardio {
                CardioEditSection(cardio: cardio)
            }
            if let swim = session.swim {
                SwimEditSection(swim: swim)
            }
        }
        .navigationTitle(session.name)
        .onDisappear { try? modelContext.save() }
    }

    private var sessionSection: some View {
        Section("Session") {
            LabeledContent("Start", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
            if let end = session.endedAt {
                LabeledContent("End", value: end.formatted(date: .abbreviated, time: .standard))
            }
            LabeledContent("Duration", value: DurationFormatting.compact(seconds: session.elapsed()))
            LabeledContent("Active", value: DurationFormatting.compact(seconds: session.totalActiveSeconds))
            LabeledContent("Rest", value: DurationFormatting.compact(seconds: session.totalRestSeconds))
            LabeledContent("Volume", value: NumberFormatting.volume(session.trainingVolumeKg, units: units))
            DatePicker("Started at", selection: $session.startedAt)
            if session.endedAt != nil {
                DatePicker("Ended at", selection: Binding(
                    get: { session.endedAt ?? session.startedAt },
                    set: { session.endedAt = $0 }
                ))
            }
            TextField("Notes", text: $session.notes, axis: .vertical)
        }
    }
}

private struct ExerciseHistorySection: View {
    @Bindable var exercise: ExerciseSession

    var body: some View {
        Section(exercise.exerciseName) {
            if let start = exercise.startedAt, let end = exercise.endedAt {
                Text(DurationFormatting.compact(seconds: WorkoutMath.duration(from: start, to: end)))
                    .foregroundStyle(.secondary)
            }
            ForEach(exercise.orderedSets, id: \.id) { set in
                SetEditRow(set: set, restLine: restLine(after: set))
            }
            TextField("Exercise note", text: $exercise.notes)
        }
    }

    private func restLine(after set: ExerciseSet) -> String {
        guard let completed = set.completedAt,
              let rest = exercise.rests.first(where: { $0.afterSetId == set.id || $0.startedAt >= completed }) else {
            return "—"
        }
        return DurationFormatting.compact(seconds: rest.actualDuration(now: rest.endedAt ?? .now))
    }
}

private struct SetEditRow: View {
    @Bindable var set: ExerciseSet
    let restLine: String
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var units: UnitSystem { profiles.first?.liftingUnits ?? .metric }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set \(set.setNumber)")
                .font(.headline)
            if set.weightKg != nil {
                Stepper(
                    "Weight \(NumberFormatting.weight(set.weightKg ?? 0, units: units))",
                    value: Binding(
                        get: { set.weightKg ?? 0 },
                        set: { set.weightKg = $0 }
                    ),
                    in: 0...200,
                    step: 1
                )
            }
            if set.reps != nil {
                Stepper("Reps \(set.reps ?? 0)", value: Binding(
                    get: { set.reps ?? 0 },
                    set: { set.reps = $0 }
                ), in: 0...40)
            }
            Text("Rest after: \(restLine)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Set note", text: $set.notes)
        }
    }
}

private struct CardioEditSection: View {
    @Bindable var cardio: CardioMetrics

    var body: some View {
        Section("Cardio") {
            TextField("Activity", text: $cardio.activityKind)
            TextField("Notes", text: $cardio.notes)
        }
    }
}

private struct SwimEditSection: View {
    @Bindable var swim: SwimMetrics

    var body: some View {
        Section("Swim") {
            Stepper("Pool \(Int(swim.poolLengthMeters)) m", value: $swim.poolLengthMeters, in: 15...50, step: 5)
            TextField("Stroke", text: $swim.stroke)
            TextField("Notes", text: $swim.notes)
        }
    }
}
