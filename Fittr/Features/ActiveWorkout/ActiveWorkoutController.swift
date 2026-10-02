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
    var draftDurationSeconds: Int = ExerciseLibrarySeed.plankTargetSeconds
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
    var isMusicPlaying = false
    var tick: Date = .now
    /// Hold-timer state for duration exercises (plank). Like the rest timer it is
    /// derived from timestamps rather than counted down in a tick, so backgrounding
    /// the app mid-hold does not distort the recorded time.
    private(set) var holdStartedAt: Date?
    private(set) var holdElapsedBeforePause: TimeInterval = 0
    private(set) var measuredHoldSeconds: Int?
    private(set) var holdDidComplete = false
    private var holdDidFireHaptic = false

    private var restActive = false
    private var musicPausedForRest = false
    private var musicStoppedByUser = false
    private var allowMusicDuringRest = false
    private var playbackGeneration = 0

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
        self.units = profile?.liftingUnits ?? .metric
        self.weightIncrementKg = settings?.weightIncrementKg ?? 2
        self.autoPlayExerciseTrack = settings?.autoPlayExerciseTrack ?? true
        self.restartExerciseTrack = settings?.restartExerciseTrack ?? true
        (haptics as? HapticService)?.isEnabled = settings?.hapticsEnabled ?? true
        restoreCurrentExercise()
        let history = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        previousWorkout = resolvePreviousWorkout(in: history)
        lastTimeByExercise = AnalyticsEngine.latestExerciseSessions(
            before: session.startedAt,
            excluding: session.id,
            in: history
        )
        prefillFromHistory()
        if session.endedAt != nil {
            showingSummary = true
            isMusicPlaying = music.isPlaying
            return
        }
        activateCurrentIfNeeded()
        restActive = openRest != nil
        if restActive {
            nextExercisePlan = resolveNextExercisePlan()
        }
        // Silence belongs only on the screen between exercises. Rest between sets
        // of the same exercise keeps the current track going.
        if isRestingBeforeNextExercise {
            pauseMusicForRest()
        } else {
            isMusicPlaying = music.isPlaying
            playAssignedMusicIfNeeded()
        }
    }

    var snapshot: TemplateSnapshot? { session.snapshot }

    var currentExercise: ExerciseSession? {
        let items = session.orderedExercises
        guard items.indices.contains(currentExerciseIndex) else { return items.last }
        return items[currentExerciseIndex]
    }

    var prescription: TemplateExerciseSnapshot? { currentExercise?.prescription }

    var openRest: RestInterval? {
        currentExercise?.rests
            .filter(\.isOpen)
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    var isResting: Bool { restActive || openRest != nil }

    var isRestingBeforeNextExercise: Bool {
        guard isResting else { return false }
        return openRest?.shouldAdvanceToNextExercise == true || hasCompletedPrescribedSets
    }

    var hasCompletedPrescribedSets: Bool {
        completedSetCount >= targetSets
    }

    var completedSetCount: Int {
        let fromSets = currentExercise?.completedSets.map(\.setNumber).max() ?? 0
        return fromSets
    }

    var nextExerciseName: String? {
        nextExerciseSession?.exerciseName
    }

    var nextExerciseId: UUID? {
        nextExerciseSession?.exerciseId
    }

    var techniqueExerciseId: UUID? {
        if isRestingBeforeNextExercise {
            return nextExerciseId
        }
        return currentExercise?.exerciseId
    }

    var hasNextExercise: Bool {
        nextExerciseSession != nil
    }

    /// Resolved when a rest begins, not on demand. Building it decodes a
    /// snapshot and fetches planned loads and every exercise definition, and
    /// the rest card re-renders on every tick.
    private(set) var nextExercisePlan: NextExercisePlan?

    private func resolveNextExercisePlan() -> NextExercisePlan? {
        guard let next = nextExerciseSession else { return nil }
        let prescription = next.prescription
        let mode = prescription?.trackingMode
        // The same resolver `prefillFromHistory` uses once the rest ends, so the
        // rack trip and the first set agree on a number.
        let prefill = prefill(for: next, setNumber: next.completedSets.count + 1)
        let isPerSide = prescription?.laterality == .unilateral
        return NextExercisePlan(
            name: next.exerciseName,
            targetLabel: prescription?.targetRepLabel,
            weightKg: (mode?.usesWeight ?? false) ? prefill.weightKg : nil,
            basis: (mode?.usesWeight ?? false) ? prefill.basis.flatMap(NextExercisePlan.Basis.init) : nil,
            reps: (mode?.usesReps ?? false) ? (isPerSide ? prefill.leftReps : prefill.reps) : nil,
            rightReps: (mode?.usesReps ?? false) && isPerSide ? prefill.rightReps : nil,
            isPerSide: isPerSide,
            equipmentLabel: prescription.map(\.equipment).flatMap { $0 == .none ? nil : $0.title }
        )
    }

    private func prefill(for exercise: ExerciseSession, setNumber: Int) -> SetPrefill {
        SetPrefillResolver.resolve(
            setNumber: setNumber,
            sessionSets: exercise.completedSets,
            plannedWeightKg: PlannedLoadService.weight(for: exercise.exerciseId, in: modelContext),
            previousSets: lastTimeByExercise[exercise.exerciseId]?.completedSets ?? [],
            startingWeightKg: startingWeightKg(for: exercise.exerciseId),
            maxReps: exercise.prescription?.maxReps
        )
    }

    private var nextExerciseSession: ExerciseSession? {
        let items = session.orderedExercises
        let next = currentExerciseIndex + 1
        guard items.indices.contains(next) else { return nil }
        return items[next]
    }

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

    /// The last time the current exercise was lifted, in any workout — not just
    /// the previous run of this template.
    var previousExerciseSession: ExerciseSession? {
        guard let current = currentExercise else { return nil }
        return lastTimeByExercise[current.exerciseId]
    }

    /// Resolved once in `init`. Which session this one compares against cannot
    /// change while it is under way, and computing it fetched every workout ever
    /// recorded — on every body evaluation, several times a second. Only the
    /// summary's whole-workout comparison uses it; per-exercise numbers come
    /// from `lastTimeByExercise`.
    private(set) var previousWorkout: WorkoutSession?

    /// Resolved once in `init`, for the same reason. Keyed by exercise so a
    /// replaced exercise still finds its own history.
    private var lastTimeByExercise: [UUID: ExerciseSession] = [:]

    private func resolvePreviousWorkout(in all: [WorkoutSession]) -> WorkoutSession? {
        AnalyticsEngine.previousComparableSession(
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

    // MARK: - Hold timer

    var isHolding: Bool { holdStartedAt != nil }

    var holdTargetSeconds: Int { max(1, draftDurationSeconds) }

    var holdElapsed: TimeInterval {
        guard let holdStartedAt else { return holdElapsedBeforePause }
        return holdElapsedBeforePause + max(0, tick.timeIntervalSince(holdStartedAt))
    }

    var holdRemaining: TimeInterval {
        max(0, Double(holdTargetSeconds) - holdElapsed)
    }

    var holdProgress: Double {
        min(1, holdElapsed / Double(holdTargetSeconds))
    }

    /// True once the full target has been held. The set is not logged
    /// automatically — you still confirm it, because dropping out early is
    /// normal and the honest number matters more than the convenience.
    var holdIsFinished: Bool { holdDidComplete }

    func startHold() {
        guard !isHolding else { return }
        holdDidComplete = false
        holdDidFireHaptic = false
        holdStartedAt = .now
    }

    /// Stops the hold and keeps whatever was actually held, so a 22-second
    /// attempt at a 30-second plank is recorded as 22.
    func stopHold() {
        holdElapsedBeforePause = holdElapsed
        holdStartedAt = nil
        measuredHoldSeconds = Int(holdElapsedBeforePause.rounded())
    }

    func resetHold() {
        holdStartedAt = nil
        holdElapsedBeforePause = 0
        measuredHoldSeconds = nil
        holdDidComplete = false
        holdDidFireHaptic = false
    }

    /// Whether anything on screen is counting. When nothing is, there is nothing to
    /// refresh, and the app can go idle — which the battery appreciates and which
    /// XCUITest requires before it will do anything at all.
    var needsTicking: Bool { isResting || isHolding }

    /// Reads the player rather than assuming, so the Play/Pause label survives the
    /// user reaching for Control Center. Called on events, not on a timer: polling
    /// `playbackState` is an IPC round trip and it was running four times a second.
    func syncMusicState() {
        isMusicPlaying = music.isPlaying
    }

    func pulse() {
        tick = .now
        if restIsReady && !restDidFireHaptic {
            restDidFireHaptic = true
            haptics.restComplete()
        }
        if isHolding, holdRemaining == 0, !holdDidFireHaptic {
            holdDidFireHaptic = true
            holdDidComplete = true
            stopHold()
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
            durationSeconds: usesDuration ? Double(measuredHoldSeconds ?? draftDurationSeconds) : nil,
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
        resetHold()
        persist()
        PlannedLoadService.consume(exerciseId: exercise.exerciseId, in: modelContext)
        haptics.setCompleted()
        beginRestAfterCompletedSet(set, on: exercise)
    }

    func startRest(after set: ExerciseSet?, exercise: ExerciseSession, advancesToNextExercise: Bool) {
        finishOpenRest()
        restDidFireHaptic = false
        restActive = true
        let target = max(prescription?.targetRestSeconds ?? 90, 1)
        let rest = RestInterval(
            targetDurationSeconds: target,
            startedAt: .now,
            afterSetId: set?.id,
            advancesToNextExercise: advancesToNextExercise,
            exercise: exercise
        )
        exercise.rests.append(rest)
        nextExercisePlan = resolveNextExercisePlan()
        persist()
        notifications.scheduleRestComplete(after: TimeInterval(target))
        if advancesToNextExercise {
            pauseMusicForRest()
        }
    }

    func addRest(_ seconds: Int) {
        guard let rest = openRest else { return }
        rest.targetDurationSeconds += seconds
        persist()
        notifications.scheduleRestComplete(after: remainingRest + TimeInterval(seconds))
    }

    func skipRest() {
        let shouldAdvance = openRest?.shouldAdvanceToNextExercise == true || hasCompletedPrescribedSets
        finishOpenRest()
        notifications.cancelRestComplete()
        persist()
        if shouldAdvance {
            musicPausedForRest = false
            allowMusicDuringRest = false
            markCurrentExerciseCompleted()
            moveToNextExercise()
        } else if musicPausedForRest {
            // The track was left running through this rest, so there is nothing to
            // resume unless the listener paused it themselves.
            resumeMusicAfterRest()
        }
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
        if advance, hasNextExercise {
            if isRestingBeforeNextExercise {
                skipRest()
                return
            }
            startRest(after: exercise.completedSets.last, exercise: exercise, advancesToNextExercise: true)
            return
        }
        finishOpenRest()
        notifications.cancelRestComplete()
        markCurrentExerciseCompleted()
        if advance {
            if hasNextExercise {
                moveToNextExercise()
            } else {
                finishWorkout()
            }
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
        playbackGeneration += 1
        music.pause()
        isMusicPlaying = false
        musicPausedForRest = false
        allowMusicDuringRest = false
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
            Task { await WorkoutReminderService.reconcile(in: modelContext) }
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
            nextExercisePlan = nil
            resetHold()
            activateCurrentIfNeeded()
            prefillFromHistory()
            playAssignedMusicIfNeeded()
        } else {
            finishWorkout()
        }
    }

    /// Marks the exercise started. Deliberately does not touch music: it used to
    /// start playback too, so advancing an exercise requested the new track twice
    /// — once here and once from `moveToNextExercise` — and the two requests raced.
    /// Callers start music themselves, exactly once.
    private func activateCurrentIfNeeded() {
        guard let exercise = currentExercise else { return }
        if exercise.startedAt == nil {
            exercise.startedAt = .now
        }
        if exercise.status == .pending {
            exercise.status = .active
        }
        persist()
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
        guard let exercise = currentExercise else { return }
        let values = prefill(for: exercise, setNumber: currentSetNumber)
        if let weight = values.weightKg { draftWeightKg = weight }
        if let reps = values.reps { draftReps = reps }
        if let left = values.leftReps { draftLeftReps = left }
        if let right = values.rightReps { draftRightReps = right }
        if let duration = prescription?.targetDurationSeconds, duration > 0 {
            draftDurationSeconds = duration
        }
    }

    private func startingWeightKg(for exerciseId: UUID) -> Double? {
        if let stored = (try? modelContext.fetch(FetchDescriptor<ExerciseDefinition>()))?
            .first(where: { $0.id == exerciseId })?
            .defaultWeightKg {
            return stored
        }
        return ExerciseLibrarySeed.startingWeightKg[exerciseId]
    }

    private func beginRestAfterCompletedSet(_ set: ExerciseSet, on exercise: ExerciseSession) {
        let completedCount = max(set.setNumber, exercise.completedSets.map(\.setNumber).max() ?? 0)
        let moreSetsHere = completedCount < targetSets
        if moreSetsHere {
            startRest(after: set, exercise: exercise, advancesToNextExercise: false)
            return
        }
        if hasNextExercise {
            startRest(after: set, exercise: exercise, advancesToNextExercise: true)
            return
        }
        markCurrentExerciseCompleted()
        finishWorkout()
    }

    private func markCurrentExerciseCompleted() {
        guard let exercise = currentExercise else { return }
        if exercise.startedAt == nil {
            exercise.startedAt = .now
        }
        exercise.endedAt = .now
        exercise.status = .completed
        persist()
        haptics.exerciseComplete()
    }

    private func finishOpenRest() {
        if let exercise = currentExercise {
            for rest in exercise.rests where rest.isOpen {
                rest.endedAt = .now
            }
        }
        restActive = false
        restDidFireHaptic = false
    }

    private func persist() {
        try? modelContext.save()
    }

    func pauseMusic() {
        allowMusicDuringRest = false
        music.pause()
        musicPausedForRest = isResting
        isMusicPlaying = false
    }

    /// True when the current exercise plays a playlist rather than one song, which
    /// is the only case where skipping forward has anywhere to go.
    var hasPlaylistAssigned: Bool {
        guard let exercise = currentExercise else { return false }
        let assignments = (try? modelContext.fetch(FetchDescriptor<MusicAssignment>())) ?? []
        if let match = assignments.first(where: { $0.exerciseId == exercise.exerciseId && $0.scope == .exercise }) {
            return match.isPlaylist
        }
        return assignments.first {
            $0.template?.id == session.workoutTemplateId && $0.scope == .workout
        }?.isPlaylist ?? false
    }

    func nextTrack() {
        music.next()
        isMusicPlaying = true
    }

    func previousTrack() {
        music.previous()
        isMusicPlaying = true
    }

    func stopMusic() {
        allowMusicDuringRest = false
        playbackGeneration += 1
        music.stop()
        musicPausedForRest = false
        musicStoppedByUser = true
        isMusicPlaying = false
    }

    func playMusic() {
        musicStoppedByUser = false
        musicPausedForRest = false
        allowMusicDuringRest = isResting
        if music.nowPlaying != nil {
            music.resume()
            isMusicPlaying = true
            return
        }
        playAssignedMusicIfNeeded()
    }

    private func pauseMusicForRest() {
        allowMusicDuringRest = false
        music.pause()
        musicPausedForRest = true
        isMusicPlaying = false
    }

    private func resumeMusicAfterRest() {
        allowMusicDuringRest = false
        musicPausedForRest = false
        guard !musicStoppedByUser else { return }
        music.resume()
        isMusicPlaying = true
    }

    private func playAssignedMusicIfNeeded() {
        guard session.endedAt == nil, !showingSummary else { return }
        guard autoPlayExerciseTrack, !musicStoppedByUser, let exercise = currentExercise else { return }
        if isRestingBeforeNextExercise && !allowMusicDuringRest { return }
        let assignments = (try? modelContext.fetch(FetchDescriptor<MusicAssignment>())) ?? []
        let assignment: MusicAssignment
        let restart: Bool
        if let match = assignments.first(where: { $0.exerciseId == exercise.exerciseId && $0.scope == .exercise }) {
            assignment = match
            restart = restartExerciseTrack && match.restartFromBeginning
        } else if let workoutMusic = assignments.first(where: { $0.template?.id == session.workoutTemplateId && $0.scope == .workout }) {
            assignment = workoutMusic
            restart = false
        } else {
            return
        }
        let playlistID = assignment.isPlaylist ? assignment.playlistID : nil
        let itemID = assignment.musicItemID
        let shuffle = assignment.shufflePlaylist
        let repeatAll = assignment.repeatPlaylist
        playbackGeneration += 1
        let generation = playbackGeneration
        Task {
            if let playlistID {
                // Resolved at playback time rather than stored, so editing the
                // playlist in the Music app is picked up without touching Fittr.
                let tracks = await music.songsInPlaylist(id: playlistID)
                if tracks.isEmpty {
                    await music.play(itemID: itemID, restart: restart)
                } else {
                    await music.play(
                        itemIDs: tracks.map(\.id),
                        restart: restart,
                        shuffle: shuffle,
                        repeatAll: repeatAll
                    )
                }
            } else {
                await music.play(itemID: itemID, restart: restart)
            }
            guard generation == playbackGeneration else {
                music.pause()
                return
            }
            if isRestingBeforeNextExercise && !allowMusicDuringRest {
                music.pause()
                isMusicPlaying = false
                return
            }
            isMusicPlaying = true
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

/// What to fetch from the rack before the next exercise starts, captured as
/// plain values so the rest card can re-render without decoding a snapshot.
struct NextExercisePlan: Equatable, Sendable {
    enum Basis: Equatable, Sendable {
        case planned
        case lastTime
        case starting

        init?(_ basis: SetPrefill.Basis) {
            switch basis {
            case .planned: self = .planned
            case .lastTime, .thisSession: self = .lastTime
            case .starting: self = .starting
            }
        }

        var label: String {
            switch self {
            case .planned: "Planned"
            case .lastTime: "Last time"
            case .starting: "Starting weight"
            }
        }
    }

    var name: String
    var targetLabel: String?
    var weightKg: Double?
    var basis: Basis?
    /// Reps the first set will start from. For a per-side exercise this is the
    /// left side and `rightReps` the right.
    var reps: Int?
    var rightReps: Int?
    var isPerSide: Bool
    var equipmentLabel: String?
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
