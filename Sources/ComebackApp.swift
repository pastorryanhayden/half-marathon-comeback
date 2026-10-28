import SwiftUI
import UIKit

@main struct ComebackApp: App {
    @StateObject private var store = ProgressStore()
    var body: some Scene { WindowGroup { RootView().environmentObject(store).tint(.green) } }
}
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { WeekView(week: Plan.currentWeek()) }.tabItem { Label("This week", systemImage: "figure.run") }
            NavigationStack { ScheduleView() }.tabItem { Label("Plan", systemImage: "calendar") }
            NavigationStack { StrengthView() }.tabItem { Label("Strength", systemImage: "dumbbell") }
            NavigationStack { IntervalView() }.tabItem { Label("Timer", systemImage: "timer") }
            NavigationStack { GuideView() }.tabItem { Label("Guide", systemImage: "book") }
        }
    }
}
struct WeekView: View {
    let week: Int
    @EnvironmentObject var store: ProgressStore
    func binding<T>(_ path: WritableKeyPath<WeekRecord,T>) -> Binding<T> { Binding(get: { store.record(week)[keyPath:path] }, set: { v in store.update(week) { $0[keyPath:path] = v } }) }
    var body: some View {
        Form {
            Section {
                Text("THE COMEBACK / 13.1").font(.caption).foregroundStyle(.secondary)
                Text(week == 25 ? "Your race week" : "Keep showing up.").font(.largeTitle.bold())
                Text("\(Plan.shortDate(Plan.date(week))) – \(Plan.shortDate(Plan.date(week, day: 6))) · \(Plan.phase(week))")
                Text("Illinois Half Marathon · April 24, 2027\nGoal: 2:10 · 9:55/mi average").foregroundStyle(.secondary)
            }
            if let error = store.error { Section("Storage needs attention") { Text(error).foregroundStyle(.red) } }
            Section("This week's sessions") {
                ForEach(Array(Plan.sessions(week).enumerated()), id: \.offset) { index, title in
                    Toggle(title, isOn: Binding(get: { store.record(week).done[index] }, set: { v in store.update(week) { $0.done[index] = v } }))
                    if week != 25 && (index == 0 || index == 3) { NavigationLink(index == 0 ? "See workout A" : "See workout B") { StrengthView(selected: index == 0 ? 0 : 1) } }
                }
            }
            Section(week == 25 ? "Race day" : "Saturday long run") {
                Text("\(Plan.distance(week)) miles").font(.largeTitle.bold())
                Text(week == 25 ? "April 24 · 7:33 a.m. Central wave start. Check your final race instructions." : "\(Plan.shortDate(Plan.date(week, day: 5))) · Allow \(Int(Plan.miles[week]*12))–\(Int(Plan.miles[week]*15)) minutes at an assumed 12–15 min/mi.")
                Text("Keep it conversational. Walk breaks from the start. Distance is a ceiling; repeat or shorten a week if recovery needs it.").foregroundStyle(.secondary)
            }
            Section("Your progress · saves automatically") {
                TextField("Long run completed (miles)", text: binding(\.miles)).keyboardType(.decimalPad)
                Picker("How it felt", selection: binding(\.feel)) { ForEach(["", "Comfortable", "Manageable", "Too hard", "Pain / stopped"], id: \.self) { Text($0.isEmpty ? "Choose" : $0).tag($0) } }
                TextField("Weekly notes", text: binding(\.notes), axis: .vertical).lineLimit(3...8)
                ProgressView(value: Double(store.completed), total: 130)
                Text("\(store.completed) of 130 sessions completed").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Week \(week+1)").navigationBarTitleDisplayMode(.inline)
    }
}
struct ScheduleView: View {
    var body: some View {
        List {
            Section { Text("26 weeks · October 26, 2026 to April 24, 2027. Three runs and two strength sessions each week.") }
            ForEach(0..<26, id: \.self) { week in
                NavigationLink { WeekView(week: week) } label: {
                    HStack { VStack(alignment: .leading) { Text("Week \(week+1) · \(Plan.shortDate(Plan.date(week)))").font(.headline); Text(Plan.phase(week)).foregroundStyle(.secondary) }; Spacer(); Text("\(Plan.distance(week)) mi").monospacedDigit() }
                }
            }
        }.navigationTitle("The road ahead")
    }
}
struct StrengthView: View {
    var selected: Int? = nil
    private let result = Result { try TrainingContent.load() }
    var body: some View {
        List {
            Section("Start with one easy set") {
                Text("First two weeks: one set per exercise. A rep is one complete movement; a set is a group of reps. Monday is your main session. Friday stays light before Saturday's long run.")
                Text("Warm up for 4–5 minutes: walk the court, then 5 gentle squats, 5 hip hinges, and 10 easy calf raises. Rest 45–90 seconds between sets or exercises.")
                Text("Start with bodyweight or your lightest kettlebell. Finish each set able to do about 3 more good reps. Exhale during effort. Reduce weight if balance or form slips.")
            }
            switch result {
            case .success(let content):
                ForEach(Array(content.workouts.enumerated()), id: \.offset) { i, workout in
                    if selected == nil || selected == i {
                        Section(workout.title) { ForEach(workout.exercises) { exercise in DisclosureGroup { Text(exercise.instructions).padding(.vertical, 6) } label: { Text(exercise.title) } } }
                    }
                }
                Section("Progression and recovery") { Text(content.progression) }
            case .failure: Text("Training instructions could not load. Please reinstall the app.")
            }
        }.navigationTitle("Strength workouts")
    }
}
struct GuideView: View {
    @EnvironmentObject var store: ProgressStore
    @ViewState private var export = false
    @ViewState private var importing = false
    @ViewState private var pending: Data?
    @ViewState private var message: String?
    private let result = Result { try TrainingContent.load() }
    var body: some View {
        List {
            Section("Your race") { Text("Christie Clinic Illinois Half Marathon\nChampaign-Urbana\nSaturday, April 24, 2027 · 7:33 a.m. Central"); Link("Official race information", destination: URL(string:"https://illinoismarathon.com/races/half-marathon/")!) }
            Section("Run / walk from the start") { Text("Begin with 30–60 seconds easy running and 60 seconds walking. Use full-sentence conversation as your effort guide. Include 5 minutes walking to warm up and cool down within weekday session times. Stay easy for the first eight weeks.") }
            if case .success(let content) = result { ForEach(content.guide) { item in Section(item.title) { Text(item.body) } } }
            Section("Backups") {
                Text("Progress is stored on this iPhone. This version does not sync with Spaces. Export a backup before reinstalling or changing phones. You can import the JSON exported by the Spaces app.").foregroundStyle(.secondary)
                Button("Export progress") { export = true }
                Button("Import progress") { importing = true }
            }
            Section("About") { Text("Comeback 1.0 · A personal, Galloway-inspired training plan. No account, tracking SDKs, or health permissions required."); Link("Run Walk Run reference", destination: URL(string:"https://www.jeffgalloway.com/training/run-walk/")!) }
        }.navigationTitle("Training guide")
        .fileExporter(isPresented: $export, document: Backup(store.data), contentType: .json, defaultFilename: "half-marathon-progress") { result in if case .failure(let e) = result { message = e.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let bytes = try Data(contentsOf:url); _ = try JSONDecoder().decode(ProgressData.self, from:bytes).validated(); pending = bytes } catch { message = "Import failed: \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace progress on this iPhone with this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility:.visible) {
            Button("Replace progress", role:.destructive) { if let bytes = pending { do { try store.restore(bytes) } catch { message = error.localizedDescription } }; pending = nil }
            Button("Cancel", role:.cancel) { pending = nil }
        }
        .alert("Progress", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
}
