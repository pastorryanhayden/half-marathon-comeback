import SwiftUI
import UIKit
import AudioToolbox
struct IntervalView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("runSeconds") private var runSeconds = 60
    @AppStorage("walkSeconds") private var walkSeconds = 60
    @ViewState private var running = false
    @ViewState private var walking = false
    @ViewState private var remaining = 60
    @ViewState private var deadline = Date()
    @ViewState private var backgroundNotice = false
    private let ticker = Timer.publish(every:0.2,on:.main,in:.common).autoconnect()
    var body: some View {
        Form {
            Section("Your intervals") {
                Stepper("Run: \(runSeconds) seconds",value:$runSeconds,in:10...1200,step:5).disabled(running)
                Stepper("Walk: \(walkSeconds) seconds",value:$walkSeconds,in:10...600,step:5).disabled(running)
            }
            Section {
                VStack(spacing:18) {
                    Text(walking ? "Walk & recover" : "Run easy").font(.title2)
                    Text(String(format:"%d:%02d",remaining/60,remaining%60)).font(.system(size:76,weight:.semibold,design:.rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1).accessibilityLabel("\(remaining/60) minutes \(remaining%60) seconds remaining")
                    HStack {
                        Button(running ? "Pause" : "Start") { if running { pause() } else { deadline = Date().addingTimeInterval(Double(remaining)); running = true; UIApplication.shared.isIdleTimerDisabled = true } }.buttonStyle(.borderedProminent)
                        Button("Reset") { reset() }.buttonStyle(.bordered)
                    }
                }.frame(maxWidth:.infinity).padding(.vertical,20)
            }
            Section("Keep the timer visible") {
                Text("The screen stays awake while running. Interval changes use a sound and haptic; volume and device settings affect alerts. This version pauses if you lock your phone or leave the app.")
                if backgroundNotice { Text("Timer paused when the app left the foreground. Tap Start when ready.").foregroundStyle(.orange) }
            }
        }.navigationTitle("Run / walk timer")
        .onReceive(ticker) { now in
            guard running else { return }
            if now >= deadline { walking.toggle(); remaining = walking ? walkSeconds : runSeconds; deadline = now.addingTimeInterval(Double(remaining)); UINotificationFeedbackGenerator().notificationOccurred(.success); AudioServicesPlaySystemSound(1057) }
            else { remaining = max(1,Int(ceil(deadline.timeIntervalSince(now)))) }
        }
        .onChange(of:runSeconds) { _,value in if !running && !walking { remaining = value } }
        .onChange(of:walkSeconds) { _,value in if !running && walking { remaining = value } }
        .onChange(of:scenePhase) { _,phase in if phase != .active && running { pause(); backgroundNotice = true } }
        .onAppear { if !running { remaining = walking ? walkSeconds : runSeconds } }
        .onDisappear { if running { pause() }; UIApplication.shared.isIdleTimerDisabled = false }
    }
    private func pause() { remaining = max(1,Int(ceil(deadline.timeIntervalSinceNow))); running = false; UIApplication.shared.isIdleTimerDisabled = false }
    private func reset() { running = false; walking = false; remaining = runSeconds; backgroundNotice = false; UIApplication.shared.isIdleTimerDisabled = false }
}
