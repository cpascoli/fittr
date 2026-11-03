import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

struct HealthSnapshot: Sendable, Equatable {
    var bodyMassKg: Double?
    var restingHeartRate: Double?
    var stepCount: Double?
    var exerciseMinutes: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergy: Double?
}

/// One weigh-in as Health holds it. The UUID is Health's own, so the same
/// reading is never imported twice.
struct HealthBodyMassSample: Sendable, Equatable {
    var uuid: String
    var recordedAt: Date
    var weightKg: Double
    var sourceName: String
}

/// What a workout recorded outside Fittr was, in the few buckets the app
/// cares about. The raw Health activity type has dozens of cases.
enum HealthActivityKind: String, Sendable, CaseIterable {
    case walking, hiking, running, cycling, swimming, strength, other

    var displayName: String {
        switch self {
        case .walking: "Walk"
        case .hiking: "Hike"
        case .running: "Run"
        case .cycling: "Cycle"
        case .swimming: "Swim"
        case .strength: "Strength (Health)"
        case .other: "Activity"
        }
    }

    var workoutType: WorkoutType {
        switch self {
        case .walking, .hiking, .other: .recovery
        case .running, .cycling: .cardio
        case .swimming: .swimming
        case .strength: .mixed
        }
    }
}

/// A workout as Health holds it. `isFromThisApp` marks the ones Fittr wrote
/// itself, which must never come back in as a second copy.
struct HealthWorkoutSample: Sendable, Equatable {
    var uuid: String
    var kind: HealthActivityKind
    var startedAt: Date
    var endedAt: Date
    var distanceKm: Double?
    var activeEnergyKcal: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var sourceName: String
    var isFromThisApp: Bool
}

/// One day's totals from Health. Steps and distance merge every source the
/// phone knows about, so a watch and a phone carried together count once.
struct HealthDailyActivity: Sendable, Equatable {
    var day: Date
    var steps: Int
    var distanceKm: Double
    var activeEnergyKcal: Double
    var exerciseMinutes: Double
}

struct HealthHeartRateSummary: Sendable, Equatable {
    var average: Double
    var max: Double
}

protocol HealthServicing: AnyObject {
    var isAvailable: Bool { get }
    var isAuthorized: Bool { get }
    func requestAuthorization() async throws
    func latestSnapshot(workoutStart: Date?, workoutEnd: Date?) async -> HealthSnapshot
    /// Every body-mass reading from `start` onward, oldest first. Smart scales
    /// write these to Health on their own, which makes this the easiest way to
    /// get a weight history into the app.
    func bodyMassSamples(since start: Date) async -> [HealthBodyMassSample]
    /// Workouts from any source from `start` onward, oldest first.
    func workouts(since start: Date) async -> [HealthWorkoutSample]
    /// Per-day step, distance, energy and exercise-minute totals, oldest first.
    func dailyActivity(from start: Date, to end: Date) async -> [HealthDailyActivity]
    func heartRate(from start: Date, to end: Date) async -> HealthHeartRateSummary?
    func saveWorkout(
        sessionID: UUID,
        type: WorkoutType,
        start: Date,
        end: Date,
        existingUUID: String?
    ) async throws -> String?
    func deleteWorkout(uuid: String) async throws
}

#if canImport(HealthKit)
final class HealthService: HealthServicing {
    private let store = HKHealthStore()
    private(set) var isAuthorized = false

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) { read.insert(bodyMass) }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(heartRate) }
        if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { read.insert(resting) }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { read.insert(distance) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { read.insert(steps) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(energy) }
        if let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) { read.insert(exercise) }

        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
        isAuthorized = true
    }

    func latestSnapshot(workoutStart: Date?, workoutEnd: Date?) async -> HealthSnapshot {
        guard isAvailable else { return HealthSnapshot() }
        let mass = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        let rhr = await latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        let steps = await sum(.stepCount, unit: .count(), start: DateHelpers.startOfDay(.now), end: .now)
        let exercise = await sum(.appleExerciseTime, unit: .minute(), start: DateHelpers.startOfDay(.now), end: .now)
        var averageHR: Double?
        var maxHR: Double?
        if let workoutStart, let workoutEnd {
            let samples = await heartRates(from: workoutStart, to: workoutEnd)
            if !samples.isEmpty {
                averageHR = samples.reduce(0, +) / Double(samples.count)
                maxHR = samples.max()
            }
        }
        return HealthSnapshot(
            bodyMassKg: mass,
            restingHeartRate: rhr,
            stepCount: steps,
            exerciseMinutes: exercise,
            averageHeartRate: averageHR,
            maxHeartRate: maxHR,
            activeEnergy: nil
        )
    }

    func saveWorkout(
        sessionID: UUID,
        type: WorkoutType,
        start: Date,
        end: Date,
        existingUUID: String?
    ) async throws -> String? {
        guard isAvailable, existingUUID == nil else { return existingUUID }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: type)
        configuration.locationType = type == .swimming ? .unknown : .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        return try await builder.finishWorkout()?.uuid.uuidString
    }

    func deleteWorkout(uuid: String) async throws {
        guard isAvailable, let objectUUID = UUID(uuidString: uuid) else { return }
        let predicate = HKQuery.predicateForObject(with: objectUUID)
        _ = try await store.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate)
    }

    private func activityType(for type: WorkoutType) -> HKWorkoutActivityType {
        switch type {
        case .strength: .traditionalStrengthTraining
        case .cardio: .cycling
        case .swimming: .swimming
        case .recovery: .walking
        case .rest: .flexibility
        case .mixed: .mixedCardio
        }
    }

    func bodyMassSamples(since start: Date) async -> [HealthBodyMassSample] {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let readings = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthBodyMassSample(
                        uuid: sample.uuid.uuidString,
                        recordedAt: sample.startDate,
                        weightKg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                        sourceName: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: readings)
            }
            store.execute(query)
        }
    }

    func workouts(since start: Date) async -> [HealthWorkoutSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let ownBundle = Bundle.main.bundleIdentifier
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    HealthWorkoutSample(
                        uuid: workout.uuid.uuidString,
                        kind: Self.kind(for: workout.workoutActivityType),
                        startedAt: workout.startDate,
                        endedAt: workout.endDate,
                        distanceKm: Self.distanceKm(of: workout),
                        activeEnergyKcal: Self.energyKcal(of: workout),
                        sourceName: workout.sourceRevision.source.name,
                        isFromThisApp: workout.sourceRevision.source.bundleIdentifier == ownBundle
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    func dailyActivity(from start: Date, to end: Date) async -> [HealthDailyActivity] {
        guard isAvailable else { return [] }
        let steps = await dailySums(.stepCount, unit: .count(), from: start, to: end)
        let distance = await dailySums(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), from: start, to: end)
        let energy = await dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        let exercise = await dailySums(.appleExerciseTime, unit: .minute(), from: start, to: end)
        let days = Set(steps.keys).union(distance.keys).union(energy.keys).union(exercise.keys)
        return days.sorted().map { day in
            HealthDailyActivity(
                day: day,
                steps: Int((steps[day] ?? 0).rounded()),
                distanceKm: distance[day] ?? 0,
                activeEnergyKcal: energy[day] ?? 0,
                exerciseMinutes: exercise[day] ?? 0
            )
        }
    }

    func heartRate(from start: Date, to end: Date) async -> HealthHeartRateSummary? {
        let samples = await heartRates(from: start, to: end)
        guard let max = samples.max(), !samples.isEmpty else { return nil }
        return HealthHeartRateSummary(average: samples.reduce(0, +) / Double(samples.count), max: max)
    }

    private static func kind(for type: HKWorkoutActivityType) -> HealthActivityKind {
        switch type {
        case .walking: .walking
        case .hiking: .hiking
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining: .strength
        default: .other
        }
    }

    private static func distanceKm(of workout: HKWorkout) -> Double? {
        let identifiers: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        for identifier in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier),
               let metres = workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()), metres > 0 {
                return metres / 1000
            }
        }
        return nil
    }

    private static func energyKcal(of workout: HKWorkout) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let kcal = workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .kilocalorie()), kcal > 0
        else { return nil }
        return kcal
    }

    /// One statistics query per metric, bucketed by local day. Health merges
    /// overlapping sources inside a cumulative sum, so phone and watch steps for
    /// the same minutes are not double counted.
    private func dailySums(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        let anchor = DateHelpers.startOfDay(start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var sums: [Date: Double] = [:]
                collection?.enumerateStatistics(from: anchor, to: end) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: unit), sum > 0 {
                        sums[stats.startDate] = sum
                    }
                }
                continuation.resume(returning: sums)
            }
            store.execute(query)
        }
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples as? [HKQuantitySample])?.first?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func sum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func heartRates(from start: Date, to end: Date) async -> [Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
}
#else
final class HealthService: HealthServicing {
    var isAvailable: Bool { false }
    var isAuthorized: Bool { false }
    func requestAuthorization() async throws {}
    func latestSnapshot(workoutStart: Date?, workoutEnd: Date?) async -> HealthSnapshot { HealthSnapshot() }
    func bodyMassSamples(since start: Date) async -> [HealthBodyMassSample] { [] }
    func workouts(since start: Date) async -> [HealthWorkoutSample] { [] }
    func dailyActivity(from start: Date, to end: Date) async -> [HealthDailyActivity] { [] }
    func heartRate(from start: Date, to end: Date) async -> HealthHeartRateSummary? { nil }
    func saveWorkout(sessionID: UUID, type: WorkoutType, start: Date, end: Date, existingUUID: String?) async throws -> String? { existingUUID }
    func deleteWorkout(uuid: String) async throws {}
}
#endif

final class MockHealthService: HealthServicing {
    var isAvailable = true
    var isAuthorized = false
    var snapshot = HealthSnapshot()
    var savedWorkouts: [UUID] = []
    var bodyMass: [HealthBodyMassSample] = []
    var workoutSamples: [HealthWorkoutSample] = []
    var activityDays: [HealthDailyActivity] = []
    var heartRateSummary: HealthHeartRateSummary?

    func requestAuthorization() async throws {
        isAuthorized = true
    }

    func latestSnapshot(workoutStart: Date?, workoutEnd: Date?) async -> HealthSnapshot {
        snapshot
    }

    func bodyMassSamples(since start: Date) async -> [HealthBodyMassSample] {
        bodyMass.filter { $0.recordedAt >= start }.sorted { $0.recordedAt < $1.recordedAt }
    }

    func workouts(since start: Date) async -> [HealthWorkoutSample] {
        workoutSamples.filter { $0.startedAt >= start }.sorted { $0.startedAt < $1.startedAt }
    }

    func dailyActivity(from start: Date, to end: Date) async -> [HealthDailyActivity] {
        activityDays.filter { $0.day >= DateHelpers.startOfDay(start) && $0.day <= end }.sorted { $0.day < $1.day }
    }

    func heartRate(from start: Date, to end: Date) async -> HealthHeartRateSummary? {
        heartRateSummary
    }

    func saveWorkout(sessionID: UUID, type: WorkoutType, start: Date, end: Date, existingUUID: String?) async throws -> String? {
        if let existingUUID { return existingUUID }
        savedWorkouts.append(sessionID)
        return sessionID.uuidString
    }

    func deleteWorkout(uuid: String) async throws {
        savedWorkouts.removeAll { $0.uuidString == uuid }
    }
}
