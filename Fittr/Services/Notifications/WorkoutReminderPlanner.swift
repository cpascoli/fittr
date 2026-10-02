import Foundation

struct ReminderRequest: Equatable, Sendable {
    var id: UUID
    var title: String
    var start: Date
    var trainable: Bool
    var pending: Bool
    var cue: String?
}

struct ReminderPlan: Equatable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var fireAt: Date
}

enum WorkoutReminderPlanner {
    /// Reminders for workouts still ahead. Finished, skipped, and rest days are
    /// dropped, and so is anything whose alert time has already passed.
    static func plans(
        for items: [ReminderRequest],
        leadMinutes: Int,
        enabled: Bool,
        now: Date
    ) -> [ReminderPlan] {
        guard enabled else { return [] }
        let lead = TimeInterval(max(0, leadMinutes) * 60)
        return items.compactMap { item in
            guard item.trainable, item.pending else { return nil }
            let fireAt = item.start.addingTimeInterval(-lead)
            guard fireAt > now else { return nil }
            return ReminderPlan(
                id: item.id,
                title: item.title,
                body: item.cue ?? "Time to head out.",
                fireAt: fireAt
            )
        }
    }
}
