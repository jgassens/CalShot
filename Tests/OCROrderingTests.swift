import CoreGraphics
import XCTest
@testable import CalShot

final class OCROrderingTests: XCTestCase {
    func testOCRLinesSortTopToBottomThenLeftToRight() {
        let candidates = [
            OCRTextCandidate(text: "bottom", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), confidence: 0.9),
            OCRTextCandidate(text: "top right", boundingBox: CGRect(x: 0.6, y: 0.8, width: 0.2, height: 0.1), confidence: 0.9),
            OCRTextCandidate(text: "top left", boundingBox: CGRect(x: 0.1, y: 0.805, width: 0.2, height: 0.1), confidence: 0.9)
        ]

        let lines = OCRLineOrdering.sortedLines(from: candidates)

        XCTAssertEqual(lines.map(\.text), ["top left", "top right", "bottom"])
        XCTAssertEqual(lines.map(\.lineIndex), [0, 1, 2])
    }

    func testVisionBoxConvertsToTopLeftOverlayCoordinates() {
        let box = CGRect(x: 0.25, y: 0.75, width: 0.25, height: 0.1)
        let converted = OCRGeometry.convertVisionBox(
            box,
            imageSize: CGSize(width: 100, height: 100),
            containerSize: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(converted.minX, 75, accuracy: 0.001)
        XCTAssertEqual(converted.minY, 15, accuracy: 0.001)
        XCTAssertEqual(converted.width, 25, accuracy: 0.001)
        XCTAssertEqual(converted.height, 10, accuracy: 0.001)
    }
}
