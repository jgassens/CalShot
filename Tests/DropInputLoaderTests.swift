import AppKit
import XCTest
@testable import CalShot

final class DropInputLoaderTests: XCTestCase {
    func testLoadsEmailFileURLFromPasteboard() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalShotDropInputLoaderTests-\(UUID().uuidString)")
            .appendingPathExtension("eml")
        try "Subject: Drop Test\n\nMay 20 at 3 PM".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CalShotDropInputLoaderTests.email.\(UUID().uuidString)"))
        pasteboard.clearContents()

        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))
        XCTAssertTrue(DropInputLoader.canLoad(from: pasteboard))

        guard case .emailFile(let loadedURL)? = try DropInputLoader.loadImmediate(from: pasteboard) else {
            return XCTFail("Expected an email file drop")
        }
        XCTAssertEqual(loadedURL, url)
    }

    func testLoadsImageDropThroughUnifiedLoader() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CalShotDropInputLoaderTests.image.\(UUID().uuidString)"))
        pasteboard.clearContents()

        XCTAssertTrue(pasteboard.writeObjects([makeImage()]))
        XCTAssertTrue(DropInputLoader.canLoad(from: pasteboard))

        guard case .image(let image)? = try DropInputLoader.loadImmediate(from: pasteboard) else {
            return XCTFail("Expected an image drop")
        }
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testAcceptedTypesIncludeFilePromises() {
        let accepted = Set(DropInputLoader.acceptedPasteboardTypes.map(\.rawValue))
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)

        XCTAssertFalse(accepted.intersection(promiseTypes).isEmpty)
    }

    func testOutlookPrivateMessageDragIsAcceptedForDiagnostics() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CalShotDropInputLoaderTests.outlook.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let outlookType = NSPasteboard.PasteboardType("com.microsoft.outlook.mail-message")
        pasteboard.declareTypes([outlookType], owner: nil)
        pasteboard.setString("opaque-outlook-message-reference", forType: outlookType)

        XCTAssertFalse(DropInputLoader.canLoad(from: pasteboard))
        XCTAssertTrue(DropInputLoader.canAcceptDrop(from: pasteboard))
    }

    func testObservedOutlookPromiseTypesAreRegistered() {
        let accepted = Set(DropInputLoader.acceptedPasteboardTypes.map(\.rawValue))

        XCTAssertTrue(accepted.contains("com.microsoft.kOlxMessagePasteboardType"))
        XCTAssertTrue(accepted.contains("WMOutlookInternalFilePromisePboardType"))
    }

    func testObservedOutlookMessageDragIsAcceptedForPromiseReceive() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CalShotDropInputLoaderTests.outlookObserved.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let type = NSPasteboard.PasteboardType("WMOutlookInternalFilePromisePboardType")
        pasteboard.declareTypes([type], owner: nil)
        pasteboard.setString("opaque-outlook-file-promise", forType: type)

        XCTAssertFalse(DropInputLoader.canLoad(from: pasteboard))
        XCTAssertTrue(DropInputLoader.canAcceptDrop(from: pasteboard))
    }

    private func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 80, height: 48))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 80, height: 48).fill()
        NSColor.black.setFill()
        NSRect(x: 12, y: 12, width: 56, height: 24).fill()
        image.unlockFocus()
        return image
    }
}
