import Foundation
import Testing
@testable import Fittr

struct StrengthTrendTests {
    @Test func eachWeekKeepsItsBestEstimate() throws {
        let firstWeek = Date(timeIntervalSince1970: 1_700_000_000)
        let laterThatWeek = firstWeek.addingTimeInterval(2 * 24 * 3600)
        let nextWeek = firstWeek.addingTimeInterval(8 * 24 * 3600)
        let points = StrengthTrend.weeklyBestEstimates(
            [
                StrengthSample(date: firstWeek, weightKg: 100, reps: 1),
                StrengthSample(date: laterThatWeek, weightKg: 80, reps: 10),
                StrengthSample(date: nextWeek, weightKg: 100, reps: 5),
            ],
            weekStart: { date in date < nextWeek ? firstWeek : nextWeek }
        )

        #expect(points.count == 2)
        // 80 × 10 is a higher Epley than 100 × 1, so that week keeps 80 × 10.
        let first = try #require(WorkoutMath.estimatedOneRepMaxKg(weightKg: 80, reps: 10))
        let second = try #require(WorkoutMath.estimatedOneRepMaxKg(weightKg: 100, reps: 5))
        #expect(points[0].value == first)
        #expect(points[1].value == second)
        #expect(StrengthTrend.change(across: points) == second - first)
    }

    @Test func oneWeekIsNotYetAChange() {
        let points = StrengthTrend.weeklyBestEstimates(
            [StrengthSample(date: .now, weightKg: 40, reps: 8)],
            weekStart: { _ in Date(timeIntervalSince1970: 0) }
        )
        #expect(points.count == 1)
        #expect(StrengthTrend.change(across: points) == nil)
    }

    @Test func setsOutsideTheFormulaAreLeftOut() {
        let points = StrengthTrend.weeklyBestEstimates(
            [StrengthSample(date: .now, weightKg: 40, reps: 20)],
            weekStart: { _ in Date(timeIntervalSince1970: 0) }
        )
        #expect(points.isEmpty)
    }
}
