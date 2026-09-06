import Foundation
import Testing
@testable import Fittr

struct WorkoutMathTests {
    @Test func bilateralVolumeIsWeightTimesReps() {
        let volume = WorkoutMath.setVolumeKg(weightKg: 10, reps: 12, leftReps: nil, rightReps: nil, laterality: .bilateral)
        #expect(volume == 120)
    }

    @Test func unilateralVolumeUsesPerSideWeight() {
        let volume = WorkoutMath.setVolumeKg(weightKg: 12, reps: nil, leftReps: 10, rightReps: 10, laterality: .unilateral)
        #expect(volume == 240)
    }

    @Test func durationUsesTimestamps() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_090)
        #expect(WorkoutMath.duration(from: start, to: end) == 90)
    }

    @Test func durationAfterRestartUsesOriginalStart() {
        let start = Date(timeIntervalSince1970: 5_000)
        let now = Date(timeIntervalSince1970: 5_125)
        #expect(WorkoutMath.duration(from: start, to: nil, now: now) == 125)
    }

    @Test func averageRestIgnoresOpenIntervals() {
        let start = Date(timeIntervalSince1970: 0)
        let rests = [
            RestDurationInput(startedAt: start, endedAt: start.addingTimeInterval(90)),
            RestDurationInput(startedAt: start.addingTimeInterval(200), endedAt: start.addingTimeInterval(270)),
            RestDurationInput(startedAt: start.addingTimeInterval(400), endedAt: nil),
        ]
        #expect(WorkoutMath.averageRestSeconds(rests: rests) == 80)
    }

    @Test func epleyEstimateIsLabeledFormula() {
        let estimate = WorkoutMath.estimatedOneRepMaxKg(weightKg: 10, reps: 10)
        #expect(estimate == 10 * (1 + 10 / 30.0))
        #expect(WorkoutMath.estimatedOneRepMaxKg(weightKg: 10, reps: 20) == nil)
    }

    @Test func percentChange() {
        #expect(WorkoutMath.percentChange(from: 100, to: 110) == 10)
    }
}
