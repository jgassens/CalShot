import CoreGraphics
import Foundation

struct OCRLine: Equatable {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    let lineIndex: Int
}

struct OCRDocument: Equatable {
    let lines: [OCRLine]
    let rawText: String
    let averageConfidence: Float

    var isLowConfidence: Bool {
        averageConfidence < 0.65
    }

    static let empty = OCRDocument(lines: [], rawText: "", averageConfidence: 0)

    static func textOnly(_ text: String) -> OCRDocument {
        let lines = text
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { index, line -> OCRLine? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return OCRLine(
                    text: trimmed,
                    boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0),
                    confidence: 1,
                    lineIndex: index
                )
            }

        return OCRDocument(lines: lines, rawText: text, averageConfidence: lines.isEmpty ? 0 : 1)
    }
}

struct OCRTextCandidate {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

enum OCRLineOrdering {
    static func sortedLines(from candidates: [OCRTextCandidate]) -> [OCRLine] {
        candidates
            .sorted { lhs, rhs in
                let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if yDelta > 0.015 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .enumerated()
            .map { index, candidate in
                OCRLine(
                    text: candidate.text,
                    boundingBox: candidate.boundingBox,
                    confidence: candidate.confidence,
                    lineIndex: index
                )
            }
    }
}

enum OCRGeometry {
    static func imageRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let rendered = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - rendered.width) / 2,
            y: (containerSize.height - rendered.height) / 2,
            width: rendered.width,
            height: rendered.height
        )
    }

    static func convertVisionBox(_ box: CGRect, imageSize: CGSize, containerSize: CGSize) -> CGRect {
        let rect = imageRect(for: imageSize, in: containerSize)
        guard rect != .zero else { return .zero }
        return CGRect(
            x: rect.minX + box.minX * rect.width,
            y: rect.minY + (1 - box.maxY) * rect.height,
            width: box.width * rect.width,
            height: box.height * rect.height
        )
    }
}
