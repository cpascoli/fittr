import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    @Bindable var controller: ActiveWorkoutController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.name) private var library: [ExerciseDefinition]
    @Query private var settings: [AppSettings]
    @Query private var assignments: [MusicAssignment]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var showingMusicPicker = false
    @State private var confirmSkipOptional = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                (controller.isResting ? FittrTheme.restBackgroundGradient : FittrTheme.backgroundGradient)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.35), value: controller.isResting)
                if controller.showingSummary {
                    WorkoutSummaryView(controller: controller) {
                        dismiss()
                    }
                } else {
                    workoutBody
                        .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add note") { controller.showingNote = true }
                        Button("Replace exercise") { controller.showingReplace = true }
                        Button("Skip exercise", role: .destructive) { controller.skipExercise() }
                        Button("Finish workout") { controller.finishWorkout() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("workout.menu")
                }
            }
            .sheet(isPresented: $controller.showingTechnique) {
                if let exercise = techniqueDefinition {
                    TechniqueView(exercise: exercise)
                }
            }
            .sheet(isPresented: $controller.showingReplace) {
                ReplaceExerciseSheet(exercises: library) { definition in
                    controller.replaceCurrentExercise(with: definition)
                    controller.showingReplace = false
                }
            }
            .sheet(isPresented: $controller.showingNote) {
                NoteEditorSheet(title: "Exercise note", text: controller.currentExercise?.notes ?? "") { text in
                    controller.saveNote(text, scope: .exercise)
                }
            }
            .sheet(isPresented: $showingMusicPicker) {
                MusicPickerView(exerciseId: controller.currentExercise?.exerciseId)
            }
            .confirmationDialog(
                "Skip \(controller.currentExercise?.exerciseName ?? "this exercise")?",
                isPresented: $confirmSkipOptional,
                titleVisibility: .visible
            ) {
                Button("Skip exercise") { controller.skipExercise() }
                Button("Keep it", role: .cancel) {}
            }
            .onAppear {
                controller.pulse()
                controller.syncMusicState()
                syncUnits()
                setIdleTimerDisabled(true)
            }
            // The controller captured units at init; switching them in Settings
            // should reach a session already underway.
            .onChange(of: profiles.first?.liftingUnits) { _, _ in syncUnits() }
            .onDisappear {
                setIdleTimerDisabled(false)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    controller.pulse()
                    controller.syncMusicState()
                    setIdleTimerDisabled(true)
                case .inactive:
                    break
                case .background:
                    setIdleTimerDisabled(false)
                @unknown default:
                    break
                }
            }
            // Only tick while a rest or hold is actually counting. This used to run
            // unconditionally and invalidate the whole screen four times a second,
            // which cost battery and meant the app never reached idle — XCUITest
            // then needed 63 seconds to resolve a single button.
            .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
                guard controller.needsTicking else { return }
                controller.pulse()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var workoutBody: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    exerciseHeader
                    if controller.isResting {
                        RestTimerView(controller: controller)
                        restTechniquePreview
                    } else if controller.usesDuration {
                        // For a timed hold the clock is the control, not a
                        // reference, so it outranks the technique clip for the
                        // space above the fold — you must be able to start it
                        // without scrolling.
                        HoldTimerView(controller: controller)
                        techniqueGlance
                        previousCard
                        metaRow
                    } else {
                        techniqueGlance
                        previousCard
                        if controller.isCardio {
                            CardioLoggerView(controller: controller)
                        } else {
                            SetLoggerView(controller: controller)
                        }
                        metaRow
                    }
                    musicRow
                }
                .padding(20)
                .padding(.bottom, 120)
                .containerRelativeFrame(.horizontal, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            bottomBar
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.session.name.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                WorkoutClockView(session: controller.session)
            }
            Spacer()
            Text("\(controller.currentExerciseIndex + 1) / \(max(controller.session.orderedExercises.count, 1))")
                .font(.headline.monospacedDigit())
                .foregroundStyle(controller.isResting ? FittrTheme.restAccent : FittrTheme.accent)
        }
    }

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(controller.currentExercise?.exerciseName ?? "Exercise")
                .font(.largeTitle.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("workout.exerciseName")
            HStack {
                if let prescription = controller.prescription {
                    StatusChip(text: prescription.targetRepLabel)
                    if prescription.isOptional {
                        StatusChip(text: "Optional", color: FittrTheme.warning)
                    }
                }
                if controller.isRestingBeforeNextExercise {
                    StatusChip(text: "Done", color: FittrTheme.success)
                } else {
                    StatusChip(text: "Set \(controller.currentSetNumber)", color: .white)
                }
            }
            if controller.prescription?.isOptional == true {
                Button("Skip optional — no machine") {
                    confirmSkipOptional = true
                }
                .buttonStyle(GymButtonStyle(fill: FittrTheme.warning, foreground: .black))
                .accessibilityIdentifier("workout.skipOptional")
            }
        }
    }

    @ViewBuilder
    private var previousCard: some View {
        if controller.previousWorkout == nil {
            // One line, not a whole card: on a first session this said nothing
            // and cost the vertical space the technique clip now uses.
            Text("No previous session yet — values start from useful defaults.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            previousSetsCard
        }
    }

    private var previousSetsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previous = controller.previousWorkout {
                Text("LAST TIME — \(previous.startedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                if controller.previousSets.isEmpty {
                    Text("No sets recorded last time.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.previousSets, id: \.id) { set in
                        Text(previousLine(set))
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                    Button("Copy last values") {
                        if let last = controller.previousSets.first(where: { $0.setNumber == controller.currentSetNumber }) ?? controller.previousSets.last {
                            if let weight = last.weightKg { controller.draftWeightKg = weight }
                            if let reps = last.reps { controller.draftReps = reps }
                        }
                    }
                    .buttonStyle(SecondaryGymButtonStyle())
                    .accessibilityIdentifier("workout.copyLast")
                }
            }
        }
        .fittrCard()
    }


    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prescription = controller.prescription {
                VStack(alignment: .leading, spacing: 4) {
                    if let min = prescription.minReps, let max = prescription.maxReps, max > 0 {
                        Text("Target: \(min)–\(max) reps · RIR 3–4")
                    }
                    Text("Suggested rest: \(prescription.targetRestSeconds) sec")
                }
            }

        }
    }

    private var musicRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Music")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(assignedMusicTitle)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Button(controller.isMusicPlaying ? "Pause" : "Play") {
                    if controller.isMusicPlaying {
                        controller.pauseMusic()
                    } else {
                        controller.playMusic()
                    }
                }
                .buttonStyle(SecondaryGymButtonStyle())
                .accessibilityIdentifier("workout.music.playPause")
                Button("Stop") {
                    controller.stopMusic()
                }
                .buttonStyle(SecondaryGymButtonStyle())
                .accessibilityIdentifier("workout.music.stop")
            }
            // Only worth showing when there is a queue to move through.
            if controller.hasPlaylistAssigned {
                HStack(spacing: 8) {
                    Button("Previous") { controller.previousTrack() }
                        .buttonStyle(SecondaryGymButtonStyle())
                        .accessibilityIdentifier("workout.music.previous")
                    Button("Next") { controller.nextTrack() }
                        .buttonStyle(SecondaryGymButtonStyle())
                        .accessibilityIdentifier("workout.music.next")
                }
            }
            Button("Choose local track") { showingMusicPicker = true }
                .buttonStyle(SecondaryGymButtonStyle())
        }
        .padding(.vertical, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if controller.isResting {
                Button(controller.isRestingBeforeNextExercise ? "START NEXT EXERCISE" : "START NEXT SET") {
                    controller.startNextSet()
                }
                .buttonStyle(GymButtonStyle())
                .accessibilityIdentifier("workout.startNextSet")
                HStack(spacing: 8) {
                    Button("+15s") { controller.addRest(15) }
                        .buttonStyle(SecondaryGymButtonStyle(compact: true))
                        .accessibilityIdentifier("workout.addRest15")
                    Button("+30s") { controller.addRest(30) }
                        .buttonStyle(SecondaryGymButtonStyle(compact: true))
                        .accessibilityIdentifier("workout.addRest30")
                    Button("Skip Rest") { controller.skipRest() }
                        .buttonStyle(SecondaryGymButtonStyle(compact: true))
                        .accessibilityIdentifier("workout.skipRest")
                }
                .frame(maxWidth: .infinity)
            } else {
                Button("COMPLETE SET \(controller.currentSetNumber)") {
                    controller.completeSet()
                }
                .buttonStyle(GymButtonStyle())
                .accessibilityIdentifier("workout.completeSet")
                HStack {
                    Button("Finish Exercise") { controller.finishExercise(advance: true) }
                        .buttonStyle(SecondaryGymButtonStyle())
                        .accessibilityIdentifier("workout.finishExercise")
                    Button("Add Set") { controller.addSet() }
                        .buttonStyle(SecondaryGymButtonStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    /// A compact, tappable still of the movement, sitting directly under the
    /// exercise name so it is visible without scrolling. Tapping opens the full
    /// technique sheet — cues and common mistakes live there, not here, because
    /// anything taller pushes the weight and rep steppers off screen.
    @ViewBuilder
    private var techniqueGlance: some View {
        if let definition = techniqueDefinition {
            Button {
                controller.showingTechnique = true
            } label: {
                TechniqueClipView(exercise: definition, height: 140)
                    .id(definition.id)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                            .padding(10)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workout.technique")
            .accessibilityLabel("Technique for \(definition.name)")
            .accessibilityHint("Opens setup, movement and coaching cues")
        }
    }

    private var restTechniquePreview: some View {
        techniqueCard(
            height: 240,
            heading: controller.isRestingBeforeNextExercise ? "Next exercise" : "Technique",
            showsName: true
        )
    }

    /// The looping technique clip, its first coaching cue, and the way into the
    /// full instructions. Shared by the rest phase and the set-logging phase so
    /// the movement is visible before a set, not only between sets.
    @ViewBuilder
    private func techniqueCard(height: CGFloat, heading: String, showsName: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: heading)
            if let definition = techniqueDefinition {
                if showsName {
                    Text(definition.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                TechniqueClipView(exercise: definition, height: height)
                    .id(definition.id)
                    .frame(minWidth: 0, maxWidth: .infinity)
                if let cue = definition.coachingCues.first {
                    Text(cue)
                        .foregroundStyle(.secondary)
                }
                Button {
                    controller.showingTechnique = true
                } label: {
                    Label("Show Technique", systemImage: "play.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryGymButtonStyle())
                .accessibilityIdentifier("workout.technique")
            } else {
                Text("Technique clip unavailable for this exercise.")
                    .foregroundStyle(.secondary)
            }
        }
        .fittrCard()
    }

    private var techniqueDefinition: ExerciseDefinition? {
        definition(for: controller.techniqueExerciseId)
    }

    private func definition(for id: UUID?) -> ExerciseDefinition? {
        guard let id else { return nil }
        return library.first { $0.id == id }
    }

    private func syncUnits() {
        if let preferred = profiles.first?.liftingUnits {
            controller.units = preferred
        }
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private var assignedMusicTitle: String {
        let assignment = assignedMusic
        if let current = music.nowPlaying {
            let line = "\(current.artist) — \(current.title)"
            // Name the playlist as well as the song, so it is obvious that more is
            // queued behind this one and skipping will land somewhere.
            guard let assignment, assignment.isPlaylist else { return line }
            return "\(assignment.playlistName) · \(line)"
        }
        if let assignment {
            return "\(assignment.cachedArtist) — \(assignment.cachedTitle)"
        }
        return "No assigned track"
    }

    private var assignedMusic: MusicAssignment? {
        guard let exerciseID = controller.currentExercise?.exerciseId else { return nil }
        return assignments.first { $0.exerciseId == exerciseID }
    }

    private var music: any MusicServicing {
        FittrDependencies.shared.music
    }

    private func previousLine(_ set: ExerciseSet) -> String {
        if let weight = set.weightKg, let reps = set.reps {
            return "Set \(set.setNumber): \(NumberFormatting.weight(weight, units: controller.units)) × \(reps)"
        }
        if let duration = set.durationSeconds {
            return "Set \(set.setNumber): \(DurationFormatting.compact(seconds: duration))"
        }
        return "Set \(set.setNumber)"
    }
}

/// The workout clock, ticking on its own rather than through the controller. It
/// lived in the header and read `controller.tick`, so the second hand redrew the
/// entire screen — the exercise, the set logger, the music row, everything.
/// `TimelineView` keeps the invalidation inside these few points of text.
private struct WorkoutClockView: View {
    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(DurationFormatting.clock(seconds: session.elapsed(now: context.date)))
                .font(.title2.weight(.bold).monospacedDigit())
                .accessibilityIdentifier("workout.elapsed")
        }
    }
}

struct ReplaceExerciseSheet: View {
    let exercises: [ExerciseDefinition]
    let onSelect: (ExerciseDefinition) -> Void

    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                // Swapping mid-workout is exactly when you discover the machine
                // you have moved to is not in the library.
                Button("Create a new exercise", systemImage: "plus") { creating = true }
                ForEach(exercises.filter(\.isEnabled), id: \.id) { exercise in
                    Button {
                        onSelect(exercise)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(exercise.name)
                            Text(exercise.category.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Replace exercise")
            .sheet(isPresented: $creating) {
                NewExerciseSheet { definition in
                    onSelect(definition)
                }
            }
        }
    }
}

struct NoteEditorSheet: View {
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(text)
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}
