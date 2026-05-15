import XCTest
@testable import CalShot

final class ICSExporterTests: XCTestCase {
    func testAllDayEventUsesDateValuesAndExclusiveEndDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let exporter = ICSExporter(calendar: calendar)
        let start = makeICSDate(2026, 5, 9, 0, 0, calendar: calendar)
        let draft = EventDraft(
            title: "All Day",
            start: start,
            end: calendar.date(byAdding: .day, value: 1, to: start),
            allDay: true,
            location: nil,
            url: nil,
            notes: "",
            alternatives: [],
            sources: [:]
        )

        let ics = exporter.icsString(for: draft, start: start)

        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20260509"))
        XCTAssertTrue(ics.contains("DTEND;VALUE=DATE:20260510"))
    }

    func testTimedEventEscapesTextAndUsesUTCDateTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let exporter = ICSExporter(calendar: calendar)
        let start = makeICSDate(2026, 5, 9, 15, 0, calendar: calendar)
        let draft = EventDraft(
            title: "Talk, Demo; Q&A",
            start: start,
            end: start.addingTimeInterval(60 * 60),
            allDay: false,
            location: "Room 1, Building A",
            url: URL(string: "https://example.com/zoom"),
            notes: "Line one\nLine two",
            alternatives: [],
            sources: [:]
        )

        let ics = exporter.icsString(for: draft, start: start)

        XCTAssertTrue(ics.contains("SUMMARY:Talk\\, Demo\\; Q&A"))
        XCTAssertTrue(ics.contains("LOCATION:Room 1\\, Building A"))
        XCTAssertTrue(ics.contains("DESCRIPTION:Line one\\nLine two"))
        XCTAssertTrue(ics.contains("DTSTART:"))
        XCTAssertTrue(ics.contains("DTEND:"))
    }
}

private func makeICSDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
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

