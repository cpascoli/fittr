import Foundation
import SwiftData

/// One day of movement as the phone and watch measured it, pulled from Apple
/// Health. Sits beside the logged workouts so a long walk that was never a
/// "workout" still counts for something.
@Model
final class DailyActivity {
    @Attribute(.unique) var id: UUID
    /// Local start of day.
    var day: Date
    var steps: Int
    var distanceKm: Double
    var activeEnergyKcal: Double
    var exerciseMinutes: Double
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        day: Date,
        steps: Int = 0,
        distanceKm: Double = 0,
        activeEnergyKcal: Double = 0,
        exerciseMinutes: Double = 0,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.day = day
        self.steps = steps
        self.distanceKm = distanceKm
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.updatedAt = updatedAt
    }
}
