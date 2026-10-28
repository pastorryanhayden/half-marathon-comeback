import XCTest
@testable import HalfMarathonComeback
final class PlanTests: XCTestCase {
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
