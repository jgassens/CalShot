import Foundation

struct DetectedDate: Equatable {
    var text: String
    var date: Date
    var duration: TimeInterval
}

struct DataDetectorExtraction: Equatable {
    var dates: [DetectedDate]
    var addresses: [String]
    var urls: [URL]
}

enum DataDetectorExtractor {
    static func extract(from text: String) -> DataDetectorExtraction {
        let types = NSTextCheckingResult.CheckingType.date.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
            | NSTextCheckingResult.CheckingType.link.rawValue
        guard let detector = try? NSDataDetector(types: types) else {
            return DataDetectorExtraction(dates: [], addresses: [], urls: [])
        }

        let range = NSRange(text.startIndex..., in: text)
        var dates: [DetectedDate] = []
        var addresses: [String] = []
        var urls: [URL] = []

        for match in detector.matches(in: text, options: [], range: range) {
            let matchedText = Range(match.range, in: text).map { String(text[$0]) } ?? ""
            if let date = match.date {
                dates.append(DetectedDate(text: matchedText, date: date, duration: match.duration))
            }
            if match.resultType.contains(.address), !matchedText.isEmpty {
                addresses.append(matchedText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if let url = match.url {
                urls.append(url)
            }
        }

        urls = urls.mergingSupplementalWebURLs(from: text)
        return DataDetectorExtraction(dates: dates, addresses: addresses, urls: urls)
    }
}

private extension Array where Element == URL {
    func mergingSupplementalWebURLs(from text: String) -> [URL] {
        var merged = self
        var seen = Set(map(\.absoluteString))
        guard let regex = try? NSRegularExpression(pattern: #"https?://\S+"#, options: [.caseInsensitive]) else {
            return merged
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let value = String(text[swiftRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}<>'\""))
            guard let url = URL(string: value),
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            merged.append(url)
        }

        return merged
    }
}
