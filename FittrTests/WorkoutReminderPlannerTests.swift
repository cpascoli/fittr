import Foundation
import Testing
@testable import Fittr

struct WorkoutReminderPlannerTests {
    @Test func aPendingWorkoutIsRemindedByItsLeadTime() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let now = start.addingTimeInterval(-3 * 3600)
        let id = UUID()
        let plans = WorkoutReminderPlanner.plans(
            for: [
                ReminderRequest(
                    id: id,
                    title: "Full Body Strength",
                    start: start,
                    trainable: true,
                    pending: true,
                    cue: "Goblet Squat · 22 kg is waiting."
                ),
            ],
            leadMinutes: 30,
            enabled: true,
            now: now
        )
        #expect(plans.count == 1)
        #expect(plans[0].id == id)
        #expect(plans[0].fireAt == start.addingTimeInterval(-30 * 60))
        #expect(plans[0].body == "Goblet Squat · 22 kg is waiting.")
    }

    @Test func finishedRestAndPastAlertsAreDropped() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let plans = WorkoutReminderPlanner.plans(
            for: [
                ReminderRequest(id: UUID(), title: "Rest", start: start, trainable: false, pending: true, cue: nil),
                ReminderRequest(id: UUID(), title: "Done", start: start, trainable: true, pending: false, cue: nil),
                ReminderRequest(
                    id: UUID(),
                    title: "Already due",
                    start: start,
                    trainable: true,
                    pending: true,
                    cue: nil
                ),
            ],
            leadMinutes: 30,
            enabled: true,
            now: start
        )
        #expect(plans.isEmpty)
    }

    @Test func turningRemindersOffClearsThePlan() {
        let plans = WorkoutReminderPlanner.plans(
            for: [
                ReminderRequest(
                    id: UUID(),
                    title: "Full Body Strength",
                    start: Date(timeIntervalSince1970: 1_800_000_000),
                    trainable: true,
                    pending: true,
                    cue: nil
                ),
            ],
            leadMinutes: 30,
            enabled: false,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(plans.isEmpty)
    }

    @Test func aWorkoutWithoutACueStillSaysToLeave() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let plans = WorkoutReminderPlanner.plans(
            for: [
                ReminderRequest(id: UUID(), title: "Easy Cardio", start: start, trainable: true, pending: true, cue: nil),
            ],
            leadMinutes: 45,
            enabled: true,
            now: start.addingTimeInterval(-2 * 3600)
        )
        #expect(plans.first?.body == "Time to head out.")
        #expect(plans.first?.fireAt == start.addingTimeInterval(-45 * 60))
    }
}
