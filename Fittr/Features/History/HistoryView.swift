import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \ExerciseDefinition.name) private var exercises: [ExerciseDefinition]

    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var units: UnitSystem { profiles.first?.liftingUnits ?? .metric }
    @State private var typeFilter: WorkoutType?
    @State private var search = ""
    @State private var selectedExerciseID: UUID?
    @State private var sessionPendingDelete: WorkoutSession?

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    EmptyStateView(
                        title: "No workouts yet",
                        systemImage: "figure.strengthtraining.traditional",
                        message: "Finished sessions land here with their sets, volume and timings."
                    )
                    .listRowBackground(Color.clear)
                } else {
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
                    if filtered.isEmpty {
                        EmptyStateView(
                            title: "No matches",
                            systemImage: "magnifyingglass",
                            message: "Nothing matches that filter or search."
                        )
                        .listRowBackground(Color.clear)
                    }
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", role: .destructive) {
                                    sessionPendingDelete = session
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .confirmationDialog(
                "Delete this workout?",
                isPresented: Binding(
                    get: { sessionPendingDelete != nil },
                    set: { if !$0 { sessionPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete workout", role: .destructive) {
                    if let session = sessionPendingDelete {
                        delete(session)
                    }
                    sessionPendingDelete = nil
                }
            } message: {
                Text("It will be removed from history, records, and next-session weights as if it never happened.")
            }
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

    private func delete(_ session: WorkoutSession) {
        let healthUUID = session.healthKitWorkoutUUID
        try? WorkoutSessionDeletionService.delete(session, in: modelContext)
        if let healthUUID {
            Task {
                try? await FittrDependencies.shared.health.deleteWorkout(uuid: healthUUID)
            }
        }
    }

    private func summaryLine(_ session: WorkoutSession) -> String {
        let duration = DurationFormatting.compact(seconds: session.elapsed())
        switch session.type {
        case .strength:
            return "\(duration) · \(session.completedSetCount) sets · \(NumberFormatting.volume(session.trainingVolumeKg, units: units))"
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
