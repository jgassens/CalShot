import Foundation

#if DEBUG
enum SmokeSummary {
    static func string(for draft: EventDraft) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return [
            "title=\(draft.title)",
            "allDay=\(draft.allDay)",
            "start=\(draft.start.map { formatter.string(from: $0) } ?? "nil")",
            "end=\(draft.end.map { formatter.string(from: $0) } ?? "nil")",
            "location=\(draft.location ?? "nil")",
            "url=\(draft.url?.absoluteString ?? "nil")",
            "canCreate=\(draft.canCreate)"
        ].joined(separator: " | ")
    }

    static func write(_ draft: EventDraft, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try string(for: draft).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[CalShot Smoke] Could not write smoke summary: \(error.localizedDescription)")
        }
    }
}
#endif
