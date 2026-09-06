import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ActiveWorkoutController {
    private let modelContext: ModelContext
    private let haptics: any HapticServicing
    private let notifications: any NotificationServicing
    private let music: any MusicServicing

    private(set) var session: WorkoutSession
    var currentExerciseIndex: Int = 0
    var draftWeightKg: Double = 10
    var draftReps: Int = 10
    var draftLeftReps: Int = 10
    var draftRightReps: Int = 10
    var draftDurationSeconds: Int = 25
    var draftRIR: Double?
    var draftRPE: Double?
    var draftNote: String = ""
    var showingTechnique = false
    var showingSummary = false
    var showingReplace = false
    var showingNote = false
    var progressionPrompts: [ProgressionSuggestion] = []
    var lastCreatedRecords: [PersonalRecord] = []
    var comparison: WorkoutComparison?
    var restDidFireHaptic = false
    var units: UnitSystem = .metric
    var weightIncrementKg: Double = 2
    var autoPlayExerciseTrack = false
    var restartExerciseTrack = true
    var tick: Date = .now

    init(
        session: WorkoutSession,
        modelContext: ModelContext,
        haptics: any HapticServicing,
        notifications: any NotificationServicing,
        music: any MusicServicing,
        settings: AppSettings?,
        profile: UserProfile?
    ) {
        self.session = session
        self.modelContext = modelContext
        self.haptics = haptics
        self.notifications = notifications
        self.music = music
        self.units = profile?.preferredUnits ?? .metric
        self.weightIncrementKg = settings?.weightIncrementKg ?? 2
        self.autoPlayExerciseTrack = settings?.autoPlayExerciseTrack ?? true
        self.restartExerciseTrack = settings?.restartExerciseTrack ?? true
        (haptics as? HapticService)?.isEnabled = settings?.hapticsEnabled ?? true
        restoreCurrentExercise()
        prefillFromHistory()
        activateCurrentIfNeeded()
    }

    var snapshot: TemplateSnapshot? { session.snapshot }

    var currentExercise: ExerciseSession? {
        let items = session.orderedExercises
        guard items.indices.contains(currentExerciseIndex) else { return items.last }
        return items[currentExerciseIndex]
    }

    var prescription: TemplateExerciseSnapshot? { currentExercise?.prescription }

    var openRest: RestInterval? {
        currentExercise?.rests.first { $0.isOpen }
    }

    var isResting: Bool { openRest != nil }

    var elapsedWorkout: TimeInterval {
        session.elapsed(now: tick)
    }

    var remainingRest: TimeInterval {
        guard let rest = openRest else { return 0 }
        let target = TimeInterval(rest.targetDurationSeconds)
        return max(0, target - tick.timeIntervalSince(rest.startedAt))
    }

    var restProgress: Double {
        guard let rest = openRest else { return 0 }
        let target = max(1, Double(rest.targetDurationSeconds))
        return min(1, tick.timeIntervalSince(rest.startedAt) / target)
    }

    var restIsReady: Bool {
        isResting && remainingRest == 0
    }

    var previousSets: [ExerciseSet] {
        previousExerciseSession?.completedSets ?? []
    }

    var previousExerciseSession: ExerciseSession? {
        guard let current = currentExercise else { return nil }
        return previousWorkout?.orderedExercises.first { $0.exerciseId == current.exerciseId }
    }

    var previousWorkout: WorkoutSession? {
        let all = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return AnalyticsEngine.previousComparableSession(
            for: session.workoutTemplateId,
            type: session.type,
            before: session.id,
            startedAt: session.startedAt,
            in: all
        )
    }

    var currentSetNumber: Int {
        (currentExercise?.completedSets.count ?? 0) + 1
    }

    var targetSets: Int {
        prescription?.targetSets ?? 2
    }

    func pulse() {
        tick = .now
        if restIsReady && !restDidFireHaptic {
            restDidFireHaptic = true
            haptics.restComplete()
        }
    }

    func completeSet() {
        guard let exercise = currentExercise else { return }
        finishOpenRest()
        let now = Date.now
        let set = ExerciseSet(
            setNumber: currentSetNumber,
            weightKg: usesWeight ? draftWeightKg : nil,
            reps: usesReps && !isUnilateral ? draftReps : (isUnilateral ? draftLeftReps + draftRightReps : nil),
            leftReps: isUnilateral ? draftLeftReps : nil,
            rightReps: isUnilateral ? draftRightReps : nil,
            durationSeconds: usesDuration ? Double(draftDurationSeconds) : nil,
            rpe: draftRPE,
            rir: draftRIR,
            startedAt: exercise.startedAt ?? now,
            completedAt: now,
            status: .completed,
            notes: draftNote,
            laterality: prescription?.laterality ?? .bilateral,
            exercise: exercise
        )
        exercise.sets.append(set)
        draftNote = ""
        persist()
        PlannedLoadService.consume(exerciseId: exercise.exerciseId, in: modelContext)
        haptics.setCompleted()

        let completedCount = exercise.completedSets.count
        if completedCount < targetSets {
            startRest(after: set, exercise: exercise)
        } else {
            finishExercise(advance: true)
        }
    }

    func startRest(after set: ExerciseSet, exercise: ExerciseSession) {
        finishOpenRest()
        restDidFireHaptic = false
        let target = prescription?.targetRestSeconds ?? 90
        let rest = RestInterval(
            targetDurationSeconds: target,
            startedAt: .now,
            afterSetId: set.id,
            exercise: exercise
        )
        exercise.rests.append(rest)
        persist()
        notifications.scheduleRestComplete(after: TimeInterval(target))
    }

    func addRest(_ seconds: Int) {
        guard let rest = openRest else { return }
        rest.targetDurationSeconds += seconds
        persist()
        notifications.scheduleRestComplete(after: remainingRest + TimeInterval(seconds))
    }

    func skipRest() {
        finishOpenRest()
        notifications.cancelRestComplete()
        persist()
    }

    func startNextSet() {
        skipRest()
    }

    func addSet() {
        guard let prescription else { return }
        // Extra set beyond the snapshot target is allowed; targetSets is a prescription, not a hard cap.
        _ = prescription
    }

    func removeLastSet() {
        guard let exercise = currentExercise, let last = exercise.orderedSets.last else { return }
        modelContext.delete(last)
        persist()
    }

    func finishExercise(advance: Bool) {
        guard let exercise = currentExercise else { return }
        finishOpenRest()
        notifications.cancelRestComplete()
        if exercise.startedAt == nil {
            exercise.startedAt = .now
        }
        exercise.endedAt = .now
        exercise.status = .completed
        persist()
        haptics.exerciseComplete()
        if advance {
            moveToNextExercise()
        }
    }

    func skipExercise() {
        guard let exercise = currentExercise else { return }
        finishOpenRest()
        exercise.status = .skipped
        exercise.endedAt = .now
        persist()
        moveToNextExercise()
    }

    func replaceCurrentExercise(with definition: ExerciseDefinition) {
        guard let exercise = currentExercise else { return }
        exercise.exerciseId = definition.id
        exercise.exerciseName = definition.name
        let updated = TemplateExerciseSnapshot(
            id: exercise.prescription?.id ?? UUID(),
            exerciseId: definition.id,
            exerciseName: definition.name,
            category: definition.category,
            trackingMode: definition.trackingMode,
            laterality: definition.laterality,
            order: exercise.order,
            targetSets: exercise.prescription?.targetSets ?? definition.defaultSetCount,
            minReps: definition.defaultMinReps,
            maxReps: definition.defaultMaxReps,
            targetDurationSeconds: definition.defaultDurationSeconds == 0 ? nil : definition.defaultDurationSeconds,
            targetRestSeconds: definition.defaultRestSeconds,
            isOptional: exercise.prescription?.isOptional ?? false,
            equipment: definition.equipment,
            slug: definition.slug
        )
        exercise.snapshotJSON = SnapshotCodec.encodeExercise(updated)
        persist()
        prefillFromHistory()
    }

    func finishWorkout() {
        finishOpenRest()
        notifications.cancelRestComplete()
        for exercise in session.orderedExercises where exercise.status == .active || exercise.status == .pending {
            if exercise.completedSets.isEmpty {
                exercise.status = .skipped
            } else {
                exercise.status = .completed
            }
            exercise.endedAt = exercise.endedAt ?? .now
        }
        session.endedAt = .now
        persist()
        if let scheduled = session.scheduled {
            try? ScheduleService.markCompleted(scheduled, session: session, in: modelContext)
        }
        lastCreatedRecords = (try? PersonalRecordService.evaluate(session: session, in: modelContext)) ?? []
        comparison = AnalyticsEngine.compare(current: session, previous: previousWorkout)
        let increment = weightIncrementKg
        progressionPrompts = ProgressionEngine.suggestions(from: session.progressionSummary, incrementKg: increment)
        haptics.workoutComplete()
        showingSummary = true
    }

    func saveNote(_ text: String, scope: NoteScope) {
        switch scope {
        case .workout:
            session.notes = text
        case .exercise:
            currentExercise?.notes = text
        }
        persist()
    }

    private func moveToNextExercise() {
        let items = session.orderedExercises
        if currentExerciseIndex + 1 < items.count {
            currentExerciseIndex += 1
            activateCurrentIfNeeded()
            prefillFromHistory()
            playAssignedMusicIfNeeded()
        } else {
            finishWorkout()
        }
    }

    private func activateCurrentIfNeeded() {
        guard let exercise = currentExercise else { return }
        if exercise.startedAt == nil {
            exercise.startedAt = .now
        }
        if exercise.status == .pending {
            exercise.status = .active
        }
        persist()
        playAssignedMusicIfNeeded()
    }

    private func restoreCurrentExercise() {
        if let activeIndex = session.orderedExercises.firstIndex(where: { $0.status == .active }) {
            currentExerciseIndex = activeIndex
            return
        }
        if let nextPending = session.orderedExercises.firstIndex(where: { $0.status == .pending }) {
            currentExerciseIndex = nextPending
            return
        }
        currentExerciseIndex = max(0, session.orderedExercises.count - 1)
    }

    func acceptProgression(_ suggestion: ProgressionSuggestion, weightKg: Double? = nil) {
        PlannedLoadService.accept(
            exerciseId: suggestion.exerciseId,
            weightKg: weightKg ?? suggestion.suggestedWeightKg,
            in: modelContext
        )
    }

    func keepCurrentWeight(_ suggestion: ProgressionSuggestion) {
        PlannedLoadService.clear(exerciseId: suggestion.exerciseId, in: modelContext)
    }

    private func prefillFromHistory() {
        let previous = previousSets
        if let planned = currentExercise.flatMap({ PlannedLoadService.weight(for: $0.exerciseId, in: modelContext) }) {
            draftWeightKg = planned
            if let matching = previous.first(where: { $0.setNumber == currentSetNumber }) ?? previous.last,
               let reps = matching.reps {
                draftReps = min(reps, prescription?.maxReps ?? reps)
                draftLeftReps = matching.leftReps ?? draftReps
                draftRightReps = matching.rightReps ?? draftReps
            } else if let maxReps = prescription?.maxReps, maxReps > 0 {
                draftReps = min(10, maxReps)
            }
            if let duration = prescription?.targetDurationSeconds, duration > 0 {
                draftDurationSeconds = duration
            }
            return
        }
        if let matching = previous.first(where: { $0.setNumber == currentSetNumber }) ?? previous.last {
            if let weight = matching.weightKg {
                draftWeightKg = weight
            }
            if let reps = matching.reps {
                draftReps = reps
                draftLeftReps = matching.leftReps ?? reps
                draftRightReps = matching.rightReps ?? reps
            }
        } else if let lastCompleted = currentExercise?.completedSets.last {
            draftWeightKg = lastCompleted.weightKg ?? draftWeightKg
            draftReps = lastCompleted.reps ?? draftReps
        } else if let maxReps = prescription?.maxReps, maxReps > 0 {
            draftReps = min(10, maxReps)
        }
        if let duration = prescription?.targetDurationSeconds, duration > 0 {
            draftDurationSeconds = duration
        }
    }

    private func finishOpenRest() {
        if let rest = openRest {
            rest.endedAt = .now
        }
        restDidFireHaptic = false
    }

    private func persist() {
        try? modelContext.save()
    }

    private func playAssignedMusicIfNeeded() {
        guard autoPlayExerciseTrack, let exercise = currentExercise else { return }
        let assignments = (try? modelContext.fetch(FetchDescriptor<MusicAssignment>())) ?? []
        if let match = assignments.first(where: { $0.exerciseId == exercise.exerciseId && $0.scope == .exercise }) {
            Task { await music.play(itemID: match.musicItemID, restart: restartExerciseTrack && match.restartFromBeginning) }
            return
        }
        if let workoutMusic = assignments.first(where: { $0.template?.id == session.workoutTemplateId && $0.scope == .workout }) {
            Task { await music.play(itemID: workoutMusic.musicItemID, restart: false) }
        }
    }

    var usesWeight: Bool { prescription?.trackingMode.usesWeight ?? true }
    var usesReps: Bool { prescription?.trackingMode.usesReps ?? true }
    var usesDuration: Bool { prescription?.trackingMode == .duration }
    var isUnilateral: Bool { prescription?.laterality == .unilateral }
    var isCardio: Bool {
        switch session.type {
        case .cardio, .swimming, .recovery: true
        case .strength, .rest, .mixed: false
        }
    }

    enum NoteScope {
        case workout
        case exercise
    }
}

enum WorkoutSessionFactory {
    static func start(
        template: WorkoutTemplate,
        scheduled: ScheduledWorkout?,
        source: WorkoutSource,
        in context: ModelContext
    ) throws -> WorkoutSession {
        let snapshot = template.makeSnapshot()
        let session = WorkoutSession(
            name: template.name,
            type: template.type,
            source: source,
            templateSnapshotJSON: SnapshotCodec.encode(snapshot),
            calendarEventIdentifier: scheduled?.calendarEventIdentifier.isEmpty == true ? nil : scheduled?.calendarEventIdentifier,
            workoutTemplateId: template.id,
            scheduled: scheduled
        )
        for item in snapshot.trainableExercises {
            let exercise = ExerciseSession(
                exerciseId: item.exerciseId,
                exerciseName: item.exerciseName,
                order: item.order,
                snapshotJSON: SnapshotCodec.encodeExercise(item),
                workout: session
            )
            session.exercises.append(exercise)
        }
        switch template.type {
        case .cardio, .recovery:
            let metrics = CardioMetrics(activityKind: template.name, workout: session)
            session.cardio = metrics
        case .swimming:
            let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
            session.swim = SwimMetrics(poolLengthMeters: settings?.defaultPoolLengthMeters ?? 25, workout: session)
        case .strength, .rest, .mixed:
            break
        }
        context.insert(session)
        try context.save()
        return session
    }

    static func inProgress(in context: ModelContext) -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }
}
