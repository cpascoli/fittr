import Foundation
import SwiftData

/// Schedules the alerts Settings already offers. The toggle used to ask for
/// permission and then never queue anything.
@MainActor
enum WorkoutReminderService {
    static func reconcile(in context: ModelContext, now: Date = .now) async {
        let notifications = FittrDependencies.shared.notifications
        let items = (try? context.fetch(FetchDescriptor<ScheduledWorkout>())) ?? []
        let settings = try? ScheduleService.fetchSettings(in: context)
        guard settings?.workoutRemindersEnabled == true else {
            for item in items {
                notifications.cancelWorkoutReminder(id: item.id)
            }
            return
        }
        guard await notifications.requestAuthorizationIfNeeded() else { return }

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let loads = (try? context.fetch(FetchDescriptor<PlannedExerciseLoad>())) ?? []
        let planned = Dictionary(loads.map { ($0.exerciseId, $0.weightKg) }, uniquingKeysWith: { _, latest in latest })
        let units = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.liftingUnits ?? .metric
        let increment = settings?.weightIncrementKg ?? 2
        let requests = items.map { item in
            ReminderRequest(
                id: item.id,
                title: item.template?.name ?? "Workout",
                start: item.scheduledStart,
                trainable: item.template?.type.isTrainable == true && item.template?.isOptionalDay == false,
                pending: item.status == .upcoming || item.status == .rescheduled,
                cue: cue(for: item, sessions: sessions, planned: planned, incrementKg: increment, units: units)
            )
        }
        let upcoming = WorkoutReminderPlanner.plans(
            for: requests,
            leadMinutes: settings?.reminderLeadMinutes ?? 30,
            enabled: true,
            now: now
        )
        let keep = Set(upcoming.map(\.id))
        for item in items where !keep.contains(item.id) {
            notifications.cancelWorkoutReminder(id: item.id)
        }
        for plan in upcoming {
            notifications.scheduleWorkoutReminder(
                id: plan.id,
                title: plan.title,
                body: plan.body,
                fireAt: plan.fireAt
            )
        }
    }

    private static func cue(
        for item: ScheduledWorkout,
        sessions: [WorkoutSession],
        planned: [UUID: Double],
        incrementKg: Double,
        units: UnitSystem
    ) -> String? {
        guard let template = item.template else { return nil }
        // Per exercise, across every workout: Thursday's cue should know what
        // was lifted on Monday.
        let lastTime = AnalyticsEngine.latestExerciseSessions(
            before: item.scheduledStart,
            excluding: nil,
            in: sessions
        )
        let lifts: [LiftSnapshot] = template.orderedExercises.compactMap { slot in
            guard let exercise = slot.exercise else { return nil }
            let mode = slot.trackingModeOverride ?? exercise.trackingMode
            guard mode.usesWeight else { return nil }
            let logged = lastTime[exercise.id]?.completedSets ?? []
            return LiftSnapshot(
                exerciseId: exercise.id,
                exerciseName: exercise.name,
                targetSets: slot.targetSets,
                maxReps: slot.maxReps,
                sets: logged.map {
                    CompletedSetSummary(
                        setNumber: $0.setNumber,
                        weightKg: $0.weightKg,
                        reps: $0.reps,
                        rir: $0.rir,
                        status: $0.status
                    )
                }
            )
        }
        return SessionCueBuilder.cue(
            lifts: lifts,
            plannedWeightKg: planned,
            incrementKg: incrementKg,
            formatWeight: { NumberFormatting.weight($0, units: units) }
        )?.headline
    }
}
