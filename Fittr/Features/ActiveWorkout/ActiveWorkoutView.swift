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
    @State private var showingMusicPicker = false
    @State private var confirmSkipOptional = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                FittrTheme.background.ignoresSafeArea()
                if controller.showingSummary {
                    WorkoutSummaryView(controller: controller) {
                        dismiss()
                    }
                } else {
                    workoutBody
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
                setIdleTimerDisabled(true)
            }
            .onDisappear {
                setIdleTimerDisabled(false)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    controller.pulse()
                    setIdleTimerDisabled(true)
                case .inactive:
                    break
                case .background:
                    setIdleTimerDisabled(false)
                @unknown default:
                    break
                }
            }
            .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    exerciseHeader
                    if controller.isResting {
                        RestTimerView(controller: controller)
                        restTechniquePreview
                    } else {
                        previousCard
                        if controller.isCardio {
                            CardioLoggerView(controller: controller)
                        } else if controller.usesDuration {
                            durationLogger
                        } else {
                            SetLoggerView(controller: controller)
                        }
                        metaRow
                    }
                    musicRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .padding(.bottom, 120)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            bottomBar
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.session.name.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(DurationFormatting.clock(seconds: controller.elapsedWorkout))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .accessibilityIdentifier("workout.elapsed")
            }
            Spacer()
            Text("\(controller.currentExerciseIndex + 1) / \(max(controller.session.orderedExercises.count, 1))")
                .font(.headline.monospacedDigit())
                .foregroundStyle(FittrTheme.accent)
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

    private var previousCard: some View {
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
            } else {
                Text("No previous session yet. Values start from useful defaults.")
                    .foregroundStyle(.secondary)
            }
        }
        .fittrCard()
    }

    private var durationLogger: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepperControl(
                title: "Seconds",
                valueText: "\(controller.draftDurationSeconds)",
                decrement: { controller.draftDurationSeconds = max(5, controller.draftDurationSeconds - 5) },
                increment: { controller.draftDurationSeconds += 5 }
            )
        }
        .fittrCard()
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prescription = controller.prescription {
                if let min = prescription.minReps, let max = prescription.maxReps, max > 0 {
                    Text("Target: \(min)–\(max) reps · RIR 3–4")
                }
                Text("Suggested rest: \(prescription.targetRestSeconds) sec")
            }
            Button {
                controller.showingTechnique = true
            } label: {
                Label("Show Technique", systemImage: "play.rectangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryGymButtonStyle())
            .accessibilityIdentifier("workout.technique")
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
                        .buttonStyle(SecondaryGymButtonStyle())
                        .accessibilityIdentifier("workout.addRest15")
                    Button("+30s") { controller.addRest(30) }
                        .buttonStyle(SecondaryGymButtonStyle())
                        .accessibilityIdentifier("workout.addRest30")
                    Button("Skip Rest") { controller.skipRest() }
                        .buttonStyle(SecondaryGymButtonStyle())
                        .accessibilityIdentifier("workout.skipRest")
                }
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
        .background(.ultraThinMaterial)
    }

    private var restTechniquePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.isRestingBeforeNextExercise ? "NEXT EXERCISE" : "TECHNIQUE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let definition = techniqueDefinition {
                Text(definition.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TechniqueClipView(exercise: definition, height: 240)
                    .id(definition.id)
                    .frame(maxWidth: .infinity)
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

    private func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private var assignedMusicTitle: String {
        if let current = music.nowPlaying {
            return "\(current.artist) — \(current.title)"
        }
        if let exerciseID = controller.currentExercise?.exerciseId,
           let match = assignments.first(where: { $0.exerciseId == exerciseID }) {
            return "\(match.cachedArtist) — \(match.cachedTitle)"
        }
        return "No assigned track"
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

struct ReplaceExerciseSheet: View {
    let exercises: [ExerciseDefinition]
    let onSelect: (ExerciseDefinition) -> Void

    var body: some View {
        NavigationStack {
            List(exercises.filter(\.isEnabled), id: \.id) { exercise in
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
            .navigationTitle("Replace exercise")
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
