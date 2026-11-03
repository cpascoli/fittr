import Foundation
import SwiftData

/// Keeps the profile's current weight equal to the most recent entry on record,
/// whatever order the entries are written in. Logging used to assume every new
/// entry was today's, so backfilling an older weigh-in would have overwritten
/// "current" with a stale number.
enum BodyWeightLog {
    @discardableResult
    static func record(
        weightKg: Double,
        on date: Date,
        profile: UserProfile,
        in context: ModelContext
    ) throws -> BodyWeightEntry {
        let entry = BodyWeightEntry(recordedAt: date, weightKg: weightKg)
        context.insert(entry)
        try syncCurrentWeight(of: profile, in: context)
        return entry
    }

    static func update(
        _ entry: BodyWeightEntry,
        weightKg: Double,
        on date: Date,
        profile: UserProfile,
        in context: ModelContext
    ) throws {
        entry.weightKg = weightKg
        entry.recordedAt = date
        try syncCurrentWeight(of: profile, in: context)
    }

    static func delete(_ entry: BodyWeightEntry, profile: UserProfile, in context: ModelContext) throws {
        context.delete(entry)
        try syncCurrentWeight(of: profile, in: context)
    }

    static let healthSource = "healthKit"

    /// Adds readings from Health that are not already on record, matched by
    /// Health's own UUID so running the import again only picks up new ones.
    /// Returns how many were added.
    @discardableResult
    static func importFromHealth(
        _ samples: [HealthBodyMassSample],
        profile: UserProfile,
        in context: ModelContext
    ) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        let known = Set(existing.compactMap(\.healthKitUUID))
        var added = 0
        for sample in samples where !known.contains(sample.uuid) {
            context.insert(
                BodyWeightEntry(
                    recordedAt: sample.recordedAt,
                    weightKg: sample.weightKg,
                    source: healthSource,
                    notes: sample.sourceName,
                    healthKitUUID: sample.uuid
                )
            )
            added += 1
        }
        try syncCurrentWeight(of: profile, in: context)
        return added
    }

    /// The latest entry by date wins. With none left, the current weight falls
    /// back to the starting weight rather than keeping a number nothing supports.
    static func syncCurrentWeight(of profile: UserProfile, in context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        let latest = entries.max { $0.recordedAt < $1.recordedAt }
        profile.currentWeightKg = latest?.weightKg ?? profile.startingWeightKg
        profile.updatedAt = .now
        try context.save()
    }
}
