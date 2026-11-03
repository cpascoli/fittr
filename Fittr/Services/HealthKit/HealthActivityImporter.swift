import Foundation
import SwiftData

/// Turns what Health reports into Fittr records. Pure: given samples and a
/// context, it decides what to add and adds it. Talking to Health is
/// `HealthActivitySyncService`'s job.
enum HealthActivityImporter {
    /// Workouts shorter than this are watch noise, not exercise.
    static let minimumWorkoutSeconds: TimeInterval = 120

    /// Adds Health workouts as sessions. Skips the ones Fittr wrote itself, ones
    /// already imported, and ones that overlap a session Fittr logged live, such
    /// as a watch's own record of a Fittr strength session. Returns how many
    /// were added.
    @discardableResult
    static func importWorkouts(_ samples: [HealthWorkoutSample], in context: ModelContext) throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let known = Set(sessions.compactMap(\.healthKitWorkoutUUID))
        let logged = sessions.filter { $0.source != .health && $0.endedAt != nil }
        var added = 0
        for sample in samples {
            guard !sample.isFromThisApp, !known.contains(sample.uuid) else { continue }
            guard sample.endedAt.timeIntervalSince(sample.startedAt) >= minimumWorkoutSeconds else { continue }
            guard !overlapsLoggedSession(sample, in: logged) else { continue }
            insert(sample, in: context)
            added += 1
        }
        if added > 0 {
            try context.save()
        }
        return added
    }

    /// Writes one row per day, replacing the day's numbers when it is already
    /// there: today's totals keep growing until midnight.
    @discardableResult
    static func upsertDailyActivity(_ days: [HealthDailyActivity], in context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<DailyActivity>())
        var byDay = Dictionary(existing.map { (DateHelpers.startOfDay($0.day), $0) }, uniquingKeysWith: { first, _ in first })
        var touched = 0
        for day in days {
            let key = DateHelpers.startOfDay(day.day)
            if let row = byDay[key] {
                guard row.steps != day.steps
                    || row.distanceKm != day.distanceKm
                    || row.activeEnergyKcal != day.activeEnergyKcal
                    || row.exerciseMinutes != day.exerciseMinutes
                else { continue }
                row.steps = day.steps
                row.distanceKm = day.distanceKm
                row.activeEnergyKcal = day.activeEnergyKcal
                row.exerciseMinutes = day.exerciseMinutes
                row.updatedAt = .now
            } else {
                let row = DailyActivity(
                    day: key,
                    steps: day.steps,
                    distanceKm: day.distanceKm,
                    activeEnergyKcal: day.activeEnergyKcal,
                    exerciseMinutes: day.exerciseMinutes
                )
                context.insert(row)
                byDay[key] = row
            }
            touched += 1
        }
        if touched > 0 {
            try context.save()
        }
        return touched
    }

    /// True when more than half of the Health workout falls inside a session
    /// Fittr logged itself.
    static func overlapsLoggedSession(_ sample: HealthWorkoutSample, in sessions: [WorkoutSession]) -> Bool {
        let length = sample.endedAt.timeIntervalSince(sample.startedAt)
        guard length > 0 else { return false }
        return sessions.contains { session in
            guard let end = session.endedAt else { return false }
            let overlap = min(end, sample.endedAt).timeIntervalSince(max(session.startedAt, sample.startedAt))
            return overlap / length > 0.5
        }
    }

    private static func insert(_ sample: HealthWorkoutSample, in context: ModelContext) {
        let session = WorkoutSession(
            name: sample.kind.displayName,
            type: sample.kind.workoutType,
            source: .health,
            startedAt: sample.startedAt,
            endedAt: sample.endedAt,
            templateSnapshotJSON: "",
            notes: "Imported from Apple Health · \(sample.sourceName)",
            healthKitWorkoutUUID: sample.uuid,
            workoutTemplateId: SeedID.healthImport
        )
        context.insert(session)
        guard sample.kind != .strength else { return }
        let hours = sample.endedAt.timeIntervalSince(sample.startedAt) / 3600
        let metrics = CardioMetrics(
            activityKind: sample.kind.displayName,
            distanceKm: sample.distanceKm,
            averageSpeedKmh: sample.distanceKm.map { hours > 0 ? $0 / hours : 0 },
            machineCalories: sample.activeEnergyKcal,
            averageHeartRate: sample.averageHeartRate,
            maxHeartRate: sample.maxHeartRate
        )
        context.insert(metrics)
        metrics.workout = session
        session.cardio = metrics
    }
}
