import XCTest
@testable import CalShot

final class ChronoBridgeTests: XCTestCase {
    func testChronoBundleMapsCertaintyAndForwardDates() throws {
        let bridge = ChronoBridge(bundle: Bundle(for: Self.self))
        try XCTSkipUnless(bridge.loaded, "chrono.bundle.js is not available in the test bundle")

        let calendar = gregorianChicagoCalendar()
        let refBefore = date(2026, 5, 7, 9, 0, calendar: calendar)
        let beforeResults = bridge.parse(text: "Friday at noon", referenceDate: refBefore, timeZone: calendar.timeZone)
        let before = try XCTUnwrap(beforeResults.first)
        XCTAssertTrue(before.hasCertainStartTime)
        XCTAssertEqual(calendar.component(.day, from: before.startDate), 8)

        let refAfter = date(2026, 5, 9, 9, 0, calendar: calendar)
        let afterResults = bridge.parse(text: "Friday at noon", referenceDate: refAfter, timeZone: calendar.timeZone)
        let after = try XCTUnwrap(afterResults.first)
        XCTAssertEqual(calendar.component(.day, from: after.startDate), 15)
    }

    func testDateOnlyHasNoCertainStartTime() throws {
        let bridge = ChronoBridge(bundle: Bundle(for: Self.self))
        try XCTSkipUnless(bridge.loaded, "chrono.bundle.js is not available in the test bundle")

        let calendar = gregorianChicagoCalendar()
        let results = bridge.parse(text: "May 9, 2026", referenceDate: date(2026, 5, 1, 9, 0, calendar: calendar), timeZone: calendar.timeZone)
        let first = try XCTUnwrap(results.first)
        XCTAssertTrue(first.hasCertainDate)
        XCTAssertFalse(first.hasCertainStartTime)
    }

    func testDSTBoundaryKeepsLocalWallTimeSane() throws {
        let bridge = ChronoBridge(bundle: Bundle(for: Self.self))
        try XCTSkipUnless(bridge.loaded, "chrono.bundle.js is not available in the test bundle")

        let calendar = gregorianChicagoCalendar()
        let results = bridge.parse(text: "March 8, 2026 at 10 AM", referenceDate: date(2026, 3, 1, 9, 0, calendar: calendar), timeZone: calendar.timeZone)
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(calendar.component(.hour, from: first.startDate), 10)
    }
}

private func gregorianChicagoCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}

