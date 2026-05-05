import XCTest
@testable import ClaudegrainCore

final class QuietHoursTests: XCTestCase {
    private func date(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 5
        comps.hour = hour; comps.minute = minute
        return Calendar.current.date(from: comps)!
    }

    func testNotEnabledNeverContains() {
        let q = QuietHours(enabled: false, startHour: 22, startMinute: 0, endHour: 9, endMinute: 0)
        XCTAssertFalse(q.contains(date(hour: 23, minute: 30)))
    }

    func testWithinSameDayWindow() {
        let q = QuietHours(enabled: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
        XCTAssertTrue(q.contains(date(hour: 12, minute: 0)))
        XCTAssertFalse(q.contains(date(hour: 8, minute: 59)))
        XCTAssertFalse(q.contains(date(hour: 17, minute: 0)), "end is exclusive")
    }

    func testCrossMidnightWindow() {
        let q = QuietHours(enabled: true, startHour: 22, startMinute: 0, endHour: 9, endMinute: 0)
        XCTAssertTrue(q.contains(date(hour: 23, minute: 30)))
        XCTAssertTrue(q.contains(date(hour: 0, minute: 30)))
        XCTAssertTrue(q.contains(date(hour: 8, minute: 30)))
        XCTAssertFalse(q.contains(date(hour: 9, minute: 0)), "end is exclusive")
        XCTAssertFalse(q.contains(date(hour: 12, minute: 0)))
    }

    func testStartEqualsEndIsEmpty() {
        let q = QuietHours(enabled: true, startHour: 9, startMinute: 0, endHour: 9, endMinute: 0)
        XCTAssertFalse(q.contains(date(hour: 9, minute: 0)))
        XCTAssertFalse(q.contains(date(hour: 14, minute: 0)))
    }

    func testEdgeAtStartIsInclusive() {
        let q = QuietHours(enabled: true, startHour: 22, startMinute: 0, endHour: 9, endMinute: 0)
        XCTAssertTrue(q.contains(date(hour: 22, minute: 0)))
    }
}
