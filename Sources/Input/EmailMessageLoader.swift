import Foundation

struct EmailImageAttachment: Equatable {
    var filename: String?
    var mimeType: String
    var data: Data
}

struct EmailMessage: Equatable {
    var subject: String
    var from: String?
    var sentDate: String?
    var bodyText: String
    var links: [URL]
    var imageAttachments: [EmailImageAttachment]

    var cleanedSubject: String {
        var value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["re:", "fw:", "fwd:"]
        while let prefix = prefixes.first(where: { value.lowercased().hasPrefix($0) }) {
            value.removeFirst(prefix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    func shouldPreferSubject(over title: String) -> Bool {
        let subject = cleanedSubject
        guard !subject.isEmpty else { return false }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return true }

        let lower = normalizedTitle.lowercased()
        if normalizedTitle == "Untitled Event" || normalizedTitle.count < 4 {
            return true
        }
        if lower.localizedCaseInsensitiveContains("invitation") {
            return true
        }

        let greetingPrefixes = [
            "hi ",
            "hello ",
            "dear ",
            "good morning",
            "good afternoon",
            "good evening"
        ]
        if greetingPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return true
        }
        if lower.contains("with regards to") || lower.hasPrefix("regards") || lower.hasPrefix("thanks") {
            return true
        }
        if looksLikeAttachmentPlaceholder(normalizedTitle) {
            return true
        }

        return false
    }

    private func looksLikeAttachmentPlaceholder(_ title: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        let imageExtensions = [".png", ".jpg", ".jpeg", ".gif", ".tiff", ".heic"]

        if value.hasPrefix("["),
           value.hasSuffix("]"),
           imageExtensions.contains(where: { lower.contains($0) }) {
            return true
        }

        return imageExtensions.contains { lower.hasSuffix($0) }
    }

    func combinedTextForParsing(imageOCRText: [String] = []) -> String {
        var sections: [String] = []

        let subject = cleanedSubject
        if !subject.isEmpty {
            sections.append(subject)
        }
        if let from, !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("From: \(from)")
        }
        if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(bodyText)
        }

        let existingText = sections.joined(separator: "\n").lowercased()
        let linkLines = links
            .map(\.absoluteString)
            .filter { !existingText.contains($0.lowercased()) }
        if !linkLines.isEmpty {
            sections.append(linkLines.joined(separator: "\n"))
        }

        let imageText = imageOCRText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !imageText.isEmpty {
            sections.append("Image text:\n\(imageText)")
        }

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

enum EmailMessageLoader {
    static func load(from url: URL) throws -> EmailMessage {
        let data = try Data(contentsOf: url)
        EmailParseDiagnostics.reset()
        let message = EmailMessageParser.parse(data: data, fallbackSubject: url.deletingPathExtension().lastPathComponent)
        EmailParseDiagnostics.log("result subjectChars=\(message.subject.count) bodyChars=\(message.bodyText.count) links=\(message.links.count) images=\(message.imageAttachments.count)")
        return message
    }
}

private enum EmailMessageParser {
    static func parse(data: Data, fallbackSubject: String) -> EmailMessage {
        let (headers, body) = splitHeadersAndBody(in: data)
        guard !headers.isEmpty else {
            return EmailMessage(
                subject: fallbackSubject,
                from: nil,
                sentDate: nil,
                bodyText: decodeText(data, charset: "utf-8"),
                links: links(in: decodeText(data, charset: "utf-8")),
                imageAttachments: []
            )
        }

        var accumulator = ParsedEmailAccumulator()
        parsePart(headers: headers, body: body, accumulator: &accumulator)

        let bodyText = accumulator.bodyText
        let combinedForLinks = ([bodyText] + accumulator.htmlTexts + accumulator.rawHTMLTexts).joined(separator: "\n")
        let extractedLinks = links(in: combinedForLinks)
        return EmailMessage(
            subject: decodedHeader(headers["subject"]) ?? fallbackSubject,
            from: decodedHeader(headers["from"]),
            sentDate: decodedHeader(headers["date"]),
            bodyText: bodyText,
            links: uniqueLinks(extractedLinks + accumulator.links),
            imageAttachments: accumulator.imageAttachments
        )
    }

    private static func parsePart(
        headers: [String: String],
        body: Data,
        accumulator: inout ParsedEmailAccumulator
    ) {
        let contentType = MIMEHeaderValue(headers["content-type"] ?? "text/plain")
        let transferEncoding = headers["content-transfer-encoding"]?.lowercased()
        EmailParseDiagnostics.log("part type=\(contentType.mediaType) bodyBytes=\(body.count)")

        if contentType.mediaType.hasPrefix("multipart/"),
           let boundary = contentType.parameters["boundary"] {
            let partDataList = splitMultipartBody(body, boundary: boundary)
            EmailParseDiagnostics.log("multipart type=\(contentType.mediaType) boundaryChars=\(boundary.count) parts=\(partDataList.count)")
            for partData in partDataList {
                let (partHeaders, partBody) = splitHeadersAndBody(in: partData)
                parsePart(headers: partHeaders, body: partBody, accumulator: &accumulator)
            }
            return
        } else if contentType.mediaType.hasPrefix("multipart/") {
            let fallbackText = normalizedPlainText(decodeText(body, charset: contentType.parameters["charset"] ?? "utf-8"))
            EmailParseDiagnostics.log("multipartMissingBoundary type=\(contentType.mediaType) bodyChars=\(fallbackText.count)")
            if !fallbackText.isEmpty {
                accumulator.plainTexts.append(fallbackText)
            }
            return
        }

        let decodedBody = decodeTransfer(body, encoding: transferEncoding)
        let charset = contentType.parameters["charset"] ?? "utf-8"

        if contentType.mediaType == "text/plain" {
            let text = normalizedPlainText(decodeText(decodedBody, charset: charset))
            EmailParseDiagnostics.log("plainText decodedBytes=\(decodedBody.count) chars=\(text.count)")
            if !text.isEmpty {
                accumulator.plainTexts.append(text)
            }
        } else if contentType.mediaType == "text/html" {
            let html = decodeText(decodedBody, charset: charset)
            let text = stripHTML(html)
            EmailParseDiagnostics.log("html decodedBytes=\(decodedBody.count) htmlChars=\(html.count) textChars=\(text.count)")
            if !text.isEmpty {
                accumulator.htmlTexts.append(text)
            }
            accumulator.rawHTMLTexts.append(html)
        } else if contentType.mediaType.hasPrefix("image/") {
            let disposition = MIMEHeaderValue(headers["content-disposition"] ?? "")
            let filename = disposition.parameters["filename"]
                ?? contentType.parameters["name"]
                ?? decodedHeader(headers["content-id"])
            guard !decodedBody.isEmpty else { return }
            EmailParseDiagnostics.log("image type=\(contentType.mediaType) bytes=\(decodedBody.count)")
            accumulator.imageAttachments.append(EmailImageAttachment(
                filename: filename,
                mimeType: contentType.mediaType,
                data: decodedBody
            ))
        } else if contentType.mediaType == "message/rfc822" {
            let nested = parse(data: decodedBody, fallbackSubject: "")
            if !nested.bodyText.isEmpty {
                accumulator.plainTexts.append(nested.bodyText)
            }
            accumulator.links.append(contentsOf: nested.links)
            accumulator.imageAttachments.append(contentsOf: nested.imageAttachments)
        }
    }

    private static func uniqueLinks(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }

    private static func splitHeadersAndBody(in data: Data) -> ([String: String], Data) {
        let raw = string(from: data)
        let separators = ["\r\n\r\n", "\n\n", "\r\r"]
        guard let separator = separators.first(where: { raw.contains($0) }),
              let range = raw.range(of: separator) else {
            return ([:], data)
        }

        let headerText = String(raw[..<range.lowerBound])
        let bodyText = String(raw[range.upperBound...])
        return (parseHeaders(headerText), Data(bodyText.utf8))
    }

    private static func parseHeaders(_ text: String) -> [String: String] {
        var unfolded: [String] = []
        for line in normalizedLines(text) {
            guard !line.isEmpty else { continue }
            if line.first?.isWhitespace == true, let last = unfolded.indices.last {
                unfolded[last] += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                unfolded.append(line)
            }
        }

        var headers: [String: String] = [:]
        for line in unfolded {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        return headers
    }

    private static func splitMultipartBody(_ body: Data, boundary: String) -> [Data] {
        let raw = string(from: body)
        let delimiter = "--\(boundary)"
        let closingDelimiter = "--\(boundary)--"
        var parts: [Data] = []
        var current: [String] = []
        var isInsidePart = false

        for line in normalizedLines(raw) {
            let trimmed = line
            if trimmed == delimiter || trimmed == closingDelimiter {
                if isInsidePart, !current.isEmpty {
                    parts.append(Data(current.joined(separator: "\r\n").utf8))
                }
                current = []
                isInsidePart = trimmed != closingDelimiter
                continue
            }
            if isInsidePart {
                current.append(trimmed)
            }
        }

        return parts
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func decodeTransfer(_ data: Data, encoding: String?) -> Data {
        switch encoding?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "base64":
            let cleaned = string(from: data)
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            return Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]) ?? data
        case "quoted-printable":
            return decodeQuotedPrintable(data)
        default:
            return data
        }
    }

    private static func decodeText(_ data: Data, charset: String) -> String {
        let encoding = stringEncoding(for: charset)
        if let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return string(from: data)
    }

    private static func stringEncoding(for charset: String) -> String.Encoding {
        switch charset.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "us-ascii", "ascii":
            return .ascii
        case "iso-8859-1", "latin1", "latin-1":
            return .isoLatin1
        case "utf-16":
            return .utf16
        case "utf-16le":
            return .utf16LittleEndian
        case "utf-16be":
            return .utf16BigEndian
        default:
            return .utf8
        }
    }

    private static func decodedHeader(_ value: String?) -> String? {
        guard let value else { return nil }
        var result = value
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let charsetRange = Range(match.range(at: 1), in: result),
                  let encodingRange = Range(match.range(at: 2), in: result),
                  let encodedRange = Range(match.range(at: 3), in: result) else {
                continue
            }

            let charset = String(result[charsetRange])
            let encoding = String(result[encodingRange]).lowercased()
            let encoded = String(result[encodedRange])
            let data: Data?
            if encoding == "b" {
                data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters])
            } else {
                data = decodeQuotedPrintable(Data(encoded.replacingOccurrences(of: "_", with: " ").utf8))
            }

            if let data {
                let decoded = decodeText(data, charset: charset)
                result.replaceSubrange(fullRange, with: decoded)
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeQuotedPrintable(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            guard byte == 61 else {
                output.append(byte)
                index += 1
                continue
            }

            if index + 1 < bytes.count, bytes[index + 1] == 10 {
                index += 2
                continue
            }
            if index + 2 < bytes.count, bytes[index + 1] == 13, bytes[index + 2] == 10 {
                index += 3
                continue
            }
            if index + 2 < bytes.count,
               let decoded = hexByte(high: bytes[index + 1], low: bytes[index + 2]) {
                output.append(decoded)
                index += 3
                continue
            }

            output.append(byte)
            index += 1
        }

        return Data(output)
    }

    private static func hexByte(high: UInt8, low: UInt8) -> UInt8? {
        guard let high = hexNibble(high), let low = hexNibble(low) else { return nil }
        return UInt8(high << 4 | low)
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57:
            return byte - 48
        case 65...70:
            return byte - 55
        case 97...102:
            return byte - 87
        default:
            return nil
        }
    }

    private static func normalizedPlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html
        let replacements: [(String, String)] = [
            (#"(?is)<(script|style)[^>]*>.*?</\1>"#, ""),
            (#"(?i)<br\s*/?>"#, "\n"),
            (#"(?i)</(p|div|li|tr|h[1-6])>"#, "\n"),
            (#"(?s)<[^>]+>"#, " ")
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        return normalizedPlainText(text)
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen: Set<String> = []
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  seen.insert(url.absoluteString).inserted else {
                return nil
            }
            return url
        }
    }

    private static func string(from data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}

private enum EmailParseDiagnostics {
    static let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("CalShot", isDirectory: true)
        .appendingPathComponent("EmailParse.log")

    static func reset() {
        #if DEBUG
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "CalShot email parse diagnostics\n".write(to: url, atomically: true, encoding: .utf8)
        #endif
    }

    static func log(_ message: String) {
        #if DEBUG
        guard let url else { return }
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }

    private static let timestampFormatter = ISO8601DateFormatter()
}

private struct ParsedEmailAccumulator {
    var plainTexts: [String] = []
    var htmlTexts: [String] = []
    var rawHTMLTexts: [String] = []
    var links: [URL] = []
    var imageAttachments: [EmailImageAttachment] = []

    var bodyText: String {
        let preferred = plainTexts.isEmpty ? htmlTexts : plainTexts
        return preferred
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

private struct MIMEHeaderValue {
    var mediaType: String
    var parameters: [String: String]

    init(_ raw: String) {
        let parts = Self.split(raw)
        mediaType = parts.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        parameters = [:]

        for part in parts.dropFirst() {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = part[part.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            parameters[key] = String(value)
        }
    }

    private static func split(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var isQuoted = false

        for character in value {
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
            } else if character == ";", !isQuoted {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }
}
