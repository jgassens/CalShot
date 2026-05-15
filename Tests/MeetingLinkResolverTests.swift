import Foundation
import XCTest
@testable import CalShot

final class MeetingLinkResolverTests: XCTestCase {
    override func tearDown() {
        MockMeetingRedirectProtocol.finalURLs = [:]
        super.tearDown()
    }

    func testShortURLResolvingToTeamsReplacesDraftURL() async throws {
        let shortURL = try XCTUnwrap(URL(string: "https://utd.link/NIHco"))
        let teamsURL = try XCTUnwrap(URL(string: "https://teams.microsoft.com/l/meetup-join/abc123"))
        MockMeetingRedirectProtocol.finalURLs = [shortURL.absoluteString: teamsURL]

        var draft = EventDraft.empty(notes: "")
        draft.url = shortURL

        let service = EventURLResolutionService(
            resolver: NetworkMeetingLinkResolver(session: makeMockSession(), timeout: 1),
            maximumCandidateCount: 2
        )
        let resolved = await service.resolvingMeetingRedirects(
            in: draft,
            document: document("""
            Join us for a MS TEAMS webinar:
            [joinHereButton.png]<https://utd.link/NIHco>
            """)
        )

        XCTAssertEqual(resolved.url, teamsURL)
    }

    func testShortURLResolvingToNonMeetingKeepsOriginalURL() async throws {
        let shortURL = try XCTUnwrap(URL(string: "https://utd.link/eventPage"))
        let pageURL = try XCTUnwrap(URL(string: "https://example.edu/events/nih-town-hall"))
        MockMeetingRedirectProtocol.finalURLs = [shortURL.absoluteString: pageURL]

        var draft = EventDraft.empty(notes: "")
        draft.url = shortURL

        let service = EventURLResolutionService(
            resolver: NetworkMeetingLinkResolver(session: makeMockSession(), timeout: 1),
            maximumCandidateCount: 2
        )
        let resolved = await service.resolvingMeetingRedirects(
            in: draft,
            document: document("Join us online: https://utd.link/eventPage")
        )

        XCTAssertEqual(resolved.url, shortURL)
    }

    func testOutlookSafeLinkToTeamsIsUnwrappedWithoutRedirectRequest() async throws {
        let teamsURL = try XCTUnwrap(URL(string: "https://teams.microsoft.com/l/meetup-join/abc123"))
        let safeLink = try XCTUnwrap(URL(string: "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fabc123&data=05"))

        let resolved = await NetworkMeetingLinkResolver(
            session: makeMockSession(),
            timeout: 1
        ).resolvedMeetingURL(for: safeLink)

        XCTAssertEqual(resolved, teamsURL)
        XCTAssertTrue(MockMeetingRedirectProtocol.requests.isEmpty)
    }

    func testContextMeetingCandidateCanBeResolvedWhenDraftURLIsEmpty() async throws {
        let shortURL = try XCTUnwrap(URL(string: "https://utd.link/NIHco"))
        let teamsURL = try XCTUnwrap(URL(string: "https://teams.microsoft.com/l/meetup-join/abc123"))
        MockMeetingRedirectProtocol.finalURLs = [shortURL.absoluteString: teamsURL]

        let service = EventURLResolutionService(
            resolver: NetworkMeetingLinkResolver(session: makeMockSession(), timeout: 1),
            maximumCandidateCount: 2
        )
        let resolved = await service.resolvingMeetingRedirects(
            in: .empty(notes: ""),
            document: document("Join Microsoft Teams here: https://utd.link/NIHco")
        )

        XCTAssertEqual(resolved.url, teamsURL)
    }

    private func makeMockSession() -> URLSession {
        MockMeetingRedirectProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockMeetingRedirectProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func document(_ text: String) -> OCRDocument {
        let lines = text.split(whereSeparator: \.isNewline).enumerated().map { index, line in
            OCRLine(text: String(line), boundingBox: .zero, confidence: 0.95, lineIndex: index)
        }
        return OCRDocument(lines: lines, rawText: text, averageConfidence: 0.95)
    }
}

private final class MockMeetingRedirectProtocol: URLProtocol {
    static var finalURLs: [String: URL] = [:]
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)

        guard let requestURL = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let responseURL = Self.finalURLs[requestURL.absoluteString] ?? requestURL
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
