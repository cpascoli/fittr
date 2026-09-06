# Build a Native iPhone Fitness & Workout Tracking App

Build a production-quality native iOS application for personal fitness tracking.

The app is primarily a **gym companion and personal fitness data logger**. It should guide me through my workout in real time, record detailed workout telemetry with minimal interaction, show my progress over weeks/months, schedule workouts using Apple Calendar, integrate useful data with Apple Health, control Apple Music during workouts, and display short demonstration videos/animations showing correct exercise technique.

This is initially a **single-user personal app**, not a commercial/social fitness platform.

Do not build a backend for v1.

Use a local-first architecture that could later support iCloud/CloudKit and an Apple Watch companion.

If a minor requirement is ambiguous, make a sensible engineering/product decision and document it rather than blocking development.

---

# 1. Technology

Build using the current stable Apple development stack.

Preferred technologies:

- Swift
- SwiftUI
- SwiftData for persistence
- HealthKit
- EventKit
- MusicKit
- AVKit / AVPlayer
- Swift Charts for analytics
- UserNotifications
- Swift Concurrency (`async/await`)
- XCTest / Swift Testing as appropriate

Use the latest stable Xcode/iOS SDK available in the development environment.

Minimum deployment target can be iOS 18+ unless there is a strong reason to choose another recent version.

The application must work fully without a network connection except for functionality that inherently requires one, such as Apple Music catalog access or remote media.

Use metric units by default:

- kg
- km
- metres
- minutes
- bpm

Architect unit conversion so pounds/miles can be supported later.

---

# 2. Product philosophy

The most important screen in the application is the screen I use **while actually exercising**.

During exercise:

- buttons must be large
- text must be readable at a glance
- very little typing should be required
- previous values should be prefilled whenever useful
- the app should never make me navigate through several screens just to record a set
- timers should operate automatically where possible
- useful defaults should come from the previous workout
- important actions should provide optional haptic feedback

Prefer a clean, data-rich design rather than a gamified design.

Support dark mode particularly well because I am likely to use it in gyms.

---

# 3. User profile and goals

Seed the application with this user profile:

- Age: 51
- Height: 183 cm
- Starting body weight: approximately 97 kg
- Primary goal: lose approximately 10–15 kg over time
- Secondary goals:
  - increase general fitness
  - improve cardiovascular fitness
  - rebuild strength
  - preserve/increase muscle while losing fat
  - establish a sustainable long-term exercise habit

Do NOT provide medical diagnosis or aggressive health advice.

The app should primarily record, calculate, visualize and guide the training plan described below.

---

# 4. Seed workout programme

Preconfigure this weekly programme.

## Monday — Full Body Strength

Target duration: 35–45 min

Exercises:

1. Goblet Squat
   - 2 sets
   - 8–12 reps
   - default rest: 90 sec

2. Dumbbell Romanian Deadlift
   - 2 sets
   - 8–12 reps
   - default rest: 90 sec

3. Dumbbell Chest Press
   - 2 sets
   - 8–12 reps
   - default rest: 90 sec

4. One-Arm Dumbbell Row
   - 2 sets
   - 8–12 reps per side
   - default rest: 60–90 sec

5. Dumbbell Shoulder Press
   - 2 sets
   - 8–12 reps
   - default rest: 90 sec

6. Lat Pulldown
   - 2 sets
   - 8–12 reps
   - default rest: 90 sec
   - mark this exercise as optional if the gym does not have the machine

7. Plank
   - 2 sets
   - target 20–30 sec
   - default rest: 60 sec

Training principle:

The user should normally finish strength sets with approximately **3–4 repetitions in reserve** rather than training to failure.

Progression rule:

When both sets of an exercise can be completed comfortably at 12 reps with good form, recommend a modest increase in load for the next workout and return toward approximately 8–9 reps.

Do not automatically change the weight without user confirmation.

---

## Tuesday — Easy Cardio

Target:

- 30–40 min
- cycling or treadmill walking
- moderate conversational intensity

Allow user to choose:

- cycling
- treadmill walking
- another cardio activity

---

## Wednesday — Recovery

- walking
- mobility
- optional rest

No structured gym workout required.

---

## Thursday — Full Body Strength

Same initial workout as Monday.

Exercise ordering and exercises must be editable.

---

## Friday — Swimming / Cardio

Default:

- swimming
- approximately 30 min

Allow alternatives:

- cycling
- treadmill
- walking

For swimming optionally support:

- pool length
- number of lengths/laps
- total distance
- active swimming time
- rest time

---

## Saturday — Optional Activity

Default:

- long walk
- swimming
- casual physical activity

---

## Sunday — Rest

No scheduled training.

---

# 5. Workout Templates

The seeded programme must NOT be hardcoded into the UI.

Create reusable editable data structures:

`WorkoutPlan`

`WorkoutTemplate`

`WorkoutTemplateExercise`

`ExerciseDefinition`

Allow me later to:

- add exercises
- remove exercises
- reorder exercises
- change number of sets
- change rep targets
- change target duration
- change rest durations
- create new workouts
- duplicate workouts
- rename workouts
- schedule workouts on different days

The initial plan should simply be seed data.

---

# 6. Exercise library

Every exercise should have an `ExerciseDefinition`.

Suggested fields:

- id
- name
- category
- primary muscle groups
- secondary muscle groups
- equipment
- instructions
- coaching cues
- common mistakes
- optional local video asset
- optional remote video URL
- thumbnail asset
- default rep range
- default set count
- default rest duration
- tracking mode
- notes
- enabled/disabled

Tracking modes should support at least:

- reps + weight
- reps only
- duration
- distance + duration
- laps + duration
- freeform

Seed definitions for:

- Goblet Squat
- Dumbbell Romanian Deadlift
- Dumbbell Chest Press
- One-Arm Dumbbell Row
- Dumbbell Shoulder Press
- Lat Pulldown
- Plank
- Indoor Cycling
- Treadmill Walking
- Walking
- Swimming

---

# 7. Exercise demonstration

Every strength exercise screen should contain a prominent:

**Show Technique**

action.

It should display:

- short looping video or animation
- exercise name
- setup instructions
- movement instructions
- breathing cue
- 2–4 important technique cues
- common mistakes

Use AVKit / AVPlayer for video.

Video should be:

- muted by default
- loopable
- playable while workout music continues
- cached/local where practical

For the initial implementation, create the media architecture and use appropriately licensed placeholder/local demonstration clips if actual exercise clips are not available.

Do NOT scrape or bundle copyrighted exercise videos without permission.

It must be easy for me to replace each video asset later.

---

# 8. Starting a workout

Home screen should prominently show:

**Next Workout**

Example:

> Full Body Strength  
> Today  
> 7 exercises · ~40 min

Buttons:

- Start Workout
- View Workout
- Reschedule

When I tap **Start Workout**:

create a `WorkoutSession`.

Record automatically:

- workout start timestamp
- timezone
- workout template used
- template version/snapshot
- source: scheduled/manual
- related Calendar event identifier if available

Display:

- elapsed workout time
- current exercise
- exercise number, e.g. 2 / 7
- workout progress
- music status

---

# 9. Active workout screen

This is the core UX.

Example:

> FULL BODY — 12:43 elapsed
>
> Dumbbell Chest Press  
> Exercise 3 of 7
>
> Previous workout:  
> 10 kg × 10  
> 10 kg × 10
>
> SET 1
>
> Weight: [ 10 kg ]
>
> Reps: [ − ] 10 [ + ]
>
> [ COMPLETE SET ]

Below:

- target: 8–12 reps
- suggested rest: 90 sec
- RIR target: 3–4
- technique/video button
- assigned music track

Allow extremely quick changes with:

- stepper
- wheel
- direct numeric entry

Weight should default to the previous workout's weight for this exercise.

Reps should optionally default to the previous corresponding set.

---

# 10. Precise timing

Record timestamps rather than only durations.

For every workout:

- workout startedAt
- workout endedAt

For every exercise:

- exercise startedAt
- exercise endedAt

For every set:

- set startedAt
- set completedAt

For every rest:

- rest startedAt
- rest endedAt

Derived values can then calculate:

- workout duration
- exercise duration
- set duration
- actual rest duration
- total active time
- total rest time

A user must also be able to correct timestamps/history afterwards.

---

# 11. Set tracking

For resistance exercises record:

- set number
- weight
- reps
- unilateral/bilateral
- left reps if relevant
- right reps if relevant
- RPE optional
- RIR optional
- start time
- completion time
- notes
- completed/skipped status

After pressing **Complete Set**:

1. save the set
2. start the rest timer automatically
3. provide haptic confirmation
4. show countdown
5. allow:
   - +15 sec
   - +30 sec
   - Skip Rest
   - Start Next Set

At the target rest time:

- haptic notification
- optional sound
- visually indicate readiness

Do NOT force the next set to begin automatically.

Record the **actual** rest duration independently from the target rest duration.

---

# 12. Exercise tracking

When an exercise becomes active automatically record:

`exercise.startedAt`

When it is finished:

`exercise.endedAt`

Provide actions:

- Finish Exercise
- Skip Exercise
- Replace Exercise
- Add Set
- Remove Set
- Technique
- Add Note

When advancing, automatically make the next exercise active.

---

# 13. Completing the workout

At the end show a summary such as:

> Full Body Strength  
> 42m 17s
>
> 7 exercises  
> 14 sets  
> 128 reps  
> 3,460 kg training volume  
> Avg rest: 82 sec

Also show:

- previous comparable workout
- difference in total volume
- exercises where weight increased
- exercises where reps increased
- new personal records
- total active time
- total rest time
- optional average HR
- optional max HR
- optional active energy
- notes

Allow:

**Save Workout**

On save:

- persist locally
- optionally write relevant workout to HealthKit
- update progress analytics
- mark corresponding scheduled session complete

---

# 14. Progression engine

Implement a conservative progression assistant.

For an exercise with target 8–12 reps:

If the user successfully performs all prescribed sets at 12 reps and reports reasonable effort / RIR, show:

> Ready to progress  
> Last session: 10 kg × 12, 10 kg × 12  
> Suggested next session: consider 12 kg

This is a suggestion only.

Never change future workout weights silently.

Allow:

- Accept
- Keep Current Weight
- Choose Weight

The available weight increments vary by gym, so make increments configurable.

---

# 15. Calculated strength metrics

Calculate useful statistics.

At minimum:

### Training volume

`volume = weight × reps`

For unilateral exercises, explicitly define whether entered weight represents weight per hand/side and calculate consistently.

Store raw data so formulas can be changed later.

### Per exercise

Show:

- maximum weight
- best reps at each weight
- total volume
- volume per session
- total sets
- total reps
- average RPE/RIR if available

Optional calculated metric:

- estimated 1RM

If estimated 1RM is implemented, clearly label it as an estimate and state the formula used.

Do not use estimated 1RM for plank/cardio/etc.

---

# 16. Cardio session tracking

For indoor cycling record:

- start/end
- duration
- distance if available/manual
- resistance level
- average speed if known
- machine calories if manually entered
- average HR if available from HealthKit
- max HR if available
- RPE
- notes

For treadmill:

- duration
- distance
- speed
- incline
- optional HR
- steps where available
- RPE

Support intervals later, but basic continuous cardio is sufficient for v1.

---

# 17. Swimming tracking

Record:

- start/end
- pool length
- laps/lengths
- distance
- swim duration
- rest duration
- optional stroke
- optional heart rate if HealthKit provides it
- RPE
- notes

Do not assume an Apple Watch is available.

If detailed HealthKit swimming metrics are unavailable, allow manual entry.

---

# 18. Apple Health integration

Use HealthKit.

Permission must be granular, optional and gracefully degradable.

Do not make HealthKit authorization mandatory for using the app.

Potential read data:

- body mass
- heart rate
- resting heart rate
- walking/running distance
- step count
- active energy burned
- workouts
- optionally sleep duration for future recovery analytics

Potential write data:

- completed strength workout
- cycling workout
- walking workout
- swimming workout

Use the correct HealthKit activity type for each session.

For the seeded dumbbell/full-body programme, select the most semantically appropriate HealthKit strength-training type.

Do not invent heart-rate or calorie information.

If the phone/HealthKit has no measurement, display:

> No data available

rather than estimating misleading values.

After completing a workout, where authorization exists, write an `HKWorkout` corresponding to the session.

Associate relevant available samples where Apple APIs support doing so.

Prevent duplicate HealthKit workout creation.

Store the HealthKit object identifier/metadata needed to reconcile records.

---

# 19. Health dashboard

Create a lightweight health trends section.

Show, where available:

- body weight
- weight trend
- resting heart rate
- steps
- exercise minutes
- recent workouts

Weight chart options:

- 1 month
- 3 months
- 6 months
- 1 year
- all

Because daily body weight fluctuates, include:

- raw weight measurements
- 7-day moving average where data density permits

Target weight can initially be configured to:

**85 kg**

but must be editable.

Do not predict a guaranteed date for reaching the target.

---

# 20. Apple Calendar integration

Use EventKit.

The application maintains its own workout schedule.

Allow scheduled workouts to be added to Apple Calendar.

Default weekly seeded schedule:

- Monday — Full Body Strength
- Tuesday — Cardio
- Thursday — Full Body Strength
- Friday — Swim/Cardio
- Saturday — Optional Activity

Make times configurable.

Initial default times can be unset and requested during onboarding rather than assuming when I exercise.

Support recurring weekly Calendar events.

Workout Calendar event example:

> 🏋️ Full Body Strength

Include:

- expected duration
- exercise summary
- deep link back into the app if practical

The app must keep the EventKit event identifier so it does not create duplicate events.

### Permission model

Prefer least privilege.

If the app only needs to create/update its workout events, use the minimum Calendar access level Apple permits.

If implementing two-way synchronization so changes made in Apple Calendar update the fitness app, request full access only when the user explicitly enables that feature.

Calendar integration should be optional.

---

# 21. Weekly schedule UI

Create a screen similar to:

> THIS WEEK
>
> MON 7  
> ✓ Full Body Strength — 41m
>
> TUE 8  
> Cardio — 30m
>
> WED 9  
> Recovery
>
> THU 10  
> Full Body Strength — 40m
>
> FRI 11  
> Swim — 30m
>
> SAT 12  
> Optional Activity
>
> SUN 13  
> Rest

Clearly distinguish:

- upcoming
- completed
- skipped
- rescheduled

Allow drag/reschedule or a straightforward date/time editor.

---

# 22. Apple Music integration

Use MusicKit.

Music functionality is optional and the app must operate normally without authorization.

Allow me to configure:

### Workout-level music

Assign:

- Apple Music playlist
- album
- track queue

to a workout.

### Exercise-level music

Assign a specific Apple Music song to an exercise.

For example:

`Goblet Squat → track A`

`Romanian Deadlift → track B`

etc.

Store stable Apple Music/catalog identifiers rather than merely track names.

Provide MusicKit search/selection UI.

Show:

- artwork
- track title
- artist
- playback status

When the exercise starts, optionally:

- start assigned track
- restart from beginning

User setting:

**Auto-play exercise track: ON/OFF**

Options for after the track/exercise:

- continue current music
- return to workout playlist
- do nothing

Provide basic controls on active workout screen:

- play/pause
- next
- previous

Avoid disrupting audio unnecessarily.

If controlling the user's existing Music app state is the intended behavior, use the appropriate MusicKit player for that purpose.

Do not bundle copyrighted music.

---

# 23. Exercise music configuration

Exercise settings should contain:

> Workout Music  
>
> Assigned track:  
> [artwork] Daft Punk — …  
>
> [Change Track]
>
> Auto start when exercise begins: ON
>
> Restart from beginning: ON

No track should be assigned by default.

---

# 24. Notifications

Optional local notifications:

- upcoming scheduled workout
- rest timer completed

Allow user configuration.

Examples:

> Full Body Strength in 30 minutes

and:

> Rest complete — next set ready

Request notification permission only when the user enables reminders.

---

# 25. Home dashboard

Create a useful dashboard.

Suggested layout:

## Next Workout

- workout name
- scheduled time
- Start button

## This Week

- sessions completed / scheduled
- total training time
- strength sessions
- cardio minutes

## Latest Progress

Examples:

> Goblet Squat  
> 10 kg → 12 kg

> Weekly strength volume  
> +8%

> Body weight  
> 97.0 → 95.8 kg

## Consistency

Examples:

> 4 workouts completed this week  
> 86% adherence over last 30 days

No infantilizing streak/gamification is necessary.

---

# 26. Analytics

This feature matters a lot.

Provide an Analytics section with useful charts.

## Strength

Per exercise:

- weight over time
- reps over time
- best set
- total training volume over time
- estimated 1RM trend where applicable

Whole workout:

- weekly training volume
- sets/week
- reps/week
- strength sessions/week
- total workout duration
- active time vs rest time

## Cardio

- minutes/week
- distance/week
- pace/speed trend
- heart-rate trend where available

## Swimming

- distance
- duration
- pace if calculable
- sessions/week

## Body

- body weight
- 7-day moving average
- change from starting weight
- change from previous month

## Adherence

- planned sessions
- completed
- skipped
- completion percentage

Charts should support:

- 4 weeks
- 3 months
- 6 months
- 1 year
- all

Use Swift Charts.

---

# 27. Personal records

Detect and label useful PRs:

- heaviest weight
- most reps at given weight
- highest session volume
- longest plank
- longest cardio session
- longest swim
- fastest pace where relevant

Do not over-celebrate meaningless statistical noise.

Maintain a PR history.

---

# 28. Previous workout comparison

During every strength exercise, show the previous comparable session.

Example:

> LAST TIME — 4 Sep
>
> Set 1: 10 kg × 10
> Set 2: 10 kg × 11
>
> Today target:
> 10 kg × 11–12

Make copying previous values a one-tap operation.

After the session, calculate:

> Previous → Today
>
> Volume: 2,870 → 3,090 kg  
> +7.7%

---

# 29. Notes

Support notes at three levels:

### Workout

Example:

> Felt energetic today.

### Exercise

Example:

> Bench angle slightly uncomfortable.

### Set

Example:

> Last two reps difficult.

Make notes optional and unobtrusive.

---

# 30. Subjective metrics

Optional pre-workout check-in:

- energy 1–5
- motivation 1–5
- soreness 1–5

Optional post-workout:

- session RPE 1–10
- enjoyment 1–5
- notes

Do not force completion.

These metrics should become analyzable later.

---

# 31. Data model

Design a normalized but practical SwiftData model.

At minimum consider:

### UserProfile

- id
- dateOfBirth / age configuration
- height
- startingWeight
- targetWeight
- preferredUnits

### WorkoutPlan

- id
- name
- active
- createdAt

### WorkoutTemplate

- id
- planId
- name
- type
- estimatedDuration
- notes

### WorkoutTemplateExercise

- id
- templateId
- exerciseId
- order
- targetSets
- minReps
- maxReps
- targetDuration
- targetRest
- optional

### ExerciseDefinition

as described above.

### ScheduledWorkout

- id
- workoutTemplateId
- scheduledStart
- status
- calendarEventIdentifier
- recurrence metadata

### WorkoutSession

- id
- scheduledWorkoutId?
- workoutTemplateId
- startedAt
- endedAt
- timezone
- notes
- sessionRPE
- HealthKit identifier
- createdAt

### ExerciseSession

- id
- workoutSessionId
- exerciseId
- order
- startedAt
- endedAt
- notes
- status

### ExerciseSet

- id
- exerciseSessionId
- setNumber
- weightKg
- reps
- leftReps?
- rightReps?
- duration?
- RPE?
- RIR?
- startedAt
- completedAt
- status
- notes

### RestInterval

- id
- exerciseSessionId
- afterSetId
- targetDuration
- startedAt
- endedAt

### CardioMetrics

Fields appropriate for cardio.

### SwimMetrics

Fields appropriate for swimming.

### MusicAssignment

- id
- scope
- exerciseId?
- workoutTemplateId?
- Apple Music item identifier
- title cache
- artist cache
- artwork metadata
- autoplay
- restart

### HealthMetricReference

where useful for reconciling HealthKit data.

Use UUID identifiers.

Do not rely on display names as database keys.

---

# 32. Historical immutability

Workout history must remain interpretable even after workout templates change.

When a workout starts, preserve a snapshot/version of relevant template data.

Example:

If I later change Goblet Squat from:

2 × 8–12

to:

3 × 6–10

an old workout must continue showing the prescription that existed when it was performed.

---

# 33. Persistence

Use SwiftData.

Requirements:

- local persistence
- migrations considered
- data survives app updates
- writes happen immediately when sets are completed

This last requirement is important.

If the app crashes halfway through a workout, reopening it should offer:

> Resume workout started at 18:42?

and restore:

- completed exercises
- current exercise
- completed sets
- running/last rest state
- workout elapsed time

Do not keep the entire active workout solely in memory.

---

# 34. Background and interruption handling

Gym sessions will be interrupted by:

- locking the phone
- switching to Music
- phone calls
- other apps

Timers must be calculated from timestamps rather than relying on an in-memory incrementing counter.

Example:

Do not merely increment:

`elapsedSeconds += 1`

Instead derive:

`Date.now - startedAt`

so timers remain correct after app suspension.

Rest timers should likewise survive backgrounding.

---

# 35. Data export

This is important.

Provide:

**Settings → Export Data**

Formats:

- CSV
- JSON

JSON export should contain the full structured dataset.

CSV exports should include at least:

### workouts.csv

- workout id
- name
- start
- end
- duration
- session RPE
- notes

### exercises.csv

- session id
- exercise
- start
- end
- duration

### sets.csv

- workout
- date
- exercise
- set
- weight
- reps
- volume
- RPE
- RIR
- rest after set

### cardio.csv

### swimming.csv

Allow export via iOS Share Sheet.

Use ISO-8601 timestamps in machine-readable exports.

Do not trap the user's data inside the app.

---

# 36. Data import / backup

For v1, JSON export is mandatory.

If reasonably straightforward, also implement restore/import from the application's own JSON backup format.

Validate schema/version before importing.

Never silently overwrite existing data.

---

# 37. App navigation

Suggested tabs:

1. Today
2. Plan
3. History
4. Analytics
5. Settings

### Today

Current/next workout.

### Plan

Weekly schedule and workout templates.

### History

Chronological past workouts.

### Analytics

Progress charts and statistics.

### Settings

- profile
- units
- Apple Health
- Calendar
- Apple Music
- notifications
- exercise library
- weight increments
- export data

---

# 38. History screen

Example:

> SEPTEMBER 2026
>
> Sep 10 — Full Body Strength  
> 42 min · 14 sets · 3,420 kg
>
> Sep 8 — Cycling  
> 32 min · 10.2 km
>
> Sep 7 — Full Body Strength  
> 39 min · 14 sets · 3,180 kg

Selecting a workout displays its full raw record.

Allow editing erroneous entries after the workout.

If edited, derived analytics must update.

---

# 39. Search/filtering

Workout history filters:

- workout type
- exercise
- date range

Exercise history should be directly accessible.

Example:

Search:

**Goblet Squat**

Then display every historical set.

---

# 40. Accessibility and gym usability

Support:

- Dynamic Type where reasonable
- VoiceOver labels
- sufficient touch target sizes
- dark mode
- high contrast
- portrait orientation as primary
- one-handed use where possible

Avoid tiny buttons for reps/weights.

Keep important active-workout controls near the lower part of the screen.

---

# 41. Haptics

Use restrained haptics for:

- set completed
- rest timer complete
- exercise complete
- workout complete

Allow haptics to be disabled.

---

# 42. Privacy

This application handles sensitive health data.

Principles:

- local first
- no analytics SDK
- no advertising
- no third-party health-data service
- no account required
- no health data uploaded anywhere

Only request permissions immediately before the related feature is used.

Clearly explain why each permission is needed.

Required `Info.plist` privacy strings must be accurate and human-readable.

Include required usage descriptions for:

- HealthKit
- Calendar where necessary
- Apple Music
- notifications where relevant

Do not request permissions the app doesn't need.

---

# 43. No fake data in production

Seed exercise definitions and workout templates.

Do not mix fake workout history into the production database.

For development/screenshots/tests, create a separate mock/demo data provider.

---

# 44. Architecture

Use a clean feature-oriented architecture without needless enterprise complexity.

A structure like this is reasonable:

`App/`

`Models/`

`Features/Today/`

`Features/ActiveWorkout/`

`Features/Plan/`

`Features/History/`

`Features/Analytics/`

`Features/ExerciseLibrary/`

`Services/HealthKit/`

`Services/Calendar/`

`Services/Music/`

`Services/Notifications/`

`Persistence/`

`SeedData/`

`DesignSystem/`

`Utilities/`

Separate Apple framework integrations behind protocols/services so they can be mocked.

Examples:

`HealthService`

`CalendarService`

`MusicService`

`NotificationService`

This should make unit testing possible without real Apple Health/Calendar/Music access.

---

# 45. Testing

Add meaningful tests.

At minimum test:

- workout duration calculations
- exercise duration calculations
- rest duration calculations
- strength volume calculations
- progression recommendation logic
- workout template snapshot/version behavior
- weekly adherence
- 7-day body-weight moving average
- PR detection
- JSON export
- CSV export
- active workout recovery after simulated restart

Provide mock implementations for:

- HealthKit
- EventKit
- MusicKit

UI test the core workflow:

1. open app
2. start Full Body Strength
3. start Goblet Squat
4. complete set
5. observe rest timer
6. complete second set
7. advance exercise
8. finish workout
9. see workout in history
10. see analytics updated

---

# 46. Seed exercise technique text

Add concise technique instructions to the seeded exercises.

The guidance should be conservative and conventional.

Do not make medical claims.

For each exercise include:

- setup
- movement
- breathing
- key cues
- common mistakes

Keep technique guidance separate from workout history so it can be updated independently.

---

# 47. MVP priority order

Implement in this order.

## Phase 1 — Core workout logger

Must be fully functional:

- SwiftData models
- seed workout plan
- Today screen
- workout start/end
- exercise start/end
- set tracking
- weight/reps
- rest timers
- workout recovery after app termination/backgrounding
- History
- editing history

## Phase 2 — Analytics

- exercise history
- training volume
- progression
- PRs
- charts
- weekly adherence
- body-weight trend

## Phase 3 — Apple integrations

- HealthKit
- Calendar/EventKit
- MusicKit
- notifications

These integrations must not destabilize the core logger.

## Phase 4 — Exercise media

- technique screen
- video playback
- placeholder/local media architecture

## Phase 5 — Export

- CSV
- JSON
- Share Sheet
- optional restore

All phases are part of the requested v1, but complete and test each layer before adding the next.

---

# 48. Future architecture — do not implement yet

Design so the following could later be added without rewriting the data model:

### Apple Watch companion

Potential future functionality:

- live heart rate
- start/end exercises from Watch
- complete sets
- rest timer haptics
- display next set
- HealthKit workout session initiated from Watch

### CloudKit

Optional sync across Apple devices.

### Adaptive programming

Future model could analyze:

- performance
- RIR/RPE
- recovery
- workout consistency

and propose modifications.

Do NOT implement AI-generated training decisions in this version.

### Nutrition tracking

Could later track:

- calories
- protein
- body weight

but nutrition tracking is outside this initial app scope.

---

# 49. Important UX detail: minimum interaction

Optimize heavily for this sequence:

I walk into the gym.

I open the app.

I see:

> Full Body Strength  
> Scheduled today

I tap:

**START**

The app shows:

> Goblet Squat  
> 2 × 8–12
>
> Last time:
> 10 kg × 10
> 10 kg × 11
>
> Set 1  
> 10 kg  
> 10 reps

I change only what is different.

I tap:

**COMPLETE SET**

Rest timer begins automatically.

At 90 seconds the phone vibrates.

I perform the second set.

When Goblet Squat finishes the next exercise is already ready.

This should be the fastest and smoothest workflow in the application.

---

# 50. Deliverables

Produce:

1. complete Xcode project
2. runnable iPhone app
3. README
4. architecture documentation
5. SwiftData schema documentation
6. permission/capability setup instructions
7. explanation of HealthKit integration
8. explanation of EventKit integration
9. explanation of MusicKit integration
10. sample/placeholder technique media instructions
11. unit tests
12. UI tests for the main workout flow

The README must explain any Apple Developer capabilities that must be enabled manually.

---

# 51. Definition of done

The application is considered functional when I can:

1. install it on my iPhone
2. see the preconfigured weekly fitness plan
3. schedule workouts
4. see those workouts in Apple Calendar when integration is enabled
5. start a strength workout
6. see the correct exercise order
7. see a demonstration for an exercise
8. start an exercise
9. record weight and reps
10. automatically time rest periods
11. record multiple sets
12. move through all exercises
13. finish the workout
14. see exact start/end times
15. see total workout duration
16. see exercise durations
17. see actual rest durations
18. compare performance with the previous workout
19. view strength progress charts
20. view cardio/swimming history
21. optionally sync useful workout information with Apple Health
22. assign Apple Music tracks/playlists
23. have assigned music play during workouts
24. export all raw workout data as CSV/JSON
25. close/reopen the application in the middle of a workout without losing progress

Prioritize reliability of workout recording above every secondary feature.

A lost workout record is a serious application failure.

Build the core data model and active workout experience first, then layer Apple integrations and analytics on top.