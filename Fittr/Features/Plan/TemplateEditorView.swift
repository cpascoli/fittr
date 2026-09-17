import SwiftData
import SwiftUI

struct TemplateEditorView: View {
    @Bindable var template: WorkoutTemplate
    /// The scheduled occurrence this was opened from, when there is one. Carried
    /// through to the session so the schedule is marked complete and adherence
    /// counts it; starting a template directly stays `nil` and unscheduled.
    let scheduled: ScheduledWorkout?
    @Query(sort: \ExerciseDefinition.name) private var library: [ExerciseDefinition]
    @State private var adding = false
    @State private var creatingExercise = false
    @State private var startedSession: WorkoutSession?
    @State private var hasPreferredTime: Bool
    @State private var preferredTime: Date
    @Environment(\.modelContext) private var modelContext

    init(template: WorkoutTemplate, scheduled: ScheduledWorkout? = nil) {
        self.template = template
        self.scheduled = scheduled
        let hour = template.preferredHour
        let minute = template.preferredMinute
        _hasPreferredTime = State(initialValue: hour != nil && minute != nil)
        _preferredTime = State(initialValue: DateHelpers.applying(hour: hour, minute: minute, to: .now))
    }

    var body: some View {
        List {
            Section("Workout") {
                TextField("Name", text: $template.name)
                Picker("Type", selection: Binding(
                    get: { template.type },
                    set: { template.type = $0 }
                )) {
                    ForEach(WorkoutType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                Stepper("Estimated \(template.estimatedDurationMinutes) min", value: $template.estimatedDurationMinutes, in: 0...180, step: 5)
                Picker("Weekday", selection: Binding(
                    get: { template.weekday },
                    set: { newDay in
                        template.weekday = newDay
                        try? ScheduleService.syncUpcomingTimes(for: template, in: modelContext)
                    }
                )) {
                    ForEach(ISOWeekday.allCases) { day in
                        Text(day.title).tag(day)
                    }
                }
                Toggle("Optional day", isOn: $template.isOptionalDay)
                Toggle("Usual start time", isOn: $hasPreferredTime)
                    .onChange(of: hasPreferredTime) { _, enabled in
                        if enabled {
                            applyPreferredTime()
                        } else {
                            template.preferredHour = nil
                            template.preferredMinute = nil
                            try? ScheduleService.syncUpcomingTimes(for: template, in: modelContext)
                        }
                    }
                if hasPreferredTime {
                    DatePicker("Time", selection: $preferredTime, displayedComponents: .hourAndMinute)
                        .onChange(of: preferredTime) { _, _ in
                            applyPreferredTime()
                        }
                }
                TextField("Notes", text: $template.notes, axis: .vertical)
            }
            if template.type == .strength {
                Section("Music") {
                    NavigationLink("Assign local tracks") {
                        WorkoutMusicSetupView(template: template)
                    }
                }
            }
            Section("Exercises") {
                ForEach(template.orderedExercises, id: \.id) { item in
                    TemplateExerciseEditor(item: item)
                }
                .onMove { source, destination in
                    var items = template.orderedExercises
                    items.move(fromOffsets: source, toOffset: destination)
                    for (index, item) in items.enumerated() {
                        item.order = index
                    }
                }
                .onDelete { offsets in
                    let items = template.orderedExercises
                    for index in offsets {
                        template.exercises.removeAll { $0.id == items[index].id }
                    }
                    for (index, item) in template.orderedExercises.enumerated() {
                        item.order = index
                    }
                }
                Button("Add exercise") { adding = true }
            }
        }
        .navigationTitle(template.name)
        .toolbar { EditButton() }
        .safeAreaInset(edge: .bottom) {
            if template.type.isTrainable {
                Button("Start Workout") {
                    startedSession = try? WorkoutSessionFactory.start(
                        template: template,
                        scheduled: scheduled,
                        source: scheduled == nil ? .manual : .scheduled,
                        in: modelContext
                    )
                }
                .buttonStyle(GymButtonStyle())
                .padding(16)
                .accessibilityIdentifier("template.start")
            }
        }
        .fullScreenCover(item: $startedSession) { session in
            ActiveWorkoutHost(
                session: session,
                settings: try? modelContext.fetch(FetchDescriptor<AppSettings>()).first,
                profile: try? modelContext.fetch(FetchDescriptor<UserProfile>()).first,
                modelContext: modelContext
            )
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                List {
                    // Offered here as well as in the library: finding the exercise
                    // missing happens while you are building the workout.
                    Button("Create a new exercise", systemImage: "plus") { creatingExercise = true }
                    ForEach(library.filter(\.isEnabled), id: \.id) { definition in
                        Button(definition.name) { add(definition) }
                    }
                }
                .navigationTitle("Add exercise")
                .sheet(isPresented: $creatingExercise) {
                    NewExerciseSheet { definition in
                        add(definition)
                    }
                }
            }
        }
    }

    private func add(_ definition: ExerciseDefinition) {
        let item = WorkoutTemplateExercise(
            order: template.exercises.count,
            targetSets: definition.defaultSetCount,
            minReps: definition.defaultMinReps,
            maxReps: definition.defaultMaxReps,
            targetDurationSeconds: definition.defaultDurationSeconds == 0 ? nil : definition.defaultDurationSeconds,
            targetRestSeconds: definition.defaultRestSeconds,
            template: template,
            exercise: definition
        )
        template.exercises.append(item)
        adding = false
    }

    private func applyPreferredTime() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: preferredTime)
        template.preferredHour = components.hour
        template.preferredMinute = components.minute
        try? ScheduleService.syncUpcomingTimes(for: template, in: modelContext)
    }
}

private struct TemplateExerciseEditor: View {
    @Bindable var item: WorkoutTemplateExercise
    @Query private var assignments: [MusicAssignment]
    @State private var showingMusic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.exercise?.name ?? "Exercise")
                .font(.headline)
            if let assignment = assignedTrack {
                Text("\(assignment.cachedArtist) — \(assignment.cachedTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Stepper("Sets \(item.targetSets)", value: $item.targetSets, in: 1...8)
            if let mode = item.exercise?.trackingMode, mode.usesReps {
                Stepper("Min reps \(item.minReps ?? 8)", value: Binding(
                    get: { item.minReps ?? 8 },
                    set: { item.minReps = $0 }
                ), in: 1...20)
                Stepper("Max reps \(item.maxReps ?? 12)", value: Binding(
                    get: { item.maxReps ?? 12 },
                    set: { item.maxReps = $0 }
                ), in: 1...20)
            } else if let mode = item.exercise?.trackingMode, mode.usesDuration {
                durationStepper(countsInSeconds: mode.countsInSeconds)
            }
            Stepper("Rest \(item.targetRestSeconds)s", value: $item.targetRestSeconds, in: 0...300, step: 15)
            Toggle("Optional", isOn: $item.isOptional)
            Button("Choose local track") { showingMusic = true }
        }
        .sheet(isPresented: $showingMusic) {
            if let exerciseId = item.exercise?.id {
                MusicPickerView(exerciseId: exerciseId, template: item.template)
            }
        }
    }

    /// Duration-tracked exercises had no control at all here, so a 35-minute ride
    /// was fixed at whatever the seed data said.
    @ViewBuilder
    private func durationStepper(countsInSeconds: Bool) -> some View {
        if countsInSeconds {
            Stepper("Hold \(item.targetDurationSeconds ?? 30)s", value: Binding(
                get: { item.targetDurationSeconds ?? 30 },
                set: { item.targetDurationSeconds = $0 }
            ), in: 5...600, step: 5)
        } else {
            Stepper("Duration \(minutes) min", value: Binding(
                get: { minutes },
                set: { item.targetDurationSeconds = $0 * 60 }
            ), in: 5...180, step: 5)
        }
    }

    private var minutes: Int {
        max(1, (item.targetDurationSeconds ?? 1800) / 60)
    }

    private var assignedTrack: MusicAssignment? {
        guard let exerciseId = item.exercise?.id else { return nil }
        return assignments.first { $0.exerciseId == exerciseId }
    }
}
