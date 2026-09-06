import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \ExerciseDefinition.name) private var exercises: [ExerciseDefinition]
    @State private var typeFilter: WorkoutType?
    @State private var search = ""
    @State private var selectedExerciseID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Type", selection: $typeFilter) {
                        Text("All").tag(Optional<WorkoutType>.none)
                        ForEach(WorkoutType.allCases) { type in
                            Text(type.title).tag(Optional(type))
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("Search exercise", text: $search)
                }
                ForEach(grouped.keys.sorted(by: >), id: \.self) { month in
                    Section(month) {
                        ForEach(grouped[month] ?? [], id: \.id) { session in
                            NavigationLink {
                                WorkoutDetailView(session: session)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .omitted) + " — \(session.name)")
                                        .font(.headline)
                                    Text(summaryLine(session))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("history.row")
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Exercise log") {
                        ForEach(exercises, id: \.id) { exercise in
                            Button(exercise.name) { selectedExerciseID = exercise.id }
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedExerciseID) { id in
                if let exercise = exercises.first(where: { $0.id == id }) {
                    ExerciseHistoryView(exercise: exercise)
                }
            }
        }
    }

    private var filtered: [WorkoutSession] {
        sessions.filter { session in
            if let typeFilter, session.type != typeFilter { return false }
            if !search.isEmpty {
                return session.exercises.contains { $0.exerciseName.localizedCaseInsensitiveContains(search) }
                    || session.name.localizedCaseInsensitiveContains(search)
            }
            return true
        }
    }

    private var grouped: [String: [WorkoutSession]] {
        Dictionary(grouping: filtered) { session in
            session.startedAt.formatted(.dateTime.month(.wide).year())
        }
    }

    private func summaryLine(_ session: WorkoutSession) -> String {
        let duration = DurationFormatting.compact(seconds: session.elapsed())
        switch session.type {
        case .strength:
            return "\(duration) · \(session.completedSetCount) sets · \(NumberFormatting.volume(session.trainingVolumeKg, units: .metric))"
        case .cardio:
            let distance = session.cardio?.distanceKm.map { NumberFormatting.distanceKm($0, units: .metric) }
            return [duration, distance].compactMap { $0 }.joined(separator: " · ")
        case .swimming:
            let distance = session.swim?.distanceMeters.map { "\(Int($0)) m" }
            return [duration, distance].compactMap { $0 }.joined(separator: " · ")
        case .recovery, .rest, .mixed:
            return duration
        }
    }
}
