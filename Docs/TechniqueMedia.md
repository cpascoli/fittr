# Technique media

Every strength exercise has a **Show Technique** action. The screen always shows setup, movement, breathing, cues, and common mistakes from `ExerciseDefinition`.

If a local `slug.mp4` is in the app bundle, it plays muted and looped via `AVQueuePlayer` + `AVPlayerLooper`. Otherwise a placeholder explains which filename to add.

See `Fittr/Media/Technique/README.md`.
