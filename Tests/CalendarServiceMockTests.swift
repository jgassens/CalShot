import EventKit
import XCTest
@testable import CalShot

final class CalendarServiceMockTests: XCTestCase {
    func testPermissionDeniedExportsICSFallback() async {
        let service = CalendarService(
            store: MockEventStore(writeAccess: false),
            icsExporter: MockICSExporter()
        )
        let outcome = await service.saveOrExport(sampleDraft())

        guard case .exportedICS(_, let reason) = outcome else {
            return XCTFail("Expected ICS fallback")
        }
        XCTAssertTrue(reason.contains("denied"))
    }

    func testSelectedCalendarRequiresFullAccessAndSavesThere() async throws {
        let store = MockEventStore(writeAccess: true, fullAccess: true)
        let service = CalendarService(store: store, icsExporter: MockICSExporter())
        let calendarID = store.defaultCalendarForNewEvents?.calendarIdentifier

        try await service.save(sampleDraft(), calendarID: calendarID)

        XCTAssertTrue(store.didRequestFullAccess)
        XCTAssertEqual(store.savedEvent?.calendar?.title, "Work")
    }

    func testFullAccessDeniedExportsICSForSelectedCalendar() async {
        let store = MockEventStore(writeAccess: true, fullAccess: false)
        let service = CalendarService(store: store, icsExporter: MockICSExporter())
        let outcome = await service.saveOrExport(sampleDraft(), calendarID: "work")

        guard case .exportedICS(_, let reason) = outcome else {
            return XCTFail("Expected ICS fallback")
        }
        XCTAssertTrue(reason.contains("denied"))
    }

    func testTeamsMeetingRequestIsAddedToSavedNotes() async throws {
        let store = MockEventStore(writeAccess: true)
        let service = CalendarService(store: store, icsExporter: MockICSExporter())
        var draft = sampleDraft()
        draft.notes = "Bring slides."
        draft.createTeamsMeeting = true

        try await service.save(draft)

        XCTAssertEqual(store.savedEvent?.notes, "Bring slides.\n\nTeams meeting requested.")
    }

    func testTimeZoneIsAppliedToSavedEvent() async throws {
        let store = MockEventStore(writeAccess: true)
        let service = CalendarService(store: store, icsExporter: MockICSExporter())
        var draft = sampleDraft()
        draft.timeZoneIdentifier = "America/Los_Angeles"

        try await service.save(draft)

        XCTAssertEqual(store.savedEvent?.timeZone?.identifier, "America/Los_Angeles")
    }

    func testConflictsReturnsOverlappingEvents() async throws {
        let store = MockEventStore(writeAccess: true, fullAccess: true)
        let existing = EKEvent(eventStore: store.backingStore)
        existing.title = "Already booked"
        existing.startDate = Date(timeIntervalSince1970: 1_780_000_900)
        existing.endDate = Date(timeIntervalSince1970: 1_780_001_800)
        existing.calendar = store.defaultCalendarForNewEvents
        store.mockEvents = [existing]

        let service = CalendarService(store: store, icsExporter: MockICSExporter())
        let conflicts = try await service.conflicts(for: sampleDraft(), calendarID: store.defaultCalendarForNewEvents?.calendarIdentifier)

        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.title, "Already booked")
        XCTAssertEqual(conflicts.first?.calendarTitle, "Work")
    }
}

private final class MockEventStore: EventStoreProviding {
    let backingStore = EKEventStore()
    var writeAccess: Bool
    var fullAccess: Bool
    var didRequestFullAccess = false
    var didRequestWriteOnlyAccess = false
    var defaultCalendarForNewEvents: EKCalendar?
    var calendars: [EKCalendar]
    var mockEvents: [EKEvent] = []
    var savedEvent: EKEvent?

    init(writeAccess: Bool, fullAccess: Bool = true) {
        self.writeAccess = writeAccess
        self.fullAccess = fullAccess
        let calendar = EKCalendar(for: .event, eventStore: backingStore)
        calendar.title = "Work"
        self.defaultCalendarForNewEvents = calendar
        self.calendars = [calendar]
    }

    func requestWriteOnlyAccess() async throws -> Bool {
        didRequestWriteOnlyAccess = true
        return writeAccess
    }

    func requestFullAccess() async throws -> Bool {
        didRequestFullAccess = true
        return fullAccess
    }

    func calendarsForEvents() -> [EKCalendar] {
        calendars
    }

    func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]?) -> NSPredicate {
        NSPredicate(value: true)
    }

    func events(matching predicate: NSPredicate) -> [EKEvent] {
        mockEvents
    }

    func makeEvent() -> EKEvent {
        EKEvent(eventStore: backingStore)
    }

    func save(_ event: EKEvent) throws {
        savedEvent = event
    }
}

private struct MockICSExporter: ICSExporting {
    func export(_ draft: EventDraft) throws -> URL {
        URL(fileURLWithPath: "/tmp/calshot-test.ics")
    }

    func open(_ url: URL) throws {}
}

private func sampleDraft() -> EventDraft {
    EventDraft(
        title: "Sample",
        start: Date(timeIntervalSince1970: 1_780_000_000),
        end: Date(timeIntervalSince1970: 1_780_003_600),
        allDay: false,
        location: nil,
        url: nil,
        notes: "",
        alternatives: [],
        sources: [:]
    )
}
