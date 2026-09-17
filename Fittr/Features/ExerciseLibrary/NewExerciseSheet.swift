import SwiftData
import SwiftUI

/// Creating an exercise the seed data does not have. The library used to be
/// read-only, so wanting "Treadmill Running" left you renaming "Treadmill
/// Walking" — which rewrites it in every workout you have already logged.
///
/// Shared by the library tab and by the two places that add an exercise to a
/// workout, because discovering something is missing almost always happens while
/// you are standing in one of those, not in the library.
struct NewExerciseSheet: View {
    var onCreate: (ExerciseDefinition) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var category: ExerciseCategory = .strength
    @State private var equipment: Equipment = .none
    @State private var laterality: Laterality = .bilateral
    @State private var trackingMode: TrackingMode = .repsWeight

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("newExercise.name")
                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                Section("Tracking") {
                    Picker("Tracking", selection: $trackingMode) {
                        ForEach(TrackingMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("Laterality", selection: $laterality) {
                        ForEach(Laterality.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Text(trackingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: category) { _, newValue in
                applyCategoryDefaults(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("newExercise.create")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trackingDescription: String {
        switch trackingMode {
        case .repsWeight: "Logs a weight and a rep count per set."
        case .repsOnly: "Logs reps per set, no weight."
        case .duration: "Logs a timed hold, counted in seconds."
        case .distanceDuration: "Logs distance and time — treadmill, bike, walking."
        case .lapsDuration: "Logs laps and time, for the pool."
        case .freeform: "Logs a note only."
        }
    }

    /// Picking a category is the strongest signal of how something is measured,
    /// so move tracking with it rather than leaving a cardio machine defaulting
    /// to reps and weight. Still editable afterwards.
    private func applyCategoryDefaults(_ category: ExerciseCategory) {
        switch category {
        case .strength: trackingMode = .repsWeight
        case .cardio: trackingMode = .distanceDuration
        case .swimming: trackingMode = .lapsDuration
        case .mobility, .recovery: trackingMode = .duration
        }
    }

    private func create() {
        let definition = ExerciseDefinition(
            id: UUID(),
            name: trimmedName,
            slug: ExerciseSlug.make(from: trimmedName),
            category: category,
            primaryMuscleGroups: category == .strength ? [] : [.cardio],
            equipment: equipment,
            laterality: laterality,
            setupInstructions: "",
            movementInstructions: "",
            breathingCue: "",
            coachingCues: [],
            commonMistakes: [],
            defaultDurationSeconds: trackingMode.usesDuration ? defaultDuration : 0,
            trackingMode: trackingMode
        )
        modelContext.insert(definition)
        try? modelContext.save()
        onCreate(definition)
        dismiss()
    }

    private var defaultDuration: Int {
        trackingMode.countsInSeconds ? 30 : 1800
    }

}

/// Free of the view, because `View` is `@MainActor`-isolated and this is just
/// string handling that anything should be able to call.
enum ExerciseSlug {
    static func make(from name: String) -> String {
        name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
    }
}
