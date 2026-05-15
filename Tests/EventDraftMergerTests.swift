import XCTest
@testable import CalShot

final class EventDraftMergerTests: XCTestCase {
    func testDateOnlyChronoCandidateBecomesAllDay() {
        let start = makeDate(2026, 5, 9, 12, 0)
        let chrono = FakeChrono(candidates: [
            ChronoParseCandidate(
                matchedText: "May 9, 2026",
                index: 0,
                length: 11,
                startDate: start,
                endDate: nil,
                startComponents: .init(values: ["year": 2026, "month": 5, "day": 9], certain: ["year", "month", "day"]),
                endComponents: nil,
                timezoneOffsetMinutes: nil
            )
        ])
        let draft = EventDraftMerger(chrono: chrono, calendar: makeCalendar()).makeDraft(from: document("May 9, 2026\nScience Seminar"))

        XCTAssertTrue(draft.allDay)
        XCTAssertEqual(draft.start, makeDate(2026, 5, 9, 0, 0))
        XCTAssertEqual(draft.end, makeDate(2026, 5, 10, 0, 0))
        XCTAssertEqual(draft.title, "Science Seminar")
    }

    func testTimedCandidateDefaultsToOneHour() {
        let start = makeDate(2026, 5, 9, 15, 0)
        let chrono = FakeChrono(candidates: [
            ChronoParseCandidate(
                matchedText: "May 9 at 3 PM",
                index: 0,
                length: 13,
                startDate: start,
                endDate: nil,
                startComponents: .init(values: ["month": 5, "day": 9, "hour": 15], certain: ["month", "day", "hour"]),
                endComponents: nil,
                timezoneOffsetMinutes: nil
            )
        ])
        let draft = EventDraftMerger(chrono: chrono, calendar: makeCalendar()).makeDraft(from: document("May 9 at 3 PM\nLab meeting"))

        XCTAssertFalse(draft.allDay)
        XCTAssertEqual(draft.start, start)
        XCTAssertEqual(draft.end, start.addingTimeInterval(60 * 60))
    }

    func testTimedRangeUsesChronoEnd() {
        let start = makeDate(2026, 5, 9, 15, 0)
        let end = makeDate(2026, 5, 9, 17, 0)
        let chrono = FakeChrono(candidates: [
            ChronoParseCandidate(
                matchedText: "May 9, 3-5 PM",
                index: 0,
                length: 13,
                startDate: start,
                endDate: end,
                startComponents: .init(values: ["month": 5, "day": 9, "hour": 15], certain: ["month", "day", "hour"]),
                endComponents: .init(values: ["hour": 17], certain: ["hour"]),
                timezoneOffsetMinutes: nil
            )
        ])
        let draft = EventDraftMerger(chrono: chrono, calendar: makeCalendar()).makeDraft(from: document("May 9, 3-5 PM\nWorkshop"))

        XCTAssertEqual(draft.start, start)
        XCTAssertEqual(draft.end, end)
        XCTAssertEqual(draft.alternatives.count, 1)
    }

    func testFragmentedWeekdayTimeRangeKeepsEndOnSameDay() {
        let start = makeDate(2026, 5, 9, 15, 0)
        let chronoEnd = makeDate(2026, 5, 16, 16, 0)
        let expectedEnd = makeDate(2026, 5, 9, 16, 0)
        let chrono = FakeChrono(candidates: [
            ChronoParseCandidate(
                matchedText: "SAT\n3:00 PM - 4:00 PM",
                index: 47,
                length: 22,
                startDate: start,
                endDate: chronoEnd,
                startComponents: .init(values: ["weekday": 6, "hour": 15, "minute": 0], certain: ["weekday", "hour", "minute"]),
                endComponents: .init(values: ["weekday": 6, "hour": 16, "minute": 0], certain: ["weekday", "hour", "minute"]),
                timezoneOffsetMinutes: nil
            )
        ])

        let draft = EventDraftMerger(chrono: chrono, calendar: makeCalendar())
            .makeDraft(from: document("Microglia and Memory\nSAT\n3:00 PM - 4:00 PM\nMAY 9"))

        XCTAssertEqual(draft.start, start)
        XCTAssertEqual(draft.end, expectedEnd)
    }

    func testSeparatedDateAndFollowingTimesComposeIntoTimedEvent() {
        let date = makeDate(2026, 5, 8, 0, 0)
        let sixPM = makeDate(2026, 5, 4, 18, 0)
        let sevenPM = makeDate(2026, 5, 4, 19, 0)
        let chrono = FakeChrono(candidates: [
            ChronoParseCandidate(
                matchedText: "night",
                index: 23,
                length: 5,
                startDate: makeDate(2026, 5, 4, 20, 0),
                endDate: nil,
                startComponents: .init(values: ["year": 2026, "month": 5, "day": 4, "hour": 20], certain: []),
                endComponents: nil,
                timezoneOffsetMinutes: nil
            ),
            ChronoParseCandidate(
                matchedText: "FRIDAY, MAY 8",
                index: 34,
                length: 13,
                startDate: date,
                endDate: nil,
                startComponents: .init(values: ["year": 2026, "month": 5, "day": 8, "weekday": 5], certain: ["month", "day", "weekday"]),
                endComponents: nil,
                timezoneOffsetMinutes: nil
            ),
            ChronoParseCandidate(
                matchedText: "6 PM",
                index: 54,
                length: 4,
                startDate: sixPM,
                endDate: nil,
                startComponents: .init(values: ["year": 2026, "month": 5, "day": 4, "hour": 18, "minute": 0], certain: ["hour", "minute"]),
                endComponents: nil,
                timezoneOffsetMinutes: nil
            ),
            ChronoParseCandidate(
                matchedText: "7 PM",
                index: 66,
                length: 4,
                startDate: sevenPM,
                endDate: nil,
                startComponents: .init(values: ["year": 2026, "month": 5, "day": 4, "hour": 19, "minute": 0], certain: ["hour", "minute"]),
                endComponents: nil,
                timezoneOffsetMinutes: nil
            )
        ])

        let draft = EventDraftMerger(chrono: chrono, calendar: makeCalendar())
            .makeDraft(from: document("THE STATIC ARCADES\none night only\nFRIDAY, MAY 8\nDOORS 6 PM | SHOW 7 PM"))

        XCTAssertEqual(draft.start, makeDate(2026, 5, 8, 18, 0))
        XCTAssertEqual(draft.end, makeDate(2026, 5, 8, 19, 0))
        XCTAssertTrue(draft.alternatives.contains { $0.label == "FRIDAY, MAY 8 + 7 PM" })
    }

    func testLocationCueDoesNotUseGenericAtTimeText() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("Starts at 7 PM\nLocation: FO 2.702"))

        XCTAssertEqual(draft.location, "FO 2.702")
    }

    func testRoomCueWithoutColonBecomesLocation() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("CalShot hotkey test\nTuesday May 12 at 2 PM\nRoom SLC 1.102"))

        XCTAssertEqual(draft.location, "SLC 1.102")
    }

    func testRoomCueWithoutColonIgnoresTimeOnlyValue() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("Starts at 7 PM\nRoom 7 PM"))

        XCTAssertNil(draft.location)
    }

    func testInlineRoomCodesBecomeLocation() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("""
            May 20 8am-5pm in SLC 2.302, SLC 2.303, and SLC 2.304 including pizza lunch and coffee.
            Make sure your presentation works on the computers in these rooms.
            """))

        XCTAssertEqual(draft.location, "SLC 2.302, SLC 2.303, SLC 2.304")
    }

    func testInlineStateOrTimeTextDoesNotBecomeLocation() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("How about Wednesday May 6 at 8am my time, which if you are in Texas is Tuesday May 5 at 5pm your time?"))

        XCTAssertNil(draft.location)
    }

    func testTimeZoneSentenceDoesNotBecomeLocation() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("How about Wednesday May 6 at 8am my time, which if you are in Texas is Tuesday May 5 at 5pm your time?"))

        XCTAssertNil(draft.location)
    }

    func testWebURLIsPreferredOverSenderEmailAddress() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("From: program.office@example.edu\nJoin link:\nhttps://example.com/t32-writing-room"))

        XCTAssertEqual(draft.url?.absoluteString, "https://example.com/t32-writing-room")
    }

    func testMeetingLinkIsPreferredOverMailingListLinks() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("""
            List help: https://lists.utdallas.edu/sympa/help
            Subscribe: https://lists.utdallas.edu/sympa/subscribe/principal-investigators

            Join us for a MS TEAMS webinar:
            Wednesday, May 20, 2026
            2:00 PM
            [joinHereButton.png]<https://utd.link/NIHco>
            """))

        XCTAssertEqual(draft.url?.absoluteString, "https://utd.link/NIHco")
    }

    func testDirectMeetingURLWinsOverGenericEventPage() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("""
            Details: https://example.edu/calendar/series
            Meeting: https://us02web.zoom.us/j/123456789
            """))

        XCTAssertEqual(draft.url?.absoluteString, "https://us02web.zoom.us/j/123456789")
    }

    func testOutlookSafeLinksWrappedMeetingURLWins() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("""
            Agenda: https://example.edu/meeting-agenda
            Join Microsoft Teams meeting:
            https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fabc123&data=05
            """))

        XCTAssertEqual(
            draft.url?.absoluteString,
            "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fabc123&data=05"
        )
    }

    func testTitleSkipsEmailChromeForActualSubject() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("Calendar invitation\nFrom: program.office@example.edu\nT32 Writing Workshop\nWhen: May 12 at 10:30 AM"))

        XCTAssertEqual(draft.title, "T32 Writing Workshop")
    }

    func testMultiLineHeadingBecomesCompleteTitle() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("""
            Faculty End of the
            Semester Social
            Thursday, May 7, 2026
            4 to 6:00 p.m.
            Northside Drafthouse
            3000 Northside Blvd., Ste. 800
            Richardson, TX 75080
            """))

        XCTAssertEqual(draft.title, "Faculty End of the Semester Social")
    }

    func testNoDateCannotCreate() {
        let draft = EventDraftMerger(chrono: FakeChrono(candidates: []), calendar: makeCalendar())
            .makeDraft(from: document("No date anywhere\nCoffee soon"))

        XCTAssertNil(draft.start)
        XCTAssertFalse(draft.canCreate)
    }
}

private struct FakeChrono: ChronoParsing {
    var candidates: [ChronoParseCandidate]

    func parse(text: String, referenceDate: Date, timeZone: TimeZone) -> [ChronoParseCandidate] {
        candidates
    }
}

private func document(_ text: String) -> OCRDocument {
    let lines = text.split(whereSeparator: \.isNewline).enumerated().map { index, line in
        OCRLine(text: String(line), boundingBox: .zero, confidence: 0.95, lineIndex: index)
    }
    return OCRDocument(lines: lines, rawText: text, averageConfidence: 0.95)
}

private func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
}

private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var components = DateComponents()
    components.calendar = makeCalendar()
    components.timeZone = TimeZone(identifier: "America/Chicago")!
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}
