import Foundation
import SwiftData

struct HealthSyncResult: Equatable {
    var workoutsAdded = 0
    var daysUpdated = 0
    var weighInsAdded = 0

    var summary: String {
        var parts: [String] = []
        if workoutsAdded > 0 { parts.append("\(workoutsAdded) workout\(workoutsAdded == 1 ? "" : "s")") }
        if weighInsAdded > 0 { parts.append("\(weighInsAdded) weigh-in\(weighInsAdded == 1 ? "" : "s")") }
        if daysUpdated > 0 { parts.append("\(daysUpdated) day\(daysUpdated == 1 ? "" : "s") of activity") }
        return parts.isEmpty ? "Up to date with Apple Health." : "Added " + parts.joined(separator: ", ") + " from Apple Health."
    }
}

/// Pulls workouts, daily activity and weigh-ins from Apple Health into the
/// store. Runs at launch when the setting is on, and on demand from Settings.
@MainActor
enum HealthActivitySyncService {
    /// How far back the first sync reaches. Later syncs re-read the last week,
    /// so a day whose totals were still growing is corrected.
    static let initialLookbackDays = 90
    static let refreshOverlapDays = 7

    @discardableResult
    static func sync(in context: ModelContext, force: Bool = false, now: Date = .now) async -> HealthSyncResult? {
        guard let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first else { return nil }
        guard force || settings.healthImportEnabled else { return nil }
        let health = FittrDependencies.shared.health
        guard health.isAvailable else { return nil }
        if !health.isAuthorized {
            guard (try? await health.requestAuthorization()) != nil else { return nil }
        }

        let calendar = Calendar.current
        let since: Date
        if let last = settings.healthLastSyncAt {
            since = calendar.date(byAdding: .day, value: -refreshOverlapDays, to: last) ?? last
        } else {
            since = calendar.date(byAdding: .day, value: -initialLookbackDays, to: now) ?? now
        }

        var result = HealthSyncResult()
        var workouts = await health.workouts(since: since)
        // Heart rate is one query per workout, so only fetch it for the ones
        // that will actually be added.
        let known = Set(((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []).compactMap(\.healthKitWorkoutUUID))
        for index in workouts.indices where !workouts[index].isFromThisApp && !known.contains(workouts[index].uuid) {
            if let summary = await health.heartRate(from: workouts[index].startedAt, to: workouts[index].endedAt) {
                workouts[index].averageHeartRate = summary.average
                workouts[index].maxHeartRate = summary.max
            }
        }
        result.workoutsAdded = (try? HealthActivityImporter.importWorkouts(workouts, in: context)) ?? 0

        let days = await health.dailyActivity(from: since, to: now)
        result.daysUpdated = (try? HealthActivityImporter.upsertDailyActivity(days, in: context)) ?? 0

        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            let weights = await health.bodyMassSamples(since: .distantPast)
            result.weighInsAdded = (try? BodyWeightLog.importFromHealth(weights, profile: profile, in: context)) ?? 0
        }

        settings.healthLastSyncAt = now
        try? context.save()
        return result
    }
}
