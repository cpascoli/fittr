import Foundation
import Testing
@testable import Fittr

/// Covers §3.11 and §3.12: creating an exercise the seed data lacks, and the
/// tracking-mode gating the template editor uses to decide whether to offer reps
/// or a duration.
struct ExerciseAuthoringTests {
    @Test func slugsAreDerivedFromTheName() {
        #expect(ExerciseSlug.make(from: "Treadmill Running") == "treadmill-running")
        #expect(ExerciseSlug.make(from: "Farmer's Walk") == "farmer-s-walk")
        #expect(ExerciseSlug.make(from: "  Sled Push  ") == "sled-push")
        #expect(ExerciseSlug.make(from: "Bench Press 2.0") == "bench-press-2-0")
    }

    /// Every mode has to land on one side of the reps/duration split, because the
    /// template editor shows one control or the other. A mode that answers false
    /// to both is a prescription nobody can edit, which is how §3.12 happened.
    @Test func everyTrackingModeIsEditable() {
        for mode in TrackingMode.allCases {
            let editable = mode.usesReps || mode.usesDuration || mode == .freeform
            #expect(editable, "\(mode.rawValue) offers no way to edit its target")
            #expect(!(mode.usesReps && mode.usesDuration), "\(mode.rawValue) claims both")
        }
    }

    @Test func onlyAHoldIsCountedInSeconds() {
        #expect(TrackingMode.duration.countsInSeconds)
        #expect(TrackingMode.distanceDuration.countsInSeconds == false)
        #expect(TrackingMode.lapsDuration.countsInSeconds == false)
    }
}
