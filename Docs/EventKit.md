# EventKit

`CalendarService` requests **full** calendar access (`requestFullAccessToEvents()`).

Write-only was tried first and does not work for this feature. Updating or deleting an event means finding it first, and `store.event(withIdentifier:)` is a read that a write-only store cannot serve — so the "update the existing event" branch never matched and every sync wrote a fresh copy of every upcoming workout. That is where the duplicated workout events came from.

When Calendar sync is enabled, `ScheduledWorkout` rows for trainable templates are upserted as events titled `🏋️ Full Body Strength` (or the template name). Notes include expected duration, exercise summary, and a `fittr://workout/{id}` deep link. Rest days get no event.

The EventKit event identifier is stored on `ScheduledWorkout.calendarEventIdentifier` so Fittr updates the same event instead of creating duplicates.

`CalendarSyncService` owns the mirroring and is the only thing that should write to the calendar:

- `reconcile(in:)` brings the calendar in line with the schedule. Idempotent, and driven from launch, from every mutation in `PlanView`, and from Settings.
- `removeEvent(for:in:)` must run **before** a `ScheduledWorkout` is deleted. The identifier is the only handle on the event and it disappears with the row.
- `removeAllEvents(in:)` clears Fittr's events, including copies it has lost track of. Matching is on the `fittr://` deep link, falling back to the `🏋️ ` title prefix for events written before the link was attached.

Two-way sync (reacting to changes made in Calendar) is still not implemented.
