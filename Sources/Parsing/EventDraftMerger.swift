import Foundation

final class EventDraftMerger {
    private let chrono: ChronoParsing
    private let calendar: Calendar

    init(chrono: ChronoParsing = ChronoBridge.shared, calendar: Calendar = .current) {
        self.chrono = chrono
        self.calendar = calendar
    }

    func makeDraft(from document: OCRDocument, referenceDate: Date = Date(), timeZone: TimeZone = .current) -> EventDraft {
        let text = document.rawText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty(notes: "")
        }

        let chronoCandidates = chrono.parse(text: text, referenceDate: referenceDate, timeZone: timeZone)
        let detector = DataDetectorExtractor.extract(from: text)
        let location = LocationExtractor.extract(from: text, detectorExtraction: detector)
        let url = eventURL(from: detector.urls, in: text)

        var draft = EventDraft.empty(notes: text)
        let selectedDate = selectedDraftDate(from: chronoCandidates)
            ?? detector.dates.first.map { detectorDate(from: $0) }

        if let selectedDate {
            draft.start = selectedDate.start
            draft.end = selectedDate.end
            draft.allDay = selectedDate.allDay
            draft.sources[.start] = selectedDate.source
            draft.sources[.end] = selectedDate.source
            draft.sources[.allDay] = selectedDate.source
        }

        draft.alternatives = alternatives(from: chronoCandidates)

        if let location {
            draft.location = location.value
            draft.sources[.location] = location.source
        }

        if let url {
            draft.url = url
            draft.sources[.url] = .dataDetector(text: url.absoluteString)
        }

        draft.title = title(from: document.lines, excluding: [selectedDate?.matchedText, location?.value, url?.absoluteString])
        draft.sources[.title] = .heuristic(label: "prominent line", text: draft.title)

        if document.isLowConfidence {
            draft.notes = "Low OCR confidence. Please review carefully.\n\n\(text)"
        }

        return draft
    }

    private func selectedDraftDate(from candidates: [ChronoParseCandidate]) -> DraftDate? {
        if let composite = dateWithNearbyTime(from: candidates) {
            return composite
        }

        return candidates
            .filter { $0.hasCertainDate }
            .max { score(for: $0) < score(for: $1) }
            .map { draftDate(from: $0) }
    }

    private func eventURL(from urls: [URL], in text: String) -> URL? {
        let webURLs = urls.enumerated().compactMap { index, url -> EventURLCandidate? in
            guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
                return nil
            }
            return EventURLCandidate(
                url: url,
                score: score(eventURL: url, in: text),
                index: index
            )
        }

        guard !webURLs.isEmpty else { return urls.first }
        return webURLs.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.index < rhs.index
            }
            return lhs.score > rhs.score
        }.first?.url
    }

    private func score(eventURL url: URL, in text: String) -> Int {
        let absolute = url.absoluteString.lowercased()
        let decoded = url.absoluteString.removingPercentEncoding?.lowercased() ?? absolute
        let host = url.host?.lowercased() ?? ""
        let pathAndQuery = ([url.path, url.query ?? ""] + [decoded]).joined(separator: " ").lowercased()
        let context = urlContext(for: url, in: text)
        let lineContext = urlLineContext(for: url, in: text)
        let urlOnly = [absolute, decoded, host, pathAndQuery].joined(separator: " ")
        let combined = [urlOnly, context].joined(separator: " ")

        var score = 0

        if containsAny(urlOnly, [
            "teams.microsoft.com",
            "events.teams.microsoft.com",
            "teams.live.com",
            "meet.google.com",
            "zoom.us/",
            "zoomgov.com/",
            "webex.com",
            "gotomeeting.com",
            "global.gotomeeting.com",
            "bluejeans.com",
            "whereby.com",
            "ringcentral.com",
            "chime.aws",
            "8x8.vc"
        ]) {
            score += 120
        }

        if containsAny(combined, [
            "teams",
            "zoom",
            "google meet",
            "meet.google",
            "webex",
            "teleconference",
            "video conference",
            "videoconference",
            "webinar",
            "join meeting",
            "join event",
            "join here",
            "join link"
        ]) {
            score += 60
        }

        if containsAny(pathAndQuery, [
            "/meetup-join",
            "/meet/",
            "/j/",
            "/wc/join",
            "/join/",
            "/webinar/",
            "meeting",
            "webinar",
            "teleconference"
        ]) {
            score += 35
        }

        if containsAny(context, ["join", "attend", "dial", "call in", "call-in", "webinar", "meeting"]) {
            score += 25
        }

        if containsAny([urlOnly, lineContext].joined(separator: " "), [
            "unsubscribe",
            "subscribe",
            "signoff",
            "preferences",
            "listinfo",
            "mailman",
            "sympa/",
            "/help",
            "/privacy",
            "/terms",
            "/archive",
            "view in browser",
            "viewonline",
            "tracking"
        ]) {
            score -= 80
        }

        return score
    }

    private func urlContext(for url: URL, in text: String) -> String {
        let lowerText = text.lowercased()
        let candidates = [
            url.absoluteString.lowercased(),
            url.absoluteString.removingPercentEncoding?.lowercased()
        ].compactMap { $0 }

        for candidate in candidates where !candidate.isEmpty {
            guard let range = lowerText.range(of: candidate) else { continue }
            let start = lowerText.index(range.lowerBound, offsetBy: -300, limitedBy: lowerText.startIndex) ?? lowerText.startIndex
            let end = lowerText.index(range.upperBound, offsetBy: 300, limitedBy: lowerText.endIndex) ?? lowerText.endIndex
            return String(lowerText[start..<end])
        }

        return ""
    }

    private func urlLineContext(for url: URL, in text: String) -> String {
        let lowerText = text.lowercased()
        let candidates = [
            url.absoluteString.lowercased(),
            url.absoluteString.removingPercentEncoding?.lowercased()
        ].compactMap { $0 }

        for candidate in candidates where !candidate.isEmpty {
            guard let range = lowerText.range(of: candidate) else { continue }
            let lineStart = lowerText[..<range.lowerBound].lastIndex(of: "\n").map { lowerText.index(after: $0) } ?? lowerText.startIndex
            let lineEnd = lowerText[range.upperBound...].firstIndex(of: "\n") ?? lowerText.endIndex
            return String(lowerText[lineStart..<lineEnd])
        }

        return ""
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func dateWithNearbyTime(from candidates: [ChronoParseCandidate]) -> DraftDate? {
        for dateCandidate in candidates where dateCandidate.hasCertainDate && !dateCandidate.hasCertainStartTime {
            let dateRangeEnd = dateCandidate.index + dateCandidate.length
            let timeCandidates = candidates
                .filter { candidate in
                    candidate.index >= dateRangeEnd
                        && candidate.index - dateRangeEnd <= 180
                        && candidate.hasCertainStartTime
                        && !candidate.hasCertainDate
                }
                .sorted { $0.index < $1.index }

            guard let timeCandidate = timeCandidates.first,
                  let start = combine(dateCandidate: dateCandidate, timeCandidate: timeCandidate) else {
                continue
            }

            let sourceText = "\(dateCandidate.matchedText) + \(timeCandidate.matchedText)"
            return DraftDate(
                start: start,
                end: combinedEnd(for: timeCandidate, start: start),
                allDay: false,
                matchedText: sourceText,
                source: .chrono(text: sourceText, confidence: 0.82)
            )
        }

        return nil
    }

    private func combine(dateCandidate: ChronoParseCandidate, timeCandidate: ChronoParseCandidate) -> Date? {
        guard let hour = timeCandidate.startComponents.values["hour"] else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: dateCandidate.startDate)
        components.hour = hour
        components.minute = timeCandidate.startComponents.values["minute"] ?? 0
        components.second = timeCandidate.startComponents.values["second"] ?? 0
        return calendar.date(from: components)
    }

    private func combinedEnd(for timeCandidate: ChronoParseCandidate, start: Date) -> Date {
        guard let endComponents = timeCandidate.endComponents,
              timeCandidate.hasCertainEndTime,
              let hour = endComponents.values["hour"] else {
            return start.addingTimeInterval(60 * 60)
        }

        var components = calendar.dateComponents([.year, .month, .day], from: start)
        components.hour = hour
        components.minute = endComponents.values["minute"] ?? 0
        components.second = endComponents.values["second"] ?? 0

        guard let end = calendar.date(from: components), end > start else {
            return start.addingTimeInterval(60 * 60)
        }
        return end
    }

    private func alternatives(from candidates: [ChronoParseCandidate]) -> [ParseAlternative] {
        var alternatives = candidates
            .filter { $0.hasCertainDate || $0.hasCertainStartTime }
            .map { candidate in
                let date = draftDate(from: candidate)
                return ParseAlternative(
                    label: candidate.matchedText,
                    start: date.start,
                    end: date.end,
                    allDay: date.allDay,
                    source: date.source
                )
            }

        alternatives.append(contentsOf: compositeAlternatives(from: candidates))
        return alternatives
    }

    private func compositeAlternatives(from candidates: [ChronoParseCandidate]) -> [ParseAlternative] {
        var alternatives: [ParseAlternative] = []

        for dateCandidate in candidates where dateCandidate.hasCertainDate && !dateCandidate.hasCertainStartTime {
            let dateRangeEnd = dateCandidate.index + dateCandidate.length
            let timeCandidates = candidates
                .filter { candidate in
                    candidate.index >= dateRangeEnd
                        && candidate.index - dateRangeEnd <= 180
                        && candidate.hasCertainStartTime
                        && !candidate.hasCertainDate
                }
                .sorted { $0.index < $1.index }

            for timeCandidate in timeCandidates {
                guard let start = combine(dateCandidate: dateCandidate, timeCandidate: timeCandidate) else { continue }
                let label = "\(dateCandidate.matchedText) + \(timeCandidate.matchedText)"
                let source = FieldSource.chrono(text: label, confidence: 0.78)
                alternatives.append(ParseAlternative(
                    label: label,
                    start: start,
                    end: combinedEnd(for: timeCandidate, start: start),
                    allDay: false,
                    source: source
                ))
            }
        }

        return alternatives
    }

    private func draftDate(from candidate: ChronoParseCandidate) -> DraftDate {
        let source = FieldSource.chrono(text: candidate.matchedText, confidence: confidence(for: candidate))
        let isAllDay = candidate.hasCertainDate && !candidate.hasCertainStartTime && candidate.endDate == nil

        if isAllDay {
            let start = calendar.startOfDay(for: candidate.startDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
            return DraftDate(start: start, end: end, allDay: true, matchedText: candidate.matchedText, source: source)
        }

        let start = candidate.startDate
        let end = normalizedEnd(for: candidate, start: start)
        return DraftDate(start: start, end: end, allDay: false, matchedText: candidate.matchedText, source: source)
    }

    private func normalizedEnd(for candidate: ChronoParseCandidate, start: Date) -> Date {
        guard let endDate = candidate.endDate else {
            return start.addingTimeInterval(60 * 60)
        }

        let duration = endDate.timeIntervalSince(start)
        guard duration > 18 * 60 * 60,
              let endComponents = candidate.endComponents,
              candidate.hasCertainEndTime,
              !endComponents.isCertain("year"),
              !endComponents.isCertain("month"),
              !endComponents.isCertain("day") else {
            return endDate
        }

        var sameDay = calendar.dateComponents([.year, .month, .day], from: start)
        sameDay.hour = endComponents.values["hour"]
        sameDay.minute = endComponents.values["minute"] ?? 0
        sameDay.second = endComponents.values["second"] ?? 0

        guard let sameDayEnd = calendar.date(from: sameDay), sameDayEnd > start else {
            return endDate
        }
        return sameDayEnd
    }

    private func detectorDate(from detected: DetectedDate) -> DraftDate {
        let duration = detected.duration > 0 ? detected.duration : 60 * 60
        return DraftDate(
            start: detected.date,
            end: detected.date.addingTimeInterval(duration),
            allDay: false,
            matchedText: detected.text,
            source: .dataDetector(text: detected.text)
        )
    }

    private func confidence(for candidate: ChronoParseCandidate) -> Double {
        var score = 0.55
        if candidate.hasCertainDate { score += 0.25 }
        if candidate.hasCertainStartTime { score += 0.15 }
        if candidate.endDate != nil { score += 0.05 }
        return min(score, 0.98)
    }

    private func score(for candidate: ChronoParseCandidate) -> Double {
        var score = confidence(for: candidate)
        if candidate.hasCertainDate && candidate.hasCertainStartTime {
            score += 0.35
        }
        if !candidate.hasCertainStartTime {
            score -= 0.05
        }
        return score
    }

    private func title(from lines: [OCRLine], excluding values: [String?]) -> String {
        let exclusions = values
            .flatMap { value in value?.components(separatedBy: .newlines) ?? [] }
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidates: [TitleCandidate] = []
        for line in lines {
            var value = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            for exclusion in exclusions {
                value = value.replacingOccurrences(of: exclusion, with: "", options: .caseInsensitive)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t,.-:;|"))
            guard value.count >= 3, value.count <= 90 else { continue }
            guard !looksLikeNonTitle(value) else { continue }
            candidates.append(TitleCandidate(text: value, lineIndex: line.lineIndex))
        }

        guard let first = candidates.first else { return "Untitled Event" }

        var fragments = [first]
        for candidate in candidates.dropFirst() {
            guard let previous = fragments.last else { break }
            guard candidate.lineIndex == previous.lineIndex + 1 else { break }
            guard fragments.count < 3, looksLikeTitleContinuation(candidate.text) else { break }
            let joined = (fragments.map(\.text) + [candidate.text]).joined(separator: " ")
            guard joined.count <= 120 else { break }
            fragments.append(candidate)
        }

        return fragments.map(\.text).joined(separator: " ")
    }

    private func looksLikeNonTitle(_ value: String) -> Bool {
        if looksLikeDateOnly(value) { return true }
        if containsLikelyTime(value) { return true }
        if looksLikeAddress(value) { return true }

        let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let exactBoilerplate = [
            "calendar invitation",
            "event invitation",
            "invitation",
            "agenda",
            "details"
        ]
        if exactBoilerplate.contains(lower) { return true }

        let labelPrefixes = [
            "from:",
            "to:",
            "when:",
            "where:",
            "join link:",
            "zoom:",
            "location:",
            "venue:"
        ]
        if labelPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }

        let dateWords = [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december"
        ]
        return value.rangeOfCharacter(from: .decimalDigits) != nil && dateWords.contains { lower.contains($0) }
    }

    private func looksLikeDateOnly(_ value: String) -> Bool {
        if value.rangeOfCharacter(from: .letters) == nil, value.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }
        let lower = value.lowercased()
        return ["am", "pm", "today", "tomorrow"].contains { lower == $0 || lower.hasPrefix("\($0) ") }
    }

    private func looksLikeTitleContinuation(_ value: String) -> Bool {
        guard !value.contains(":") else { return false }
        guard !containsLikelyTime(value), !looksLikeAddress(value) else { return false }

        let words = value.split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return false }

        let capitalizedWords = words.filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase || word.allSatisfy { $0.isUppercase || $0.isNumber }
        }

        return capitalizedWords.count >= 2 && Double(capitalizedWords.count) / Double(words.count) >= 0.5
    }

    private func containsLikelyTime(_ value: String) -> Bool {
        let pattern = #"(?i)\b\d{1,2}(:\d{2})?\s*(a\.?m\.?|p\.?m\.?)\b|\b\d{1,2}\s*(to|-|–)\s*\d{1,2}(:\d{2})?\b"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func looksLikeAddress(_ value: String) -> Bool {
        let lower = value.lowercased()
        let streetWords = ["street", "st.", "road", "rd.", "avenue", "ave", "blvd", "boulevard", "suite", "ste."]
        return value.range(of: #"^\d{2,}\b"#, options: .regularExpression) != nil
            && streetWords.contains { lower.contains($0) }
    }
}

private struct TitleCandidate {
    var text: String
    var lineIndex: Int
}

private struct EventURLCandidate {
    var url: URL
    var score: Int
    var index: Int
}

private struct DraftDate {
    var start: Date
    var end: Date
    var allDay: Bool
    var matchedText: String
    var source: FieldSource
}
