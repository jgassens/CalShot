import XCTest
@testable import CalShot

final class TextInputTests: XCTestCase {
    func testTextOnlyDocumentPreservesRawTextAndBuildsLines() {
        let document = OCRDocument.textOnly("  Research Roundtable  \n\nMay 9 at 3 PM\nLocation: FO 2.702  ")

        XCTAssertEqual(document.rawText, "  Research Roundtable  \n\nMay 9 at 3 PM\nLocation: FO 2.702  ")
        XCTAssertEqual(document.averageConfidence, 1)
        XCTAssertEqual(document.lines.map(\.text), ["Research Roundtable", "May 9 at 3 PM", "Location: FO 2.702"])
    }

    func testSelectedTextCanProduceCreatableDraft() {
        let calendar = Calendar(identifier: .gregorian)
        let draft = EventDraftMerger(calendar: calendar).makeDraft(
            from: OCRDocument.textOnly("Microglia Seminar\nMay 9 at 3 PM\nWhere: FO 2.702"),
            referenceDate: Date(timeIntervalSince1970: 1_767_225_600)
        )

        XCTAssertEqual(draft.title, "Microglia Seminar")
        XCTAssertEqual(draft.location, "FO 2.702")
        XCTAssertTrue(draft.canCreate)
        XCTAssertFalse(draft.allDay)
    }
}
