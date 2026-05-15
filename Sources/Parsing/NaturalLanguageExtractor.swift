import Foundation
import NaturalLanguage

enum NaturalLanguageExtractor {
    static func placeCandidates(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var candidates: [String] = []

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard tag == .placeName || tag == .organizationName else { return true }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 3, !candidates.contains(value) {
                candidates.append(value)
            }
            return true
        }

        return candidates
    }
}

