import Foundation

struct LocationExtraction: Equatable {
    var value: String
    var source: FieldSource
}

enum LocationExtractor {
    private static let cueLabels = ["location", "where", "venue", "room", "building"]

    static func extract(from text: String, detectorExtraction: DataDetectorExtraction) -> LocationExtraction? {
        if let address = detectorExtraction.addresses.first, !address.isEmpty {
            return LocationExtraction(value: address, source: .dataDetector(text: address))
        }

        if let cue = cueLocation(from: text) {
            return cue
        }

        if let inlineRoomCodes = inlineRoomCodes(from: text) {
            return inlineRoomCodes
        }

        if let place = NaturalLanguageExtractor.placeCandidates(from: text).first(where: { isPlausibleSoftPlace($0, in: text) }) {
            return LocationExtraction(value: place, source: .naturalLanguage(text: place))
        }

        return nil
    }

    private static func cueLocation(from text: String) -> LocationExtraction? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let label = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard cueLabels.contains(label) else { continue }

                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard isAcceptableCueValue(value) else { continue }
                return LocationExtraction(value: value, source: .heuristic(label: label, text: value))
            }

            guard let labeledValue = whitespaceCueLocation(from: line) else { continue }
            return labeledValue
        }

        return nil
    }

    private static func whitespaceCueLocation(from line: String) -> LocationExtraction? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let labelRange = trimmedLine.range(
            of: #"(?i)^(location|where|venue|room|building)\b"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let label = String(trimmedLine[labelRange]).lowercased()
        var value = String(trimmedLine[labelRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["is ", "at "] where value.lowercased().hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard isAcceptableCueValue(value), looksLikeLocationCueValue(value, label: label) else {
            return nil
        }

        return LocationExtraction(value: value, source: .heuristic(label: label, text: value))
    }

    private static func inlineRoomCodes(from text: String) -> LocationExtraction? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines where !line.isEmpty {
            let roomCodes = roomCodeMatches(in: line)
            guard !roomCodes.isEmpty, hasInlineRoomContext(in: line, roomCodes: roomCodes) else {
                continue
            }

            let value = deduplicatedValues(roomCodes.map(\.value)).joined(separator: ", ")
            guard isAcceptableCueValue(value) else { continue }
            return LocationExtraction(value: value, source: .heuristic(label: "inline room codes", text: value))
        }

        return nil
    }

    private static func deduplicatedValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func roomCodeMatches(in line: String) -> [(value: String, range: Range<String.Index>)] {
        let pattern = #"\b[A-Z]{2,8}\s+\d{1,4}(?:\.\d{1,4})?[A-Z]?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: line) else { return nil }
            let value = line[range]
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return (value: value, range: range)
        }
    }

    private static func hasInlineRoomContext(
        in line: String,
        roomCodes: [(value: String, range: Range<String.Index>)]
    ) -> Bool {
        guard let firstRange = roomCodes.first?.range else { return false }
        let lower = line.lowercased()
        if lower.contains("room") || lower.contains("rooms") {
            return true
        }

        if roomCodes.count > 1, line.contains(",") || lower.contains(" and ") {
            return true
        }

        let prefix = line[..<firstRange.lowerBound]
            .suffix(24)
            .lowercased()
        return prefix.hasSuffix(" in ")
            || prefix.hasSuffix(" at ")
            || prefix.hasSuffix(" inside ")
            || prefix.hasSuffix(" for ")
            || prefix.trimmingCharacters(in: .whitespacesAndNewlines) == "in"
            || prefix.trimmingCharacters(in: .whitespacesAndNewlines) == "at"
    }

    private static func isAcceptableCueValue(_ value: String) -> Bool {
        value.count >= 2 && value.count <= 120
    }

    private static func looksLikeLocationCueValue(_ value: String, label: String) -> Bool {
        let lower = value.lowercased()
        let timeOnlyPattern = #"(?i)^(at\s+)?\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)$"#
        if lower.range(of: timeOnlyPattern, options: .regularExpression) != nil {
            return false
        }

        let hasDigit = value.rangeOfCharacter(from: .decimalDigits) != nil
        let hasRoomPunctuation = value.contains(".") || value.contains("-") || value.contains(",")
        let hasAddressWord = [
            "street", "st.", "st ", "avenue", "ave", "road", "rd.", "boulevard", "blvd",
            "drive", "dr.", "parkway", "pkwy", "suite", "ste", "room", "hall", "center",
            "building", "campus", "theater", "theatre", "auditorium"
        ].contains { lower.contains($0) }
        let hasUppercaseCode = value.split { !$0.isLetter && !$0.isNumber }.contains { token in
            token.count <= 8 && token.contains { $0.isUppercase }
        }

        if label == "room" || label == "building" {
            return hasDigit || hasRoomPunctuation || hasUppercaseCode || hasAddressWord
        }

        return hasDigit || hasRoomPunctuation || hasAddressWord
    }

    private static func isPlausibleSoftPlace(_ candidate: String, in text: String) -> Bool {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let candidateLower = candidate.lowercased()

        guard let line = lines.first(where: { $0.lowercased().contains(candidateLower) }) else {
            return true
        }

        let lower = line.lowercased()
        let timeZonePhrases = ["my time", "your time", "their time", "time zone", "timezone"]
        if timeZonePhrases.contains(where: { lower.contains($0) }) {
            return false
        }

        let dateOrTimePattern = #"(?i)\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|am|pm|a\.m\.|p\.m\.)\b|\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#
        if lower.range(of: dateOrTimePattern, options: .regularExpression) != nil {
            return false
        }

        return true
    }
}
