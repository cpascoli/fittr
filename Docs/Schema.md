# SwiftData schema

All identifiers are UUIDs. Display names are never keys.

| Model | Role |
| --- | --- |
| `UserProfile` | Age/DOB, height, start/current/target weight, units |
| `AppSettings` | increments, haptics, reminders, music/calendar/health flags |
| `ExerciseDefinition` | Library entry, technique text, tracking mode, media names |
| `WorkoutPlan` | Active programme container |
| `WorkoutTemplate` | One weekday workout (editable) |
| `WorkoutTemplateExercise` | Prescription inside a template |
| `ScheduledWorkout` | Dated instance + Calendar event id + status |
| `WorkoutSession` | Performed workout + template snapshot JSON + HealthKit id |
| `ExerciseSession` | Per-exercise timestamps, notes, status, snapshot JSON |
| `ExerciseSet` | Weight/reps/RIR/RPE + start/complete timestamps |
| `RestInterval` | Target vs actual rest, tied to the set that preceded it |
| `CardioMetrics` / `SwimMetrics` | Optional session telemetry |
| `MusicAssignment` | Local Music-library persistent ID at workout or exercise scope |
| `BodyWeightEntry` | Manual (or later Health-reconciled) weight points |
| `PersonalRecord` | Conservative PR history |
| `HealthMetricReference` | Reserved for HealthKit reconciliation |

Schema name: `Fittr`. Store is local. Destructive migrations are not used in v1; additive fields should be optional.
