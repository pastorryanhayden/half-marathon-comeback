import SwiftUI
import CoreLocation
import MapKit

struct RoutePoint: Codable, Identifiable {
    var id = UUID()
    let latitude: Double
    let longitude: Double
    let elapsed: Double
    let segment: Int
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
struct MileSplit: Codable, Identifiable {
    var id: Int { mile }
    let mile: Int
    let seconds: Double
}
struct RunRecord: Codable, Identifiable {
    var id = UUID()
    var started = Date()
    var title = "Run / walk"
    var week: Int?
    var session: Int?
    var meters = 0.0
    var elapsed = 0.0
    var route: [RoutePoint] = []
    var splits: [MileSplit] = []
    var miles: Double { meters / 1609.344 }
    var pace: String { Self.pace(seconds: miles > 0.01 ? elapsed / miles : 0) }
    static func pace(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
struct RunArchive: Codable {
    var runs: [RunRecord] = []
    var active: RunRecord?
}

@MainActor final class RunTracker: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var archive = RunArchive()
    @Published private(set) var message: String?
    @Published private(set) var savingError: String?
    var onSplit: ((MileSplit) -> Void)?
    private let manager = CLLocationManager()
    private let url: URL
    private var activeSince: Date?
    private var accumulated = 0.0
    private var last: CLLocation?
    private var segment = 0
    private var acceptingSince = Date()
    private var lastCheckpoint = Date.distantPast
    private var writable = true
    var recording: Bool { activeSince != nil }
    var current: RunRecord? { archive.active }
    init(url: URL = URL.documentsDirectory.appendingPathComponent("runs.json")) {
        self.url = url
        super.init()
        if FileManager.default.fileExists(atPath: url.path) {
            do { archive = try JSONDecoder().decode(RunArchive.self, from: Data(contentsOf: url)) }
            catch { writable = false; savingError = "Run history could not be read. It has not been overwritten." }
        }
        accumulated = archive.active?.elapsed ?? 0
        segment = (archive.active?.route.last?.segment ?? -1) + 1
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if archive.active != nil { message = "An unfinished run was recovered. Resume or finish to save it." }
    }
    func start(title: String, week: Int?, session: Int?, now: Date = Date()) -> Bool {
        guard writable else { return false }
        if archive.active == nil { archive.active = RunRecord(title: title, week: week, session: session); accumulated = 0 }
        guard activeSince == nil else { return true }
        activeSince = now; acceptingSince = now; last = nil; segment += 1
        authorizeAndTrack(); checkpoint()
        return true
    }
    private func authorizeAndTrack() {
        guard recording else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            message = manager.accuracyAuthorization == .reducedAccuracy ? "Enable Precise Location in Settings for useful distance and route tracking." : "Waiting for a GPS fix…"
            manager.startUpdatingLocation()
        default: message = "Location access is off. The timer works, but distance and route cannot be recorded. Enable Precise Location in Settings."
        }
    }
    func tick(now: Date = Date()) {
        guard let activeSince else { return }
        let elapsed = accumulated + max(0, now.timeIntervalSince(activeSince))
        guard abs(elapsed - (archive.active?.elapsed ?? 0)) >= 0.5 else { return }
        archive.active?.elapsed = elapsed
        if now.timeIntervalSince(lastCheckpoint) >= 10 { checkpoint() }
    }
    func pause(now: Date = Date()) {
        if let activeSince { archive.active?.elapsed = accumulated + max(0, now.timeIntervalSince(activeSince)) }
        accumulated = archive.active?.elapsed ?? 0; activeSince = nil; last = nil
        manager.stopUpdatingLocation(); checkpoint()
    }
    @discardableResult func finish() -> RunRecord? {
        pause()
        guard let run = archive.active else { return nil }
        archive.runs.insert(run, at: 0); archive.active = nil
        accumulated = 0; checkpoint()
        return run
    }
    func delete(_ id: UUID) { archive.runs.removeAll { $0.id == id }; checkpoint() }
    private func checkpoint() {
        guard writable else { return }
        do {
            try JSONEncoder().encode(archive).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            savingError = nil; lastCheckpoint = Date()
        } catch { savingError = "Could not save this run: \(error.localizedDescription)" }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { last = nil; authorizeAndTrack() }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        last = nil; segment += 1; message = "GPS is unavailable. Tracking will resume when a signal returns."
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard recording else { return }
        for location in locations { accept(location) }
    }
    // Kept independent of the location delegate so GPS filtering and splits can be tested.
    func accept(_ location: CLLocation, now: Date = Date()) {
        guard recording, CLLocationCoordinate2DIsValid(location.coordinate), location.timestamp >= acceptingSince,
              abs(location.timestamp.timeIntervalSince(now)) <= 15,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30 else { return }
        tick(now: now)
        guard var run = archive.active else { return }
        let elapsed = accumulated + max(0, location.timestamp.timeIntervalSince(activeSince ?? location.timestamp))
        if let previous = last {
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0 else { return }
            let distance = location.distance(from: previous)
            if seconds > 30 || distance / seconds > 10 {
                segment += 1 // Never draw or count a bridge across a lost GPS signal.
            } else if distance >= 3 {
                let before = run.meters
                run.meters += distance
                while run.meters >= Double(run.splits.count + 1) * 1609.344 {
                    let mile = run.splits.count + 1
                    let fraction = (Double(mile) * 1609.344 - before) / distance
                    let previousElapsed = run.route.last?.elapsed ?? elapsed
                    let boundary = previousElapsed + fraction * (elapsed - previousElapsed)
                    let totalBefore = run.splits.reduce(0) { $0 + $1.seconds }
                    let split = MileSplit(mile: mile, seconds: max(0, boundary - totalBefore))
                    run.splits.append(split); onSplit?(split)
                }
            } else { return }
        }
        last = location
        run.route.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, elapsed: elapsed, segment: segment))
        archive.active = run; message = nil
    }
}

struct RunRouteMap: View {
    let run: RunRecord
    var body: some View {
        Map {
            ForEach(Array(Set(run.route.map(\.segment))).sorted(), id: \.self) { segment in
                MapPolyline(coordinates: run.route.filter { $0.segment == segment }.map(\.coordinate)).stroke(.orange, lineWidth: 4)
            }
            if let first = run.route.first { Marker("Start", systemImage: "play.fill", coordinate: first.coordinate).tint(.green) }
            if let last = run.route.last { Marker("Latest", systemImage: "flag.fill", coordinate: last.coordinate) }
        }.frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
struct RunDetails: View {
    let run: RunRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(run.title).font(.headline)
            Text(run.started.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            HStack {
                metric("MILES", run.miles.formatted(.number.precision(.fractionLength(2))))
                Spacer(); metric("AVG / MI", run.pace)
                Spacer(); metric("ACTIVE TIME", RunRecord.pace(seconds: run.elapsed))
            }
            if !run.route.isEmpty { RunRouteMap(run: run) }
            ForEach(run.splits) { split in
                HStack { Text("Mile \(split.mile)"); Spacer(); Text("\(RunRecord.pace(seconds: split.seconds)) / mi").monospacedDigit() }.font(.subheadline)
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.system(size: 9, design: .monospaced)); Text(value).font(.title3).monospacedDigit() }
    }
}
