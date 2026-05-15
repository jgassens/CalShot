import AppKit
import Foundation

protocol ICSExporting {
    func export(_ draft: EventDraft) throws -> URL
    func open(_ url: URL) throws
}

enum ICSError: Error, LocalizedError {
    case missingStartDate

    var errorDescription: String? {
        switch self {
        case .missingStartDate:
            return "A start date is required before exporting an ICS file."
        }
    }
}

struct ICSExporter: ICSExporting {
    var fileManager: FileManager = .default
    var calendar: Calendar = .current

    func export(_ draft: EventDraft) throws -> URL {
        guard let start = draft.start else {
            throw ICSError.missingStartDate
        }

        let directory = fileManager.temporaryDirectory.appendingPathComponent("CalShot", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = safeFileName(draft.title.isEmpty ? "CalShot Event" : draft.title)
        let url = directory.appendingPathComponent("\(fileName)-\(UUID().uuidString).ics")
        try icsString(for: draft, start: start).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func open(_ url: URL) throws {
        NSWorkspace.shared.open(url)
    }

    func icsString(for draft: EventDraft, start: Date) -> String {
        let end = draft.end ?? start.addingTimeInterval(draft.allDay ? 24 * 60 * 60 : 60 * 60)
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//CalShot//CalShot 0.1//EN",
            "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            "UID:\(UUID().uuidString)@calshot.local",
            "DTSTAMP:\(Self.utcFormatter.string(from: Date()))",
            "SUMMARY:\(escapeText(draft.title.isEmpty ? "Untitled Event" : draft.title))"
        ]

        if draft.allDay {
            let allDayStart = calendar.startOfDay(for: start)
            let allDayEnd = calendar.date(byAdding: .day, value: 1, to: allDayStart) ?? end
            lines.append("DTSTART;VALUE=DATE:\(Self.dateFormatter.string(from: allDayStart))")
            lines.append("DTEND;VALUE=DATE:\(Self.dateFormatter.string(from: allDayEnd))")
        } else {
            lines.append("DTSTART:\(Self.utcFormatter.string(from: start))")
            lines.append("DTEND:\(Self.utcFormatter.string(from: end))")
        }

        if let location = draft.location, !location.isEmpty {
            lines.append("LOCATION:\(escapeText(location))")
        }
        if let url = draft.url {
            lines.append("URL:\(url.absoluteString)")
        }
        let notes = draft.notesForCalendarSave
        if !notes.isEmpty {
            lines.append("DESCRIPTION:\(escapeText(notes))")
        }

        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        return lines.map(foldLine).joined(separator: "\r\n") + "\r\n"
    }

    private func escapeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func foldLine(_ line: String) -> String {
        guard line.count > 75 else { return line }
        var result = ""
        var current = ""
        for character in line {
            if current.count >= 75 {
                result += current + "\r\n "
                current = ""
            }
            current.append(character)
        }
        return result + current
    }

    private func safeFileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "CalShot Event" : trimmed).prefix(48))
    }

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
