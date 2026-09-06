import Foundation
import SwiftData

enum PlannedLoadService {
    static func accept(exerciseId: UUID, weightKg: Double, in context: ModelContext) {
        if let existing = load(for: exerciseId, in: context) {
            existing.weightKg = weightKg
            existing.updatedAt = .now
        } else {
            context.insert(PlannedExerciseLoad(exerciseId: exerciseId, weightKg: weightKg))
        }
        try? context.save()
    }

    static func clear(exerciseId: UUID, in context: ModelContext) {
        if let existing = load(for: exerciseId, in: context) {
            context.delete(existing)
            try? context.save()
        }
    }

    static func weight(for exerciseId: UUID, in context: ModelContext) -> Double? {
        load(for: exerciseId, in: context)?.weightKg
    }

    static func consume(exerciseId: UUID, in context: ModelContext) {
        clear(exerciseId: exerciseId, in: context)
    }

    private static func load(for exerciseId: UUID, in context: ModelContext) -> PlannedExerciseLoad? {
        let descriptor = FetchDescriptor<PlannedExerciseLoad>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try? context.fetch(descriptor).first
    }
}
