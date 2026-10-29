import XCTest
import CoreLocation
import AVFoundation
import UIKit
@testable import HalfMarathonComeback
final class PlanTests: XCTestCase {
    func testIntervalBoundariesAndMultipleCycles() {
        let start = IntervalTiming.state(at: 0, run: 30, walk: 60)
        XCTAssertFalse(start.walking)
        XCTAssertEqual(start.remaining, 30)
        let walk = IntervalTiming.state(at: 30, run: 30, walk: 60)
        XCTAssertTrue(walk.walking)
        XCTAssertEqual(walk.remaining, 60)
        let nextRun = IntervalTiming.state(at: 270, run: 30, walk: 60)
        XCTAssertFalse(nextRun.walking)
        XCTAssertEqual(nextRun.remaining, 30)
        XCTAssertEqual(IntervalTiming.state(at: 89.1, run: 30, walk: 60).remaining, 1)
    }
    func testCoachingTrackContainsBothCuesAtExactOffsets() throws {
        let track = try IntervalTrack.render(run: 10, walk: 15)
        let file = try AVAudioFile(forReading: track.url)
        XCTAssertEqual(file.processingFormat.sampleRate, 22050)
        XCTAssertEqual(file.length, 25 * 22050)
        XCTAssertGreaterThan(track.runCue, 0.5)
        XCTAssertGreaterThan(track.walkCue, 0.5)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 22050 * 2))
        try file.read(into: buffer)
        let first = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(first[$0]) > 0.01 })
        file.framePosition = 10 * 22050
        try file.read(into: buffer)
        let second = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(second[$0]) > 0.01 })
        file.framePosition = 5 * 22050
        try file.read(into: buffer)
        let between = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertTrue((0..<Int(buffer.frameLength)).allSatisfy { between[$0] == 0 })
    }
    func testEveryExerciseHasAnOfflineIllustration() throws {
        let content = try TrainingContent.load()
        var names = Set<String>()
        for workout in content.workouts {
            for exercise in workout.exercises {
                XCTAssertNotNil(UIImage(named: exercise.illustration), exercise.title)
                XCTAssertFalse(exercise.illustrationDescription.isEmpty)
                names.insert(exercise.illustration)
            }
        }
        XCTAssertEqual(names.count, 9)
    }
    func testOptionalCountdownAddsBeepsBeforeEachTransition() throws {
        let track = try IntervalTrack.render(run: 10, walk: 15, countdown: true)
        let file = try AVAudioFile(forReading: track.url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2205))
        for second in [5, 6, 7, 8, 9, 20, 21, 22, 23, 24] {
            file.framePosition = AVAudioFramePosition(second * 22050)
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(samples[$0]) > 0.01 }, "Missing beep at \(second)")
        }
    }
    func testRaceAndSchedule() {
        XCTAssertEqual(Plan.miles.count,26)
        XCTAssertEqual(Plan.minutes.count,26)
        XCTAssertTrue(Plan.calendar.isDate(Plan.date(25,day:5),inSameDayAs:Plan.race))
        XCTAssertEqual(Plan.calendar.component(.weekday,from:Plan.race),7)
        XCTAssertEqual(Plan.currentWeek(now:Plan.date(10)),10)
        XCTAssertEqual(Plan.currentWeek(now:.distantPast),0)
        XCTAssertEqual(Plan.currentWeek(now:.distantFuture),25)
    }
    func testInvalidBackupRejected() {
        XCTAssertThrowsError(try ProgressData(weeks:["26":WeekRecord()]).validated())
        XCTAssertThrowsError(try ProgressData(weeks:["0":WeekRecord(done:[true])]).validated())
    }
    @MainActor func testSaveReopenAndRestore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let store = ProgressStore(url:url)
        store.update(0) { $0.done[0] = true; $0.notes = "First workout" }
        let reopened = ProgressStore(url:url)
        XCTAssertEqual(reopened.record(0).notes,"First workout")
        XCTAssertEqual(reopened.completed,1)
        try reopened.restore(JSONEncoder().encode(ProgressData(weeks:["1":WeekRecord(notes:"Imported")])))
        XCTAssertEqual(reopened.record(1).notes,"Imported")
        XCTAssertEqual(reopened.completed,0)
    }
}

@MainActor final class RunTrackingTests: XCTestCase {
    private func location(_ meters: Double, at date: Date, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: 40, longitude: -88 + meters / 85393.8), altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: date)
    }
    func testDistanceSplitsPauseAndRecovery() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let tracker = RunTracker(url: url)
        let start = Date()
        XCTAssertTrue(tracker.start(title: "Test run", week: 0, session: 1, now: start))
        var announced: [Int] = []
        tracker.onSplit = { announced.append($0.mile) }
        for step in 0...180 {
            let time = start.addingTimeInterval(Double(step) * 5)
            tracker.accept(location(Double(step) * 10, at: time), now: time)
        }
        XCTAssertEqual(tracker.current!.meters, 1800, accuracy: 10)
        XCTAssertEqual(announced, [1])
        XCTAssertEqual(tracker.current!.splits[0].seconds, 804.7, accuracy: 5)
        let pause = start.addingTimeInterval(900)
        tracker.pause(now: pause)
        tracker.accept(location(5000, at: pause), now: pause)
        XCTAssertEqual(tracker.current!.meters, 1800, accuracy: 10)
        XCTAssertTrue(tracker.start(title: "ignored", week: nil, session: nil, now: start.addingTimeInterval(1000)))
        tracker.accept(location(5000, at: start.addingTimeInterval(1000)), now: start.addingTimeInterval(1000))
        tracker.accept(location(5010, at: start.addingTimeInterval(1005)), now: start.addingTimeInterval(1005))
        tracker.pause(now: start.addingTimeInterval(1005))
        XCTAssertEqual(tracker.current!.meters, 1810, accuracy: 10)
        XCTAssertEqual(tracker.current!.elapsed, 905, accuracy: 0.1)
        XCTAssertEqual(Set(tracker.current!.route.map(\.segment)).count, 2)
        let recovered = RunTracker(url: url)
        XCTAssertFalse(recovered.recording)
        XCTAssertEqual(recovered.current?.title, "Test run")
        XCTAssertEqual(recovered.current?.elapsed, 905)
        _ = recovered.finish()
        let saved = RunTracker(url: url)
        XCTAssertNil(saved.current)
        XCTAssertEqual(saved.archive.runs.count, 1)
        XCTAssertEqual(saved.archive.runs[0].route.count, 183)
    }
    func testRejectsPoorStaleAndImpossibleGPSAndBreaksGaps() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let tracker = RunTracker(url: url)
        let start = Date()
        _ = tracker.start(title: "Filtering", week: nil, session: nil, now: start)
        tracker.accept(location(0, at: start), now: start)
        tracker.accept(location(30, at: start.addingTimeInterval(5), accuracy: 100), now: start.addingTimeInterval(5))
        tracker.accept(location(20, at: start.addingTimeInterval(-30)), now: start)
        tracker.accept(location(1000, at: start.addingTimeInterval(5)), now: start.addingTimeInterval(5))
        tracker.accept(location(1010, at: start.addingTimeInterval(40)), now: start.addingTimeInterval(40))
        tracker.pause(now: start.addingTimeInterval(40))
        XCTAssertEqual(tracker.current?.meters, 0)
        XCTAssertEqual(tracker.current?.route.count, 3)
        XCTAssertEqual(Set(tracker.current!.route.map(\.segment)).count, 3)
    }
    func testCorruptHistoryIsPreserved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("broken".utf8)
        try bytes.write(to: url)
        let tracker = RunTracker(url: url)
        XCTAssertFalse(tracker.start(title: "Test", week: nil, session: nil))
        XCTAssertNotNil(tracker.savingError)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
