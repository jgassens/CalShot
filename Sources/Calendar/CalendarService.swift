import AppKit
import EventKit
import Foundation

enum CalendarServiceError: Error, LocalizedError {
    case permissionDenied
    case noDefaultCalendar
    case noCalendars
    case selectedCalendarUnavailable
    case missingStartDate

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Calendar permission was denied."
        case .noDefaultCalendar:
            return "No default calendar is available."
        case .noCalendars:
            return "No writable calendars are available."
        case .selectedCalendarUnavailable:
            return "The selected calendar is not available."
        case .missingStartDate:
            return "A start date is required before creating an event."
        }
    }
}

enum CalendarSaveOutcome: Equatable {
    case saved
    case exportedICS(URL, reason: String)
}

struct CalendarChoice: Identifiable, Equatable {
    var id: String
    var title: String
    var sourceTitle: String?
    var swatch: CalendarSwatch?
    var isDefault: Bool

    var displayTitle: String {
        var parts = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sourceTitle, !sourceTitle.isEmpty, sourceTitle.localizedCaseInsensitiveCompare(parts) != .orderedSame {
            parts += " (\(sourceTitle))"
        }
        if isDefault {
            parts += " - default"
        }
        return parts
    }
}

struct CalendarSwatch: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

struct CalendarConflict: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarTitle: String
}

protocol EventStoreProviding {
    func requestWriteOnlyAccess() async throws -> Bool
    func requestFullAccess() async throws -> Bool
    var defaultCalendarForNewEvents: EKCalendar? { get }
    func calendarsForEvents() -> [EKCalendar]
    func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]?) -> NSPredicate
    func events(matching predicate: NSPredicate) -> [EKEvent]
    func makeEvent() -> EKEvent
    func save(_ event: EKEvent) throws
}

extension EKEventStore: EventStoreProviding {
    func requestWriteOnlyAccess() async throws -> Bool {
        try await requestWriteOnlyAccessToEvents()
    }

    func requestFullAccess() async throws -> Bool {
        try await requestFullAccessToEvents()
    }

    func calendarsForEvents() -> [EKCalendar] {
        calendars(for: .event)
    }

    func makeEvent() -> EKEvent {
        EKEvent(eventStore: self)
    }

    func save(_ event: EKEvent) throws {
        try save(event, span: .thisEvent, commit: true)
    }
}

final class CalendarService {
    private let store: EventStoreProviding
    private let icsExporter: ICSExporting

    init(store: EventStoreProviding = EKEventStore(), icsExporter: ICSExporting = ICSExporter()) {
        self.store = store
        self.icsExporter = icsExporter
    }

    func loadCalendars() async throws -> [CalendarChoice] {
        guard try await store.requestFullAccess() else {
            throw CalendarServiceError.permissionDenied
        }

        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        let choices = store.calendarsForEvents()
            .map { calendar in
                CalendarChoice(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: Self.cleanSourceTitle(calendar.source?.title),
                    swatch: Self.swatch(from: calendar.cgColor),
                    isDefault: calendar.calendarIdentifier == defaultID
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return (lhs.sourceTitle ?? "").localizedCaseInsensitiveCompare(rhs.sourceTitle ?? "") == .orderedAscending
            }

        guard !choices.isEmpty else {
            throw CalendarServiceError.noCalendars
        }
        return choices
    }

    func conflicts(for draft: EventDraft, calendarID: String?) async throws -> [CalendarConflict] {
        guard let start = draft.start else { return [] }
        guard try await store.requestFullAccess() else {
            throw CalendarServiceError.permissionDenied
        }

        let calendar = calendar(for: calendarID) ?? store.defaultCalendarForNewEvents
        let end = draft.end ?? start.addingTimeInterval(draft.allDay ? 24 * 60 * 60 : 60 * 60)
        let predicate = store.predicateForEvents(
            withStart: start,
            end: max(end, start.addingTimeInterval(60)),
            calendars: calendar.map { [$0] }
        )

        return store.events(matching: predicate)
            .filter { event in
                guard let eventStart = event.startDate, let eventEnd = event.endDate else { return false }
                return eventEnd > start && eventStart < end
            }
            .map { event in
                let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                return CalendarConflict(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: title?.isEmpty == false ? title ?? "Untitled event" : "Untitled event",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar?.title ?? "Calendar"
                )
            }
            .sorted { $0.start < $1.start }
    }

    func saveOrExport(_ draft: EventDraft, calendarID: String? = nil) async -> CalendarSaveOutcome {
        do {
            try await save(draft, calendarID: calendarID)
            return .saved
        } catch {
            do {
                let url = try icsExporter.export(draft)
                try icsExporter.open(url)
                return .exportedICS(url, reason: error.localizedDescription)
            } catch {
                return .exportedICS(URL(fileURLWithPath: "/dev/null"), reason: error.localizedDescription)
            }
        }
    }

    func save(_ draft: EventDraft, calendarID: String? = nil) async throws {
        guard let start = draft.start else {
            throw CalendarServiceError.missingStartDate
        }

        let calendar: EKCalendar
        if let calendarID {
            guard try await store.requestFullAccess() else {
                throw CalendarServiceError.permissionDenied
            }
            guard let selected = self.calendar(for: calendarID) else {
                throw CalendarServiceError.selectedCalendarUnavailable
            }
            calendar = selected
        } else {
            guard try await store.requestWriteOnlyAccess() else {
                throw CalendarServiceError.permissionDenied
            }
            guard let defaultCalendar = store.defaultCalendarForNewEvents else {
                throw CalendarServiceError.noDefaultCalendar
            }
            calendar = defaultCalendar
        }

        let event = store.makeEvent()
        event.calendar = calendar
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Event" : draft.title
        event.startDate = start
        event.endDate = draft.end ?? start.addingTimeInterval(draft.allDay ? 24 * 60 * 60 : 60 * 60)
        event.isAllDay = draft.allDay
        event.timeZone = draft.eventTimeZone
        event.location = draft.location
        event.url = draft.url
        event.notes = draft.notesForCalendarSave
        try store.save(event)
    }

    private func calendar(for calendarID: String?) -> EKCalendar? {
        guard let calendarID else { return nil }
        return store.calendarsForEvents().first { $0.calendarIdentifier == calendarID }
    }

    private static func cleanSourceTitle(_ title: String?) -> String? {
        let cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private static func swatch(from color: CGColor?) -> CalendarSwatch? {
        guard let color, let nsColor = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else {
            return nil
        }

        return CalendarSwatch(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent)
        )
    }
}
