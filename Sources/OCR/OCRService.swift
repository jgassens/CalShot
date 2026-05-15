@preconcurrency import Vision
import AppKit
import Foundation

enum OCRError: Error, LocalizedError {
    case noCGImage

    var errorDescription: String? {
        switch self {
        case .noCGImage:
            return "CalShot could not read image data from that file."
        }
    }
}

enum OCRService {
    static func recognizeDocument(in image: NSImage) async throws -> OCRDocument {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.noCGImage
        }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let candidates = (request.results ?? [])
                .compactMap { observation -> OCRTextCandidate? in
                    guard let best = observation.topCandidates(1).first else { return nil }
                    let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return OCRTextCandidate(text: text, boundingBox: observation.boundingBox, confidence: best.confidence)
                }

            let lines = OCRLineOrdering.sortedLines(from: candidates)
            let average = lines.isEmpty ? 0 : lines.map(\.confidence).reduce(0, +) / Float(lines.count)
            return OCRDocument(lines: lines, rawText: lines.map(\.text).joined(separator: "\n"), averageConfidence: average)
        }.value
    }
}
