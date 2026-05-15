import Foundation
import JavaScriptCore

protocol ChronoParsing {
    func parse(text: String, referenceDate: Date, timeZone: TimeZone) -> [ChronoParseCandidate]
}

struct ChronoComponentSnapshot: Equatable {
    var values: [String: Int]
    var certain: Set<String>

    func isCertain(_ component: String) -> Bool {
        certain.contains(component)
    }
}

struct ChronoParseCandidate: Equatable {
    var matchedText: String
    var index: Int
    var length: Int
    var startDate: Date
    var endDate: Date?
    var startComponents: ChronoComponentSnapshot
    var endComponents: ChronoComponentSnapshot?
    var timezoneOffsetMinutes: Int?
    #if DEBUG
    var rawPayload: String?
    #endif

    init(
        matchedText: String,
        index: Int,
        length: Int,
        startDate: Date,
        endDate: Date?,
        startComponents: ChronoComponentSnapshot,
        endComponents: ChronoComponentSnapshot?,
        timezoneOffsetMinutes: Int?
    ) {
        self.matchedText = matchedText
        self.index = index
        self.length = length
        self.startDate = startDate
        self.endDate = endDate
        self.startComponents = startComponents
        self.endComponents = endComponents
        self.timezoneOffsetMinutes = timezoneOffsetMinutes
        #if DEBUG
        self.rawPayload = nil
        #endif
    }

    var hasCertainDate: Bool {
        startComponents.isCertain("year") || startComponents.isCertain("month") || startComponents.isCertain("day") || startComponents.isCertain("weekday")
    }

    var hasCertainStartTime: Bool {
        startComponents.isCertain("hour") || startComponents.isCertain("minute")
    }

    var hasCertainEndTime: Bool {
        guard let endComponents else { return false }
        return endComponents.isCertain("hour") || endComponents.isCertain("minute")
    }
}

final class ChronoBridge: ChronoParsing {
    static let shared = ChronoBridge()

    private let context: JSContext
    private(set) var loaded = false
    private(set) var lastError: String?

    init(bundle: Bundle = .main) {
        context = JSContext() ?? JSContext()
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastError = exception?.toString() ?? "Unknown JavaScriptCore error"
            #if DEBUG
            NSLog("[CalShot Chrono] \(self?.lastError ?? "Unknown JavaScriptCore error")")
            #endif
        }
        loadChrono(from: bundle)
    }

    func parse(text: String, referenceDate: Date = Date(), timeZone: TimeZone = .current) -> [ChronoParseCandidate] {
        guard loaded else { return [] }

        context.setObject(text as NSString, forKeyedSubscript: "__calshot_text" as NSString)
        context.setObject(Self.isoFormatter.string(from: referenceDate) as NSString, forKeyedSubscript: "__calshot_ref" as NSString)
        context.setObject(timeZone.secondsFromGMT(for: referenceDate) / 60, forKeyedSubscript: "__calshot_tz" as NSString)

        let script = """
        (function() {
          try {
            return JSON.stringify(CalShotChrono.parse(__calshot_text, __calshot_ref, __calshot_tz));
          } catch (error) {
            return JSON.stringify({ error: String(error && error.message ? error.message : error) });
          }
        })()
        """

        guard let json = context.evaluateScript(script)?.toString(),
              let data = json.data(using: .utf8) else {
            return []
        }

        if let error = try? JSONDecoder().decode(ChronoScriptError.self, from: data) {
            lastError = error.error
            return []
        }

        guard let raw = try? JSONDecoder().decode([ChronoRawResult].self, from: data) else {
            return []
        }

        return raw.compactMap { result in
            let startComponents = Self.snapshot(from: result.start)
            let endComponents = result.end.map(Self.snapshot)
            guard let start = Self.date(from: result.start, snapshot: startComponents, timeZone: timeZone) else { return nil }
            let end = result.end.flatMap { payload -> Date? in
                guard let components = endComponents else { return nil }
                return Self.date(from: payload, snapshot: components, timeZone: timeZone)
            }
            let timezone = Self.explicitTimezoneOffset(from: startComponents)
                ?? endComponents.flatMap(Self.explicitTimezoneOffset)
            var candidate = ChronoParseCandidate(
                matchedText: result.text,
                index: result.index,
                length: result.text.count,
                startDate: start,
                endDate: end,
                startComponents: startComponents,
                endComponents: endComponents,
                timezoneOffsetMinutes: timezone
            )
            #if DEBUG
            candidate.rawPayload = json
            #endif
            return candidate
        }
    }

    private func loadChrono(from bundle: Bundle) {
        guard let url = bundle.url(forResource: "chrono.bundle", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            lastError = "chrono.bundle.js missing from bundle"
            return
        }

        context.evaluateScript("var window = this; var self = this; var global = this;")
        context.evaluateScript(source)

        if context.evaluateScript("typeof CalShotChrono === 'object' && typeof CalShotChrono.parse === 'function'")?.toBool() == true {
            loaded = true
        } else {
            lastError = "CalShotChrono.parse was not found"
        }
    }

    private static func snapshot(from payload: ChronoComponentPayload) -> ChronoComponentSnapshot {
        var values: [String: Int] = [:]
        var certain = Set<String>()
        for (name, value) in payload.values {
            values[name] = value.value
            if value.certain {
                certain.insert(name)
            }
        }
        return ChronoComponentSnapshot(values: values, certain: certain)
    }

    private static func explicitTimezoneOffset(from snapshot: ChronoComponentSnapshot) -> Int? {
        guard snapshot.isCertain("timezoneOffset") else { return nil }
        return snapshot.values["timezoneOffset"]
    }

    private static func date(from payload: ChronoComponentPayload, snapshot: ChronoComponentSnapshot, timeZone: TimeZone) -> Date? {
        if snapshot.isCertain("timezoneOffset"), let date = parseISODate(payload.iso) {
            return date
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = snapshot.values["year"]
        components.month = snapshot.values["month"]
        components.day = snapshot.values["day"]

        if snapshot.isCertain("hour") {
            components.hour = snapshot.values["hour"]
            components.minute = snapshot.values["minute"] ?? 0
            components.second = snapshot.values["second"] ?? 0
            if let millisecond = snapshot.values["millisecond"] {
                components.nanosecond = millisecond * 1_000_000
            }
        }

        guard components.year != nil, components.month != nil, components.day != nil else {
            return parseISODate(payload.iso)
        }
        return calendar.date(from: components) ?? parseISODate(payload.iso)
    }

    private static func parseISODate(_ string: String) -> Date? {
        if let date = fractionalISOFormatter.date(from: string) {
            return date
        }
        return isoFormatter.date(from: string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct ChronoScriptError: Decodable {
    let error: String
}

private struct ChronoRawResult: Decodable {
    let index: Int
    let text: String
    let start: ChronoComponentPayload
    let end: ChronoComponentPayload?
}

private struct ChronoComponentPayload: Decodable {
    let iso: String
    let values: [String: ChronoComponentValue]
}

private struct ChronoComponentValue: Decodable {
    let value: Int
    let certain: Bool
}
