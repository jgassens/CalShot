import Foundation

protocol MeetingLinkResolving {
    func resolvedMeetingURL(for url: URL) async -> URL?
}

struct EventURLResolutionService {
    var resolver: MeetingLinkResolving
    var maximumCandidateCount: Int

    static let live = EventURLResolutionService(
        resolver: NetworkMeetingLinkResolver(),
        maximumCandidateCount: 5
    )

    func resolvingMeetingRedirects(in draft: EventDraft, document: OCRDocument) async -> EventDraft {
        let candidates = resolutionCandidates(from: draft, text: document.rawText)
        guard !candidates.isEmpty else { return draft }

        var resolvedDraft = draft
        for candidate in candidates.prefix(maximumCandidateCount) {
            guard let resolvedURL = await resolver.resolvedMeetingURL(for: candidate) else {
                continue
            }

            guard resolvedURL != draft.url else {
                return resolvedDraft
            }

            resolvedDraft.url = resolvedURL
            resolvedDraft.sources[.url] = .heuristic(
                label: "resolved meeting link",
                text: "\(candidate.absoluteString) -> \(resolvedURL.absoluteString)"
            )
            return resolvedDraft
        }

        return resolvedDraft
    }

    private func resolutionCandidates(from draft: EventDraft, text: String) -> [URL] {
        let detectedURLs = DataDetectorExtractor.extract(from: text).urls
            .filter { MeetingLinkClassifier.isWebURL($0) }

        var candidates: [URL] = []
        if let draftURL = draft.url, MeetingLinkClassifier.isWebURL(draftURL) {
            candidates.append(draftURL)
        }

        for url in detectedURLs where shouldCheck(url, in: text) {
            candidates.append(url)
        }

        var seen: Set<String> = []
        return candidates.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }

    private func shouldCheck(_ url: URL, in text: String) -> Bool {
        MeetingLinkClassifier.isTeleconferenceURL(url)
            || MeetingLinkClassifier.embeddedTeleconferenceURL(in: url) != nil
            || MeetingLinkClassifier.isKnownShortLink(url)
            || MeetingLinkClassifier.contextSuggestsMeetingLink(url: url, in: text)
    }
}

struct NetworkMeetingLinkResolver: MeetingLinkResolving {
    var session: URLSession
    var timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 4) {
        self.session = session
        self.timeout = timeout
    }

    func resolvedMeetingURL(for url: URL) async -> URL? {
        guard MeetingLinkClassifier.isWebURL(url) else { return nil }

        if let embeddedURL = MeetingLinkClassifier.embeddedTeleconferenceURL(in: url) {
            return embeddedURL
        }

        if MeetingLinkClassifier.isTeleconferenceURL(url) {
            return url
        }

        guard let finalURL = await finalRedirectURL(for: url), finalURL != url else {
            return nil
        }

        if let embeddedURL = MeetingLinkClassifier.embeddedTeleconferenceURL(in: finalURL) {
            return embeddedURL
        }

        return MeetingLinkClassifier.isTeleconferenceURL(finalURL) ? finalURL : nil
    }

    private func finalRedirectURL(for url: URL) async -> URL? {
        if let headURL = await finalURL(for: request(url: url, method: "HEAD")) {
            return headURL
        }

        var getRequest = request(url: url, method: "GET")
        getRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        return await finalURL(for: getRequest)
    }

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("CalShot/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func finalURL(for request: URLRequest) async -> URL? {
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<400).contains(httpResponse.statusCode) else {
                return nil
            }
            return httpResponse.url ?? response.url
        } catch {
            #if DEBUG
            NSLog("[CalShot LinkResolver] \(request.url?.absoluteString ?? "unknown URL"): \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}

enum MeetingLinkClassifier {
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func isTeleconferenceURL(_ url: URL) -> Bool {
        guard isWebURL(url) else { return false }

        let absolute = url.absoluteString.lowercased()
        let decoded = url.absoluteString.removingPercentEncoding?.lowercased() ?? absolute
        let host = url.host?.lowercased() ?? ""
        let haystack = [absolute, decoded, host, url.path.lowercased(), url.query?.lowercased() ?? ""]
            .joined(separator: " ")

        return containsAny(haystack, [
            "teams.microsoft.com",
            "events.teams.microsoft.com",
            "teams.live.com",
            "meet.google.com",
            "zoom.us/",
            "zoomgov.com/",
            "webex.com",
            "gotomeeting.com",
            "global.gotomeeting.com",
            "bluejeans.com",
            "whereby.com",
            "ringcentral.com",
            "chime.aws",
            "8x8.vc"
        ])
    }

    static func embeddedTeleconferenceURL(in url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let parameterNames = ["url", "u", "target", "redirect", "redirecturl", "destination", "link"]
        let values = components.queryItems?
            .filter { item in
                parameterNames.contains(item.name.lowercased())
            }
            .compactMap(\.value) ?? []

        for value in values {
            let decoded = value.removingPercentEncoding ?? value
            guard let embeddedURL = URL(string: decoded),
                  isTeleconferenceURL(embeddedURL) else {
                continue
            }
            return embeddedURL
        }

        return nil
    }

    static func isKnownShortLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased().trimmingPrefix("www.") else { return false }
        return [
            "aka.ms",
            "bit.ly",
            "bitly.com",
            "buff.ly",
            "cutt.ly",
            "goo.gl",
            "is.gd",
            "lnkd.in",
            "ow.ly",
            "rebrand.ly",
            "shorturl.at",
            "t.co",
            "tiny.cc",
            "tinyurl.com",
            "trib.al",
            "utd.link"
        ].contains(host)
    }

    static func contextSuggestsMeetingLink(url: URL, in text: String) -> Bool {
        let context = context(for: url, in: text)
        return containsAny(context, [
            "teams",
            "zoom",
            "google meet",
            "meet.google",
            "webex",
            "teleconference",
            "video conference",
            "videoconference",
            "webinar",
            "join meeting",
            "join event",
            "join here",
            "join link",
            "attend",
            "dial in",
            "call in",
            "call-in"
        ])
    }

    private static func context(for url: URL, in text: String) -> String {
        let lowerText = text.lowercased()
        let candidates = [
            url.absoluteString.lowercased(),
            url.absoluteString.removingPercentEncoding?.lowercased()
        ].compactMap { $0 }

        for candidate in candidates where !candidate.isEmpty {
            guard let range = lowerText.range(of: candidate) else { continue }
            let start = lowerText.index(range.lowerBound, offsetBy: -300, limitedBy: lowerText.startIndex) ?? lowerText.startIndex
            let end = lowerText.index(range.upperBound, offsetBy: 300, limitedBy: lowerText.endIndex) ?? lowerText.endIndex
            return String(lowerText[start..<end])
        }

        return ""
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
