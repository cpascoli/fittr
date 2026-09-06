# Permissions and capabilities

Open `Fittr.xcodeproj`, select the **Fittr** target → **Signing & Capabilities**.

## Required to install on a physical iPhone

1. Sign in to Xcode with your Apple ID (**Xcode → Settings → Accounts**).
2. Select your **Team** on the Fittr target. Automatic signing is already enabled.
3. Bundle ID is `dev.carlo.Fittr`. Change it if that ID is taken on your team.
4. Connect the iPhone 16 Pro with USB-C, trust the computer, choose the device as the run destination, press Run.
5. On the phone: **Settings → General → VPN & Device Management** → trust your developer certificate.

## Capabilities

| Capability | Entitlement | Apple Developer portal |
| --- | --- | --- |
| HealthKit | `com.apple.developer.healthkit` in `Fittr.entitlements` | Enable HealthKit for the App ID |
| MusicKit | none in the entitlements file; MusicKit App Service | Enable MusicKit under App Services if catalog search fails |
| Calendar | none | EventKit usage strings only |
| Notifications | none | Requested only when reminders are enabled |

A **paid** Apple Developer Program membership is typically required for HealthKit on device.

If signing fails on a free Personal Team:

1. Target → Build Settings → `CODE_SIGN_ENTITLEMENTS`
2. Switch from `Fittr/Fittr.entitlements` to `Fittr/Fittr-PersonalTeam.entitlements`
3. The logger still works. Health write/read will report unavailable.

## Info.plist usage strings

All strings explain that access is optional and that data stays on device. See `Fittr/Info.plist`.
