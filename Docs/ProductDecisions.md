# Product decisions

Minor ambiguities from `specs.md` were resolved as follows.

- **Bundle ID:** `dev.carlo.Fittr`
- **Weight increment default:** 2.0 kg, editable in Settings
- **Unilateral volume:** entered weight is load per hand; volume = weight × (left reps + right reps)
- **Usual workout time:** unset until onboarding; Calendar events then use noon if still unset
- **Estimated 1RM:** Epley `weight × (1 + reps / 30)` for 1–12 reps only, labeled as an estimate
- **Starting loads:** first session uses per-exercise defaults (goblet 12 kg, RDL 10 kg/hand, chest 8 kg/hand, row 10 kg/arm, shoulder 6 kg/hand, pulldown 25 kg, plank 30 sec). After that, last session and accepted progression win.
- **Health / Calendar / Music:** requested only when the user enables the related setting
- **Exercise music:** local Music library only (playlists + title/artist search). Persistent IDs via MediaPlayer, not Apple Music catalog IDs.
- **Calendar:** write-only EventKit access by default
- **Demo history:** never seeded in production
- **Personal Team install:** use `Fittr/Fittr-PersonalTeam.entitlements` if HealthKit signing fails on a free Apple ID
