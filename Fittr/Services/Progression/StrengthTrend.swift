import Foundation

struct StrengthSample: Equatable, Sendable {
    var date: Date
    var weightKg: Double
    var reps: Int
}

enum StrengthTrend {
    /// Best Epley estimate in each week. Sets outside 1–12 reps are left out,
    /// because that formula does not apply to them.
    static func weeklyBestEstimates(
        _ samples: [StrengthSample],
        weekStart: (Date) -> Date = { DateHelpers.isoWeekStart(for: $0) }
    ) -> [DatedValue] {
        let estimates: [DatedValue] = samples.compactMap { sample in
            guard let estimate = WorkoutMath.estimatedOneRepMaxKg(weightKg: sample.weightKg, reps: sample.reps) else {
                return nil
            }
            return DatedValue(date: sample.date, value: estimate)
        }
        let grouped = Dictionary(grouping: estimates) { weekStart($0.date) }
        return grouped.keys.sorted().map { week in
            DatedValue(date: week, value: grouped[week]?.map(\.value).max() ?? 0)
        }
    }

    /// Latest minus earliest. Needs two weeks before a change means anything.
    static func change(across points: [DatedValue]) -> Double? {
        guard points.count >= 2, let first = points.first?.value, let last = points.last?.value else {
            return nil
        }
        return last - first
    }
}
