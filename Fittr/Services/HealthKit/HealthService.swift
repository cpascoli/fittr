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

protocol HealthServicing: AnyObject {
    var isAvailable: Bool { get }
    var isAuthorized: Bool { get }
    func requestAuthorization() async throws
    func latestSnapshot(workoutStart: Date?, workoutEnd: Date?) async -> HealthSnapshot
    func saveWorkout(
        sessionID: UUID,
        type: WorkoutType,
        start: Date,
        end: Date,
        existingUUID: String?
    ) async throws -> String?
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
    func saveWorkout(sessionID: UUID, type: WorkoutType, start: Date, end: Date, existingUUID: String?) async throws -> String? { existingUUID }
}
#endif

final class MockHealthService: HealthServicing {
    var isAvailable = true
    var isAuthorized = false
    var snapshot = HealthSnapshot()
    var savedWorkouts: [UUID] = []

    func requestAuthorization() async throws {
        isAuthorized = true
    }

    func latestSnapshot(workoutStart: Date?, workoutEnd: Date?) async -> HealthSnapshot {
        snapshot
    }

    func saveWorkout(sessionID: UUID, type: WorkoutType, start: Date, end: Date, existingUUID: String?) async throws -> String? {
        if let existingUUID { return existingUUID }
        savedWorkouts.append(sessionID)
        return sessionID.uuidString
    }
}
