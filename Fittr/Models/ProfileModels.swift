import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var dateOfBirth: Date
    var heightCm: Double
    var startingWeightKg: Double
    var currentWeightKg: Double
    var targetWeightKg: Double
    var preferredUnitsRaw: String
    var createdAt: Date
    var updatedAt: Date

    var preferredUnits: UnitSystem {
        get { UnitSystem(rawValue: preferredUnitsRaw) ?? .metric }
        set { preferredUnitsRaw = newValue.rawValue }
    }

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date.now).year ?? 0
    }

    init(
        id: UUID = UUID(),
        dateOfBirth: Date,
        heightCm: Double,
        startingWeightKg: Double,
        currentWeightKg: Double,
        targetWeightKg: Double,
        preferredUnits: UnitSystem = .metric,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.dateOfBirth = dateOfBirth
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.currentWeightKg = currentWeightKg
        self.targetWeightKg = targetWeightKg
        self.preferredUnitsRaw = preferredUnits.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var hasCompletedOnboarding: Bool
    var weightIncrementKg: Double
    var hapticsEnabled: Bool
    var restSoundEnabled: Bool
    var workoutRemindersEnabled: Bool
    var restRemindersEnabled: Bool
    var reminderLeadMinutes: Int
    var autoPlayExerciseTrack: Bool
    var restartExerciseTrack: Bool
    var afterTrackBehaviorRaw: String
    var calendarSyncEnabled: Bool
    var calendarTwoWaySyncEnabled: Bool
    var healthWriteEnabled: Bool
    var preferredWorkoutHour: Int?
    var preferredWorkoutMinute: Int?
    var defaultPoolLengthMeters: Double
    var createdAt: Date
    var updatedAt: Date

    var afterTrackBehavior: AfterTrackBehavior {
        get { AfterTrackBehavior(rawValue: afterTrackBehaviorRaw) ?? .continueCurrent }
        set { afterTrackBehaviorRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        hasCompletedOnboarding: Bool = false,
        weightIncrementKg: Double = 2.0,
        hapticsEnabled: Bool = true,
        restSoundEnabled: Bool = false,
        workoutRemindersEnabled: Bool = false,
        restRemindersEnabled: Bool = true,
        reminderLeadMinutes: Int = 30,
        autoPlayExerciseTrack: Bool = true,
        restartExerciseTrack: Bool = true,
        afterTrackBehavior: AfterTrackBehavior = .continueCurrent,
        calendarSyncEnabled: Bool = false,
        calendarTwoWaySyncEnabled: Bool = false,
        healthWriteEnabled: Bool = false,
        preferredWorkoutHour: Int? = nil,
        preferredWorkoutMinute: Int? = nil,
        defaultPoolLengthMeters: Double = 25,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.weightIncrementKg = weightIncrementKg
        self.hapticsEnabled = hapticsEnabled
        self.restSoundEnabled = restSoundEnabled
        self.workoutRemindersEnabled = workoutRemindersEnabled
        self.restRemindersEnabled = restRemindersEnabled
        self.reminderLeadMinutes = reminderLeadMinutes
        self.autoPlayExerciseTrack = autoPlayExerciseTrack
        self.restartExerciseTrack = restartExerciseTrack
        self.afterTrackBehaviorRaw = afterTrackBehavior.rawValue
        self.calendarSyncEnabled = calendarSyncEnabled
        self.calendarTwoWaySyncEnabled = calendarTwoWaySyncEnabled
        self.healthWriteEnabled = healthWriteEnabled
        self.preferredWorkoutHour = preferredWorkoutHour
        self.preferredWorkoutMinute = preferredWorkoutMinute
        self.defaultPoolLengthMeters = defaultPoolLengthMeters
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class BodyWeightEntry {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var weightKg: Double
    var source: String
    var notes: String
    var healthKitUUID: String?

    init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        weightKg: Double,
        source: String = "manual",
        notes: String = "",
        healthKitUUID: String? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.weightKg = weightKg
        self.source = source
        self.notes = notes
        self.healthKitUUID = healthKitUUID
    }
}

@Model
final class PersonalRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var exerciseId: UUID?
    var exerciseName: String
    var achievedAt: Date
    var workoutSessionId: UUID?
    var value: Double
    var secondaryValue: Double?
    var unitLabel: String
    var notes: String

    var kind: PersonalRecordKind {
        get { PersonalRecordKind(rawValue: kindRaw) ?? .heaviestWeight }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: PersonalRecordKind,
        exerciseId: UUID? = nil,
        exerciseName: String,
        achievedAt: Date = .now,
        workoutSessionId: UUID? = nil,
        value: Double,
        secondaryValue: Double? = nil,
        unitLabel: String,
        notes: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.achievedAt = achievedAt
        self.workoutSessionId = workoutSessionId
        self.value = value
        self.secondaryValue = secondaryValue
        self.unitLabel = unitLabel
        self.notes = notes
    }
}

@Model
final class HealthMetricReference {
    @Attribute(.unique) var id: UUID
    var kind: String
    var recordedAt: Date
    var value: Double
    var unit: String
    var healthKitUUID: String?

    init(
        id: UUID = UUID(),
        kind: String,
        recordedAt: Date,
        value: Double,
        unit: String,
        healthKitUUID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.recordedAt = recordedAt
        self.value = value
        self.unit = unit
        self.healthKitUUID = healthKitUUID
    }
}

@Model
final class PlannedExerciseLoad {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var weightKg: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        weightKg: Double,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.weightKg = weightKg
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
