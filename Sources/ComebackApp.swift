import SwiftUI
import UIKit

// Shared visual language. Colors adapt without losing the warm paper / ink palette.
enum ComebackStyle {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let paper = adaptive(0xF5F1E8, 0x171916)
    static let card = adaptive(0xFFFCF5, 0x22251F)
    static let ink = adaptive(0x232A23, 0xF5F1E8)
    static let muted = adaptive(0x72766B, 0xB1B5A8)
    static let line = adaptive(0xDDDCCF, 0x3B4035)
    static let orange = adaptive(0xB94726, 0xFF9670)
    static let forest = Color(red: 0.15, green: 0.21, blue: 0.17)
}

struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(ComebackStyle.muted) }
}
struct PageHeader: View {
    let category: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: category)
            Text(title).font(.system(size: 38, weight: .bold, design: .serif)).tracking(-1.5).fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(ComebackStyle.muted).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct TrainingPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) { content }
                .frame(maxWidth: 620).padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 30)
                .frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(ComebackStyle.paper).foregroundStyle(ComebackStyle.ink)
            .toolbar(.hidden, for: .navigationBar)
    }
}
extension View {
    func trainingCard() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(ComebackStyle.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ComebackStyle.line.opacity(0.65), lineWidth: 1))
    }
}
struct SectionHeading: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 23, weight: .bold, design: .serif)).tracking(-0.5)
            Spacer()
            Text(detail).font(.system(.caption, design: .monospaced)).foregroundStyle(ComebackStyle.muted)
        }
    }
}
struct TrackLines: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<5) { lane in
                    RoundedRectangle(cornerRadius: 100)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 160 + CGFloat(lane) * 32, height: 230 + CGFloat(lane) * 32)
                        .rotationEffect(.degrees(30))
                        .position(x: proxy.size.width - 10, y: proxy.size.height / 2)
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}

@main struct ComebackApp: App {
    @StateObject private var store = ProgressStore.shared
    @StateObject private var coach = IntervalCoach.shared
    var body: some Scene { WindowGroup { RootView().environmentObject(store).environmentObject(coach).tint(ComebackStyle.orange) } }
}
struct RootView: View {
    @EnvironmentObject private var coach: IntervalCoach
    @ViewState private var selected = 0
    private let tabs = [("Today", "sun.max"), ("Plan", "map"), ("Strength", "dumbbell"), ("Timer", "stopwatch"), ("Guide", "book.closed")]
    var body: some View {
        ZStack {
            NavigationStack { WeekView(week: Plan.currentWeek(), overview: true) }.opacity(selected == 0 ? 1 : 0).allowsHitTesting(selected == 0).accessibilityHidden(selected != 0)
            NavigationStack { ScheduleView() }.opacity(selected == 1 ? 1 : 0).allowsHitTesting(selected == 1).accessibilityHidden(selected != 1)
            NavigationStack { StrengthView() }.opacity(selected == 2 ? 1 : 0).allowsHitTesting(selected == 2).accessibilityHidden(selected != 2)
            NavigationStack { IntervalView() }.opacity(selected == 3 ? 1 : 0).allowsHitTesting(selected == 3).accessibilityHidden(selected != 3)
            NavigationStack { GuideView() }.opacity(selected == 4 ? 1 : 0).allowsHitTesting(selected == 4).accessibilityHidden(selected != 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    Button { selected = index } label: {
                        VStack(spacing: 7) {
                            Image(systemName: tabs[index].1).font(.system(size: 20, weight: selected == index ? .bold : .regular))
                            Text(tabs[index].0).font(.system(size: 10, weight: .semibold))
                        }.frame(maxWidth: .infinity).frame(minHeight: 58)
                            .foregroundStyle(selected == index ? ComebackStyle.orange : ComebackStyle.muted)
                            .background(alignment: .top) { if selected == index { Capsule().fill(ComebackStyle.orange).frame(width: 24, height: 3) } }
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == index ? [.isSelected] : [])
                }
            }.padding(.horizontal, 12).padding(.top, 8).background(ComebackStyle.paper)
                .overlay(alignment: .top) { Rectangle().fill(ComebackStyle.line).frame(height: 1) }
        }.background(ComebackStyle.paper)
            .onAppear { if coach.showWorkout { selected = 3; coach.showWorkout = false } }
            .onChange(of: coach.showWorkout) { _, show in if show { selected = 3; coach.showWorkout = false } }
    }
}
struct WeekView: View {
    let week: Int
    var overview = false
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var coach: IntervalCoach
    @Environment(\.dismiss) private var dismiss
    private var completed: Int { store.record(week).done.filter { $0 }.count }
    func binding<T>(_ path: WritableKeyPath<WeekRecord,T>) -> Binding<T> { Binding(get: { store.record(week)[keyPath:path] }, set: { value in store.update(week) { $0[keyPath:path] = value } }) }
    var body: some View {
        TrainingPage {
            if !overview { Button { dismiss() } label: { Label("The plan", systemImage: "arrow.left") }.font(.subheadline.weight(.semibold)) }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "The comeback / 13.1")
                    Text("One run closer.").font(.system(size: 34, weight: .bold, design: .serif)).tracking(-1.4)
                }
                Spacer(minLength: 10)
                Text(String(format: "%02d", week + 1)).font(.system(size: 26, weight: .medium, design: .monospaced)).foregroundStyle(ComebackStyle.orange)
                    .padding(10).background(ComebackStyle.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Week \(week + 1)")
            }
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("WEEK \(String(format: "%02d", week + 1)) / 26").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2)
                    Spacer()
                    Text(Plan.phase(week).uppercased()).font(.system(size: 10, weight: .bold)).tracking(1).padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.12), in: Capsule())
                }.foregroundStyle(.white.opacity(0.75))
                VStack(alignment: .leading, spacing: 3) {
                    Text(week == 25 ? "The finish is yours." : "Keep\nshowing up.")
                        .font(.system(size: 44, weight: .bold, design: .serif)).tracking(-1.8).lineSpacing(-5).fixedSize(horizontal: false, vertical: true)
                    Text("\(Plan.shortDate(Plan.date(week))) – \(Plan.shortDate(Plan.date(week, day: 6)))")
                        .font(.system(.subheadline, design: .monospaced)).foregroundStyle(.white.opacity(0.65)).padding(.top, 9)
                }
                HStack(spacing: 6) {
                    ForEach(0..<5) { index in
                        Capsule().fill(store.record(week).done[index] ? Color(red: 0.97, green: 0.63, blue: 0.38) : .white.opacity(0.17)).frame(height: 4)
                    }
                }.accessibilityLabel("\(completed) of 5 sessions complete")
                Text("\(completed) OF 5 SESSIONS COMPLETE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(.white.opacity(0.7))
            }.padding(24).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                .background { ComebackStyle.forest.overlay { TrackLines() } }.clipShape(RoundedRectangle(cornerRadius: 24))
            if let error = store.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(ComebackStyle.orange).trainingCard() }
            VStack(spacing: 14) {
                SectionHeading(title: "This week", detail: "5 SESSIONS")
                ForEach(Array(Plan.sessions(week).enumerated()), id: \.offset) { index, session in
                    sessionCard(index: index, session: session)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: week == 25 ? "The starting line" : "Saturday / the long run")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Plan.distance(week)).font(.system(size: 68, weight: .medium, design: .serif)).tracking(-4)
                    Text("miles").font(.title3).foregroundStyle(ComebackStyle.muted)
                    Spacer()
                    Image(systemName: "figure.run").font(.system(size: 34)).foregroundStyle(ComebackStyle.orange)
                }
                Text(week == 25 ? "April 24 · 7:33 a.m. Central wave start. Check your final race instructions." : "\(Plan.shortDate(Plan.date(week, day: 5))) · Allow \(Int(Plan.miles[week] * 12))–\(Int(Plan.miles[week] * 15)) minutes at an easy 12–15 min/mi.")
                    .font(.subheadline).foregroundStyle(ComebackStyle.muted)
                Text("Conversational pace. Walk breaks from the start. Repeat or shorten a week when recovery needs it.").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }.trainingCard()
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "How did it go?", detail: "SAVED AUTOMATICALLY")
                HStack {
                    Text("Long run completed").font(.subheadline)
                    Spacer()
                    TextField("0", text: binding(\.miles)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 65).font(.title3.weight(.semibold)).accessibilityLabel("Long run completed, miles")
                    Text("mi").foregroundStyle(ComebackStyle.muted)
                }
                Rectangle().fill(ComebackStyle.line).frame(height: 1)
                Picker("How it felt", selection: binding(\.feel)) {
                    ForEach(["", "Comfortable", "Manageable", "Too hard", "Pain / stopped"], id: \.self) { Text($0.isEmpty ? "Choose an effort" : $0).tag($0) }
                }.tint(ComebackStyle.orange)
                TextField("A small win. A tough moment. A note for next week…", text: binding(\.notes), axis: .vertical).font(.subheadline).lineLimit(3...8).padding(14).background(ComebackStyle.paper, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Weekly notes")
            }.trainingCard()
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Every session counts.", detail: "\(store.completed) / 130")
                ProgressView(value: Double(store.completed), total: 130).tint(ComebackStyle.orange)
                Text("ILLINOIS HALF MARATHON · APR 24, 2027").font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(ComebackStyle.muted)
            }
        }
    }
    private func sessionCard(index: Int, session: String) -> some View {
        let parts = session.components(separatedBy: " · ")
        let day = parts.first ?? "Session"
        let detail = parts.dropFirst().joined(separator: " · ")
        let done = store.record(week).done[index]
        return HStack(alignment: .center, spacing: 14) {
            Toggle(isOn: Binding(get: { store.record(week).done[index] }, set: { value in store.update(week) { $0.done[index] = value } })) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(day.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(ComebackStyle.muted)
                    Text(detail).font(.system(size: 16, weight: .semibold)).foregroundStyle(done ? ComebackStyle.muted : ComebackStyle.ink).fixedSize(horizontal: false, vertical: true)
                }
            }.toggleStyle(SessionCheckStyle())
            if [1, 2, 4].contains(index) {
                Button { coach.startWorkout(week: week, session: index) } label: {
                    Image(systemName: "play.circle").font(.title2).frame(width: 44, height: 44)
                }.accessibilityLabel("Start \(detail) with GPS and timer")
            }
            if week != 25 && (index == 0 || index == 3) {
                NavigationLink { StrengthView(selected: index == 0 ? 0 : 1) } label: {
                    Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44).background(ComebackStyle.paper, in: Circle())
                }.accessibilityLabel("Open workout \(index == 0 ? "A" : "B")")
            }
        }.padding(16).background(ComebackStyle.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ComebackStyle.line.opacity(0.65), lineWidth: 1))
    }
}
struct SessionCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 14) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 27, weight: .light)).foregroundStyle(configuration.isOn ? ComebackStyle.orange : ComebackStyle.line)
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(configuration.isOn ? "Complete" : "Not complete")
            .accessibilityHint("Double tap to change completion")
    }
}
struct ScheduleView: View {
    @EnvironmentObject var store: ProgressStore
    var body: some View {
        TrainingPage {
            PageHeader(category: "26 weeks / one finish line", title: "The road ahead.", subtitle: "October 26, 2026 – April 24, 2027")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("13.1").font(.system(size: 76, weight: .medium, design: .serif)).tracking(-4)
                Text("miles to make yours.").font(.system(size: 19, design: .serif)).foregroundStyle(ComebackStyle.muted)
            }.padding(.vertical, 6)
            VStack(spacing: 10) {
                ForEach(0..<26, id: \.self) { week in
                    if week == 0 || Plan.phase(week) != Plan.phase(week - 1) {
                        Eyebrow(text: Plan.phase(week)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, week == 0 ? 0 : 22).padding(.bottom, 6)
                    }
                    NavigationLink { WeekView(week: week) } label: {
                        HStack(spacing: 16) {
                            Text(String(format: "%02d", week + 1)).font(.system(size: 23, design: .monospaced)).foregroundStyle(week == Plan.currentWeek() ? ComebackStyle.orange : ComebackStyle.muted).frame(width: 36)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(Plan.shortDate(Plan.date(week))).font(.headline)
                                Text("\(store.record(week).done.filter { $0 }.count) / 5 complete\(week == Plan.currentWeek() ? " · This week" : "")").font(.caption).foregroundStyle(ComebackStyle.muted)
                            }
                            Spacer(minLength: 6)
                            Text("\(Plan.distance(week)) mi").font(.system(.subheadline, design: .monospaced)).fontWeight(.semibold)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(ComebackStyle.orange)
                        }.padding(18).background(ComebackStyle.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(week == Plan.currentWeek() ? ComebackStyle.orange : ComebackStyle.line.opacity(0.65), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
struct StrengthView: View {
    var selected: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @ViewState private var illustratedExercise: Exercise?
    private let result = Result { try TrainingContent.load() }
    var body: some View {
        TrainingPage {
            if selected != nil { Button { dismiss() } label: { Label("This week", systemImage: "arrow.left") }.font(.subheadline.weight(.semibold)) }
            PageHeader(category: "Build your foundation", title: "Strong for\nthe long run.", subtitle: "Simple movements. Consistent effort.")
            VStack(alignment: .leading, spacing: 14) {
                Label("START WITH ONE EASY SET", systemImage: "dumbbell").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(ComebackStyle.orange)
                Text("First two weeks: one set per exercise. Monday is your main session. Friday stays light for Saturday.").font(.subheadline)
                DisclosureGroup("Before you begin") {
                    Text("A rep is one complete movement; a set is a group of reps. Warm up for 4–5 minutes: walk the court, then 5 gentle squats, 5 hip hinges, and 10 easy calf raises. Rest 45–90 seconds between sets or exercises.\n\nStart with bodyweight or your lightest kettlebell. Finish each set able to do about 3 more good reps. Exhale during effort. Reduce weight if balance or form slips.").font(.subheadline).foregroundStyle(ComebackStyle.muted).padding(.top, 10)
                }.font(.subheadline.weight(.semibold))
            }.trainingCard()
            switch result {
            case .success(let content):
                ForEach(Array(content.workouts.enumerated()), id: \.offset) { index, workout in
                    if selected == nil || selected == index {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading(title: index == 0 ? "Workout A" : "Workout B", detail: index == 0 ? "MONDAY / 20–30 MIN" : "FRIDAY / 15–20 MIN")
                            ForEach(workout.exercises) { exercise in
                                DisclosureGroup {
                                    Button { illustratedExercise = exercise } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Image(exercise.illustration).resizable().scaledToFit()
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                .accessibilityLabel(exercise.illustrationDescription)
                                            HStack {
                                                Text("MOVEMENT GUIDE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                                                Spacer()
                                                Label("Enlarge", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption)
                                            }.foregroundStyle(ComebackStyle.orange)
                                        }.padding(.top, 14)
                                    }.buttonStyle(.plain).accessibilityHint("Opens a larger illustration you can zoom")
                                    Text(exercise.instructions).font(.subheadline).foregroundStyle(ComebackStyle.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                                } label: { Text(exercise.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(ComebackStyle.ink) }.trainingCard()
                            }
                        }
                    }
                }
                DisclosureGroup("Progression & recovery") { Text(content.progression).font(.subheadline).foregroundStyle(ComebackStyle.muted).padding(.top, 12) }.font(.headline).trainingCard()
            case .failure: Text("Training instructions could not load. Please reinstall the app.").trainingCard()
            }
        }.sheet(item: $illustratedExercise) { exercise in ExerciseIllustrationSheet(exercise: exercise) }
    }
}
struct ExerciseIllustrationSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @ViewState private var scale: CGFloat = 1
    @ViewState private var savedScale: CGFloat = 1
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        Image(exercise.illustration).resizable().scaledToFit()
                            .frame(width: geometry.size.width * scale)
                            .frame(minHeight: geometry.size.height)
                            .accessibilityLabel(exercise.illustrationDescription)
                    }
                    .simultaneousGesture(MagnifyGesture()
                        .onChanged { value in scale = min(4, max(1, savedScale * value.magnification)) }
                        .onEnded { _ in savedScale = scale })
                    .onTapGesture(count: 2) { scale = scale > 1 ? 1 : 2; savedScale = scale }
                }
                Text(exercise.illustrationDescription).font(.subheadline).foregroundStyle(ComebackStyle.ink).padding(.horizontal, 24)
                Text("Pinch to zoom · Double tap to reset or enlarge").font(.caption).foregroundStyle(ComebackStyle.muted).padding(.bottom, 20)
            }.background(ComebackStyle.paper)
                .navigationTitle(exercise.title.components(separatedBy: " · ").first ?? "Movement guide")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(ComebackStyle.orange)
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
        TrainingPage {
            PageHeader(category: "A little knowledge / a long way", title: "Run your\nown race.", subtitle: "Your field guide to a sustainable comeback.")
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "The finish line")
                Text("Illinois\nHalf Marathon").font(.system(size: 30, weight: .bold, design: .serif)).tracking(-1)
                Text("Champaign-Urbana · April 24, 2027\n7:33 a.m. Central").font(.subheadline).foregroundStyle(ComebackStyle.muted)
                Text("Goal: 2:10 · 9:55/mi average").font(.system(.caption, design: .monospaced)).foregroundStyle(ComebackStyle.orange)
                Link(destination: URL(string: "https://illinoismarathon.com/races/half-marathon/")!) { Label("Race information", systemImage: "arrow.up.right") }.font(.subheadline.weight(.semibold))
            }.trainingCard()
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Run. Walk. Repeat.")
                Text("Begin with 30–60 seconds easy running and 60 seconds walking. Use full-sentence conversation as your effort guide. Include 5 minutes walking to warm up and cool down within weekday session times. Stay easy for the first eight weeks.").font(.subheadline).foregroundStyle(ComebackStyle.muted)
            }
            if case .success(let content) = result {
                VStack(spacing: 12) {
                    ForEach(content.guide) { item in
                        DisclosureGroup { Text(item.body).font(.subheadline).foregroundStyle(ComebackStyle.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 12) } label: { Text(item.title).font(.headline).foregroundStyle(ComebackStyle.ink) }.trainingCard()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Keep your progress.")
                Text("Saved on this iPhone. Export a backup before reinstalling or changing phones. You can also import a JSON backup from Spaces.").font(.subheadline).foregroundStyle(ComebackStyle.muted)
                HStack(spacing: 12) {
                    Button { export = true } label: { Label("Export", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 12) }.background(ComebackStyle.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 12) }.background(ComebackStyle.paper, in: RoundedRectangle(cornerRadius: 12))
                }.font(.subheadline.weight(.semibold))
            }.trainingCard()
            Text("THE COMEBACK / 13.1\nA personal, Galloway-inspired training plan.\nNo account. No tracking. Just your progress.").font(.system(size: 11, design: .monospaced)).lineSpacing(6).foregroundStyle(ComebackStyle.muted)
            Link("Run Walk Run reference ↗", destination: URL(string: "https://www.jeffgalloway.com/training/run-walk/")!).font(.caption)
        }
        .fileExporter(isPresented: $export, document: Backup(store.data), contentType: .json, defaultFilename: "half-marathon-progress") { result in if case .failure(let error) = result { message = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bytes = try Data(contentsOf: url)
                _ = try JSONDecoder().decode(ProgressData.self, from: bytes).validated()
                pending = bytes
            } catch { message = "Import failed: \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace progress on this iPhone with this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Replace progress", role: .destructive) { if let bytes = pending { do { try store.restore(bytes) } catch { message = error.localizedDescription } }; pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        }
        .alert("Progress", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
}
