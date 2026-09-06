# HealthKit

`HealthService` wraps `HKHealthStore`. Authorization is requested from Settings, not at launch.

**Read (optional):** body mass, heart rate, resting heart rate, walking/running distance, steps, active energy, exercise minutes, workouts.

**Write (optional):** one `HKWorkout` per saved Fittr session.

Activity types:

- Strength → `traditionalStrengthTraining`
- Cardio → `cycling`
- Swim → `swimming`
- Recovery → `walking`

Duplicate writes are prevented by storing `healthKitWorkoutUUID` on `WorkoutSession`. Heart rate and calories are never invented; the UI shows **No data available** when Health has no samples.
