import SwiftData
import SwiftUI

struct WorkoutMusicSetupView: View {
    @Bindable var template: WorkoutTemplate
    @Query private var assignments: [MusicAssignment]
    @Query private var settings: [AppSettings]
    @State private var pickingExerciseId: UUID?
    @State private var showingPicker = false
    @State private var previewingId: String?

    var body: some View {
        List {
            if let current = settings.first {
                Section {
                    Toggle("Auto-play when an exercise starts", isOn: Bindable(current).autoPlayExerciseTrack)
                    Text("Uses music already on this iPhone. Assign one track, or a whole playlist for a long session — a playlist repeats, so it outlasts the workout. Preview plays about 5 seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(template.name) {
                ForEach(template.orderedExercises, id: \.id) { item in
                    if let exercise = item.exercise {
                        musicRow(exercise: exercise)
                    }
                }
            }
        }
        .navigationTitle("Workout music")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            if let pickingExerciseId {
                MusicPickerView(exerciseId: pickingExerciseId, template: template)
            }
        }
    }

    private func musicRow(exercise: ExerciseDefinition) -> some View {
        let assignment = assignments.first { $0.exerciseId == exercise.id }
        return VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name)
                .font(.headline)
            if let assignment {
                Text(description(of: assignment))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No music")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Button(assignment == nil ? "Choose music" : "Change") {
                    pickingExerciseId = exercise.id
                    showingPicker = true
                }
                .buttonStyle(SecondaryGymButtonStyle())
                if let assignment {
                    Button(previewingId == assignment.musicItemID ? "Playing…" : "Preview 5s") {
                        Task { await preview(assignment.musicItemID) }
                    }
                    .buttonStyle(SecondaryGymButtonStyle())
                    .disabled(previewingId != nil)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// A playlist is named as one, rather than reading "3 songs — Ride playlist"
    /// from fields meant to hold an artist and a title.
    private func description(of assignment: MusicAssignment) -> String {
        guard assignment.isPlaylist else {
            return "\(assignment.cachedArtist) — \(assignment.cachedTitle)"
        }
        let mode = assignment.repeatPlaylist ? "repeating" : "once through"
        return "Playlist: \(assignment.playlistName) · \(mode)"
    }

    private func preview(_ itemID: String) async {
        previewingId = itemID
        await FittrDependencies.shared.music.preview(itemID: itemID, seconds: 5)
        previewingId = nil
    }
}
