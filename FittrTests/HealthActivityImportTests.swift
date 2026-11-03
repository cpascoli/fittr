import Foundation
import SwiftData
import Testing
@testable import Fittr

/// Walks and runs recorded by a watch or another app come into Fittr as sessions,
/// and daily step totals come in one row per day, without ever duplicating a
/// workout Fittr logged itself.
@MainActor
struct HealthActivityImportTests {
    @Test func aHealthWalkBecomesARecoverySessionWithDistanceAndIsImportedOnce() throws {
        let context = try makeContext()
        let walk = sample(uuid: "walk-1", kind: .walking, start: day(-3, hour: 8), minutes: 65, km: 5.4, kcal: 310)

        #expect(try HealthActivityImporter.importWorkouts([walk], in: context) == 1)
        #expect(try HealthActivityImporter.importWorkouts([walk], in: context) == 0)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.source == .health)
        #expect(session.type == .recovery)
        #expect(session.name == "Walk")
        #expect(session.healthKitWorkoutUUID == "walk-1")
        #expect(session.workoutTemplateId == SeedID.healthImport)
        #expect(session.cardio?.distanceKm == 5.4)
        #expect(session.cardio?.machineCalories == 310)
        #expect(session.cardio?.averageSpeedKmh.map { ($0 * 10).rounded() / 10 } == 5.0)
    }

    @Test func fittrsOwnWorkoutsAndOverlappingOnesAreNotImported() throws {
        let context = try makeContext()
        let gymStart = day(-1, hour: 13)
        let gym = WorkoutSession(
            name: "Full Body Strength",
            type: .strength,
            source: .scheduled,
            startedAt: gymStart,
            endedAt: gymStart.addingTimeInterval(50 * 60),
            templateSnapshotJSON: "",
            workoutTemplateId: SeedID.mondayStrength
        )
        context.insert(gym)
        try context.save()

        let own = sample(uuid: "own", kind: .strength, start: day(-2, hour: 13), minutes: 50, fromThisApp: true)
        let watchCopyOfGym = sample(uuid: "watch-gym", kind: .strength, start: gymStart.addingTimeInterval(120), minutes: 45)
        let tooShort = sample(uuid: "blip", kind: .walking, start: day(-2, hour: 9), minutes: 1)
        let realRun = sample(uuid: "run", kind: .running, start: day(-2, hour: 18), minutes: 30, km: 4.1)

        let added = try HealthActivityImporter.importWorkouts([own, watchCopyOfGym, tooShort, realRun], in: context)

        #expect(added == 1)
        let imported = try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.source == .health }
        #expect(imported.map(\.healthKitWorkoutUUID) == ["run"])
        #expect(imported.first?.type == .cardio)
    }

    @Test func dailyActivityIsOneRowPerDayAndTodayIsReplacedNotDuplicated() throws {
        let context = try makeContext()
        let monday = DateHelpers.startOfDay(day(-2, hour: 0))
        let tuesday = DateHelpers.startOfDay(day(-1, hour: 0))
        let first = [
            HealthDailyActivity(day: monday, steps: 8_200, distanceKm: 6.1, activeEnergyKcal: 420, exerciseMinutes: 38),
            HealthDailyActivity(day: tuesday, steps: 3_000, distanceKm: 2.2, activeEnergyKcal: 150, exerciseMinutes: 10),
        ]
        #expect(try HealthActivityImporter.upsertDailyActivity(first, in: context) == 2)

        let later = [
            HealthDailyActivity(day: monday, steps: 8_200, distanceKm: 6.1, activeEnergyKcal: 420, exerciseMinutes: 38),
            HealthDailyActivity(day: tuesday, steps: 11_400, distanceKm: 8.7, activeEnergyKcal: 560, exerciseMinutes: 61),
        ]
        #expect(try HealthActivityImporter.upsertDailyActivity(later, in: context) == 1)

        let rows = try context.fetch(FetchDescriptor<DailyActivity>()).sorted { $0.day < $1.day }
        #expect(rows.count == 2)
        #expect(rows[1].steps == 11_400)
        #expect(rows[1].distanceKm == 8.7)
    }

    /// The whole pull, through the service: workouts get their heart rate, days
    /// are written, weigh-ins come along, and the sync time is remembered.
    @Test func syncPullsWorkoutsDaysAndWeighInsAndRecordsWhenItRan() async throws {
        let context = try makeContext()
        let settings = AppSettings(id: SeedID.settings, healthImportEnabled: true)
        context.insert(settings)
        let profile = UserProfile(dateOfBirth: day(-18_000, hour: 0), heightCm: 183, startingWeightKg: 97, currentWeightKg: 97, targetWeightKg: 85)
        context.insert(profile)
        try context.save()

        let health = MockHealthService()
        health.workoutSamples = [sample(uuid: "walk", kind: .walking, start: day(-4, hour: 7), minutes: 70, km: 6)]
        health.activityDays = [HealthDailyActivity(day: DateHelpers.startOfDay(day(-4, hour: 0)), steps: 12_000, distanceKm: 9, activeEnergyKcal: 600, exerciseMinutes: 70)]
        health.heartRateSummary = HealthHeartRateSummary(average: 112, max: 134)
        health.bodyMass = [HealthBodyMassSample(uuid: "w1", recordedAt: day(-4, hour: 7), weightKg: 94.3, sourceName: "Scale")]
        let previous = FittrDependencies.shared.health
        FittrDependencies.shared.health = health
        defer { FittrDependencies.shared.health = previous }

        let result = try #require(await HealthActivitySyncService.sync(in: context, now: day(0, hour: 12)))

        #expect(result == HealthSyncResult(workoutsAdded: 1, daysUpdated: 1, weighInsAdded: 1))
        let walk = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(walk.cardio?.averageHeartRate == 112)
        #expect(walk.cardio?.maxHeartRate == 134)
        #expect(profile.currentWeightKg == 94.3)
        #expect(settings.healthLastSyncAt == day(0, hour: 12))

        // Off means off: nothing runs unless forced.
        settings.healthImportEnabled = false
        #expect(await HealthActivitySyncService.sync(in: context) == nil)
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try FittrSchema.container(inMemory: true))
    }

    private func day(_ offset: Int, hour: Int) -> Date {
        let base = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour)) ?? .now
        return Calendar.current.date(byAdding: .day, value: offset, to: base) ?? base
    }

    private func sample(
        uuid: String,
        kind: HealthActivityKind,
        start: Date,
        minutes: Double,
        km: Double? = nil,
        kcal: Double? = nil,
        fromThisApp: Bool = false
    ) -> HealthWorkoutSample {
        HealthWorkoutSample(
            uuid: uuid,
            kind: kind,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            distanceKm: km,
            activeEnergyKcal: kcal,
            sourceName: fromThisApp ? "Fittr" : "Apple Watch",
            isFromThisApp: fromThisApp
        )
    }
}
