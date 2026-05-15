import Foundation

enum EventField: Hashable {
    case title
    case start
    case end
    case allDay
    case timeZone
    case calendar
    case teamsMeeting
    case location
    case url
    case notes
}

enum FieldSource: Equatable {
    case chrono(text: String, confidence: Double)
    case dataDetector(text: String)
    case naturalLanguage(text: String)
    case heuristic(label: String, text: String)
    case userEdited
}

struct ParseAlternative: Identifiable, Equatable {
    let id = UUID()
    var label: String
    var start: Date
    var end: Date?
    var allDay: Bool
    var source: FieldSource
}

struct EventDraft: Equatable {
    var title: String
    var start: Date?
    var end: Date?
    var allDay: Bool
    var timeZoneIdentifier: String
    var createTeamsMeeting: Bool
    var location: String?
    var url: URL?
    var notes: String
    var alternatives: [ParseAlternative]
    var sources: [EventField: FieldSource]

    init(
        title: String,
        start: Date?,
        end: Date?,
        allDay: Bool,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        createTeamsMeeting: Bool = false,
        location: String?,
        url: URL?,
        notes: String,
        alternatives: [ParseAlternative],
        sources: [EventField: FieldSource]
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createTeamsMeeting = createTeamsMeeting
        self.location = location
        self.url = url
        self.notes = notes
        self.alternatives = alternatives
        self.sources = sources
    }

    var canCreate: Bool {
        start != nil
    }

    var eventTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    var notesForCalendarSave: String {
        guard createTeamsMeeting else { return notes }

        let teamsLine = "Teams meeting requested."
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.localizedCaseInsensitiveContains(teamsLine) else {
            return notes
        }
        return trimmed.isEmpty ? teamsLine : "\(trimmed)\n\n\(teamsLine)"
    }

    static func empty(notes: String = "") -> EventDraft {
        EventDraft(
            title: "Untitled Event",
            start: nil,
            end: nil,
            allDay: false,
            timeZoneIdentifier: TimeZone.current.identifier,
            createTeamsMeeting: false,
            location: nil,
            url: nil,
            notes: notes,
            alternatives: [],
            sources: [:]
        )
    }
}
