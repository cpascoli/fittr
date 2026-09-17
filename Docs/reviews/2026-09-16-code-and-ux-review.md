# Fittr — code, features and UX review (second pass)

**Date:** 16 September 2026
**Reviewed at:** `main` @ `98d64f5`, clean working tree
**Scope:** 56 Swift files under `Fittr/`, plus tests, `Docs/` and `specs.md`
**Method:** full read of the source, a real `xcodebuild test` run on the iPhone 17 Pro simulator (iOS 26.5), and throwaway instrumented unit tests written specifically to confirm the music defect (§1) and the reschedule defect (§3.1)
**Updated:** 17 September — §3.1 (reschedule incident) and §1.6 (playlists for long cardio) added from live use
**Previous review:** [`2026-09-07-code-and-ux-review.md`](./2026-09-07-code-and-ux-review.md)

---

## Verdict

The durability work since the last review is real and it was the right thing to do first. `StoreRecoveryView` replaces the launch `fatalError`, the migration policy is now written down in `FittrSchema.swift` including the `VersionedSchema` dead end that was actually tried and rejected, and `WorkoutSessionDeletionService` unwinds a session's side effects properly. All 30 unit tests pass.

Three things stand out as needing attention now.

**Rescheduling can strand a workout where nothing can reach it.** Added 17 September after you hit it in real use: tapping "Tomorrow" moves a workout onto a day that already has one, and because both the Plan week list and Today's week strip render only one item per day, the workout you just moved becomes invisible and therefore un-reschedulable. I reproduced it exactly. Relaunching the app silently recreates the missing day, so it looks self-healing, but the stranded copy stays in the database and counts against your adherence forever. Details and a fix order in §3.1.

**The music bug you suspected is real, and I found the mechanism.** When a new exercise starts, the previous exercise's track can keep playing while the UI displays the new track's name. There are three separate defects stacked on top of each other; one of them I confirmed empirically. Details in §1, with a fix design.

**The 0.25-second refresh in the active workout screen has stopped being a theoretical performance note and is now a measurable defect.** Both UI tests fail, and the reason is that the app never becomes idle: XCUITest needed **63 seconds** to resolve a single menu button, and a short workout flow that should take 20 seconds takes 285–415 seconds. That is the same root cause as the per-frame database scans flagged last time, and it is now costing you your UI test coverage. Details in §2.

One feature gap was also added on 17 September: long cardio sessions get a single track and then silence, because an assignment can only hold one song. §1.6 has a design that mostly reuses machinery the app already has.

Beyond those, the main theme is **dead controls**. I counted nine settings and toggles that are written to the database and never read by anything. Some of them describe features that do not exist at all — "Workout reminders" schedules nothing. §4.

Roughly: architecture 8/10, gym UX 8/10, correctness 6/10, durability 7/10 (up from 4).

---

## Verified build and test status

| Check | Result |
|---|---|
| `xcodebuild build` | ✅ Builds clean |
| `xcrun swiftc -typecheck` over `Fittr/*.swift` (iOS 18, Swift 6) | ✅ Clean |
| Unit tests (`FittrTests`) | ✅ **30 of 30 pass** in 0.14 s |
| `WorkoutFlowUITests.testCoreStrengthWorkoutFlow` | ❌ Fails after 415 s |
| `WorkoutFlowUITests.testPlankHoldTimerIsReachableWithoutScrolling` | ❌ Fails after 285 s |

The unit suite is genuinely healthy now, including the six new `HoldTimerTests` and three `WorkoutDeletionTests`. Both UI failures share one root cause, covered in §2.

---

## 1. Music: the previous exercise's track plays on the new exercise

You are right, and the UI is actively misleading you about it. Here is the full mechanism.

### 1.1 `holdQueue` does not know *which* track it paused — the deterministic cause

`MusicService` keeps two pieces of resume state:

```151:156:Fittr/Services/Music/MusicService.swift
    func pause() {
        let systemPlayer = MPMusicPlayerController.systemMusicPlayer
        pausedAt = Self.sanitizedTime(systemPlayer.currentPlaybackTime)
        holdQueue = true
        systemPlayer.pause()
    }
```

`holdQueue` means "we paused deliberately, so resume rather than re-queue." But it records no identity, so it cannot tell whether the thing it paused is the thing now being requested. `play(itemID:restart:)` then trusts it:

```122:130:Fittr/Services/Music/MusicService.swift
        if holdQueue || alreadyQueued {
            if holdQueue {
                resume()
            } else {
                systemPlayer.play()
            }
            nowPlaying = Self.track(from: item)
            return
        }
```

Every rest interval sets `holdQueue = true`, because `startRest` calls `pauseMusicForRest()` → `music.pause()`. So by the time you tap **START NEXT EXERCISE**, `holdQueue` is always true. If the new exercise is requested with `restart: false`, this branch calls `resume()` — which resumes **whatever is still in the system queue**, namely the previous exercise's track, at the position where rest paused it. The requested `itemID` is never queued.

Then the last line of that branch writes `nowPlaying` to the *requested* track anyway. That is why the Music row on the workout screen shows the correct new song title while the wrong song is audible — and it is the cheapest way for you to confirm this diagnosis on the device: when it misbehaves, the name on screen and the sound will disagree.

**When is `restart` false?** Three ways, and the first is the likely one:

```633:641:Fittr/Features/ActiveWorkout/ActiveWorkoutController.swift
        if let match = assignments.first(where: { $0.exerciseId == exercise.exerciseId && $0.scope == .exercise }) {
            itemID = match.musicItemID
            restart = restartExerciseTrack && match.restartFromBeginning
        } else if let workoutMusic = assignments.first(where: { $0.template?.id == session.workoutTemplateId && $0.scope == .workout }) {
            itemID = workoutMusic.musicItemID
            restart = false
        } else {
            return
        }
```

1. **Any exercise without its own assigned track** falls through to workout-scope music with a hard-coded `restart = false`. So if you have assigned tracks to some exercises but not all, the ones without a track will resume the previous exercise's song instead of the workout song. This fires 100% of the time.
2. Turning off **Restart track from beginning** in Settings makes `restart` false for *every* exercise.
3. Turning off **Restart from beginning** for one exercise in the Exercise library does the same for that exercise.

### 1.2 The new exercise's track is requested twice — confirmed empirically

`moveToNextExercise` calls the playback entry point, and the function it calls first has already called it:

```440:465:Fittr/Features/ActiveWorkout/ActiveWorkoutController.swift
    private func moveToNextExercise() {
        let items = session.orderedExercises
        if currentExerciseIndex + 1 < items.count {
            currentExerciseIndex += 1
            resetHold()
            activateCurrentIfNeeded()
            prefillFromHistory()
            playAssignedMusicIfNeeded()
        } else {
            finishWorkout()
        }
    }

    private func activateCurrentIfNeeded() {
        // ...
        persist()
        if openRest == nil {
            playAssignedMusicIfNeeded()
        }
    }
```

I verified this with a temporary test that gave two exercises their own tracks, completed the last set of the first, advanced, and printed the mock's call log:

```
PROBE playedIDs after advancing = ["track-A", "track-B", "track-B"]
```

`track-B` twice. Each call bumps `playbackGeneration` and spawns a detached `Task`, so the two races: the first task finishes its `await music.play(...)`, sees that the generation moved on, and calls `music.pause()` — which sets `holdQueue = true` and captures a `pausedAt` from a queue that may not have swapped yet. The second task then resumes or re-queues on top of that. With `restart: false` both tasks take the `resume()` path and the previous track simply keeps going. With `restart: true` you get an audible double-start or stutter.

### 1.3 `setQueue(with:)` is asynchronous and is treated as synchronous

```111:121:Fittr/Services/Music/MusicService.swift
        let systemPlayer = MPMusicPlayerController.systemMusicPlayer
        let alreadyQueued = systemPlayer.nowPlayingItem?.persistentID == persistentID
        if restart {
            holdQueue = false
            pausedAt = nil
            systemPlayer.setQueue(with: MPMediaItemCollection(items: [item]))
            systemPlayer.play()
            systemPlayer.currentPlaybackTime = 0
            nowPlaying = Self.track(from: item)
            return
        }
```

`MPMusicPlayerController.setQueue(with:)` does not take effect immediately — the contract is to call `prepareToPlay(completionHandler:)` and wait for the callback before issuing playback commands. Calling `play()` and then assigning `currentPlaybackTime = 0` on the very next lines is a race against the queue swap. When the swap has not landed, `play()` resumes the *old* queue — the previous exercise's track again — and the `currentPlaybackTime = 0` lands on the old item, rewinding it.

This is an independent path to the same symptom, and it can fire even with `restart: true` and default settings. The 80 ms sleep in `resume()` is the same race being papered over:

```158:168:Fittr/Services/Music/MusicService.swift
    func resume() {
        holdQueue = false
        let systemPlayer = MPMusicPlayerController.systemMusicPlayer
        let time = pausedAt
        systemPlayer.play()
        restorePlaybackTime(time, on: systemPlayer)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            restorePlaybackTime(time, on: systemPlayer)
        }
    }
```

Setting the playback time twice, 80 ms apart, in the hope that one of them sticks, is a sign the design is fighting the framework rather than using it.

### 1.4 Suggested fix

Three changes, in order of value:

**(a) Make resume state track-identified.** Replace the bare `holdQueue` boolean with the identity of what was paused, and decide from the player's actual state rather than from a flag:

```swift
private var paused: (itemID: String, time: TimeInterval)?

func play(itemID: String, restart: Bool) async {
    guard await ensureAuthorized(), let persistentID = UInt64(itemID) else { return }
    guard let item = songItem(persistentID) else { return }
    let player = MPMusicPlayerController.systemMusicPlayer
    let isCurrent = player.nowPlayingItem?.persistentID == persistentID

    if !isCurrent {
        // A different track: always queue it. Never inherit the old queue.
        paused = nil
        player.setQueue(with: MPMediaItemCollection(items: [item]))
        await prepare(player)          // prepareToPlay(completionHandler:)
        player.currentPlaybackTime = 0
        player.play()
        nowPlaying = Self.track(from: item)
        return
    }

    if restart { player.currentPlaybackTime = 0 }
    else if let paused, paused.itemID == itemID { player.currentPlaybackTime = paused.time }
    player.play()
    paused = nil
    nowPlaying = Self.track(from: item)
}
```

The key invariant: **a request for a track that is not the current item must always go through `setQueue`, regardless of any resume flag.** That alone kills §1.1.

**(b) Wrap `prepareToPlay` in a continuation** and await it after every `setQueue` before touching `play()` or `currentPlaybackTime`. That kills §1.3 and lets you delete the 80 ms sleep.

**(c) Call `playAssignedMusicIfNeeded()` exactly once per advance.** Remove it from `activateCurrentIfNeeded()` and let the two callers (`init` and `moveToNextExercise`) each make one explicit call. That kills §1.2 and removes the need for the `playbackGeneration` counter to defend against the app's own duplicate requests.

Also set `nowPlaying` only from what the player reports, not from what was asked for. A UI that cannot lie about the current track would have made this bug obvious in seconds instead of requiring a code read.

### 1.5 Other music issues

- **`pulse()` pauses the player up to four times a second during rest.** `if isResting && !allowMusicDuringRest && music.isPlaying { music.pause() }`. If you start a song from Control Center or the Music app while resting, Fittr will fight you and win, within 250 ms, with no explanation. Rest-pause should be an intent applied once at the start of rest, not a condition enforced continuously.
- **`systemMusicPlayer` hijacks the global queue.** Starting a workout clobbers whatever you had playing, and `stop()` kills it. `applicationMusicPlayer` scopes playback to Fittr and restores the system queue on exit. Still the right change, still not made.
- **The per-exercise "Auto start when exercise begins" toggle is dead.** `MusicAssignment.autoplay` is written by a `Toggle` in `ExerciseLibraryView` and read by nothing. Playback consults only the global `autoPlayExerciseTrack`.
- **The "After track / exercise" picker is dead.** `AppSettings.afterTrackBehavior` is written by `SettingsView` and read nowhere in the app.
- **The state machine is still flag soup**: `restActive`, `musicPausedForRest`, `musicStoppedByUser`, `allowMusicDuringRest`, `playbackGeneration` in the controller, plus `holdQueue` and `pausedAt` in the service. Seven interacting pieces of state for "play a song, pause it during rest." Extracting a `WorkoutMusicCoordinator` with an explicit enum (`.idle / .playing / .pausedForRest / .stoppedByUser`) was recommended last time and would have made §1.1 structurally impossible.

### 1.6 Feature gap — long cardio gets one song, then silence — **implemented 17 September**

**Requested 17 September:** treadmill walking and indoor cycling run 30–40 minutes, but an exercise can only be assigned a *single* track, so the music stops after three or four minutes.

This is not a subjective gap, it is the literal behaviour of the queue. Every play call builds a one-item queue:

```116:116:Fittr/Services/Music/MusicService.swift
            systemPlayer.setQueue(with: MPMediaItemCollection(items: [item]))
```

When that item finishes there is nothing behind it, so `systemMusicPlayer` stops. Nothing in the app notices or refills the queue — the `MPMusicPlayerControllerNowPlayingItemDidChange` notification is never observed. So a 35-minute ride gets one song and then 30 minutes of nothing, unless you pick up the phone mid-session.

**The good news is that most of the machinery already exists.** `MusicService` can already enumerate local playlists and expand one into tracks, and the picker already browses them — it just throws the playlist away and keeps the one song you tapped:

```74:98:Fittr/Services/Music/MusicService.swift
    func localPlaylists() async -> [MusicPlaylistInfo] { … }

    func songsInPlaylist(id: String) async -> [MusicTrackInfo] { … }
```

`MPMediaItemCollection` already takes an array, and `next()` / `previous()` already exist on `MusicServicing` (currently called by nothing). So this is mostly a data-model and UI change, not a playback-engine change.

**Suggested design**

1. **Store a playlist reference, not a snapshot of track IDs.** Add to `MusicAssignment`:

   ```swift
   var playlistID: String = ""
   var playlistName: String = ""
   ```

   Both non-optional with defaults, which keeps the change additive and lightweight-migratable under the policy documented in `FittrSchema.swift`. `musicItemID` stays as-is and continues to mean single-track, so every existing assignment keeps working untouched. A non-empty `playlistID` means "play this playlist"; resolve it through `songsInPlaylist(id:)` at playback time so that editing the playlist in the Music app is reflected in Fittr automatically, and a track deleted from the library cannot leave a dead ID behind.

2. **Add `func play(itemIDs: [String], startAt: Int, restart: Bool)`** to `MusicServicing`, queueing `MPMediaItemCollection(items:)` with the whole list. Whatever resume-state fix §1.4 lands on needs to key on the collection as well as the item, or a playlist assignment will hit exactly the §1.1 bug at a larger scale.

3. **Let the picker assign the playlist itself.** It already drills into a playlist to list its songs; that screen needs one more row at the top — "Use this whole playlist (N songs)" — above the individual tracks. That is a genuinely small addition to `MusicPickerView.playlistContent`.

4. **Offer shuffle and repeat for playlist assignments**, mapping to `MPMusicPlayerController.shuffleMode` and `.repeatMode`. Repeat-all is what actually guarantees the music covers the session regardless of how long you ride, and it is the setting that makes this feature reliable rather than merely longer.

5. **Surface skip controls during the workout.** `next()` and `previous()` exist and are unused; with a playlist they finally mean something, and skipping a track you are not in the mood for is a real gym need. They want the large hit targets described in §6.

6. **This is where `afterTrackBehavior` comes back to life.** The dead picker in §4 has cases `.continueCurrent / .returnToPlaylist / .doNothing`, which only make sense in a world where a workout-level playlist exists and an exercise-level track interrupts it. Implement it as part of this rather than deleting it: after an exercise's track finishes, either continue into the playlist, return to the workout playlist, or stop.

**Scope note.** Rather than restricting playlists to cardio types in the model, allow a playlist on any assignment and simply *default* to the playlist tab for duration-based exercises. Strength exercises benefit too — a 45-minute session currently has the same silence problem between the per-exercise tracks — and a type restriction would be extra logic that buys nothing.

---

## 2. The active workout screen never goes idle, and it has now broken the UI tests

Last review flagged `previousWorkout` as a computed property that fetches every session ever recorded, called twice per body evaluation, with the body re-evaluating four times a second. It is unchanged:

```175:184:Fittr/Features/ActiveWorkout/ActiveWorkoutController.swift
    var previousWorkout: WorkoutSession? {
        let all = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return AnalyticsEngine.previousComparableSession(
            for: session.workoutTemplateId,
            type: session.type,
            before: session.id,
            startedAt: session.startedAt,
            in: all
        )
    }
```

The new information is that this is no longer a prediction about next year. It is measurable today, and the measurement is in your test logs. XCUITest waits for the app to reach quiescence before each interaction. Because `pulse()` writes `tick` every 250 ms and the header reads it, the whole body invalidates continuously and the app never quiesces, so every interaction burns the full timeout:

```
t =    16.02s Tap "workout.menu" Button
t =    79.74s Tap "Skip exercise" Button          ← 63 seconds to resolve one menu item
t =   143.79s     Failed: Failed to compute hit point for Button, label: 'Skip exercise':
                  Activation point invalid and no suggested hit points based on element frame
```

Both UI tests die this way, on the same toolbar `Menu`: the menu is presented, but by the time XCUITest resolves the item, the re-render has invalidated its frame (`{{inf, inf}, {0.0, 0.0}}`). `testCoreStrengthWorkoutFlow` takes 415 s and fails on "Finish workout"; the plank test takes 285 s and fails on "Skip exercise" after three retries.

So the 4 Hz whole-screen invalidation is costing you, right now: two dead UI tests, plus battery and heat on a 45-minute session with `isIdleTimerDisabled = true`. The fixes are unchanged from last time and are worth doing now rather than later:

- Resolve `previousWorkout` **once** in `init` and store it. It cannot change during a session.
- Give the fetch a `#Predicate` on `workoutTemplateId` and `endedAt != nil`, with a reverse sort and `fetchLimit = 1`.
- Move the clock into a small leaf subview so the timer invalidates a `Text`, not the screen. This is the change that should let the UI tests pass again.

---

## 3. Bugs

### 3.1 P1 — "Tomorrow" can move a workout somewhere you cannot reach it, and there is no undo — **fixed 17 September**

**Reported from real use, 16 September:** after finishing Wednesday's workout, Today showed the next session (Thursday). Tapping **Tomorrow** to see what it did moved it, and there was no way to move it back — Thursday then read "Unscheduled" with no way to put anything on it.

I reproduced the exact sequence in a throwaway test against the seeded programme. The output:

```
--- BEFORE ---
  Thu: Full Body Strength [upcoming]
  Fri: Swim / Cardio [upcoming]

--- AFTER pressing Tomorrow ---
  Thu: Unscheduled
  Fri: Swim / Cardio [upcoming] + Full Body Strength [rescheduled]

PROBE items landing on Fri: 2
PROBE times: ["18 Sep 2026 at 12:00", "18 Sep 2026 at 12:00"]
PROBE Plan row would show only: Swim / Cardio
```

Four distinct defects combine here.

**(a) One tap, destructive, no confirmation and no undo.** The button does a real mutation with no way back:

```154:158:Fittr/Features/Today/TodayView.swift
                        Button("Tomorrow") {
                            if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: item.scheduledStart) {
                                try? ScheduleService.reschedule(item, to: tomorrow, in: modelContext)
                            }
                        }
```

`ScheduleService.reschedule` also overwrites `item.notes` with the literal string `"Rescheduled"`, so any note you had on that day is destroyed too.

**(b) Rescheduling onto an occupied day hides one of the two workouts — permanently.** Every seeded item sits at 12:00 (`DateHelpers.applying` defaults the hour to 12), so the moved workout lands at exactly the same timestamp as the day's existing one. Both the Plan week list and Today's week strip resolve a day to a *single* item:

```76:83:Fittr/Features/Plan/PlanView.swift
    private var weekRows: [WeekRow] {
        let start = DateHelpers.isoWeekStart(for: .now)
        return ISOWeekday.allCases.map { day in
            let date = DateHelpers.dateOnISOWeekday(day, weekStart: start, hour: 12, minute: 0)
            let item = weekItems.first { ISOWeekday.from(date: $0.scheduledStart) == day }
            return WeekRow(id: day.rawValue, weekday: day, date: date, scheduled: item)
        }
    }
```

`weekItems.first { ... }` silently drops the collision, and on a timestamp tie which one survives is arbitrary. In the reproduction the surviving row is **Swim / Cardio**, so the workout that was just moved is invisible. Since the only reschedule affordance is a swipe action *on that row*, the moved workout cannot be selected, cannot be moved back, and cannot be skipped. That is precisely the dead end reported.

**(c) The reschedule editor exists but is effectively hidden.** `ScheduleEditorView` has exactly what is needed — a date-and-time picker and a status picker — and it is reachable only by swiping a "This week" row in the Plan tab and tapping **Reschedule**. Nothing on the Today tab points to it, and the September 7 pass deliberately moved rescheduling off the row tap to make the tap open the workout. That was the right call for the tap, but it left the feature with no discoverable entry point. The affordance you actually want after tapping "Tomorrow" by mistake is on a different tab, behind a gesture, on a row that may no longer exist.

**(d) There is no way to schedule a workout *onto* a day.** An empty day renders as a plain, non-interactive `Text("Unscheduled")` — no tap target, no "add workout here". Once a day is vacated, the only thing that can refill it is the seeder.

**Why it partially self-heals, and why that is not a fix.** `ScheduleService.ensureUpcomingSchedule` runs on every launch via `SeedService.seedIfNeeded`, and it recreates any missing (template, day) pair for today or later. The probe confirms Thursday comes back after a relaunch — but the stray copy stays on Friday:

```
--- AFTER relaunch ---
  Thu: Full Body Strength [upcoming]
  Fri: Swim / Cardio [upcoming] + Full Body Strength [rescheduled]
```

So the schedule silently accumulates unreachable duplicates. Each one is counted in the adherence denominator by `AnalyticsEngine.adherence` (it is neither optional nor a rest day), so it will quietly drag the adherence ring down and can never be completed or skipped.

**Suggested work, in order:**

1. **Make a day able to hold more than one workout, or refuse the move.** Either render all items for a day (the honest fix) or have `reschedule` reject a target day that is already occupied and say so. Today's silent drop is the actual data-loss bug.
2. **Keep rescheduling on the swipe, but record where the workout came from.** Carlo's call on 17 September: the swipe is fine now that it is known about, so no new control on Today. Storing the previous date still matters, so that undo is exact rather than "subtract a day".
3. **Add "Schedule a workout" to empty days.** Make the `Unscheduled` row tappable, offering the templates.
4. **Add "Move to today"** as a one-tap action, which is the inverse of the button that caused this and the thing most often wanted.
5. **Stop `reschedule` from clobbering `notes`.** Append or leave alone; do not overwrite user text with a status word.
6. **Stop the backfill refilling a vacated day.** `ensureUpcomingSchedule` should treat a moved workout as occupying both its new day and its original one, so the duplicate is never created. Collapsing duplicates after the fact was considered and rejected: any rule for choosing a winner deletes a schedule row the user can see, and the two plausible rules disagree on exactly the case that prompted this. Prevention plus a manual "Remove" action is the safer pair.

A regression test is cheap here and would have caught (b) immediately: seed, reschedule a day onto an occupied one, and assert that both items are still reachable through whatever the Plan tab renders.

### 3.2 P1 — An in-progress workout can be swiped away from History

`HistoryView` filters only on type and search text, never on `endedAt`:

```85:94:Fittr/Features/History/HistoryView.swift
    private var filtered: [WorkoutSession] {
        sessions.filter { session in
            if let typeFilter, session.type != typeFilter { return false }
            if !search.isEmpty {
                return session.exercises.contains { $0.exerciseName.localizedCaseInsensitiveContains(search) }
                    || session.name.localizedCaseInsensitiveContains(search)
            }
            return true
        }
    }
```

So a workout you are part-way through appears in History with a duration that ticks upward, and the swipe-to-delete I added last session will happily delete it. Two consequences:

- The Today tab's resume banner vanishes and the session is unrecoverable — which is at least *consistent* with "like it never happened", but it is not what you would expect from tapping Delete on a History row.
- Worse, `RootTabView` holds the session in `@Binding var presentedSession`. Close the workout cover without finishing (the **Close** button does not end the session), delete the row from History, and that binding plus any live `ActiveWorkoutController` now reference a deleted `@Model`. Reading a deleted SwiftData object is a crash.

Filter History to `endedAt != nil`, and surface unfinished sessions only through the resume banner. If you want them deletable, do it from the banner with its own wording ("Discard unfinished workout").

`ExerciseHistoryView` has the same missing filter, so an in-progress session's completed sets already leak into the per-exercise log.

### 3.3 P1 — RIR is still impossible to record

Unchanged since last review, and still the widest gap between the spec and the app. `draftRIR` and `draftRPE` are declared, written into every saved set, and **never assigned by any view**. The only other reference is a read in `SetLoggerView`:

```57:61:Fittr/Features/ActiveWorkout/SetLoggerView.swift
            if let rir = controller.draftRIR {
                Text("RIR \(rir.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

which is always nil, so it never renders. Every set in your database has `rir = nil`. `ProgressionEngine`'s safety gate on RIR is unreachable code. The CSV columns are permanently empty. Meanwhile the screen prints "Target: 8–12 reps · RIR 3–4" as a goal.

A five-button row (0 / 1 / 2 / 3 / 4+) under the reps stepper closes this, and it is the one number that would make the progression engine trustworthy.

### 3.4 P2 — "Add Set" is still a no-op button

```332:336:Fittr/Features/ActiveWorkout/ActiveWorkoutController.swift
    func addSet() {
        guard let prescription else { return }
        // Extra set beyond the snapshot target is allowed; targetSets is a prescription, not a hard cap.
        _ = prescription
    }
```

Wired to a visible button in the bottom bar. You tap it in the gym and nothing happens. Meanwhile `removeLastSet()` is fully implemented and wired to nothing, so there is still no way to undo a mis-tapped set — much the more likely gym scenario. Swap them: delete or implement "Add Set", and give "Undo last set" the slot.

### 3.5 P2 — Resuming mid-workout still reverts to last week's weight

`prefillFromHistory()` prefers an accepted planned load, then the *previous workout's* sets, and only then the current session's own completed sets. Since `completeSet()` calls `PlannedLoadService.consume()` after the first set, a crash-and-resume mid-exercise falls through to last week's numbers rather than the weight you were lifting five minutes ago. Reorder so the current session wins.

### 3.6 P2 — `HealthService.isAuthorized` is still not authorisation

```40:53:Fittr/Services/HealthKit/HealthService.swift
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        // ...
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
        isAuthorized = true
    }
```

HealthKit's `requestAuthorization` succeeds when the user taps Deny — by design, so apps cannot detect refusal for read types. So `SettingsView` prints "Connected" after a denial, and `writeHealthIfNeeded()` proceeds on the false positive, meaning workouts silently never reach Health while the UI claims they do. Use `store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized`, which *is* reliable for write types and is exactly what you need here.

### 3.7 P2 — The CSV rest join is wrong, and the join key has been dropped from the DTO

```270:271:Fittr/Services/Export/DataExportService.swift
                    let completedAt = set.completedAt ?? .distantPast
                    let rest = exercise.rests.first { $0.startedAt >= completedAt }
```

`rests` is an unordered SwiftData relationship, so `.first` is not "the earliest" — `rest_after_seconds` is wrong more or less at random. `RestInterval.afterSetId` is the correct join key and is populated at creation, but `RestDTO` does not carry it at all, so the export layer has thrown away the only correct way to do this. Add `afterSetId` to `RestDTO` and match on it. The JSON export has the same problem: `rests: exercise.rests.map` preserves no order.

### 3.8 P2 — Unilateral reps still corrupt PRs and 1RM estimates

`completeSet()` stores `reps = draftLeftReps + draftRightReps` for unilateral movements alongside the per-side values. Volume handles this correctly; two other places do not.

- `PersonalRecordService` takes `mostRepsAtWeight` from `set.reps`, so a one-arm row PR records as the sum of both arms — "20 reps at 10 kg".
- `AnalyticsView.epleyPoints` feeds `set.reps` into `estimatedOneRepMaxKg`, so 6+6 is treated as a 12-rep set and materially overestimates. At 10+10 the 1–12 guard drops the point silently, leaving invisible holes in the chart.

### 3.9 P3 — `AnalyticsView` still builds throwaway `@Model` objects during body evaluation

`strengthExercises` reduces sessions into `ExerciseDefinitionStub` values and then constructs full `ExerciseDefinition` SwiftData models from them to feed a `Picker` that needs only an id and a name. The comment says "fetch from first matching definition if present", describing code that is not there. They are never inserted so nothing is corrupted, but it allocates model instances on every render of the Analytics tab. Make `ExerciseDefinitionStub` `Identifiable` and use it.

### 3.10 P3 — Every save error is still swallowed

`persist()` is `try? modelContext.save()`, called roughly 20 times in the controller, with the same pattern in most views' `.onDisappear`. A failed save mid-workout is silent and the data is gone. At minimum log it; better, raise a banner. This is the one category of bug where "it works on my phone" tells you nothing.

---

### 3.11 P2 — The exercise library is read-only, so you cannot add an exercise

**Found 17 September, from "can I do treadmill running instead of indoor cycling?"**

You cannot, because the exercise does not exist and there is no way to create it. The seeded library holds ten exercises, of which five are cardio-ish: Indoor Cycling, Treadmill Walking, Walking, Swimming, Mobility. There is no running entry of any kind.

`ExerciseLibraryView` is a `List` with a search field and navigation links — no add button, no `context.insert` anywhere in the file. `ExerciseDetailView` lets you rename an existing definition and toggle `isEnabled`, and that is the entire write surface. So the only route to "Treadmill Running" today is to rename "Treadmill Walking", which mutates the definition everywhere it is referenced, including in already-logged history and existing personal records.

Both places that add an exercise to a workout — the template editor's "Add exercise" sheet and the live `ReplaceExerciseSheet` — read from the same library, so the gap closes both at once. This wants a "New exercise" button writing an `ExerciseDefinition` with a name, category, equipment, laterality and tracking mode, and it should be reachable from the Add and Replace sheets as well as the library tab, since that is where you are standing when you discover the exercise is missing.

### 3.12 P2 — A cardio or hold target cannot be edited from the template editor

`TemplateExerciseEditor` exposes sets, min/max reps, rest and the optional toggle — but never `targetDurationSeconds`:

```168:182:Fittr/Features/Plan/TemplateEditorView.swift
            Stepper("Sets \(item.targetSets)", value: $item.targetSets, in: 1...8)
            if item.exercise?.trackingMode.usesReps == true {
                Stepper("Min reps \(item.minReps ?? 8)", …)
                Stepper("Max reps \(item.maxReps ?? 12)", …)
            }
            Stepper("Rest \(item.targetRestSeconds)s", value: $item.targetRestSeconds, in: 0...300, step: 15)
            Toggle("Optional", isOn: $item.isOptional)
```

The reps steppers are correctly gated on `trackingMode.usesReps`, but nothing was written for the other branch. So for every duration-tracked exercise — Indoor Cycling at 2100 s, Walking at 1800 s, Swimming at 1800 s, the plank hold — the target is whatever the seed set and there is no way to change it in the app. Wanting a 25-minute ride instead of 35 is an ordinary request with no answer. Add a duration control in the `else` branch, in minutes for cardio and seconds for holds.

---

## 4. Dead controls: nine settings that are written and never read

This is the dominant new finding. Each of these is a switch in the UI, persisted to the database, that no code consults.

| Control | Where | Status |
|---|---|---|
| **Workout reminders** | Settings → Notifications | `NotificationService.scheduleWorkoutReminder` exists and is **never called**. No reminder is ever scheduled. The toggle only requests permission. |
| **Remind N min before** | Settings → Notifications | `reminderLeadMinutes` read nowhere. The reminder body even hard-codes "in 30 minutes". |
| **Rest timer sound / notification** | Settings → Training | `restRemindersEnabled` read nowhere. `startRest` schedules the rest notification unconditionally, so turning this off does nothing. |
| `restSoundEnabled` | model only | Never read, no UI. |
| **Auto start when exercise begins** | Exercise library | `MusicAssignment.autoplay` read nowhere. |
| **After track / exercise** | Settings → Workout music | `afterTrackBehavior` read nowhere. |
| Two-way calendar sync | model only | `calendarTwoWaySyncEnabled` read nowhere. Settings copy is at least honest that it is future work. |
| `--reset-store` launch arg | `LaunchArguments.resetStore` | Defined, never read. Both UI tests pass this flag expecting a clean slate; they get one only because UI-test runs use an in-memory store. |
| **Add Set** | workout bottom bar | No-op (§3.4). |

Two of these are worth promoting from "dead code" to "missing feature": **workout reminders do not exist**, despite being a spec item and having a working service method and two UI controls, and **the rest notification cannot be turned off**, which matters if you ever train somewhere you would rather the phone stayed quiet.

The rest should simply be deleted until they do something. A settings screen where a third of the switches are inert is worse than a smaller one, because it teaches you not to trust any of them.

---

## 5. Test quality

The unit suite is in good shape: 30 tests, fast, and the new `HoldTimerTests` cover the behaviour that actually matters (stopping early records what was held, not the target). `WorkoutDeletionTests` covers the subtle planned-load ownership case properly.

Two problems with the UI tests beyond the quiescence failure in §2:

**`testPlankHoldTimerIsReachableWithoutScrolling` is date-dependent and can only pass on a Monday or Thursday.** It taps `today.start`, which starts *whatever is scheduled next*, then skips six exercises to reach the plank. But the seed programme puts a single-exercise recovery walk on Wednesday and Saturday, cardio on Tuesday, swimming on Friday, rest on Sunday. I ran it on a Wednesday: it started the recovery template, and skipping its one exercise ends the workout, so `workout.startHold` can never appear. The test should navigate to the Monday strength template explicitly rather than trusting the calendar.

**Neither UI test would survive the menu being restyled.** Both drive the workout through `app.buttons["Finish workout"]` and `app.buttons["Skip exercise"]` — localised menu labels with no `accessibilityIdentifier`. Given the identifiers used elsewhere in these tests, these two are an inconsistency worth closing.

---

## 6. UX and UI

### 6.1 Still good

The gym screen remains the best part of the app: 76 pt primary button, 64 pt stepper targets, monospaced digits, dark-locked, screen kept awake, one tap to log a set, last session's numbers above the input, technique clip surfaced during rest. The hold timer added since the last review is a genuine improvement, and showing the alternate unit under the weight ("= 26.5 lb") is the kind of detail that only comes from actually using the thing.

### 6.2 "Save Workout" still overstates and under-delivers

By the time `WorkoutSummaryView` appears, `finishWorkout()` has already set `endedAt`, saved, evaluated PRs and marked the schedule complete. The workout *is* saved. What the button actually commits is session RPE, enjoyment, notes — and the HealthKit write. Dismiss the summary any other way and all four are silently lost. Rename it "Done" and persist RPE/enjoyment on change.

Related, and unchanged: `sessionRPE` is `@State` initialised to `6`, so reopening a finished session shows 6 regardless of what you saved.

### 6.3 Two templates still both called "Full Body Strength"

Monday and Thursday seed identical names, so the Templates list shows two visually identical rows distinguished only by a caption. "Full Body A / B", or prefix the weekday.

### 6.4 Rest still pauses music by default

`pauseMusicForRest()` runs on every rest interval, so with 90-second rests the music is off for most of the workout. Not a spec requirement, and an unusual default. Worth a preference, defaulting to "keep playing" — and see §1.5 on how aggressively `pulse()` currently enforces it.

### 6.5 No undo on history deletion

The swipe-to-delete added last session is guarded by a confirmation dialog, which is right, but it is irreversible and it unwinds PRs and planned loads as well. For a testing-phase convenience that is fine; before this stops being a test app, consider a soft delete or an undo snackbar.

### 6.6 Smaller things, mostly unchanged

- **Reschedule** is now a confirmed P1 incident rather than a smaller thing — see §3.1.
- **Dynamic Type**: hard-coded `.system(size: 44)` in the hold ring and `size: 56/40` elsewhere with `minimumScaleFactor` will not scale at larger accessibility sizes. Worth testing at XL given you read this at arm's length.
- **VoiceOver**: `ProgressRing` and `WeekStrip` now carry proper labels and values, which is a real improvement. The rest timer still announces as a bare number.
- **Light mode does not exist** — `.preferredColorScheme(.dark)` app-wide, no light palette in `FittrTheme`. Defensible for a gym app, but it is an undocumented decision; add it to `ProductDecisions.md`.

---

## 7. Architecture

The layering is still sound and the protocol-backed services with mocks are still what makes the unit suite possible. Three notes, two carried forward:

**`ActiveWorkoutController` is 725 lines and growing** (up from 661). It owns session state, the rest state machine, music orchestration, the hold timer, history prefill, progression and persistence. The music portion is the part that just produced a real bug; the hold timer added since last review is clean but is one more responsibility. Extracting `WorkoutMusicCoordinator` is now the highest-value refactor in the app, because §1 is a direct consequence of that state living here as loose booleans.

**`FittrDependencies.shared` is still used two ways.** The controller takes constructor injection; views reach for the singleton directly (`ActiveWorkoutView.music`, `WorkoutSummaryView.writeHealthIfNeeded()`, `HistoryView.delete()`). The injection half is the good half.

**The migration policy is genuinely well handled now.** The comment block in `FittrSchema.swift` explaining why `VersionedSchema` was removed — that two versions listing the same live types hash identically and Core Data rejects the stage with `Duplicate version checksums detected`, found by round-tripping a real store — is the most useful thing in the codebase for whoever touches the schema next, including future-you-with-an-AI. That is the standard the rest of the tricky code should aim for.

Still outstanding from last time: the CloudKit path remains blocked by `@Attribute(.unique)` on all 18 models, and there is still no automatic periodic backup even though `DataExportService` already produces a complete one.

---

## 8. Suggested order of work

**Done on 17 September**
- ~~Stop "Tomorrow" from stranding a workout (§3.1).~~ Every item on a day now renders, empty days are tappable to schedule, and the Plan swipe gained "Today", "Undo move" and "Remove". `reschedule` records where the workout came from and no longer overwrites notes; the launch backfill treats a moved workout as occupying its original day too, so the duplicate is never created. Eight regression tests in `ScheduleReschedulingTests`.
- ~~Let a cardio exercise hold a playlist rather than one track (§1.6).~~ `MusicAssignment` carries a playlist reference with shuffle and repeat, `MusicService` queues the whole collection and tracks queue identity, the picker offers "Play the whole playlist", and skip controls appear during the workout when there is a queue to move through. Four tests in `MusicPlaylistTests`.

**First — the two things that are still actively wrong**
1. Fix the music queue (§1.4): track-identified resume state, `prepareToPlay` before playback commands, and one `playAssignedMusicIfNeeded()` per advance. Make `nowPlaying` reflect the player, not the request. Note that §1.6 added queue-identity tracking to `MusicService`, which is the hook this wants to build on.
2. Move the workout clock into a leaf subview and cache `previousWorkout` in `init` (§2). Confirm the UI tests go green again.

**Then — correctness**
3. Filter History to finished sessions (§3.2).
4. Add the RIR input (§3.3).
5. Wire `removeLastSet()` as undo; delete or implement "Add Set" (§3.4).
6. Fix `HealthService.isAuthorized` (§3.6).
7. Fix the unilateral reps leak into PRs and Epley (§3.8), and the CSV rest join (§3.7).
8. Let people create an exercise, from the library and from the Add/Replace sheets (§3.11), and edit duration targets in the template editor (§3.12).

**Then — honesty of the UI**
9. Delete or implement the nine dead controls (§4). Schedule the workout reminders, or remove both controls and the service method. `afterTrackBehavior` is now genuinely implementable rather than deletable, since §1.6 gave it a world to mean something in.
10. Make the plank UI test date-independent; add identifiers to the menu items (§5).
11. Rename "Save Workout" and persist the check-in on change (§6.2).

**Then — structure**
12. Extract `WorkoutMusicCoordinator` with an explicit state enum, and switch to `applicationMusicPlayer`.
13. Automatic periodic JSON backup to Files or iCloud Drive.

---

## One closing note

Last review's closing note was "run the tests." You did, and the unit suite is now genuinely green and genuinely useful — the deletion and hold-timer tests are the good kind, testing behaviour you care about rather than implementation.

The note this time is narrower: **when something plays, ask the system what is playing.** The music bug was hard to see from the code and easy to see from the device, and the single thing that stopped you from seeing it was `nowPlaying = Self.track(from: item)` — a line that reports what was requested as though it were what happened. Any display derived from intent rather than from observed state will eventually lie, and it will lie exactly when you most need it to be honest. That one line cost more debugging time than the queue bug behind it.
