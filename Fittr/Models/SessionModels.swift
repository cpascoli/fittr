import Foundation
import SwiftData

@Model
final class ScheduledWorkout {
    @Attribute(.unique) var id: UUID
    var scheduledStart: Date
    var statusRaw: String
    var calendarEventIdentifier: String
    var recurrenceGroupId: UUID?
    var notes: String
    var createdAt: Date
    /// Where this workout sat before it was moved, so a reschedule can be undone
    /// exactly rather than by guessing "subtract a day". Survives repeated moves:
    /// after Thu → Fri → Sat this still reads Thursday, which is the day that was
    /// actually planned. `nil` means the workout is on its original day.
    var rescheduledFrom: Date?
    var template: WorkoutTemplate?
    var completedSession: WorkoutSession?

    var status: ScheduledStatus {
        get { ScheduledStatus(rawValue: statusRaw) ?? .upcoming }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        scheduledStart: Date,
        status: ScheduledStatus = .upcoming,
        calendarEventIdentifier: String = "",
        recurrenceGroupId: UUID? = nil,
        notes: String = "",
        createdAt: Date = .now,
        rescheduledFrom: Date? = nil,
        template: WorkoutTemplate? = nil,
        completedSession: WorkoutSession? = nil
    ) {
        self.id = id
        self.scheduledStart = scheduledStart
        self.statusRaw = status.rawValue
        self.calendarEventIdentifier = calendarEventIdentifier
        self.recurrenceGroupId = recurrenceGroupId
        self.notes = notes
        self.createdAt = createdAt
        self.rescheduledFrom = rescheduledFrom
        self.template = template
        self.completedSession = completedSession
    }
}

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String
    var sourceRaw: String
    var startedAt: Date
    var endedAt: Date?
    var timeZoneIdentifier: String
    var templateSnapshotJSON: String
    var notes: String
    var preEnergy: Int?
    var preMotivation: Int?
    var preSoreness: Int?
    var sessionRPE: Int?
    var enjoyment: Int?
    var healthKitWorkoutUUID: String?
    var calendarEventIdentifier: String?
    var createdAt: Date
    var workoutTemplateId: UUID
    var scheduled: ScheduledWorkout?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSession.workout)
    var exercises: [ExerciseSession]
    @Relationship(deleteRule: .cascade, inverse: \CardioMetrics.workout)
    var cardio: CardioMetrics?
    @Relationship(deleteRule: .cascade, inverse: \SwimMetrics.workout)
    var swim: SwimMetrics?

    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRaw) ?? .strength }
        set { typeRaw = newValue.rawValue }
    }

    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var snapshot: TemplateSnapshot? {
        SnapshotCodec.decode(templateSnapshotJSON)
    }

    var isInProgress: Bool { endedAt == nil }

    var orderedExercises: [ExerciseSession] {
        exercises.sorted { $0.order < $1.order }
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: WorkoutType,
        source: WorkoutSource,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        templateSnapshotJSON: String,
        notes: String = "",
        preEnergy: Int? = nil,
        preMotivation: Int? = nil,
        preSoreness: Int? = nil,
        sessionRPE: Int? = nil,
        enjoyment: Int? = nil,
        healthKitWorkoutUUID: String? = nil,
        calendarEventIdentifier: String? = nil,
        createdAt: Date = .now,
        workoutTemplateId: UUID,
        scheduled: ScheduledWorkout? = nil,
        exercises: [ExerciseSession] = []
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.sourceRaw = source.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.templateSnapshotJSON = templateSnapshotJSON
        self.notes = notes
        self.preEnergy = preEnergy
        self.preMotivation = preMotivation
        self.preSoreness = preSoreness
        self.sessionRPE = sessionRPE
        self.enjoyment = enjoyment
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.calendarEventIdentifier = calendarEventIdentifier
        self.createdAt = createdAt
        self.workoutTemplateId = workoutTemplateId
        self.scheduled = scheduled
        self.exercises = exercises
    }
}

@Model
final class ExerciseSession {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var order: Int
    var startedAt: Date?
    var endedAt: Date?
    var notes: String
    var statusRaw: String
    var snapshotJSON: String
    var workout: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exercise)
    var sets: [ExerciseSet]
    @Relationship(deleteRule: .cascade, inverse: \RestInterval.exercise)
    var rests: [RestInterval]

    var status: ExerciseSessionStatus {
        get { ExerciseSessionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var prescription: TemplateExerciseSnapshot? {
        SnapshotCodec.decodeExercise(snapshotJSON)
    }

    var orderedSets: [ExerciseSet] {
        sets.sorted { $0.setNumber < $1.setNumber }
    }

    var completedSets: [ExerciseSet] {
        orderedSets.filter { $0.status == .completed }
    }

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseName: String,
        order: Int,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        notes: String = "",
        status: ExerciseSessionStatus = .pending,
        snapshotJSON: String,
        workout: WorkoutSession? = nil,
        sets: [ExerciseSet] = [],
        rests: [RestInterval] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.statusRaw = status.rawValue
        self.snapshotJSON = snapshotJSON
        self.workout = workout
        self.sets = sets
        self.rests = rests
    }
}

@Model
final class ExerciseSet {
    @Attribute(.unique) var id: UUID
    var setNumber: Int
    var weightKg: Double?
    var reps: Int?
    var leftReps: Int?
    var rightReps: Int?
    var durationSeconds: Double?
    var rpe: Double?
    var rir: Double?
    var startedAt: Date?
    var completedAt: Date?
    var statusRaw: String
    var notes: String
    var lateralityRaw: String
    var exercise: ExerciseSession?

    var status: SetStatus {
        get { SetStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var laterality: Laterality {
        get { Laterality(rawValue: lateralityRaw) ?? .bilateral }
        set { lateralityRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weightKg: Double? = nil,
        reps: Int? = nil,
        leftReps: Int? = nil,
        rightReps: Int? = nil,
        durationSeconds: Double? = nil,
        rpe: Double? = nil,
        rir: Double? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        status: SetStatus = .pending,
        notes: String = "",
        laterality: Laterality = .bilateral,
        exercise: ExerciseSession? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.leftReps = leftReps
        self.rightReps = rightReps
        self.durationSeconds = durationSeconds
        self.rpe = rpe
        self.rir = rir
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.statusRaw = status.rawValue
        self.notes = notes
        self.lateralityRaw = laterality.rawValue
        self.exercise = exercise
    }
}

@Model
final class RestInterval {
    @Attribute(.unique) var id: UUID
    var targetDurationSeconds: Int
    var startedAt: Date
    var endedAt: Date?
    var afterSetId: UUID?
    var advancesToNextExercise: Bool?
    var exercise: ExerciseSession?

    var isOpen: Bool { endedAt == nil }
    var shouldAdvanceToNextExercise: Bool { advancesToNextExercise == true }

    init(
        id: UUID = UUID(),
        targetDurationSeconds: Int,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        afterSetId: UUID? = nil,
        advancesToNextExercise: Bool = false,
        exercise: ExerciseSession? = nil
    ) {
        self.id = id
        self.targetDurationSeconds = targetDurationSeconds
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.afterSetId = afterSetId
        self.advancesToNextExercise = advancesToNextExercise
        self.exercise = exercise
    }
}

@Model
final class CardioMetrics {
    @Attribute(.unique) var id: UUID
    var activityKind: String
    var distanceKm: Double?
    var resistanceLevel: Double?
    var averageSpeedKmh: Double?
    var machineCalories: Double?
    var inclinePercent: Double?
    var steps: Int?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var rpe: Double?
    var notes: String
    var workout: WorkoutSession?

    init(
        id: UUID = UUID(),
        activityKind: String,
        distanceKm: Double? = nil,
        resistanceLevel: Double? = nil,
        averageSpeedKmh: Double? = nil,
        machineCalories: Double? = nil,
        inclinePercent: Double? = nil,
        steps: Int? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        rpe: Double? = nil,
        notes: String = "",
        workout: WorkoutSession? = nil
    ) {
        self.id = id
        self.activityKind = activityKind
        self.distanceKm = distanceKm
        self.resistanceLevel = resistanceLevel
        self.averageSpeedKmh = averageSpeedKmh
        self.machineCalories = machineCalories
        self.inclinePercent = inclinePercent
        self.steps = steps
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.rpe = rpe
        self.notes = notes
        self.workout = workout
    }
}

@Model
final class SwimMetrics {
    @Attribute(.unique) var id: UUID
    var poolLengthMeters: Double
    var laps: Int?
    var distanceMeters: Double?
    var swimDurationSeconds: Double?
    var restDurationSeconds: Double?
    var stroke: String
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var rpe: Double?
    var notes: String
    var workout: WorkoutSession?

    init(
        id: UUID = UUID(),
        poolLengthMeters: Double = 25,
        laps: Int? = nil,
        distanceMeters: Double? = nil,
        swimDurationSeconds: Double? = nil,
        restDurationSeconds: Double? = nil,
        stroke: String = "",
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        rpe: Double? = nil,
        notes: String = "",
        workout: WorkoutSession? = nil
    ) {
        self.id = id
        self.poolLengthMeters = poolLengthMeters
        self.laps = laps
        self.distanceMeters = distanceMeters
        self.swimDurationSeconds = swimDurationSeconds
        self.restDurationSeconds = restDurationSeconds
        self.stroke = stroke
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.rpe = rpe
        self.notes = notes
        self.workout = workout
    }
}

extension SnapshotCodec {
    static func encodeExercise(_ snapshot: TemplateExerciseSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(snapshot)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decodeExercise(_ json: String) -> TemplateExerciseSnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TemplateExerciseSnapshot.self, from: data)
    }
}
