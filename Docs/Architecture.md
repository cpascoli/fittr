# Architecture

Fittr is a local-first SwiftUI app. There is no backend.

```
Fittr/
  App/                 launch, tabs, onboarding, service locator
  Models/              SwiftData models + template snapshots
  Persistence/         ModelContainer / schema
  SeedData/            exercise library + weekly plan
  Features/            Today, ActiveWorkout, Plan, History, Analytics, Settings
  Services/            Health, Calendar, Music, Notifications, Export, Progression
  DesignSystem/        gym-first typography and controls
  Utilities/           duration, units, workout math
```

Apple integrations sit behind protocols (`HealthServicing`, `CalendarServicing`, `MusicServicing`, `NotificationServicing`) so tests can use mocks.

The active workout is not kept only in memory. Completing a set writes SwiftData immediately. Timers are `Date.now - startedAt`, so backgrounding or a crash does not lose elapsed time. On launch, an `endedAt == nil` session offers resume.

When a workout starts, the template is snapshotted into JSON on `WorkoutSession` and each `ExerciseSession`. Later template edits do not rewrite history.
