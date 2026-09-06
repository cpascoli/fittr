import Foundation
import SwiftData

enum SeedService {
    @discardableResult
    static func seedIfNeeded(in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        if !existing.isEmpty {
            try ScheduleService.ensureUpcomingSchedule(in: context)
            return false
        }

        let definitions = ExerciseLibrarySeed.definitions()
        definitions.forEach(context.insert)

        let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let plan = WorkoutPlanSeed.makePlan(exercises: byID)
        context.insert(plan)

        let birth = Calendar.current.date(from: DateComponents(year: 1975, month: 1, day: 15)) ?? Date(timeIntervalSince1970: 0)
        let profile = UserProfile(
            id: SeedID.profile,
            dateOfBirth: birth,
            heightCm: 183,
            startingWeightKg: 97,
            currentWeightKg: 97,
            targetWeightKg: 85
        )
        context.insert(profile)
        context.insert(BodyWeightEntry(weightKg: 97, source: "seed-profile", notes: "Starting weight"))

        let settings = AppSettings(id: SeedID.settings)
        context.insert(settings)

        try context.save()
        try ScheduleService.ensureUpcomingSchedule(in: context)
        return true
    }
}
