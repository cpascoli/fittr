# Fittr — code, features and UX review

**Date:** 7 September 2026
**Reviewed at:** `main` @ `6bd3c6d`, including uncommitted working-tree changes
**Scope:** 59 Swift files, ~8,600 LOC, plus `Docs/` and `specs.md`
**Method:** full read of the source, plus a real `xcodebuild` build and test run on the simulator

---

> **Status update — 7 Sep 2026, same day.** Three items below are now fixed and verified:
> the test target compiles and all 21 unit tests pass; the README test command is corrected;
> and the P1 data-durability work is done (`VersionedSchema` + `SchemaMigrationPlan`, and the
> launch `fatalError` replaced with a recovery screen). Verified on the simulator by writing a
> store with the pre-change build and opening it with the new one — row counts identical, no
> reseed. Everything else below is still open. The UI test still fails for the real reason
> given in §4.2.
>
> **Correction to the P1 fix.** The `VersionedSchema` + `SchemaMigrationPlan`
> scaffolding added in the first pass was wrong and has been removed. Two
> `VersionedSchema`s that list the same live Swift types hash to the same
> checksum, and Core Data rejects the stage between them with
> `NSInvalidArgumentException: Duplicate version checksums detected` — at launch,
> before the recovery screen can run. Found by round-tripping a real store on the
> simulator when the first additive change was made. The schema now relies on
> SwiftData's automatic lightweight migration for additive changes, with the
> escalation path for destructive ones documented in `FittrSchema.swift`. The
> `fatalError` removal and `StoreRecoveryView` — the parts that actually protect
> the data — stand and are verified.
>
> **Second pass — UX/UI.** §4.2 (Plan tap target) is fixed, and with it the UI test
> now passes, so the whole suite is green. A design-system pass added surface depth
> and hairline borders, a hero card, a week strip, an adherence ring and real empty
> states across Today / Analytics / History. Two further bugs were found and fixed
> while doing it, both listed under "Found during the UI pass" below.

---

## Verdict

This is a genuinely good personal app, and noticeably better than most AI-generated iOS codebases. The layering is real (models / services / features / design system), the domain modelling is careful, the maths is factored into a pure, testable `WorkoutMath` and actually tested, and the product doc trail (`Docs/ProductDecisions.md`) records decisions instead of hiding them. The gym-facing screen — big buttons, timestamp-driven timers, prefilled previous values, crash-resume — is designed by someone who thought about standing in a gym holding a dumbbell.

The weak spots are the ones that typically survive an AI build loop: **a red test suite that nobody ran**, **a handful of controls that are wired to nothing**, **an over-complicated music state machine**, **a per-frame database scan in the hot screen**, and — highest stakes for you personally — **no SwiftData migration plan**, which means the next model change can cost you your training history.

Roughly: architecture 8/10, gym UX 8/10, correctness 6/10, durability 4/10.

---

## Verified build and test status

I ran these, rather than assuming:

| Check | Result |
|---|---|
| `xcodebuild build` (iPhone 16 Pro, iOS 18.2) | ✅ Builds clean |
| Test command **as documented in README.md** | ❌ Fails — no destination matches `name=iPhone 16 Pro` |
| `xcodebuild test` | ❌ **Test suite does not compile** |
| Unit tests, after a one-line fix | ⚠️ 21 tests run: **20 pass, 1 fails** |
| UI test `testCoreStrengthWorkoutFlow` | ❌ Fails at `WorkoutFlowUITests.swift:22` |

### 1. The test target does not compile

```
error: the compiler is unable to type-check this expression in reasonable time
```

Cause — `FittrTests/WorkoutMathTests.swift:40`:

```swift
#expect(estimate == 10 * (1 + 10 / 30.0))   // estimate is Double?
```

Comparing `Double?` against an untyped literal expression inside the `#expect` macro blows up the type checker. Fix (verified — with this change the suite compiles and runs):

```swift
let expected: Double = 10 * (1 + 10 / 30.0)
#expect(estimate == expected)
```

**Applied.** The suite now compiles and runs.

**This is the most important finding in the review.** You have four test files and 21 reasonable tests covering volume, progression, records, export and recovery. None of them have ever run. Every "the tests pass" signal in this project so far has been fictional.

### 2. `README.md`'s test command is wrong

`-destination 'platform=iOS Simulator,name=iPhone 16 Pro'` doesn't resolve on this machine. Use the ID, or `OS=18.2,name=iPhone 16 Pro`. **Applied.**

### 3. One unit test genuinely fails

`ExportAndRecoveryTests.swift:94` — `inProgressSessionSurvivesStoreReload`:

```
Expectation failed: (reloaded?.exercises.first?.completedSets.count → 0) == 1
```

The bug is in the test, and it's an instructive one. `exercises` is a SwiftData relationship, so **its order is arbitrary after a fetch**. The test writes a set into `exercises[0]`, then reads back `exercises.first` — which, for a 7-exercise Monday template, is usually a different exercise. Use `orderedExercises.first`.

Worth knowing because your app code mostly gets this right (`orderedExercises`, `orderedSets` are used consistently) — this is the one place the assumption leaked. **Applied** — the test now addresses the exercise through `orderedExercises` on both sides of the save.

### 4. The UI test fails, and it's a real UX finding

`WorkoutFlowUITests.swift:22` waits for `template.start` after tapping the "Full Body Strength" text on the Plan tab. It never appears, because in `PlanView.swift:26` the *This week* rows use:

```swift
.onTapGesture { editing = row.scheduled }
```

Tapping the workout name in *This week* opens the **schedule editor sheet**, not the workout. `firstMatch` hits that row before the *Templates* row below it. So the test is right to fail — and a real user tapping today's workout in the week list also lands on a reschedule sheet rather than the workout. See UX §4.1.

---

## What's genuinely good

Worth stating plainly, because it's the part you'd otherwise rewrite by accident.

- **Timestamp-driven timers, not tick counters.** `RestInterval` stores `startedAt`, and remaining time is derived from `Date.now` (`ActiveWorkoutController.swift:145`). Background the app for ten minutes and the rest timer is still correct. Most hobby workout apps get this wrong.
- **Template snapshotting.** `WorkoutSession` stores `templateSnapshotJSON` at start, so editing a template later doesn't rewrite history. This is a mature decision that a lot of shipped apps miss.
- **Progression never mutates weight silently.** `ProgressionEngine` returns *suggestions*; `PlannedLoadService` only stores a weight after explicit acceptance. This matches your spec's "do not automatically change the weight without user confirmation" exactly, and the summary screen even says "Nothing changes unless you accept."
- **Pure, tested maths.** `WorkoutMath` takes plain structs, not model objects — which is why it's testable at all. Epley is correctly gated to 1–12 reps and labelled as an estimate in the UI.
- **`WorkoutSessionDeletionService`** is genuinely thoughtful: it unwinds PRs, planned loads, schedule status and the HealthKit workout, and it correctly *doesn't* clear a planned load that a later session owns. That's a subtle case handled well and tested.
- **Honest permission strings and privacy posture.** Every `NS*UsageDescription` explains the actual use and says it's optional. Permissions are requested on toggle, not at launch.
- **Documentation.** `Docs/ProductDecisions.md` recording unilateral volume semantics, starting loads and the Epley choice is better practice than most production teams manage.

---

## Bugs, ranked

### P1 — Data durability: no schema migration plan

`Fittr/Persistence/FittrSchema.swift` builds a `Schema` from a bare model list. There is no `VersionedSchema`, no `SchemaMigrationPlan`, and `FittrApp.swift:16` does:

```swift
fatalError("Failed to create Fittr store: \(error)")
```

SwiftData handles purely additive changes automatically. Anything else — renaming a property, changing a type, making something non-optional — fails to open the store, and the app then **crashes on launch, every launch**. Your only recovery is delete-and-reinstall, which destroys every workout you've logged.

This is the highest-stakes issue in the app precisely *because* you're iterating on it with an AI assistant. A model tweak is a one-line diff that looks harmless and silently costs you months of training history.

Three things, in order:
1. Replace `fatalError` with a fallback: catch, and either open a recovery store or show a screen offering export/reset. Never crash-loop on a device holding the only copy of your data.
2. Add `VersionedSchema` now, while there's exactly one version, so future changes have somewhere to hang a migration stage.
3. Wire the JSON export to something automatic. `DataExportService` already produces a complete backup — a weekly write to iCloud Drive or Files turns a catastrophe into an inconvenience.

**Also note:** the stated future path to CloudKit (`README`, `specs.md` §1) is currently blocked. CloudKit sync requires every attribute to be optional or defaulted and **forbids `@Attribute(.unique)`** — which every one of your 18 models uses on `id`. Worth knowing before you plan that work.

### P1 — Per-frame full-table scans in the active workout screen

`ActiveWorkoutController.swift:166`:

```swift
var previousWorkout: WorkoutSession? {
    let all = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
    return AnalyticsEngine.previousComparableSession(...)
}
```

This is a **computed property** that fetches *every workout session ever recorded*, with no predicate and no limit. `previousSets` (`:157`) calls it again.

Now look at `ActiveWorkoutView.swift:93`:

```swift
.onReceive(Timer.publish(every: 0.25, ...)) { _ in controller.pulse() }
```

`pulse()` writes `tick`, which is observed by the header, so **the whole view body re-evaluates 4× per second**. `previousCard` (`:185–200`) reads `controller.previousWorkout` and `controller.previousSets` on each pass. That's ~8 full table scans per second, each one decoding JSON snapshots, for a 45-minute session with the screen kept awake by `isIdleTimerDisabled = true`.

Today, with little history, you won't notice. After a year of training it will visibly stutter and eat battery mid-workout.

Fixes, cheapest first:
- Resolve `previousWorkout` **once** in `init` and cache it — it cannot change during a session.
- Add a `#Predicate` on `workoutTemplateId` + `endedAt != nil`, with `fetchLimit = 1` and a reverse sort, instead of fetching all and sorting in Swift.
- Move the ticking clock into a small leaf subview so the 0.25s timer doesn't invalidate the entire screen.

### P1 — RIR is never captured, anywhere

`draftRIR` and `draftRPE` (`ActiveWorkoutController.swift:20–21`) are **written to every saved set** (`:208–209`) but **never assigned by any view**. I grepped the whole app: the only other reference is a read in `SetLoggerView.swift:56`, guarded by `if let rir = controller.draftRIR` — which is always nil, so the label never renders.

Consequences:
- Every `ExerciseSet` in your database has `rir = nil` and `rpe = nil`.
- `ProgressionEngine`'s safety gate — "if RIR was logged, the easiest set must still have at least 2 RIR" (`ProgressionEngine.swift:26–29`) — is dead code that can never fire.
- The `rir` and `rpe` columns in your CSV export are permanently empty.

This matters because **"finish sets with 3–4 reps in reserve" is the central training principle in your own spec** (`specs.md` §4), and the app displays "RIR 3–4" as a target (`ActiveWorkoutView.swift`, `metaRow`) while providing no way to record it. It's the one number that would make the progression engine trustworthy, and it's the one number you can't enter.

A single 5-button row (RIR 0/1/2/3/4+) under the reps stepper would close this.

### P2 — "Add Set" button does nothing

`ActiveWorkoutView.swift:306` renders a button calling `controller.addSet()`. That method (`ActiveWorkoutController.swift:269`) is:

```swift
func addSet() {
    guard let prescription else { return }
    // Extra set beyond the snapshot target is allowed; targetSets is a prescription, not a hard cap.
    _ = prescription
}
```

It is a no-op with a comment explaining what it would do. In the gym, you tap it and nothing happens.

The behaviour it describes is actually already implicit — completing a set past `targetSets` works because `beginRestAfterCompletedSet` falls through to the next-exercise branch. But the button promises something it doesn't deliver. Either make it bump a `targetSets` override on the session, or delete it. Also note `removeLastSet()` (`:275`) is fully implemented and wired to nothing — so there's no way to undo a mis-tapped set during a workout, which is a much more likely gym scenario than adding one.

### P2 — Mid-workout resume silently reverts your weight

`prefillFromHistory()` (`ActiveWorkoutController.swift:427`) prefers, in order: an accepted planned load → **the previous workout's sets** → the current session's completed sets.

The middle step is the problem. `completeSet()` calls `PlannedLoadService.consume()`, deleting the planned load after the first set. So if the app is killed mid-exercise and you resume, the planned load is gone and prefill falls through to *last week's* weight — not the weight you were actually lifting five minutes ago in this session.

Reorder so the current session's own completed sets win over the previous workout's. What you did ten minutes ago is always a better default than what you did last Thursday.

### P2 — `HealthService.isAuthorized` is not authorisation

`HealthService.swift:52` sets `isAuthorized = true` immediately after `requestAuthorization()` returns without throwing. But HealthKit's `requestAuthorization` **succeeds when the user denies** — by design, so apps can't detect refusal for read types.

So: `SettingsView` reports "Connected" when the user tapped Deny, and `writeHealthIfNeeded` (`WorkoutSummaryView`) proceeds on a false positive. Workouts silently fail to reach Health while the UI claims they're connected.

Use `store.authorizationStatus(for: HKObjectType.workoutType())` and check for `.sharingAuthorized` — that *is* reliable for share (write) types, which is what you actually need here.

### P2 — CSV export joins rests to the wrong sets

`DataExportService.swift:271`:

```swift
let rest = exercise.rests.first { $0.startedAt >= completedAt }
```

`rests` is an unordered SwiftData relationship, so `.first` is not "the earliest" — it's whatever order the store hands back. The `rest_after_seconds` column will be wrong more or less at random.

`RestInterval.afterSetId` already exists and is populated at creation — it's the correct join key and the export ignores it. Match on that, or at minimum sort by `startedAt` first.

### P2 — Unilateral reps corrupt PRs and 1RM estimates

`completeSet()` stores, for unilateral exercises, `reps = draftLeftReps + draftRightReps` **as well as** the separate left/right values. Volume handles this correctly (documented in `ProductDecisions.md`). Two other places do not:

- `PersonalRecordService` records `mostRepsAtWeight` from `set.reps` — so a one-arm row PR reads as the *sum of both arms* (e.g. "20 reps at 10 kg").
- `AnalyticsView.epleyPoints` feeds `set.reps` into `estimatedOneRepMaxKg`. At 6+6=12 it computes a 1RM from a "12-rep set" that was really two 6-rep sets, materially overestimating. At 10+10=20 the 1–12 guard silently drops the point entirely, so the chart has invisible holes.

Use per-side reps for anything rep-based on unilateral movements.

### Found during the UI pass — Today raced the first-launch seed **(fixed)**

`TodayView` loaded `nextItem`, `weekItems` and `resumePrompt` into `@State` from
`.onAppear`. On a fresh install that ran *before* `SeedService.seedIfNeeded`
finished in `ContentView.task`, and nothing recomputed afterwards — so the home
screen showed "No upcoming workout" and "0 / 1 sessions completed" on a day with a
workout scheduled, until you switched tabs and came back. Caught by screenshotting
the simulator: Plan showed Monday correctly while Today claimed there was nothing.

Fixed by deriving all three from the existing `@Query` results instead of loading
them imperatively, which removes the race rather than papering over it with a
refresh. This also fixed the `max(planned, 1)` artefact below.

### Found during the UI pass — starting from a template lost the schedule link **(fixed)**

`TemplateEditorView`'s Start button passed `scheduled: nil`, so a session begun
from the Plan tab never marked its `ScheduledWorkout` complete and never counted
toward adherence. Pre-existing, but the Plan-tap fix made it the main path to
starting a workout. It now takes an optional `scheduled:` and threads it through
the same way `TodayView.start()` always did.

### P3 — First launch flashes the main UI before onboarding

`ContentView` gates on `settings.first` and `profiles.first`, which are both empty until `.task` seeds. So the first launch renders `RootTabView` for a frame, then swaps to `OnboardingView` once seeding lands. Add a loading state until seeding completes.

### P3 — `AnalyticsView` allocates throwaway `@Model` objects during body evaluation

`AnalyticsView.swift:163–182` builds a dictionary of `ExerciseDefinitionStub`… then throws the stubs away and constructs full **`ExerciseDefinition` SwiftData model objects** from them, purely to feed a `Picker` that needs an id and a name. There's even a comment saying "fetch from first matching definition if present" describing code that isn't there.

They're never inserted into a context so it isn't corrupting anything, but it allocates model instances on every render. `ExerciseDefinitionStub` is right there and already sufficient — use it, and make it `Identifiable`.

### P3 — Every save error is swallowed

`persist()` is `try? modelContext.save()`, called ~20 times across the controller, and the same pattern appears in most views' `.onDisappear`. If a save ever fails mid-workout, the app carries on cheerfully and the data is gone with no signal. At minimum log it; better, surface a banner.

---

## Architecture

**What's right:** clean layer separation; protocol-backed services (`HealthServicing`, `MusicServicing`, `CalendarServicing`, `NotificationServicing`, `HapticServicing`) each with a `Mock` — that's what makes the unit tests possible; `@Observable` controller separate from views; pure-value snapshot types.

**Three things I'd change:**

**1. `ActiveWorkoutController` is a god object.** 661 lines owning session state, the rest state machine, music orchestration, history prefill, progression, and persistence. The music portion alone carries five interacting flags — `restActive`, `musicPausedForRest`, `musicStoppedByUser`, `allowMusicDuringRest`, `playbackGeneration` — plus `holdQueue` and `pausedAt` inside `MusicService`. Seven booleans for "play a song, pause it during rest." This is the least comprehensible code in the project and the place where the next bug will be. Extract a `WorkoutMusicCoordinator` with an explicit enum state (`.idle / .playing / .pausedForRest / .stoppedByUser`) rather than a flag soup.

**2. `FittrDependencies.shared` is used two different ways.** `ActiveWorkoutController` takes proper constructor injection — good. But views reach for the singleton directly: `ActiveWorkoutView`'s `music` property, `WorkoutSummaryView.writeHealthIfNeeded()`, and `HistoryView.delete()`. Pick one. The injection you already have is the better half; the singleton reads are what will make these views untestable.

**3. Music control targets the *system* player.** `MPMusicPlayerController.systemMusicPlayer` (`MusicService.swift:50`) means Fittr takes over the Music app's global queue — starting a workout clobbers whatever the user had playing, and `stop()` kills it. `applicationMusicPlayer` scopes playback to your app and restores the system queue on exit. Related: `pulse()` calls `music.pause()` **every 250ms** while resting if the player reports playing, and `resume()` (`MusicService.swift`) sleeps 80ms in a `Task` before re-setting `currentPlaybackTime` — a race workaround that suggests the design is fighting the framework.

---

## UX review

### 4.1 The gym screen is strong

Big things done right: 76pt primary button, 64pt stepper targets, monospaced digits, dark-locked, screen kept awake, one tap to log a set, last session's numbers visible above the input, technique clip surfaced during rest (a genuinely smart use of otherwise dead time), local notification so the rest timer works with the phone in a pocket.

### 4.2 Tapping today's workout opens a reschedule sheet

Covered above under the failing UI test. In `PlanView`, *This week* rows respond to `.onTapGesture` by opening `ScheduleEditorView`. The natural expectation — especially on today's row — is "open/start this workout." At minimum, make today's row start the workout and move rescheduling to a swipe action, which is where "Skip" already lives.

### 4.3 Two templates both called "Full Body Strength"

Monday and Thursday seed identical names (`WorkoutPlanSeed.swift`). The *Templates* list shows two visually identical rows, distinguished only by a caption. Name them "Full Body A / B" or prefix the weekday.

### 4.4 The plank has no timer **(fixed)**

`TrackingMode.duration` renders a ±5s stepper (`ActiveWorkoutView`, `durationLogger`) — you hold a plank, then type in how long it was. Your spec asks for "timers should operate automatically where possible," and the app already has all the timer machinery. A start/stop hold timer here is the single biggest remaining win on the logging screen.

**Fixed.** `HoldTimerView` counts down from the configured target with a haptic at
zero, and is timestamp-driven like the rest timer so backgrounding mid-hold does not
distort the recorded time. Stopping early records what was actually held (22 s stays
22 s) rather than the target. Covered by `FittrTests/HoldTimerTests.swift`, plus a UI
test asserting the start control is reachable without scrolling.

### 4.5 "Save Workout" is misleading

By the time `WorkoutSummaryView` appears, `finishWorkout()` has already set `endedAt`, saved, evaluated PRs and marked the schedule complete. The workout **is** saved. The button actually commits session RPE, enjoyment and notes — and triggers the HealthKit write. So if you dismiss the summary any other way, those are silently lost and the workout never reaches Health. Rename it ("Done"), and persist RPE/enjoyment on change rather than on button tap.

Related: `sessionRPE` is `@State` initialised to `6`, so reopening a finished session shows 6 regardless of what you saved.

### 4.6 Music pauses on every rest by default

`pauseMusicForRest()` runs on every rest interval. For a 90-second rest that means the music stops for most of the workout. It's an unusual default and it isn't in the spec — most people want music *continuing* through rest. Worth a settings toggle, defaulting to "keep playing."

### 4.7 Smaller things

- **Reschedule** (`TodayView`) jumps to tomorrow with no date picker, confirmation or undo.
- **No undo for a mis-logged set** during a workout — `removeLastSet()` exists and isn't wired up (see P2).
- **"0 / 1 sessions completed"** on a rest day, from `max(planned, 1)` in `thisWeekCard`.
- **Dynamic Type**: hard-coded `.system(size: 56)` and `size: 40` with `minimumScaleFactor` won't scale for larger accessibility sizes. You're 51 and using this at arm's length on a gym floor — worth testing at XL.
- **VoiceOver**: `accessibilityIdentifier` is used well for UI tests, but real `accessibilityLabel`/`accessibilityValue` are largely absent outside `StepperControl`. The rest timer in particular announces as a bare number.
- **Light mode doesn't exist.** `.preferredColorScheme(.dark)` is applied app-wide and again in `ActiveWorkoutView`, and `FittrTheme` has no light palette. Defensible for a gym app — but it's an undocumented decision worth adding to `ProductDecisions.md`.

---

## Features vs. your own spec

Delivered, and matching the spec closely: seed programme, editable templates (add/remove/reorder/duplicate/reschedule), snapshotting, rest timers, progression prompts with confirmation, technique media, HealthKit read+write, EventKit write-only, local Music library, Swift Charts analytics, JSON/CSV export, crash recovery, metric-first units with a conversion layer already in place for lb/mi.

Gaps:

| Spec item | Status |
|---|---|
| RIR 3–4 as the core training principle | **Displayed as a target, impossible to record** (P1) |
| "Timers operate automatically where possible" | Plank is manual entry (§4.4) |
| Swimming: pool length, laps, distance, active vs rest time | Partial — `SwimMetrics` has the fields, but swim/rest split isn't captured in the logger |
| Apple Watch companion readiness | Architecture supports it; nothing built (expected for v1) |
| iCloud/CloudKit readiness | **Blocked** by `@Attribute(.unique)` on all models (P1) |

The `MusicKit`/`AVKit` framing in the spec was resolved to MediaPlayer + local library and documented in `ProductDecisions.md` — that's the right call for offline gym use, and correctly disclosed in the Settings copy.

---

## Suggested order of work

**This week**
1. Fix `WorkoutMathTests.swift:40` so the suite compiles. Fix the README destination. Fix the `exercises.first` ordering assumption in `ExportAndRecoveryTests`. Get to green.
2. Replace the `fatalError` on store-open failure, and add `VersionedSchema`.
3. Add an RIR input to the set logger.

**Next**
4. Cache `previousWorkout` in `init` and predicate the fetch.
5. Wire up `removeLastSet()` as undo; make "Add Set" real or delete it.
6. Fix the `HealthService.isAuthorized` false positive.
7. Fix `PlanView`'s tap target so today's workout starts the workout.

**Then**
8. Extract `WorkoutMusicCoordinator`; switch to `applicationMusicPlayer`; make rest-pause a preference.
9. Plank hold timer.
10. Fix the unilateral reps leak into PRs and Epley; fix the CSV rest join.
11. Automatic periodic JSON backup to Files/iCloud Drive.

---

## One closing note

The single highest-value habit change here isn't a code fix: **run the tests.** You have a well-designed suite that has never executed, and two of the failures it surfaces (the relationship-ordering assumption, and the Plan tab's tap target) are genuine issues that reading the code alone wouldn't have flagged as confidently. An AI-assisted loop that never actually builds and runs its own tests will keep producing plausible-looking code with dead buttons in it — which is exactly the failure pattern visible in `addSet()`, `draftRIR`, and `removeLastSet()`.
