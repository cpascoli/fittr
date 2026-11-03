import Foundation
import SwiftData
import Testing
@testable import Fittr

/// Weigh-ins can be entered for past dates, so "current weight" must follow the
/// latest entry by date rather than the entry saved most recently.
struct BodyWeightLogTests {
    @Test func backfillingAnOlderWeighInDoesNotChangeCurrentWeight() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)
        try BodyWeightLog.record(weightKg: 94, on: day(0), profile: profile, in: context)

        try BodyWeightLog.record(weightKg: 96, on: day(-21), profile: profile, in: context)

        #expect(profile.currentWeightKg == 94)
    }

    @Test func aNewerWeighInBecomesCurrentWeight() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)
        try BodyWeightLog.record(weightKg: 96, on: day(-21), profile: profile, in: context)

        try BodyWeightLog.record(weightKg: 94, on: day(0), profile: profile, in: context)

        #expect(profile.currentWeightKg == 94)
    }

    @Test func editingADateReordersWhichEntryIsCurrent() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)
        let older = try BodyWeightLog.record(weightKg: 96, on: day(-21), profile: profile, in: context)
        try BodyWeightLog.record(weightKg: 94, on: day(-7), profile: profile, in: context)
        #expect(profile.currentWeightKg == 94)

        try BodyWeightLog.update(older, weightKg: 93.5, on: day(0), profile: profile, in: context)

        #expect(profile.currentWeightKg == 93.5)
        #expect(older.recordedAt == day(0))
    }

    @Test func deletingTheLatestEntryFallsBackToThePreviousOne() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)
        try BodyWeightLog.record(weightKg: 96, on: day(-21), profile: profile, in: context)
        let latest = try BodyWeightLog.record(weightKg: 94, on: day(0), profile: profile, in: context)

        try BodyWeightLog.delete(latest, profile: profile, in: context)
        #expect(profile.currentWeightKg == 96)

        let remaining = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        try BodyWeightLog.delete(remaining[0], profile: profile, in: context)
        #expect(profile.currentWeightKg == profile.startingWeightKg)
    }

    /// Readings arrive with Health's own IDs, so a second import adds nothing,
    /// and the newest reading becomes the current weight.
    @Test func importingFromHealthAddsOnlyNewReadings() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)
        try BodyWeightLog.record(weightKg: 97, on: day(-56), profile: profile, in: context)
        let samples = [
            HealthBodyMassSample(uuid: "a", recordedAt: day(-14), weightKg: 95.2, sourceName: "Scale"),
            HealthBodyMassSample(uuid: "b", recordedAt: day(-7), weightKg: 94.6, sourceName: "Scale"),
        ]

        let added = try BodyWeightLog.importFromHealth(samples, profile: profile, in: context)
        #expect(added == 2)
        #expect(profile.currentWeightKg == 94.6)

        let again = samples + [HealthBodyMassSample(uuid: "c", recordedAt: day(0), weightKg: 94, sourceName: "Scale")]
        #expect(try BodyWeightLog.importFromHealth(again, profile: profile, in: context) == 1)
        #expect(profile.currentWeightKg == 94)

        let entries = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        #expect(entries.count == 4)
        #expect(entries.filter { $0.source == BodyWeightLog.healthSource }.count == 3)
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try FittrSchema.container(inMemory: true))
    }

    private func makeProfile(in context: ModelContext) -> UserProfile {
        let profile = UserProfile(
            dateOfBirth: Date(timeIntervalSince1970: 158_000_000),
            heightCm: 183,
            startingWeightKg: 97,
            currentWeightKg: 97,
            targetWeightKg: 85
        )
        context.insert(profile)
        return profile
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_762_000_000 + Double(offset) * 86_400)
    }
}
