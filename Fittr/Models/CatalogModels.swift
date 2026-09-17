import Foundation
import SwiftData

@Model
final class ExerciseDefinition {
    @Attribute(.unique) var id: UUID
    var name: String
    var slug: String
    var categoryRaw: String
    var primaryMusclesRaw: String
    var secondaryMusclesRaw: String
    var equipmentRaw: String
    var lateralityRaw: String
    var setupInstructions: String
    var movementInstructions: String
    var breathingCue: String
    var coachingCuesRaw: String
    var commonMistakesRaw: String
    var localVideoName: String
    var remoteVideoURL: String
    var thumbnailName: String
    var defaultMinReps: Int
    var defaultMaxReps: Int
    var defaultSetCount: Int
    var defaultRestSeconds: Int
    var defaultDurationSeconds: Int
    var defaultWeightKg: Double?
    var trackingModeRaw: String
    var notes: String
    var isEnabled: Bool

    var category: ExerciseCategory {
        get { ExerciseCategory(rawValue: categoryRaw) ?? .strength }
        set { categoryRaw = newValue.rawValue }
    }

    var trackingMode: TrackingMode {
        get { TrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
    }

    var laterality: Laterality {
        get { Laterality(rawValue: lateralityRaw) ?? .bilateral }
        set { lateralityRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .none }
        set { equipmentRaw = newValue.rawValue }
    }

    var primaryMuscleGroups: [MuscleGroup] {
        get { decodeList(primaryMusclesRaw, as: MuscleGroup.self) }
        set { primaryMusclesRaw = encodeList(newValue) }
    }

    var secondaryMuscleGroups: [MuscleGroup] {
        get { decodeList(secondaryMusclesRaw, as: MuscleGroup.self) }
        set { secondaryMusclesRaw = encodeList(newValue) }
    }

    var coachingCues: [String] {
        get { coachingCuesRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
        set { coachingCuesRaw = newValue.joined(separator: "\n") }
    }

    var commonMistakes: [String] {
        get { commonMistakesRaw.split(separator: "\n").map(String.init) }
        set { commonMistakesRaw = newValue.joined(separator: "\n") }
    }

    init(
        id: UUID,
        name: String,
        slug: String,
        category: ExerciseCategory,
        primaryMuscleGroups: [MuscleGroup],
        secondaryMuscleGroups: [MuscleGroup] = [],
        equipment: Equipment,
        laterality: Laterality = .bilateral,
        setupInstructions: String,
        movementInstructions: String,
        breathingCue: String,
        coachingCues: [String],
        commonMistakes: [String],
        localVideoName: String = "",
        remoteVideoURL: String = "",
        thumbnailName: String = "",
        defaultMinReps: Int = 8,
        defaultMaxReps: Int = 12,
        defaultSetCount: Int = 2,
        defaultRestSeconds: Int = 90,
        defaultDurationSeconds: Int = 0,
        defaultWeightKg: Double? = nil,
        trackingMode: TrackingMode = .repsWeight,
        notes: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.categoryRaw = category.rawValue
        self.primaryMusclesRaw = encodeList(primaryMuscleGroups)
        self.secondaryMusclesRaw = encodeList(secondaryMuscleGroups)
        self.equipmentRaw = equipment.rawValue
        self.lateralityRaw = laterality.rawValue
        self.setupInstructions = setupInstructions
        self.movementInstructions = movementInstructions
        self.breathingCue = breathingCue
        self.coachingCuesRaw = coachingCues.joined(separator: "\n")
        self.commonMistakesRaw = commonMistakes.joined(separator: "\n")
        self.localVideoName = localVideoName
        self.remoteVideoURL = remoteVideoURL
        self.thumbnailName = thumbnailName
        self.defaultMinReps = defaultMinReps
        self.defaultMaxReps = defaultMaxReps
        self.defaultSetCount = defaultSetCount
        self.defaultRestSeconds = defaultRestSeconds
        self.defaultDurationSeconds = defaultDurationSeconds
        self.defaultWeightKg = defaultWeightKg
        self.trackingModeRaw = trackingMode.rawValue
        self.notes = notes
        self.isEnabled = isEnabled
    }
}

@Model
final class WorkoutPlan {
    @Attribute(.unique) var id: UUID
    var name: String
    var isActive: Bool
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \WorkoutTemplate.plan)
    var templates: [WorkoutTemplate]

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = true,
        createdAt: Date = .now,
        templates: [WorkoutTemplate] = []
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.createdAt = createdAt
        self.templates = templates
    }
}

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String
    var estimatedDurationMinutes: Int
    var notes: String
    var weekdayRaw: Int
    var isOptionalDay: Bool
    var preferredHour: Int?
    var preferredMinute: Int?
    var createdAt: Date
    var updatedAt: Date
    var plan: WorkoutPlan?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutTemplateExercise.template)
    var exercises: [WorkoutTemplateExercise]
    @Relationship(deleteRule: .cascade, inverse: \MusicAssignment.template)
    var musicAssignments: [MusicAssignment]

    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRaw) ?? .strength }
        set { typeRaw = newValue.rawValue }
    }

    var weekday: ISOWeekday {
        get { ISOWeekday(rawValue: weekdayRaw) ?? .monday }
        set { weekdayRaw = newValue.rawValue }
    }

    var orderedExercises: [WorkoutTemplateExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: WorkoutType,
        estimatedDurationMinutes: Int,
        notes: String = "",
        weekday: ISOWeekday,
        isOptionalDay: Bool = false,
        preferredHour: Int? = nil,
        preferredMinute: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        plan: WorkoutPlan? = nil,
        exercises: [WorkoutTemplateExercise] = [],
        musicAssignments: [MusicAssignment] = []
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.notes = notes
        self.weekdayRaw = weekday.rawValue
        self.isOptionalDay = isOptionalDay
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plan = plan
        self.exercises = exercises
        self.musicAssignments = musicAssignments
    }

    func makeSnapshot() -> TemplateSnapshot {
        TemplateSnapshot(
            templateId: id,
            name: name,
            type: type,
            estimatedDurationMinutes: estimatedDurationMinutes,
            notes: notes,
            exercises: orderedExercises.compactMap { item in
                guard let definition = item.exercise else { return nil }
                return TemplateExerciseSnapshot(
                    id: item.id,
                    exerciseId: definition.id,
                    exerciseName: definition.name,
                    category: definition.category,
                    trackingMode: item.trackingModeOverride ?? definition.trackingMode,
                    laterality: definition.laterality,
                    order: item.order,
                    targetSets: item.targetSets,
                    minReps: item.minReps,
                    maxReps: item.maxReps,
                    targetDurationSeconds: item.targetDurationSeconds,
                    targetRestSeconds: item.targetRestSeconds,
                    isOptional: item.isOptional,
                    equipment: definition.equipment,
                    slug: definition.slug
                )
            }
        )
    }
}

@Model
final class WorkoutTemplateExercise {
    @Attribute(.unique) var id: UUID
    var order: Int
    var targetSets: Int
    var minReps: Int?
    var maxReps: Int?
    var targetDurationSeconds: Int?
    var targetRestSeconds: Int
    var isOptional: Bool
    var trackingModeOverrideRaw: String?
    var notes: String
    var template: WorkoutTemplate?
    var exercise: ExerciseDefinition?

    var trackingModeOverride: TrackingMode? {
        get {
            guard let trackingModeOverrideRaw else { return nil }
            return TrackingMode(rawValue: trackingModeOverrideRaw)
        }
        set { trackingModeOverrideRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        order: Int,
        targetSets: Int,
        minReps: Int? = nil,
        maxReps: Int? = nil,
        targetDurationSeconds: Int? = nil,
        targetRestSeconds: Int,
        isOptional: Bool = false,
        trackingModeOverride: TrackingMode? = nil,
        notes: String = "",
        template: WorkoutTemplate? = nil,
        exercise: ExerciseDefinition? = nil
    ) {
        self.id = id
        self.order = order
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.targetDurationSeconds = targetDurationSeconds
        self.targetRestSeconds = targetRestSeconds
        self.isOptional = isOptional
        self.trackingModeOverrideRaw = trackingModeOverride?.rawValue
        self.notes = notes
        self.template = template
        self.exercise = exercise
    }
}

@Model
final class MusicAssignment {
    @Attribute(.unique) var id: UUID
    var scopeRaw: String
    var musicItemID: String
    var cachedTitle: String
    var cachedArtist: String
    var artworkURL: String
    var autoplay: Bool
    var restartFromBeginning: Bool
    var sourceRaw: String
    /// A whole playlist instead of one song, for sessions long enough that a single
    /// track leaves you in silence — a 35-minute ride outlasts any one song.
    ///
    /// This stores the playlist's persistent ID rather than a snapshot of its track
    /// IDs, so editing the playlist in the Music app is picked up automatically and
    /// a song removed from the library cannot leave a dead reference behind. Empty
    /// means this is an ordinary single-track assignment via `musicItemID`.
    var playlistID: String = ""
    var playlistName: String = ""
    var shufflePlaylist: Bool = false
    /// Loops the playlist so the music outlasts the session however long it runs.
    /// This is what actually makes the feature reliable rather than merely longer.
    var repeatPlaylist: Bool = true
    var template: WorkoutTemplate?
    var exerciseId: UUID?

    var isPlaylist: Bool { !playlistID.isEmpty }

    var scope: MusicScope {
        get { MusicScope(rawValue: scopeRaw) ?? .workout }
        set { scopeRaw = newValue.rawValue }
    }

    var source: MusicItemSource {
        get { MusicItemSource(rawValue: sourceRaw) ?? .localLibrary }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        scope: MusicScope,
        musicItemID: String,
        cachedTitle: String,
        cachedArtist: String,
        artworkURL: String = "",
        autoplay: Bool = true,
        restartFromBeginning: Bool = true,
        source: MusicItemSource = .localLibrary,
        playlistID: String = "",
        playlistName: String = "",
        shufflePlaylist: Bool = false,
        repeatPlaylist: Bool = true,
        template: WorkoutTemplate? = nil,
        exerciseId: UUID? = nil
    ) {
        self.id = id
        self.scopeRaw = scope.rawValue
        self.musicItemID = musicItemID
        self.cachedTitle = cachedTitle
        self.cachedArtist = cachedArtist
        self.artworkURL = artworkURL
        self.autoplay = autoplay
        self.restartFromBeginning = restartFromBeginning
        self.sourceRaw = source.rawValue
        self.playlistID = playlistID
        self.playlistName = playlistName
        self.shufflePlaylist = shufflePlaylist
        self.repeatPlaylist = repeatPlaylist
        self.template = template
        self.exerciseId = exerciseId
    }
}

private func encodeList<T: RawRepresentable>(_ values: [T]) -> String where T.RawValue == String {
    values.map(\.rawValue).joined(separator: ",")
}

private func decodeList<T: RawRepresentable>(_ raw: String, as: T.Type) -> [T] where T.RawValue == String {
    raw.split(separator: ",").compactMap { T(rawValue: String($0)) }
}
