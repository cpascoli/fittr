import Foundation

struct FittrBackup: Codable, Sendable {
    var formatVersion: Int
    var exportedAt: Date
    var profile: ProfileDTO?
    var settings: SettingsDTO?
    var exercises: [ExerciseDTO]
    var sessions: [SessionDTO]
    var bodyWeights: [BodyWeightDTO]
    var personalRecords: [PersonalRecordDTO]
}

struct ProfileDTO: Codable, Sendable {
    var id: UUID
    var dateOfBirth: Date
    var heightCm: Double
    var startingWeightKg: Double
    var currentWeightKg: Double
    var targetWeightKg: Double
    var preferredUnits: String
}

struct SettingsDTO: Codable, Sendable {
    var weightIncrementKg: Double
    var hapticsEnabled: Bool
    var preferredWorkoutHour: Int?
    var preferredWorkoutMinute: Int?
}

struct ExerciseDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var slug: String
    var category: String
}

struct SessionDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var type: String
    var startedAt: Date
    var endedAt: Date?
    var notes: String
    var sessionRPE: Int?
    var templateSnapshotJSON: String
    var exercises: [ExerciseSessionDTO]
}

struct ExerciseSessionDTO: Codable, Sendable {
    var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var order: Int
    var startedAt: Date?
    var endedAt: Date?
    var notes: String
    var sets: [SetDTO]
    var rests: [RestDTO]
}

struct SetDTO: Codable, Sendable {
    var id: UUID
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
    var status: String
    var notes: String
}

struct RestDTO: Codable, Sendable {
    var id: UUID
    var targetDurationSeconds: Int
    var startedAt: Date
    var endedAt: Date?
}

struct BodyWeightDTO: Codable, Sendable {
    var id: UUID
    var recordedAt: Date
    var weightKg: Double
}

struct PersonalRecordDTO: Codable, Sendable {
    var id: UUID
    var kind: String
    var exerciseName: String
    var achievedAt: Date
    var value: Double
    var unitLabel: String
}

enum DataExportService {
    static let formatVersion = 1

    static func makeBackup(
        profile: UserProfile?,
        settings: AppSettings?,
        exercises: [ExerciseDefinition],
        sessions: [WorkoutSession],
        weights: [BodyWeightEntry],
        records: [PersonalRecord]
    ) -> FittrBackup {
        FittrBackup(
            formatVersion: formatVersion,
            exportedAt: .now,
            profile: profile.map {
                ProfileDTO(
                    id: $0.id,
                    dateOfBirth: $0.dateOfBirth,
                    heightCm: $0.heightCm,
                    startingWeightKg: $0.startingWeightKg,
                    currentWeightKg: $0.currentWeightKg,
                    targetWeightKg: $0.targetWeightKg,
                    preferredUnits: $0.liftingUnits.rawValue
                )
            },
            settings: settings.map {
                SettingsDTO(
                    weightIncrementKg: $0.weightIncrementKg,
                    hapticsEnabled: $0.hapticsEnabled,
                    preferredWorkoutHour: $0.preferredWorkoutHour,
                    preferredWorkoutMinute: $0.preferredWorkoutMinute
                )
            },
            exercises: exercises.map { ExerciseDTO(id: $0.id, name: $0.name, slug: $0.slug, category: $0.category.rawValue) },
            sessions: sessions.sorted { $0.startedAt < $1.startedAt }.map(sessionDTO),
            bodyWeights: weights.map { BodyWeightDTO(id: $0.id, recordedAt: $0.recordedAt, weightKg: $0.weightKg) },
            personalRecords: records.map {
                PersonalRecordDTO(
                    id: $0.id,
                    kind: $0.kind.rawValue,
                    exerciseName: $0.exerciseName,
                    achievedAt: $0.achievedAt,
                    value: $0.value,
                    unitLabel: $0.unitLabel
                )
            }
        )
    }

    static func jsonData(from backup: FittrBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decodeBackup(from data: Data) throws -> FittrBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(FittrBackup.self, from: data)
        guard backup.formatVersion == formatVersion else {
            throw ExportError.unsupportedVersion(backup.formatVersion)
        }
        return backup
    }

    static func csvBundle(from backup: FittrBackup) -> [String: Data] {
        [
            "workouts.csv": Data(workoutsCSV(backup.sessions).utf8),
            "exercises.csv": Data(exercisesCSV(backup.sessions).utf8),
            "sets.csv": Data(setsCSV(backup.sessions).utf8),
            "cardio.csv": Data(cardioCSV(backup.sessions).utf8),
            "swimming.csv": Data(swimmingCSV(backup.sessions).utf8),
        ]
    }

    private static func sessionDTO(_ session: WorkoutSession) -> SessionDTO {
        SessionDTO(
            id: session.id,
            name: session.name,
            type: session.type.rawValue,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            notes: session.notes,
            sessionRPE: session.sessionRPE,
            templateSnapshotJSON: session.templateSnapshotJSON,
            exercises: session.orderedExercises.map { exercise in
                ExerciseSessionDTO(
                    id: exercise.id,
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseName,
                    order: exercise.order,
                    startedAt: exercise.startedAt,
                    endedAt: exercise.endedAt,
                    notes: exercise.notes,
                    sets: exercise.orderedSets.map { set in
                        SetDTO(
                            id: set.id,
                            setNumber: set.setNumber,
                            weightKg: set.weightKg,
                            reps: set.reps,
                            leftReps: set.leftReps,
                            rightReps: set.rightReps,
                            durationSeconds: set.durationSeconds,
                            rpe: set.rpe,
                            rir: set.rir,
                            startedAt: set.startedAt,
                            completedAt: set.completedAt,
                            status: set.status.rawValue,
                            notes: set.notes
                        )
                    },
                    rests: exercise.rests.map {
                        RestDTO(
                            id: $0.id,
                            targetDurationSeconds: $0.targetDurationSeconds,
                            startedAt: $0.startedAt,
                            endedAt: $0.endedAt
                        )
                    }
                )
            }
        )
    }

    private static func workoutsCSV(_ sessions: [SessionDTO]) -> String {
        var rows = ["workout_id,name,start,end,duration_seconds,session_rpe,notes"]
        rows += sessions.map { session in
            let duration = WorkoutMath.duration(from: session.startedAt, to: session.endedAt)
            return [
                session.id.uuidString,
                csv(session.name),
                iso(session.startedAt),
                session.endedAt.map(iso) ?? "",
                "\(Int(duration))",
                session.sessionRPE.map(String.init) ?? "",
                csv(session.notes),
            ].joined(separator: ",")
        }
        return rows.joined(separator: "\n")
    }

    private static func exercisesCSV(_ sessions: [SessionDTO]) -> String {
        var rows = ["session_id,exercise,start,end,duration_seconds"]
        for session in sessions {
            for exercise in session.exercises {
                rows.append([
                    session.id.uuidString,
                    csv(exercise.exerciseName),
                    exercise.startedAt.map(iso) ?? "",
                    exercise.endedAt.map(iso) ?? "",
                    "\(Int(WorkoutMath.duration(from: exercise.startedAt, to: exercise.endedAt)))",
                ].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    private static func setsCSV(_ sessions: [SessionDTO]) -> String {
        var rows = ["workout,date,exercise,set,weight_kg,reps,volume_kg,rpe,rir,rest_after_seconds"]
        for session in sessions {
            for exercise in session.exercises {
                for set in exercise.sets {
                    let volume = WorkoutMath.setVolumeKg(
                        weightKg: set.weightKg,
                        reps: set.reps,
                        leftReps: set.leftReps,
                        rightReps: set.rightReps,
                        laterality: set.leftReps != nil || set.rightReps != nil ? .unilateral : .bilateral
                    )
                    let completedAt = set.completedAt ?? .distantPast
                    let rest = exercise.rests.first { $0.startedAt >= completedAt }
                    let restSeconds: String
                    if let rest {
                        restSeconds = String(Int(WorkoutMath.duration(from: rest.startedAt, to: rest.endedAt)))
                    } else {
                        restSeconds = ""
                    }
                    let weight = set.weightKg.map { String($0) } ?? ""
                    let reps = set.reps.map(String.init) ?? ""
                    let rpe = set.rpe.map { String($0) } ?? ""
                    let rir = set.rir.map { String($0) } ?? ""
                    let row = [
                        csv(session.name),
                        iso(session.startedAt),
                        csv(exercise.exerciseName),
                        String(set.setNumber),
                        weight,
                        reps,
                        String(volume),
                        rpe,
                        rir,
                        restSeconds,
                    ].joined(separator: ",")
                    rows.append(row)
                }
            }
        }
        return rows.joined(separator: "\n")
    }

    private static func cardioCSV(_ sessions: [SessionDTO]) -> String {
        var rows = ["workout_id,name,start,end,duration_seconds"]
        rows += sessions.filter { $0.type == WorkoutType.cardio.rawValue }.map { session in
            [
                session.id.uuidString,
                csv(session.name),
                iso(session.startedAt),
                session.endedAt.map(iso) ?? "",
                "\(Int(WorkoutMath.duration(from: session.startedAt, to: session.endedAt)))",
            ].joined(separator: ",")
        }
        return rows.joined(separator: "\n")
    }

    private static func swimmingCSV(_ sessions: [SessionDTO]) -> String {
        var rows = ["workout_id,name,start,end,duration_seconds"]
        rows += sessions.filter { $0.type == WorkoutType.swimming.rawValue }.map { session in
            [
                session.id.uuidString,
                csv(session.name),
                iso(session.startedAt),
                session.endedAt.map(iso) ?? "",
                "\(Int(WorkoutMath.duration(from: session.startedAt, to: session.endedAt)))",
            ].joined(separator: ",")
        }
        return rows.joined(separator: "\n")
    }

    private static func csv(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum ExportError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This backup uses format version \(version), which Fittr cannot import."
        }
    }
}
