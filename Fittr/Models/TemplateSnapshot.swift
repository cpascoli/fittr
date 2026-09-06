import Foundation

struct TemplateSnapshot: Codable, Hashable, Sendable {
    var templateId: UUID
    var name: String
    var type: WorkoutType
    var estimatedDurationMinutes: Int
    var notes: String
    var exercises: [TemplateExerciseSnapshot]

    var trainableExercises: [TemplateExerciseSnapshot] {
        exercises.sorted { $0.order < $1.order }
    }
}

struct TemplateExerciseSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var category: ExerciseCategory
    var trackingMode: TrackingMode
    var laterality: Laterality
    var order: Int
    var targetSets: Int
    var minReps: Int?
    var maxReps: Int?
    var targetDurationSeconds: Int?
    var targetRestSeconds: Int
    var isOptional: Bool
    var equipment: Equipment
    var slug: String

    var targetRepLabel: String {
        switch trackingMode {
        case .repsWeight, .repsOnly:
            if let minReps, let maxReps, minReps != maxReps {
                return "\(targetSets) × \(minReps)–\(maxReps)"
            }
            if let maxReps {
                return "\(targetSets) × \(maxReps)"
            }
            return "\(targetSets) sets"
        case .duration:
            if let targetDurationSeconds {
                return "\(targetSets) × \(DurationFormatting.compact(seconds: TimeInterval(targetDurationSeconds)))"
            }
            return "\(targetSets) sets"
        case .distanceDuration, .lapsDuration, .freeform:
            return nameForMode
        }
    }

    private var nameForMode: String {
        switch trackingMode {
        case .distanceDuration: "Distance + time"
        case .lapsDuration: "Laps + time"
        case .freeform: "Freeform"
        case .repsWeight, .repsOnly, .duration: "\(targetSets) sets"
        }
    }
}

enum SnapshotCodec {
    static func encode(_ snapshot: TemplateSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(snapshot)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ json: String) -> TemplateSnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TemplateSnapshot.self, from: data)
    }
}
