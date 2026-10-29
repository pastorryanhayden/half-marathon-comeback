import SwiftUI
import UIKit
import Combine
import AVFoundation
import MediaPlayer

struct IntervalTiming {
    static func state(at elapsed: TimeInterval, run: Int, walk: Int) -> (walking: Bool, remaining: Int) {
        let position = max(0, elapsed).truncatingRemainder(dividingBy: Double(run + walk))
        let walking = position >= Double(run)
        return (walking, max(1, Int(ceil((walking ? Double(run + walk) : Double(run)) - position))))
    }
}

// Render a real coaching audio track: one tone cue at the start of each phase.
// Playback, rather than a foreground timer or a silent keepalive loop, owns the clock.
enum IntervalTrack {
    static func render(run: Int, walk: Int, countdown: Bool = false) throws -> (url: URL, runCue: Double, walkCue: Double) {
        guard (10...1200).contains(run), (10...600).contains(walk) else { throw CocoaError(.validationNumberTooSmall) }
        let rate = 22050
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("comeback-coach-\(run)-\(walk)-\(countdown).wav")
        let runAudio = try samples(named: "RunCue")
        let walkAudio = try samples(named: "WalkCue")
        let bytes = UInt32((run + walk) * rate * 2)
        var header = Data("RIFF".utf8)
        func append16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        func append32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        append32(bytes + 36); header.append(Data("WAVEfmt ".utf8)); append32(16)
        append16(1); append16(1); append32(UInt32(rate)); append32(UInt32(rate * 2)); append16(2); append16(16)
        header.append(Data("data".utf8)); append32(bytes)
        try header.write(to: url, options: .atomic)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        // Sparse PCM silence between interval tones avoids a large allocation.
        try file.truncate(atOffset: UInt64(44) + UInt64(bytes))
        try file.seek(toOffset: 44)
        try file.write(contentsOf: runAudio)
        try file.seek(toOffset: UInt64(44 + run * rate * 2))
        try file.write(contentsOf: walkAudio)
        if countdown {
            let tick = try samples(named: "TickCue")
            for transition in [run, run + walk] {
                for secondsBefore in 1...5 {
                    try file.seek(toOffset: UInt64(44 + (transition - secondsBefore) * rate * 2))
                    try file.write(contentsOf: tick)
                }
            }
        }
        return (url, Double(runAudio.count) / Double(rate * 2), Double(walkAudio.count) / Double(rate * 2))
    }
    private static func samples(named name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { throw CocoaError(.fileNoSuchFile) }
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 22050, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw CocoaError(.fileReadCorruptFile) }
        try file.read(into: buffer)
        guard let samples = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        var pcm = Data(capacity: Int(buffer.frameLength) * 2)
        for index in 0..<Int(buffer.frameLength) {
            var sample = Int16(max(-1, min(1, samples[index])) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        return pcm
    }
}

@MainActor final class IntervalCoach: NSObject, ObservableObject, AVAudioPlayerDelegate, @preconcurrency AVSpeechSynthesizerDelegate {
    static let shared = IntervalCoach()
    let tracker = RunTracker()
    private let speech = AVSpeechSynthesizer()
    private var plannedWorkout: (title: String, week: Int?, session: Int?)?
    private var trackerChanges: AnyCancellable?
    @Published var showWorkout = false
    @Published private(set) var running = false
    @Published private(set) var walking = false
    @Published private(set) var remaining = 60
    @Published private(set) var hasSession = false
    @Published private(set) var error: String?
    private var player: AVAudioPlayer?
    private var preview: AVAudioPlayer?
    private var run = 60
    private var walk = 60
    private var runCue = 1.0
    private var walkCue = 1.2
    private var resumeAfterInterruption = false
    private var countdown = false
    private var ducking = false
    private var ticker: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    override init() {
        super.init()
        speech.delegate = self
        trackerChanges = tracker.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        tracker.onSplit = { [weak self] split in
            guard UserDefaults.standard.object(forKey: "announceMiles") as? Bool ?? true else { return }
            self?.say("Mile \(split.mile). Split pace, \(RunRecord.pace(seconds: split.seconds)) per mile.")
        }
        ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if raw == AVAudioSession.InterruptionType.began.rawValue {
                    let wasRunning = self.running
                    self.pause()
                    self.resumeAfterInterruption = wasRunning
                    self.error = "Audio interrupted. Resume when ready if playback does not return."
                } else {
                    let resume = self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.resumeAfterInterruption = false
                    if resume { self.startSaved() }
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.pause(); self?.error = "Headphones disconnected. Check your audio, then tap Start." }
        })
        let center = MPRemoteCommandCenter.shared()
        remoteTargets.append((center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in guard let self else { return }; if self.running { self.pause() } else { self.startSaved() } }; return .success
        }))
        remoteTargets.append((center.stopCommand, center.stopCommand.addTarget { [weak self] _ in Task { @MainActor in self?.finish() }; return .success }))
        remoteTargets.append((center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skipInterval() }; return .success }))
        remoteTargets.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }))
        remoteTargets.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in Task { @MainActor in guard let self, self.hasSession else { return }; self.start(run: self.run, walk: self.walk, countdown: self.countdown) }; return .success }))
    }
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
    }
    func start(run: Int, walk: Int, countdown: Bool = false) {
        error = nil
        do {
            preview?.stop(); preview = nil
            if player == nil {
                let track = try IntervalTrack.render(run: run, walk: walk, countdown: countdown)
                self.countdown = countdown
                self.run = run; self.walk = walk; runCue = track.runCue; walkCue = track.walkCue
                player = try AVAudioPlayer(contentsOf: track.url)
                player?.numberOfLoops = -1
                player?.delegate = self
                player?.prepareToPlay()
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            ducking = false
            try updateDucking(at: player?.currentTime ?? 0)
            guard player?.play() == true else { throw CocoaError(.fileReadUnknown) }
            let next = plannedWorkout ?? nextWorkout()
            guard tracker.start(title: next.title, week: next.week, session: next.session) else {
                throw CocoaError(.fileWriteUnknown)
            }
            hasSession = true; running = true
            updateState(); updateNowPlaying()
        } catch {
            self.error = "Could not start audio: \(error.localizedDescription)"
            player?.stop(); player = nil; running = false; hasSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    func pause() {
        resumeAfterInterruption = false
        guard hasSession else { return }
        tracker.pause(); speech.stopSpeaking(at: .immediate)
        player?.pause(); running = false; updateState(); updateNowPlaying()
        ducking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func startWorkout(week: Int, session: Int) {
        guard tracker.current == nil else { showWorkout = true; return }
        plannedWorkout = ("Week \(week + 1) · \(Plan.sessions(week)[session])", week, session)
        showWorkout = true
        if UserDefaults.standard.bool(forKey: "useRunFocusShortcut"),
           let url = URL(string: "shortcuts://run-shortcut?name=Comeback%20Focus") {
            UIApplication.shared.open(url)
        } else { startSaved() }
    }
    func startSaved() {
        let defaults = UserDefaults.standard
        start(run: defaults.object(forKey: "runSeconds") as? Int ?? 60,
              walk: defaults.object(forKey: "walkSeconds") as? Int ?? 60,
              countdown: defaults.bool(forKey: "countdownTones"))
        showWorkout = true
    }
    private func nextWorkout() -> (title: String, week: Int?, session: Int?) {
        let store = ProgressStore.shared
        for week in Plan.currentWeek()..<26 {
            for index in [1, 2, 4] where !store.record(week).done[index] {
                return ("Week \(week + 1) · \(Plan.sessions(week)[index])", week, index)
            }
        }
        return ("Run / walk", nil, nil)
    }
    func finish() {
        pause()
        if let run = tracker.finish(), let week = run.week, let index = run.session, run.elapsed > 0 {
            ProgressStore.shared.update(week) { $0.done[index] = true; if index == 4 { $0.miles = String(format: "%.2f", run.miles) } }
        }
        reset(); plannedWorkout = nil
    }
    func skipInterval() {
        guard hasSession, let player else { return }
        player.currentTime = walking ? 0 : Double(run)
        updateState(); updateNowPlaying()
    }
    var status: String {
        tracker.tick()
        guard let run = tracker.current else { return "No active run. Start your next run when you are ready." }
        return "\(running ? "Running" : "Paused"). \(String(format: "%.2f", run.miles)) miles. Average pace \(run.pace) per mile. \(remaining) seconds left in your \(walking ? "walk" : "run") interval."
    }
    func say(_ text: String) {
        guard running else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .duckOthers)
        ducking = true
        speech.speak(AVSpeechUtterance(string: text))
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if running { try? updateDucking(at: player?.currentTime ?? 0) }
    }
    func reset() {
        // Reset only restarts the interval clock; the recorded workout is preserved.
        resumeAfterInterruption = false
        tracker.pause(); speech.stopSpeaking(at: .immediate)
        player?.stop(); preview?.stop(); player = nil; preview = nil
        running = false; hasSession = false; walking = false; remaining = run; error = nil; ducking = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func testCue() {
        guard !running else { return }
        do {
            guard let url = Bundle.main.url(forResource: "TestCues", withExtension: "wav") else { throw CocoaError(.fileNoSuchFile) }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .duckOthers)
            try session.setActive(true)
            preview = try AVAudioPlayer(contentsOf: url)
            preview?.delegate = self
            guard preview?.play() == true else { throw CocoaError(.fileReadUnknown) }
            error = nil
        } catch {
            self.error = "Could not play tone test: \(error.localizedDescription)"
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    private func tick() {
        guard running, let player else { return }
        guard player.isPlaying else { pause(); error = "Audio stopped. Tap Start to resume."; return }
        tracker.tick()
        let previous = walking
        updateState()
        do { try updateDucking(at: player.currentTime) }
        catch { self.error = "Audio mixing changed. Check your media volume." }
        if previous != walking { UINotificationFeedbackGenerator().notificationOccurred(.success); updateNowPlaying() }
    }
    private func updateState() {
        let state = IntervalTiming.state(at: player?.currentTime ?? 0, run: run, walk: walk)
        walking = state.walking; remaining = state.remaining
    }
    private func updateDucking(at position: Double) throws {
        let timeToChange = position < Double(run) ? Double(run) - position : Double(run + walk) - position
        let shouldDuck = speech.isSpeaking || position < runCue + 0.15 || (position >= Double(run) && position < Double(run) + walkCue + 0.15) || (countdown && timeToChange <= 5)
        guard shouldDuck != ducking else { return }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: shouldDuck ? .duckOthers : .mixWithOthers)
        ducking = shouldDuck
    }
    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: walking ? "Walk & recover" : "Run easy",
            MPMediaItemPropertyArtist: "The Comeback · Run / Walk",
            MPMediaItemPropertyPlaybackDuration: Double(run + walk),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: running ? 1.0 : 0.0
        ]
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === preview {
            preview = nil
            if !running { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        pause(); self.error = "The interval audio stopped. Reset the timer and try again."
    }
}

struct IntervalView: View {
    @EnvironmentObject private var coach: IntervalCoach
    @ViewState private var showFocus = false
    @ViewState private var confirmFinish = false
    @AppStorage("announceMiles") private var announceMiles = true
    @AppStorage("useRunFocusShortcut") private var useFocusShortcut = false
    @AppStorage("runSeconds") private var runSeconds = 60
    @AppStorage("walkSeconds") private var walkSeconds = 60
    @AppStorage("countdownTones") private var countdownTones = false
    private var running: Bool { coach.running }
    private var walking: Bool { coach.walking }
    private var remaining: Int { coach.hasSession ? coach.remaining : runSeconds }
    private var duration: Int { walking ? walkSeconds : runSeconds }
    var body: some View {
        TrainingPage {
            PageHeader(category: "Find your rhythm", title: "Easy does it.", subtitle: "One interval at a time.")
            VStack(spacing: 24) {
                Text(walking ? "WALK & RECOVER" : "RUN EASY").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(.white.opacity(0.7))
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 3)
                    Circle().trim(from: 0, to: min(1, CGFloat(remaining) / CGFloat(duration))).stroke(Color(red: 0.98, green: 0.65, blue: 0.4), style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 12) {
                        Image(systemName: walking ? "figure.walk" : "figure.run").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.7))
                        Text(String(format: "%d:%02d", remaining / 60, remaining % 60)).font(.system(size: 68, weight: .medium, design: .rounded)).monospacedDigit().tracking(-3).minimumScaleFactor(0.5).lineLimit(1)
                            .accessibilityLabel("\(remaining / 60) minutes \(remaining % 60) seconds remaining")
                        Text(running ? "KEEP IT CONVERSATIONAL" : "READY WHEN YOU ARE").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.2).foregroundStyle(.white.opacity(0.6))
                    }.padding(20)
                }.frame(maxWidth: 260).aspectRatio(1, contentMode: .fit)
                HStack(spacing: 12) {
                    Button { if running { coach.pause() } else { if useFocusShortcut && coach.tracker.current == nil {
                            if let url = URL(string: "shortcuts://run-shortcut?name=Comeback%20Focus") { UIApplication.shared.open(url) }
                        } else { coach.start(run: runSeconds, walk: walkSeconds, countdown: countdownTones) } } } label: {
                        Label(running ? "Pause" : "Start session", systemImage: running ? "pause.fill" : "play.fill").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }.foregroundStyle(ComebackStyle.forest).background(Color(red: 0.98, green: 0.65, blue: 0.4), in: RoundedRectangle(cornerRadius: 14))
                    Button { coach.reset() } label: { Image(systemName: "arrow.counterclockwise").font(.headline).frame(width: 52, height: 52) }.background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Reset timer")
                }.buttonStyle(.plain)
            }.padding(24).frame(maxWidth: .infinity).foregroundStyle(.white).background(ComebackStyle.forest, in: RoundedRectangle(cornerRadius: 24))
            if let run = coach.tracker.current {
                RunDetails(run: run).trainingCard()
                Button("Finish & save run") { confirmFinish = true }.buttonStyle(.borderedProminent)
            }
            if let message = coach.tracker.message { Text(message).font(.subheadline).foregroundStyle(ComebackStyle.muted) }
            if let message = coach.tracker.savingError { Text(message).foregroundStyle(ComebackStyle.orange) }
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Your rhythm")
                Stepper(value: $runSeconds, in: 10...1200, step: 5) { intervalLabel("Run", icon: "figure.run", seconds: runSeconds) }.disabled(coach.hasSession)
                Rectangle().fill(ComebackStyle.line).frame(height: 1)
                Stepper(value: $walkSeconds, in: 10...600, step: 5) { intervalLabel("Walk", icon: "figure.walk", seconds: walkSeconds) }.disabled(coach.hasSession)
                Rectangle().fill(ComebackStyle.line).frame(height: 1)
                Toggle("Announce mile splits", isOn: $announceMiles).font(.subheadline)
                Toggle("5-second countdown beeps", isOn: $countdownTones).font(.subheadline).disabled(coach.hasSession)
            }.trainingCard()
            VStack(alignment: .leading, spacing: 14) {
                Label("Take your music. Leave the screen off.", systemImage: "headphones").font(.subheadline.weight(.semibold))
                Text("Two rising tones mean run. Two falling tones mean walk. Cues continue with your phone locked or another app open. Other audio lowers during the cues. No spoken countdown.").font(.subheadline).foregroundStyle(ComebackStyle.muted)
                Button { coach.testCue() } label: { Label("Test run & walk tones", systemImage: "speaker.wave.2.fill") }.font(.subheadline.weight(.semibold)).disabled(running)
                Text("Start your music or podcast, then test the tones before heading out. Your media volume controls the cues. Calls and Siri temporarily pause the session; it resumes if iOS allows. Explicit pause commands keep it paused. Disconnected headphones require you to resume. Reset restarts the interval clock and preserves your run. Finish & save ends the workout. GPS includes both run and walk intervals; pauses are excluded.").font(.caption).foregroundStyle(ComebackStyle.muted)
                if let error = coach.error { Text(error).font(.subheadline).foregroundStyle(ComebackStyle.orange) }
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Hands free")
                Text("Try ‘Hey Siri, pause Comeback’, ‘resume Comeback’, ‘start my next run on Comeback with a timer’, ‘my run status in Comeback’, ‘next interval in Comeback’, or ‘finish my run in Comeback’. Find all actions in Shortcuts, including custom intervals and mile announcement settings.").font(.subheadline)
                Toggle("Start new runs with my Focus shortcut", isOn: $useFocusShortcut)
                Button("Set up running Focus & voice controls") { showFocus = true }
            }.trainingCard()
            if !coach.tracker.archive.runs.isEmpty {
                SectionHeading(title: "Your runs")
                ForEach(coach.tracker.archive.runs) { run in
                    NavigationLink { TrainingPage { RunDetails(run: run); Button("Delete saved run", role: .destructive) { coach.tracker.delete(run.id) } } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(run.started.formatted(date: .abbreviated, time: .shortened))
                            Text("\(run.miles.formatted(.number.precision(.fractionLength(2)))) mi · \(run.pace) / mi").font(.headline)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.trainingCard()
                }
            }
        }
        .sheet(isPresented: $showFocus) { NavigationStack { RunningFocusHelp() } }
        .confirmationDialog("Finish this run and save your route?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish & save run") { coach.finish() }
        }
    }
    private func intervalLabel(_ title: String, icon: String, seconds: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(ComebackStyle.orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(seconds) seconds").font(.system(.caption, design: .monospaced)).foregroundStyle(ComebackStyle.muted)
            }
        }
    }
}
