# Comeback for iPhone

Native SwiftUI iPhone app for the Christie Clinic Illinois Half Marathon on April 24, 2027. Requires iOS 17 or later.

## Included

- 26-week schedule beginning October 26, 2026, with race week April 19–25, 2027.
- Weekly checklists, mileage, effort and notes with automatic local saving.
- Kettlebell and bodyweight workouts A and B, technique instructions and progression. Nine bundled start/finish illustrations cover all 11 exercise entries; tap to enlarge and pinch to zoom. No internet is needed for the exercise guides.
- Run/walk timer with distinct rising (run) and falling (walk) tones, optional five-second countdown beeps, and background audio playback. Other audio ducks during cues. Calls or disconnected headphones pause the session; force-quitting ends it. Use the tone-test button with your music or podcast before a run.
- JSON progress export/import compatible with the Spaces app's progress backup.
- Custom cream, forest-green, and orange design with dark appearance, workout cards, and custom navigation. No analytics, account service, or third-party dependencies.

Progress stays on the iPhone. It does not automatically synchronize with Spaces or other devices. Export a backup before uninstalling. Timer preferences use app-local UserDefaults, declared in the privacy manifest.

## Get the project on another Mac

```sh
git clone https://github.com/pastorryanhayden/half-marathon-comeback.git
cd half-marathon-comeback
open HalfMarathonComeback.xcodeproj
```

## Open and build

Open `HalfMarathonComeback.xcodeproj` in Xcode. The generated project is included; XcodeGen is only needed after changing `project.yml`.

The bundle identifier is `com.ryanhayden.halfmarathoncomeback`. Automatic signing is configured for Ryan Hayden's personal Apple Developer team (`R53X844C48`).

## Validation completed

- Debug and Release builds for generic iOS device succeeded without signing.
- Native model executable checks passed for race dates, week boundaries, disk persistence, Spaces import and malformed backup rejection.
- Release bundle contains the training JSON, app icon and privacy manifest.
- XCTest coverage checks schedule dates, malformed backups, saving/reopening/restoring progress, interval boundaries over multiple cycles, tone placement, optional countdown beeps, and every bundled exercise illustration. Simulator visual checks cover the custom dashboard, exercise cards, dark appearance, and larger text. Background tones were exercised while the simulator was locked. Mixing behavior with your preferred music/podcast app and headphones still needs a physical-iPhone check.
- Signed Release build 1.0 (2) was archived with Xcode 27.1 and uploaded successfully to App Store Connect on October 28, 2026. Its archive is saved locally at `~/Library/Developer/Xcode/Archives/2026-10-28/Comeback-1.0-2.xcarchive`.
- Redesigned build 1.1 (5), with nine offline exercise illustrations and background interval tones, was archived and uploaded successfully on October 28, 2026. Its archive is `~/Library/Developer/Xcode/Archives/2026-10-28/Comeback-1.1-5.xcarchive`. All seven automated tests passed; image enlargement and dark appearance were also checked in the simulator.
- The app target explicitly supports iPhone and declares portrait and landscape orientations. These settings are included in both the generated project and `project.yml`.

## TestFlight

App Store Connect record: [Half Marathon Comeback](https://appstoreconnect.apple.com/apps/6828147901/distribution), SKU `comeback-ios-2027`, English (U.S.).

Build 1.1 (5) was uploaded for **internal testing only**. The internal group **Ryan** includes Ryan's App Store Connect account and has automatic distribution enabled. After Apple finishes processing, open TestFlight and update the installed app. Updating preserves local progress; do not uninstall.

Check layout, checklist persistence, backup import/export, strength instructions, and timer sound/haptics on the iPhone. See `TestFlight-Notes.txt` for the current testing checklist. The redesigned update is version 1.1 (5).

For future builds, increase `CURRENT_PROJECT_VERSION` in both `project.yml` and the Xcode project, archive for a generic iOS device, then use Organizer > Distribute App > TestFlight Internal Only. Use standard App Store Connect distribution if external testing is needed; internal-only builds cannot be shared with external groups.

Never put Apple passwords, verification codes, private signing keys or App Store Connect API keys in this project.

## References

- Race: https://illinoismarathon.com/races/half-marathon/
- TestFlight: https://developer.apple.com/testflight/
- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds

## Exercise artwork

Nine original illustrations were generated with the built-in image generation tool and reviewed against the written exercise cues. Assets are bundled in `Sources/Resources/Assets.xcassets/exercise-*.imageset`. The full prompt set and generation provenance are saved in `Design/exercise-image-prompts.json`. The written instructions remain the detailed form reference.

## GPS runs, Siri, and Focus

The Timer now records GPS distance, average active pace, route segments, active time, and interpolated mile splits across both running and walking intervals. Pauses exclude time and movement. GPS fixes older than 15 seconds or worse than 30 m accuracy are rejected; long gaps and implausible jumps start a separate route segment instead of adding distance. A lost signal cannot reconstruct the missing route. GPS accuracy should be checked outdoors on an actual iPhone.

Start from a running workout’s play button to associate the recording with that workout, or start from Timer/Siri to select the next incomplete running workout from the current week onward. Finish & save stores the run and marks that workout complete. Reset only resets the interval clock and pauses the recording. Mile announcements can be switched off independently of the interval tones.

Run records and routes stay in `Documents/runs.json`, protected until the first device unlock after reboot. An active recording checkpoints every ten seconds and on pause/finish. Reopening recovers it paused; resume starts a fresh interval cycle. Saved runs are visible under Timer, with a map and split list. They are separate from the existing plan backup/export. Do not uninstall to update. Deleting a saved run deletes its local route.

Siri/App Shortcuts: start next run with timer, pause, resume, finish/save, status, next interval, mute miles, and enable miles. Shortcuts also exposes interval durations/countdown and an announcement toggle. Start opens the app for GPS authorization; other audio actions use `AudioPlaybackIntent`. iOS may require unlocking for some actions. Headset/media controls support play, pause, toggle, stop/save, and next interval when Comeback owns the Now Playing session. Music apps can take ownership of media controls; app-specific Siri phrases remain available. Audio interruptions pause tracking; iOS’s `shouldResume` flag permits automatic resumption unless an explicit pause/finish/reset cancelled it.

iOS does not let Comeback directly switch Focus or read Screen Time downtime contacts. Timer includes a Focus setup guide and an opt-in start button that runs a user-created **Comeback Focus** shortcut. That shortcut should set the chosen Focus on, then invoke **Start next run with timer**. Pair **Finish and save run** with **Set Focus Off** in a second shortcut. For calls without texts, leave allowed People empty and allow calls from Favorites, adding the desired contacts there manually. Review repeated calls, Emergency Bypass, Time Sensitive Notifications, Focus Status, and Intelligent Breakthrough. No Focus profile or phone settings are silently created by the app.

Physical-device acceptance checks for TestFlight:
- Grant precise location, lock the screen, walk/run at least a mile, and compare distance/route against a known route. Confirm one spoken split and continued interval tones/music.
- Pause, travel some distance, resume, and verify no paused movement/time or straight line across that gap.
- Test every Siri phrase with the phone locked and music playing, including explicit pause after an interruption. Confirm status queries resume when iOS permits.
- Test headphones disconnecting and a real incoming call. Verify resumption behavior and no lost saved route.
- Create the Focus shortcuts and verify chosen callers ring while other calls and texts stay silenced. Verify Focus turns off with the finish shortcut.

## Release 1.2 (6)

GPS routes, distance/pace, spoken mile splits, Siri/App Shortcuts, and running Focus setup. All 10 simulator tests passed. Prepared for internal TestFlight distribution; physical-device checks above remain to be completed.
