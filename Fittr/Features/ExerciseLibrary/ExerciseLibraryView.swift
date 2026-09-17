import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Query(sort: \ExerciseDefinition.name) private var exercises: [ExerciseDefinition]
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        List {
            TextField("Search", text: $query)
            ForEach(filtered, id: \.id) { exercise in
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                } label: {
                    VStack(alignment: .leading) {
                        Text(exercise.name)
                        Text("\(exercise.category.title) · \(exercise.equipment.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Exercise library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New exercise", systemImage: "plus") { creating = true }
                    .accessibilityIdentifier("library.newExercise")
            }
        }
        .sheet(isPresented: $creating) {
            NewExerciseSheet { _ in }
        }
    }

    private var filtered: [ExerciseDefinition] {
        exercises.filter { exercise in
            query.isEmpty || exercise.name.localizedCaseInsensitiveContains(query)
        }
    }
}

struct ExerciseDetailView: View {
    @Bindable var exercise: ExerciseDefinition
    @Query private var assignments: [MusicAssignment]
    @State private var showMusic = false

    var body: some View {
        List {
            Section("Details") {
                TextField("Name", text: $exercise.name)
                Toggle("Enabled", isOn: $exercise.isEnabled)
                LabeledContent("Tracking", value: exercise.trackingMode.title)
                LabeledContent("Laterality", value: exercise.laterality.title)
            }
            Section("Technique") {
                NavigationLink("Show Technique") {
                    TechniqueView(exercise: exercise)
                }
            }
            Section("Workout Music") {
                Text("Assign a song from a local playlist or search MP3s already on this iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let existing = assignments.first(where: { $0.exerciseId == exercise.id }) {
                    MusicAssignmentToggles(assignment: existing)
                } else {
                    Text("Assigned track: none")
                        .foregroundStyle(.secondary)
                }
                Button("Choose local track") { showMusic = true }
            }
        }
        .navigationTitle(exercise.name)
        .sheet(isPresented: $showMusic) {
            MusicPickerView(exerciseId: exercise.id)
        }
    }
}

private struct MusicAssignmentToggles: View {
    @Bindable var assignment: MusicAssignment

    var body: some View {
        Text("\(assignment.cachedArtist) — \(assignment.cachedTitle)")
        Toggle("Auto start when exercise begins", isOn: $assignment.autoplay)
        Toggle("Restart from beginning", isOn: $assignment.restartFromBeginning)
        if assignment.isPlaylist {
            Toggle("Shuffle", isOn: $assignment.shufflePlaylist)
            Toggle("Repeat playlist", isOn: $assignment.repeatPlaylist)
        }
    }
}
