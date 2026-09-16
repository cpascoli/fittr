# Fittr

Personal gym companion for iPhone. Local-first, no account, no backend.

Fittr guides a workout in the gym, records sets and timestamps as they happen, keeps a weekly plan, charts progress, and optionally talks to Apple Health, Calendar, and the Music library on the iPhone.

## Install on iPhone 16 Pro (USB-C)

1. Install Xcode 26 from the App Store if needed.
2. Open `Fittr.xcodeproj`.
3. **Xcode → Settings → Accounts** → add your Apple ID.
4. Select the **Fittr** target → **Signing & Capabilities** → choose your **Team**. Leave Automatically manage signing on.
5. Unlock the iPhone, connect it with USB-C, tap **Trust** if asked.
6. In the Xcode toolbar, choose **Carlo’s iPhone** (or whatever the 16 Pro is named), then press **Run**.
7. First launch on device: **Settings → General → VPN & Device Management** → trust the developer.

If HealthKit signing fails (common on a free Personal Team), set `CODE_SIGN_ENTITLEMENTS` to `Fittr/Fittr-PersonalTeam.entitlements` and run again. Workout logging still works.

Bundle ID: `dev.carlo.Fittr`. Deployment target: iOS 18.

## What you get on first launch

- Profile prefilled: 51, 183 cm, 97 kg, target 85 kg
- Weekly plan: Mon/Thu full-body strength, Tue easy cardio, Wed recovery, Fri swim/cardio, Sat optional, Sun rest
- No fake workout history

The important path is **Today → Start Workout → Complete Set**. Rest starts from a timestamp. Killing the app mid-session offers resume.

## Docs

- [Architecture](Docs/Architecture.md)
- [SwiftData schema](Docs/Schema.md)
- [Permissions](Docs/Permissions.md)
- [HealthKit](Docs/HealthKit.md)
- [EventKit](Docs/EventKit.md)
- [MusicKit](Docs/MusicKit.md)
- [Technique media](Docs/TechniqueMedia.md)
- [Product decisions](Docs/ProductDecisions.md)

## Tests

```bash
xcodebuild -scheme Fittr -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' test
```

A bare `name=iPhone 16 Pro` does not resolve when several runtimes are installed — pin `OS=`, or use a simulator UDID from `xcrun simctl list devices available`:

```bash
xcodebuild -scheme Fittr -destination 'id=<UDID>' test
```

Unit tests cover volume, timestamps, progression, snapshots, adherence, moving average, export, and in-progress recovery. UI tests walk the core strength flow with `--uitesting`.
