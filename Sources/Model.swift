import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Use the stable property-wrapper type across Xcode SDK versions.
typealias ViewState<Value> = SwiftUI.State<Value>

struct Exercise: Codable, Identifiable {
    var id: String { title }
    let title: String
    let instructions: String
    let illustration: String
    let illustrationDescription: String
}
struct Workout: Codable, Identifiable { var id: String { title }; let title: String; let exercises: [Exercise] }
struct GuideItem: Codable, Identifiable { var id: String { title }; let title: String; let body: String }
struct TrainingContent: Codable {
    let workouts: [Workout]; let progression: String; let guide: [GuideItem]
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "Training", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
enum Plan {
    static let miles: [Double] = [2,2.5,3,2,3.5,4,4.5,3,5,5.5,6,4,7,5,8,6,9,6,10,7,11,7,12,8,5,13.1]
    static let minutes = [25,25,30,25,30,30,35,30,35,35,40,30,40,35,40,35,45,35,45,40,45,35,40,35,30,20]
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Chicago")!; return c }
    static let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
    static let race = calendar.date(from: DateComponents(year: 2027, month: 4, day: 24, hour: 7, minute: 33))!
    static func date(_ week: Int, day: Int = 0) -> Date { calendar.date(byAdding: .day, value: week * 7 + day, to: start)! }
    static func currentWeek(now: Date = Date()) -> Int { min(25, max(0, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0) / 7)) }
    static func phase(_ w: Int) -> String { w < 4 ? "Restart" : w < 8 ? "Build the habit" : w < 14 ? "Build endurance" : w < 23 ? "Race preparation" : "Taper" }
    static func sessions(_ w: Int) -> [String] {
        if w == 25 { return ["Monday · Light mobility, 15 min", "Tuesday · Easy run/walk, 20 min", "Wednesday · Light activation, 10 min", "Thursday · Easy run/walk, 15 min", "Saturday · Illinois Half Marathon, 13.1 mi"] }
        return ["Monday · Strength A, 20–30 min", "Tuesday · Easy run/walk, \(minutes[w]) min", "Thursday · Run/walk, \(minutes[w]+5) min", "Friday · Strength B, 15–20 min", "Saturday · Long run/walk, \(distance(w)) mi"]
    }
    static func distance(_ w: Int) -> String { miles[w].formatted(.number.precision(.fractionLength(0...1))) }
    static func shortDate(_ d: Date) -> String { let f = DateFormatter(); f.timeZone = calendar.timeZone; f.dateFormat = "MMM d"; return f.string(from: d) }
}
struct WeekRecord: Codable {
    var done = [false, false, false, false, false]
    var notes = ""
    var miles = ""
    var feel = ""
}
struct ProgressData: Codable {
    var weeks: [String: WeekRecord] = [:]
    func validated() throws -> Self {
        for (key, record) in weeks {
            guard let i = Int(key), (0..<26).contains(i), record.done.count == 5, record.notes.count <= 10000 else { throw CocoaError(.fileReadCorruptFile) }
        }
        return self
    }
}
@MainActor final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()
    @Published var data = ProgressData()
    @Published var error: String?
    private let url: URL
    init(url: URL = URL.documentsDirectory.appendingPathComponent("progress.json")) {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do { data = try JSONDecoder().decode(ProgressData.self, from: Data(contentsOf: url)).validated() }
            catch { self.error = "Saved progress could not be read. It has not been overwritten. Restore a backup before making changes." }
        }
    }
    func record(_ week: Int) -> WeekRecord { data.weeks[String(week)] ?? WeekRecord() }
    func update(_ week: Int, _ change: (inout WeekRecord) -> Void) {
        guard error == nil else { return }
        var r = record(week); change(&r); data.weeks[String(week)] = r; persist()
    }
    private func persist() { do { try JSONEncoder().encode(data).write(to: url, options: .atomic) } catch { self.error = "Could not save progress: \(error.localizedDescription)" } }
    func restore(_ bytes: Data) throws { let restored = try JSONDecoder().decode(ProgressData.self, from: bytes).validated(); try JSONEncoder().encode(restored).write(to: url, options: .atomic); data = restored; error = nil }
    var completed: Int { data.weeks.values.reduce(0) { $0 + $1.done.filter { $0 }.count } }
}
struct Backup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(_ progress: ProgressData) { data = (try? JSONEncoder().encode(progress)) ?? Data() }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
