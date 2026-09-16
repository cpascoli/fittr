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
        // Bind the expected value first: comparing Double? against an untyped
        // literal expression inside #expect defeats the type checker.
        let expected: Double = 10 * (1 + 10 / 30.0)
        #expect(estimate == expected)
        #expect(WorkoutMath.estimatedOneRepMaxKg(weightKg: 10, reps: 20) == nil)
    }

    @Test func percentChange() {
        #expect(WorkoutMath.percentChange(from: 100, to: 110) == 10)
    }
}

struct UnitConversionTests {
    @Test func poundsRoundTripBackToTheSameKilograms() {
        let kg = 12.0
        let lb = UnitConversion.kilogramsToPounds(kg)
        #expect(abs(lb - 26.4555) < 0.001)
        #expect(abs(UnitConversion.poundsToKilograms(lb) - kg) < 0.000001)
    }

    @Test func alternateWeightShowsTheOtherUnit() {
        // The set logger always shows both, so a kg user can match a lb-labelled
        // rack without changing any setting.
        #expect(NumberFormatting.alternateWeight(12, units: .metric) == "26.5 lb")
        #expect(NumberFormatting.alternateWeight(UnitConversion.poundsToKilograms(25), units: .imperial) == "11.3 kg")
    }

    @Test func storageAlwaysStaysInKilograms() {
        // A pound value entered by the user is persisted as kilograms, so history
        // stays comparable regardless of the display setting.
        let stored = UnitConversion.storageWeight(displayed: 25, units: .imperial)
        #expect(abs(stored - 11.3398) < 0.001)
        #expect(UnitConversion.storageWeight(displayed: 25, units: .metric) == 25)
    }
}
