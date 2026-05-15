import AppKit
import Foundation

@MainActor
final class EventReviewViewModel: ObservableObject {
    let image: NSImage
    let document: OCRDocument
    let calendarService: CalendarService

    @Published var draft: EventDraft
    @Published var statusMessage: String?
    @Published var isSaving = false
    @Published var calendars: [CalendarChoice] = []
    @Published var selectedCalendarID: String?
    @Published var conflicts: [CalendarConflict] = []
    @Published var calendarStatusMessage: String?
    @Published var isLoadingCalendars = false
    @Published var isLoadingConflicts = false

    var closeWindow: (() -> Void)?
    private var didRequestCalendarContext = false
    private var conflictTask: Task<Void, Never>?

    init(image: NSImage, document: OCRDocument, draft: EventDraft, calendarService: CalendarService) {
        self.image = image
        self.document = document
        self.draft = draft
        self.calendarService = calendarService
    }

    var parseConfidenceLabel: String {
        guard !document.lines.isEmpty else { return "No OCR text" }
        return "\(Int(document.averageConfidence * 100))% OCR confidence"
    }

    var selectedCalendarTitle: String {
        selectedCalendarChoice?.displayTitle ?? "Default calendar"
    }

    var selectedCalendarChoice: CalendarChoice? {
        calendars.first { $0.id == selectedCalendarID }
    }

    var selectedCalendarAccountTitle: String? {
        selectedCalendarChoice?.sourceTitle
    }

    var timeZoneChoices: [TimeZoneChoice] {
        TimeZoneChoice.common(including: draft.timeZoneIdentifier)
    }

    var eventTimeSummary: String {
        guard let start = draft.start else {
            return "No start time selected"
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = draft.eventTimeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = draft.allDay ? .none : .short

        if draft.allDay {
            return formatter.string(from: start)
        }

        let end = draft.end ?? start.addingTimeInterval(60 * 60)
        return "\(formatter.string(from: start)) to \(formatter.string(from: end))"
    }

    #if DEBUG
    var smokeSummary: String {
        SmokeSummary.string(for: draft)
    }
    #endif

    func loadCalendarContext() {
        guard !didRequestCalendarContext else { return }
        didRequestCalendarContext = true
        isLoadingCalendars = true
        calendarStatusMessage = nil

        Task { @MainActor in
            do {
                let choices = try await calendarService.loadCalendars()
                calendars = choices
                selectedCalendarID = choices.first { $0.isDefault }?.id ?? choices.first?.id
                isLoadingCalendars = false
                refreshConflicts()
            } catch {
                calendars = []
                selectedCalendarID = nil
                conflicts = []
                isLoadingCalendars = false
                calendarStatusMessage = "Calendar preview needs full calendar access. Create can still fall back to an ICS file."
            }
        }
    }

    func selectCalendar(_ calendarID: String?) {
        selectedCalendarID = calendarID
        markEdited(.calendar)
        refreshConflicts()
    }

    func selectTimeZone(_ identifier: String) {
        draft.timeZoneIdentifier = identifier
        markEdited(.timeZone)
        refreshConflicts()
    }

    func applyAlternative(_ alternative: ParseAlternative) {
        draft.start = alternative.start
        draft.end = alternative.end
        draft.allDay = alternative.allDay
        draft.sources[.start] = alternative.source
        draft.sources[.end] = alternative.source
        draft.sources[.allDay] = alternative.source
        refreshConflicts()
    }

    func markEdited(_ field: EventField) {
        draft.sources[field] = .userEdited
    }

    func draftDateChanged(_ field: EventField) {
        markEdited(field)
        refreshConflicts()
    }

    func refreshConflicts() {
        conflictTask?.cancel()
        guard draft.start != nil, selectedCalendarID != nil else {
            conflicts = []
            isLoadingConflicts = false
            return
        }

        isLoadingConflicts = true
        calendarStatusMessage = nil
        let draft = draft
        let calendarID = selectedCalendarID
        conflictTask = Task { @MainActor in
            do {
                let matches = try await calendarService.conflicts(for: draft, calendarID: calendarID)
                guard !Task.isCancelled else { return }
                conflicts = matches
                isLoadingConflicts = false
            } catch {
                guard !Task.isCancelled else { return }
                conflicts = []
                isLoadingConflicts = false
                calendarStatusMessage = error.localizedDescription
            }
        }
    }

    func createEvent() {
        guard draft.canCreate else { return }
        isSaving = true
        statusMessage = nil

        Task { @MainActor in
            let outcome = await calendarService.saveOrExport(draft, calendarID: selectedCalendarID)
            isSaving = false
            switch outcome {
            case .saved:
                statusMessage = "Created event in \(selectedCalendarTitle)."
                closeWindow?()
            case .exportedICS(let url, let reason):
                statusMessage = "Calendar save fell back to ICS: \(reason). Opened \(url.lastPathComponent)."
            }
        }
    }
}

struct TimeZoneChoice: Identifiable, Equatable {
    var id: String
    var title: String

    static func common(including currentID: String) -> [TimeZoneChoice] {
        let ids = [
            currentID,
            TimeZone.current.identifier,
            "America/New_York",
            "America/Chicago",
            "America/Denver",
            "America/Los_Angeles",
            "America/Phoenix",
            "UTC",
            "Europe/London",
            "Europe/Berlin",
            "Asia/Tokyo"
        ]

        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted, let timeZone = TimeZone(identifier: id) else {
                return nil
            }
            return TimeZoneChoice(id: id, title: title(for: timeZone))
        }
    }

    private static func title(for timeZone: TimeZone) -> String {
        let offset = timeZone.secondsFromGMT() / 60
        let sign = offset >= 0 ? "+" : "-"
        let absolute = abs(offset)
        let hours = absolute / 60
        let minutes = absolute % 60
        return "\(timeZone.identifier) (GMT\(sign)\(String(format: "%02d:%02d", hours, minutes)))"
    }
}
