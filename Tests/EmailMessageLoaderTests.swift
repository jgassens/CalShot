import AppKit
import XCTest
@testable import CalShot

final class EmailMessageLoaderTests: XCTestCase {
    func testPlainTextEmailExtractsHeadersBodyAndHTTPLinks() throws {
        let url = try writeEML("""
        From: Research Office <research@example.edu>
        Subject: Seminar Invite
        Date: Wed, 13 May 2026 09:00:00 -0500
        Content-Type: text/plain; charset=utf-8

        Seminar is May 20 at 3 PM.
        Join at https://example.edu/seminar
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertEqual(email.subject, "Seminar Invite")
        XCTAssertEqual(email.from, "Research Office <research@example.edu>")
        XCTAssertEqual(email.sentDate, "Wed, 13 May 2026 09:00:00 -0500")
        XCTAssertTrue(email.bodyText.contains("Seminar is May 20 at 3 PM."))
        XCTAssertEqual(email.links.map(\.absoluteString), ["https://example.edu/seminar"])
    }

    func testHTMLOnlyEmailStripsHTMLAndKeepsHrefLinks() throws {
        let url = try writeEML("""
        Subject: HTML Invite
        Content-Type: text/html; charset=utf-8

        <html><body><p>Meet May 20 at 3 PM.</p><a href="https://teams.example.edu/meet/123">Join</a></body></html>
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertEqual(email.bodyText, "Meet May 20 at 3 PM.\nJoin")
        XCTAssertEqual(email.links.map(\.absoluteString), ["https://teams.example.edu/meet/123"])
    }

    func testMultipartAlternativePrefersPlainTextBody() throws {
        let url = try writeEML("""
        Subject: Alternative Invite
        Content-Type: multipart/alternative; boundary="alt"

        --alt
        Content-Type: text/plain; charset=utf-8

        Plain body May 20 at 3 PM.
        --alt
        Content-Type: text/html; charset=utf-8

        <p>HTML body May 21 at 4 PM.</p>
        --alt--
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertEqual(email.bodyText, "Plain body May 20 at 3 PM.")
    }

    func testOutlookRelatedAlternativeWithImagesKeepsPlainTextBody() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let url = try writeEML("""
        From: Research Office <research@example.edu>
        Subject: NIH Town Hall - Foreign Co-Authors - May 20
        Content-Type: multipart/related;
            boundary="_related";
            type="multipart/alternative"

        --_related
        Content-Type: multipart/alternative;
            boundary="_alternative"

        --_alternative
        Content-Type: text/plain; charset="iso-8859-1"
        Content-Transfer-Encoding: quoted-printable

        Join us for a MS TEAMS webinar:
        Wednesday, May 20, 2026
        2:00 PM
        [joinHereButton.png]<https://utd.link/NIHco>
        Publications with foreign
        co-authors must be disclosed in RPPRs if they involve significant scientifi=
        c work conducted outside the US.

        --_alternative
        Content-Type: text/html; charset="iso-8859-1"
        Content-Transfer-Encoding: quoted-printable

        <html><body><a href=3D"https://utd.link/NIHco">Join Here</a></body></html>
        --_alternative--

        --_related
        Content-Type: image/png; name="joinHereButton.png"
        Content-Disposition: inline; filename="joinHereButton.png"
        Content-ID: <join>
        Content-Transfer-Encoding: base64

        \(imageData.base64EncodedString())
        --_related--
        """, lineEnding: "\r\n")
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertTrue(email.bodyText.contains("Join us for a MS TEAMS webinar:"))
        XCTAssertTrue(email.bodyText.contains("Wednesday, May 20, 2026"))
        XCTAssertTrue(email.bodyText.contains("2:00 PM"))
        XCTAssertEqual(email.links.map(\.absoluteString), ["https://utd.link/NIHco"])
        XCTAssertEqual(email.imageAttachments.count, 1)
    }

    func testSubjectBeatsInlineImageFilenameTitle() {
        let email = EmailMessage(
            subject: "NIH Town Hall - Foreign Co-Authors - May 20",
            from: nil,
            sentDate: nil,
            bodyText: "",
            links: [],
            imageAttachments: []
        )

        XCTAssertTrue(email.shouldPreferSubject(over: "[NIH_Email_header.jpg]"))
    }

    func testBase64TextPartDecodes() throws {
        let encoded = Data("Base64 body May 20 at 3 PM.".utf8).base64EncodedString()
        let url = try writeEML("""
        Subject: Base64 Invite
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        \(encoded)
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertEqual(email.bodyText, "Base64 body May 20 at 3 PM.")
    }

    func testQuotedPrintableTextPartDecodes() throws {
        let url = try writeEML("""
        Subject: Quoted Printable Invite
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Meet in SLC=202.302 on May=2020 at 3=20PM.
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertEqual(email.bodyText, "Meet in SLC 2.302 on May 20 at 3 PM.")
    }

    func testImageAttachmentDecodes() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let url = try writeEML("""
        Subject: Image Invite
        Content-Type: multipart/mixed; boundary="mix"

        --mix
        Content-Type: text/plain; charset=utf-8

        See flyer.
        --mix
        Content-Type: image/png; name="flyer.png"
        Content-Disposition: attachment; filename="flyer.png"
        Content-Transfer-Encoding: base64

        \(imageData.base64EncodedString())
        --mix--
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)
        let attachment = try XCTUnwrap(email.imageAttachments.first)

        XCTAssertEqual(attachment.filename, "flyer.png")
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertEqual(attachment.data, imageData)
    }

    func testInlineCIDImageDecodes() throws {
        let imageData = Data([0x47, 0x49, 0x46])
        let url = try writeEML("""
        Subject: Inline Image Invite
        Content-Type: multipart/related; boundary="rel"

        --rel
        Content-Type: text/html; charset=utf-8

        <p>Details are in the embedded image.</p><img src="cid:image001.png@abc">
        --rel
        Content-Type: image/gif
        Content-ID: <image001.png@abc>
        Content-Transfer-Encoding: base64

        \(imageData.base64EncodedString())
        --rel--
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)
        let attachment = try XCTUnwrap(email.imageAttachments.first)

        XCTAssertEqual(attachment.filename, "<image001.png@abc>")
        XCTAssertEqual(attachment.mimeType, "image/gif")
        XCTAssertEqual(attachment.data, imageData)
    }

    func testMalformedEmailFallsBackToFilenameAndBodyText() throws {
        let url = try writeEML(
            "This is not a header block but has https://example.edu/fallback",
            filename: "fallback-email.eml"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertEqual(email.subject, "fallback-email")
        XCTAssertEqual(email.bodyText, "This is not a header block but has https://example.edu/fallback")
        XCTAssertEqual(email.links.map(\.absoluteString), ["https://example.edu/fallback"])
    }

    func testMalformedMultipartWithoutBoundaryKeepsReadableBody() throws {
        let url = try writeEML("""
        Subject: Broken Multipart Invite
        Content-Type: multipart/mixed

        Meet May 21 at 4 PM.
        Details: https://example.edu/broken-multipart
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertTrue(email.bodyText.contains("Meet May 21 at 4 PM."))
        XCTAssertEqual(email.links.map(\.absoluteString), ["https://example.edu/broken-multipart"])
    }

    func testNestedHTMLMessageKeepsHrefLink() throws {
        let nestedHTML = """
        Subject: Nested Invite
        Content-Type: text/html; charset=utf-8

        <html><body><p>Meet May 22 at 11 AM.</p><a href="https://teams.example.edu/nested">Join nested meeting</a></body></html>
        """
        let url = try writeEML("""
        Subject: Forwarded Invite
        Content-Type: message/rfc822

        \(nestedHTML)
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)

        XCTAssertTrue(email.bodyText.contains("Meet May 22 at 11 AM."))
        XCTAssertEqual(email.links.map(\.absoluteString), ["https://teams.example.edu/nested"])
    }

    func testOutlookStyleEmailProducesEventDetails() throws {
        let bridge = ChronoBridge(bundle: Bundle(for: Self.self))
        try XCTSkipUnless(bridge.loaded, "chrono.bundle.js is not available in the test bundle")

        let url = try writeEML("""
        From: Nielsen, Steven <steven.nielsen@utdallas.edu>
        Subject: Re: QE1 May 20
        Content-Type: text/plain; charset=utf-8

        Hi everyone, a few items with regards to QE1:

        -May 20 8am-5pm in SLC 2.302, SLC 2.303, and SLC 2.304 including pizza lunch and coffee.
        Make sure your presentation works on the computers in these rooms.
        More details: https://example.edu/qe1
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let email = try EmailMessageLoader.load(from: url)
        let calendar = makeEmailTestCalendar()
        var draft = EventDraftMerger(chrono: bridge, calendar: calendar).makeDraft(
            from: OCRDocument.textOnly(email.combinedTextForParsing()),
            referenceDate: emailTestDate(2026, 5, 15, 12, 0, calendar: calendar),
            timeZone: calendar.timeZone
        )
        if email.shouldPreferSubject(over: draft.title) {
            draft.title = email.cleanedSubject
        }

        XCTAssertEqual(draft.title, "QE1 May 20")
        XCTAssertEqual(draft.start, emailTestDate(2026, 5, 20, 8, 0, calendar: calendar))
        XCTAssertEqual(draft.end, emailTestDate(2026, 5, 20, 17, 0, calendar: calendar))
        XCTAssertEqual(draft.location, "SLC 2.302, SLC 2.303, SLC 2.304")
        XCTAssertEqual(draft.url?.absoluteString, "https://example.edu/qe1")
    }

    private func writeEML(_ contents: String, filename: String = "message.eml", lineEnding: String = "\n") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalShotEmailMessageLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        let text = normalized(contents)
            .replacingOccurrences(of: "\n", with: lineEnding)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func normalized(_ contents: String) -> String {
        contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                String(line).replacingOccurrences(of: #"^\s{8}"#, with: "", options: .regularExpression)
            }
            .joined(separator: "\n")
    }
}

private func makeEmailTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
}

private func emailTestDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}
