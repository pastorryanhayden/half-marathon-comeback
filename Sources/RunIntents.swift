import AppIntents
import SwiftUI

struct StartComebackRun: AppIntent {
    static var title: LocalizedStringResource = "Start next run with timer"
    static var description = IntentDescription("Start or resume GPS recording and your saved run/walk timer. The next incomplete running workout is selected from your plan.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let coach = IntervalCoach.shared
        coach.startSaved()
        return .result(dialog: "\(coach.running ? "Your run and interval timer are started." : coach.error ?? "Unable to start your run.")")
    }
}
struct PauseComebackRun: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Pause run"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        IntervalCoach.shared.pause()
        return .result(dialog: "Your run is paused.")
    }
}
struct ResumeComebackRun: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Resume run"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let coach = IntervalCoach.shared
        guard coach.tracker.current != nil else { return .result(dialog: "No run to resume. Ask Siri to start your next run in Comeback.") }
        coach.startSaved()
        return .result(dialog: "\(coach.running ? "Your run is resumed." : coach.error ?? "Unable to resume.")")
    }
}
struct FinishComebackRun: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Finish and save run"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let coach = IntervalCoach.shared
        guard coach.tracker.current != nil else { return .result(dialog: "No active run to finish.") }
        coach.finish()
        return .result(dialog: "\(coach.tracker.savingError ?? "Your run and route are saved.")")
    }
}
struct ComebackRunStatus: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Get run status"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(IntervalCoach.shared.status)")
    }
}
struct SkipComebackInterval: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Skip to next interval"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let coach = IntervalCoach.shared
        guard coach.hasSession else { return .result(dialog: "Start a run first.") }
        coach.skipInterval()
        return .result(dialog: "\(coach.walking ? "Walk and recover." : "Run easy.")")
    }
}
struct MuteComebackMiles: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Mute mile announcements"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(false, forKey: "announceMiles")
        return .result(dialog: "Mile announcements are off. Interval tones remain on.")
    }
}
struct UnmuteComebackMiles: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Enable mile announcements"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(true, forKey: "announceMiles")
        return .result(dialog: "Mile announcements are on.")
    }
}
struct SetComebackMileAnnouncements: AppIntent {
    static var title: LocalizedStringResource = "Set mile announcements"
    @Parameter(title: "Announce mile splits") var enabled: Bool
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(enabled, forKey: "announceMiles")
        return .result()
    }
}
struct ConfigureComebackIntervals: AppIntent {
    static var title: LocalizedStringResource = "Set run and walk intervals"
    @Parameter(title: "Run seconds", default: 60, inclusiveRange: (10, 1200)) var run: Int
    @Parameter(title: "Walk seconds", default: 60, inclusiveRange: (10, 600)) var walk: Int
    @Parameter(title: "Countdown beeps", default: false) var countdown: Bool
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !IntervalCoach.shared.hasSession else { return .result(dialog: "Reset the interval timer or finish your current run before changing intervals.") }
        guard (10...1200).contains(run), (10...600).contains(walk) else { return .result(dialog: "Choose 10 to 1200 run seconds and 10 to 600 walk seconds.") }
        let defaults = UserDefaults.standard
        defaults.set(run, forKey: "runSeconds"); defaults.set(walk, forKey: "walkSeconds"); defaults.set(countdown, forKey: "countdownTones")
        return .result(dialog: "Your intervals are saved.")
    }
}
struct ComebackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartComebackRun(), phrases: ["Start my next run on \(.applicationName) with a timer", "Start my run in \(.applicationName)"], shortTitle: "Start next run", systemImageName: "figure.run")
        AppShortcut(intent: PauseComebackRun(), phrases: ["Pause \(.applicationName)", "Pause my run in \(.applicationName)"], shortTitle: "Pause run", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeComebackRun(), phrases: ["Resume \(.applicationName)", "Resume my run in \(.applicationName)"], shortTitle: "Resume run", systemImageName: "play.fill")
        AppShortcut(intent: FinishComebackRun(), phrases: ["Finish my run in \(.applicationName)", "Save my run in \(.applicationName)"], shortTitle: "Finish run", systemImageName: "flag.fill")
        AppShortcut(intent: ComebackRunStatus(), phrases: ["My run status in \(.applicationName)", "How far have I run in \(.applicationName)"], shortTitle: "Run status", systemImageName: "speedometer")
        AppShortcut(intent: MuteComebackMiles(), phrases: ["Mute mile announcements in \(.applicationName)"], shortTitle: "Mute miles", systemImageName: "speaker.slash")
        AppShortcut(intent: UnmuteComebackMiles(), phrases: ["Enable mile announcements in \(.applicationName)"], shortTitle: "Announce miles", systemImageName: "speaker.wave.2")
        AppShortcut(intent: SkipComebackInterval(), phrases: ["Next interval in \(.applicationName)"], shortTitle: "Next interval", systemImageName: "forward.end.fill")
    }
}

struct RunningFocusHelp: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TrainingPage {
            PageHeader(category: "A quieter run", title: "Running Focus", subtitle: "One setup on your iPhone, then start by voice.")
            Text("iOS controls notification silencing. Comeback cannot switch Focus directly or read your Screen Time downtime contacts. Choose those same people in your running Focus.")
            Text("1. In Settings → Focus, create a custom Focus named Comeback. For calls without texts, leave People → Allow Notifications From empty and set Calls From to Favorites. Add your chosen downtime contacts to Favorites in Phone. Turn off repeated calls and review Emergency Bypass for contacts.")
            Text("2. Under Apps, allow Comeback and your music app. Disable Time Sensitive Notifications and Intelligent Breakthrough if shown. Turn off Share Focus Status to avoid Notify Anyway messages. Timer tones and music playback continue during Focus.")
            Text("3. In Shortcuts, create a shortcut named Comeback Focus. Add Set Focus → Comeback → On until turned off, then Comeback → Start next run with timer. Enable ‘Start new runs with my Focus shortcut’ in Comeback once you have created it.")
            Text("4. Say ‘Hey Siri, Comeback Focus’. At the end, turn the Focus off in Control Center, or make a second shortcut with Finish and save run followed by Set Focus → Off. Focus stays on through pauses.")
            Text("You can add Comeback’s pause, resume, status, next interval, announcement settings, and interval configuration actions to your own shortcuts. Siri may require unlocking your phone to open the app or grant location permission. Try your phrases and headset controls before leaving.")
            Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
            Link("Apple’s Focus setup guide", destination: URL(string: "https://support.apple.com/guide/iphone/iphd6288a67f/ios")!)
            Text("Routes are stored locally on this phone. Deleting a saved run removes its route. Run history is separate from the plan’s JSON backup; keep the app installed to retain it.").font(.caption).foregroundStyle(ComebackStyle.muted)
            Button("Done") { dismiss() }
        }
    }
}
