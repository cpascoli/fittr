import SwiftUI

struct WorkoutSummaryView: View {
    @Bindable var controller: ActiveWorkoutController
    var onDone: () -> Void
    @State private var sessionRPE: Double = 6
    @State private var enjoyment: Double = 4
    @State private var notes: String = ""
    @State private var acceptedIds: Set<UUID> = []
    @State private var choosing: ProgressionSuggestion?
    @State private var chosenWeight: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(controller.session.name)
                    .font(.largeTitle.weight(.bold))
                Text(DurationFormatting.compact(seconds: controller.session.elapsed()))
                    .font(.title.monospacedDigit())
                    .foregroundStyle(FittrTheme.accent)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(title: "Exercises", value: "\(controller.session.exercises.filter { $0.status != .skipped }.count)")
                    MetricTile(title: "Sets", value: "\(controller.session.completedSetCount)")
                    MetricTile(title: "Reps", value: "\(controller.session.completedReps)")
                    MetricTile(title: "Volume", value: NumberFormatting.volume(controller.session.trainingVolumeKg, units: controller.units))
                    MetricTile(title: "Active", value: DurationFormatting.compact(seconds: controller.session.totalActiveSeconds))
                    MetricTile(title: "Rest", value: DurationFormatting.compact(seconds: controller.session.totalRestSeconds))
                }

                if let avg = controller.session.averageRestSeconds {
                    Text("Avg rest: \(Int(avg.rounded())) sec")
                        .foregroundStyle(.secondary)
                }

                if let comparison = controller.comparison {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Previous → Today")
                            .font(.headline)
                        Text(comparison.volumeLine)
                        if !comparison.heavierExercises.isEmpty {
                            Text("Heavier: \(comparison.heavierExercises.joined(separator: ", "))")
                        }
                        if !comparison.higherRepExercises.isEmpty {
                            Text("More reps: \(comparison.higherRepExercises.joined(separator: ", "))")
                        }
                    }
                    .fittrCard()
                }

                if !controller.lastCreatedRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New personal records")
                            .font(.headline)
                        ForEach(controller.lastCreatedRecords, id: \.id) { record in
                            Text("\(record.kind.title) · \(record.exerciseName)")
                        }
                    }
                    .fittrCard()
                }

                ForEach(controller.progressionPrompts, id: \.exerciseId) { prompt in
                    progressionCard(prompt)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Optional check-in")
                        .font(.headline)
                    Text("Session RPE \(Int(sessionRPE))")
                    Slider(value: $sessionRPE, in: 1...10, step: 1)
                    Text("Enjoyment \(Int(enjoyment))")
                    Slider(value: $enjoyment, in: 1...5, step: 1)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
                .fittrCard()

                Button("Save Workout") {
                    controller.session.sessionRPE = Int(sessionRPE)
                    controller.session.enjoyment = Int(enjoyment)
                    if !notes.isEmpty {
                        controller.session.notes = notes
                    }
                    try? FittrDependencies.shared.modelContext?.save()
                    Task { await writeHealthIfNeeded() }
                    onDone()
                }
                .buttonStyle(GymButtonStyle())
                .accessibilityIdentifier("workout.save")
            }
            .padding(20)
        }
        .alert("Choose next weight", isPresented: Binding(
            get: { choosing != nil },
            set: { if !$0 { choosing = nil } }
        )) {
            TextField("Weight", value: $chosenWeight, format: .number)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let choosing {
                    let kg = UnitConversion.storageWeight(displayed: chosenWeight, units: controller.units)
                    controller.acceptProgression(choosing, weightKg: kg)
                    acceptedIds.insert(choosing.exerciseId)
                }
            }
            Button("Cancel", role: .cancel) { choosing = nil }
        }
    }

    private func progressionCard(_ prompt: ProgressionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready to progress")
                .font(.headline)
            Text(prompt.exerciseName)
                .font(.title3.weight(.semibold))
            Text("Last session: \(prompt.lastSets.joined(separator: ", "))")
            Text("Suggested next session: \(NumberFormatting.weight(prompt.suggestedWeightKg, units: controller.units))")
                .fontWeight(.semibold)
            if acceptedIds.contains(prompt.exerciseId) {
                Text("Next \(prompt.exerciseName) will start at the accepted weight.")
                    .font(.caption)
                    .foregroundStyle(FittrTheme.success)
            } else {
                Text("Nothing changes unless you accept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    Button("Accept \(NumberFormatting.weight(prompt.suggestedWeightKg, units: controller.units))") {
                        controller.acceptProgression(prompt)
                        acceptedIds.insert(prompt.exerciseId)
                    }
                    .buttonStyle(GymButtonStyle())
                    HStack {
                        Button("Keep current") {
                            controller.keepCurrentWeight(prompt)
                        }
                        .buttonStyle(SecondaryGymButtonStyle())
                        Button("Choose weight") {
                            chosenWeight = UnitConversion.displayWeight(kg: prompt.suggestedWeightKg, units: controller.units)
                            choosing = prompt
                        }
                        .buttonStyle(SecondaryGymButtonStyle())
                    }
                }
            }
        }
        .fittrCard()
    }

    private func writeHealthIfNeeded() async {
        let health = FittrDependencies.shared.health
        let settings = FittrDependencies.shared.settings
        guard settings?.healthWriteEnabled == true, health.isAuthorized else { return }
        guard let end = controller.session.endedAt else { return }
        do {
            let uuid = try await health.saveWorkout(
                sessionID: controller.session.id,
                type: controller.session.type,
                start: controller.session.startedAt,
                end: end,
                existingUUID: controller.session.healthKitWorkoutUUID
            )
            controller.session.healthKitWorkoutUUID = uuid
            try? FittrDependencies.shared.modelContext?.save()
        } catch {
            return
        }
    }
}
