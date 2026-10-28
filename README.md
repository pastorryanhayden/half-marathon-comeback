# Comeback for iPhone

Native SwiftUI iPhone app for the Christie Clinic Illinois Half Marathon on April 24, 2027. Requires iOS 17 or later.

## Included

- 26-week schedule beginning October 26, 2026, with race week April 19–25, 2027.
- Weekly checklists, mileage, effort and notes with automatic local saving.
- Kettlebell and bodyweight workouts A and B, technique instructions and progression.
- Run/walk timer with foreground sound and haptic cues. It pauses when the app loses foreground access or the timer screen closes.
- JSON progress export/import compatible with the Spaces app's progress backup.
- Native system colors and Dynamic Type. No web view, analytics, account service or third-party dependencies.

Progress stays on the iPhone. It does not automatically synchronize with Spaces or other devices. Export a backup before uninstalling. Timer preferences use app-local UserDefaults, declared in the privacy manifest.

## Get the project on another Mac

```sh
git clone https://github.com/pastorryanhayden/half-marathon-comeback.git
cd half-marathon-comeback
open HalfMarathonComeback.xcodeproj
```

## Open and build

Open `HalfMarathonComeback.xcodeproj` in Xcode. The generated project is included; XcodeGen is only needed after changing `project.yml`.

The current bundle identifier is `com.ryanhayden.halfmarathoncomeback`. Verify its availability with the selected Apple Developer team before registration. In Signing & Capabilities, select that team. The app supports automatic signing.

## Validation completed

- Debug and Release builds for generic iOS device succeeded without signing.
- Native model executable checks passed for race dates, week boundaries, disk persistence, Spaces import and malformed backup rejection.
- Release bundle contains the training JSON, app icon and privacy manifest.
- XCTest coverage is included for schedule and storage behavior. Simulator XCTest execution and visual UI checks have not been completed: this execution environment cannot connect to CoreSimulatorService.

## TestFlight setup remaining

1. Finish Xcode's first-launch setup. If the External Agent Access dialog appears, choose your preferred access policy; this app does not require external-agent access to Xcode.
2. Sign in through Xcode Settings > Accounts with an active Apple Developer Program membership. Select the correct team on the app target.
3. Run on a simulator or a connected iPhone and check layout, checklist persistence, backup import/export, strength instructions, and timer pause/resume.
4. Create the matching iOS app record in App Store Connect. Suggested name: Half Marathon Comeback; SKU: comeback-ios-2027; language: English (U.S.). The name and identifier may need adjustment if unavailable.
5. Product > Archive for a generic iOS device, then Organizer > Distribute App > App Store Connect > Upload. The included unsigned archive cannot be installed or uploaded as a signed TestFlight build.
6. After Apple processes the upload, add the build to an internal testing group containing your account and install it through TestFlight on the iPhone. External testing can require Apple's beta review.

Never put Apple passwords, verification codes, private signing keys or App Store Connect API keys in this project.

## References

- Race: https://illinoismarathon.com/races/half-marathon/
- TestFlight: https://developer.apple.com/testflight/
- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
