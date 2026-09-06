# EventKit

`CalendarService` requests **write-only** calendar access (`requestWriteOnlyAccessToEvents()`).

When Calendar sync is enabled, upcoming `ScheduledWorkout` rows are upserted as events titled `🏋️ Full Body Strength` (or the template name). Notes include expected duration, exercise summary, and a `fittr://workout/{id}` deep link.

The EventKit event identifier is stored on `ScheduledWorkout.calendarEventIdentifier` so Fittr updates the same event instead of creating duplicates.

Two-way sync (reading changes made in Calendar) is not on by default and would require full calendar access. That toggle exists in settings data but is not activated in v1.
