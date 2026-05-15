import AppKit
import XCTest
@testable import CalShot

final class DropImageLoaderTests: XCTestCase {
    func testLoadsDirectPasteboardImageData() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CalShotDropImageLoaderTests.imageData.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let image = makeImage()

        XCTAssertTrue(pasteboard.writeObjects([image]))
        XCTAssertTrue(DropImageLoader.canLoadImage(from: pasteboard))

        let loaded = try XCTUnwrap(DropImageLoader.loadImage(from: pasteboard))
        XCTAssertGreaterThan(loaded.size.width, 0)
        XCTAssertGreaterThan(loaded.size.height, 0)
    }

    func testLoadsImageFileURLFromPasteboard() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalShotDropImageLoaderTests-\(UUID().uuidString)")
            .appendingPathExtension("tiff")
        let data = try XCTUnwrap(makeImage().tiffRepresentation)
        try data.write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CalShotDropImageLoaderTests.fileURL.\(UUID().uuidString)"))
        pasteboard.clearContents()

        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))
        XCTAssertTrue(DropImageLoader.canLoadImage(from: pasteboard))

        let loaded = try XCTUnwrap(DropImageLoader.loadImage(from: pasteboard))
        XCTAssertGreaterThan(loaded.size.width, 0)
        XCTAssertGreaterThan(loaded.size.height, 0)
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
