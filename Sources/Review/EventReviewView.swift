import AppKit
import SwiftUI

struct EventReviewView: View {
    @ObservedObject var viewModel: EventReviewViewModel
    @State private var sourceTextExpanded = false
    @State private var defaultStartDate = Date().roundedUpToNextHalfHour

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    EventCard(
                        viewModel: viewModel,
                        titleBinding: titleBinding,
                        locationBinding: locationBinding,
                        calendarBinding: calendarBinding,
                        timeZoneBinding: timeZoneBinding,
                        allDayBinding: allDayBinding,
                        teamsBinding: teamsBinding,
                        startBinding: optionalStartBinding,
                        endBinding: optionalEndBinding,
                        defaultStartDate: defaultStartDate
                    )

                    SourcePreviewCard(
                        image: viewModel.image,
                        sourceText: sourceText,
                        confidenceLabel: viewModel.parseConfidenceLabel,
                        lineCount: viewModel.document.lines.count,
                        isLowConfidence: viewModel.document.isLowConfidence,
                        isExpanded: $sourceTextExpanded
                    )

                    CalendarPreviewPanel(viewModel: viewModel)

                    if !viewModel.draft.alternatives.isEmpty {
                        AlternativesPanel(viewModel: viewModel)
                    }

                    DetailsPanel(urlBinding: urlBinding, notesBinding: notesBinding)
                }
                .padding(18)
            }

            Divider()

            footer
        }
        .frame(minWidth: 540, idealWidth: 620, maxWidth: 720, minHeight: 620, idealHeight: 760, maxHeight: 860)
        .background(windowBackground)
        .accessibilityIdentifier("reviewWindow")
        .onAppear {
            defaultStartDate = Date().roundedUpToNextHalfHour
            viewModel.loadCalendarContext()
        }
        #if DEBUG
        .accessibilityValue(viewModel.smokeSummary)
        #endif
    }

    private var windowBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Color.red.opacity(0.035)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 14) {
            statusText
            Spacer()
            Button("Create Event") {
                viewModel.createEvent()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.draft.canCreate || viewModel.isSaving)
            .accessibilityIdentifier("createEventButton")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var sourceText: String {
        viewModel.document.rawText.isEmpty ? "No text was detected. You can still create the event manually." : viewModel.document.rawText
    }

    @ViewBuilder
    private var statusText: some View {
        if let message = viewModel.statusMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if !viewModel.draft.canCreate {
            Text("Add a start date before creating the event.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var titleBinding: Binding<String> {
        Binding {
            viewModel.draft.title
        } set: {
            viewModel.draft.title = $0
            viewModel.markEdited(.title)
        }
    }

    private var calendarBinding: Binding<String> {
        Binding {
            viewModel.selectedCalendarID ?? ""
        } set: {
            viewModel.selectCalendar($0.isEmpty ? nil : $0)
        }
    }

    private var timeZoneBinding: Binding<String> {
        Binding {
            viewModel.draft.timeZoneIdentifier
        } set: {
            viewModel.selectTimeZone($0)
        }
    }

    private var allDayBinding: Binding<Bool> {
        Binding {
            viewModel.draft.allDay
        } set: {
            viewModel.draft.allDay = $0
            if let start = viewModel.draft.start {
                viewModel.draft.end = start.addingTimeInterval($0 ? 24 * 60 * 60 : 60 * 60)
            }
            viewModel.draftDateChanged(.allDay)
        }
    }

    private var teamsBinding: Binding<Bool> {
        Binding {
            viewModel.draft.createTeamsMeeting
        } set: {
            viewModel.draft.createTeamsMeeting = $0
            viewModel.markEdited(.teamsMeeting)
        }
    }

    private var optionalStartBinding: Binding<Date?> {
        Binding {
            viewModel.draft.start
        } set: { newStart in
            viewModel.draft.start = newStart
            if let newStart, let end = viewModel.draft.end, end <= newStart {
                viewModel.draft.end = newStart.addingTimeInterval(viewModel.draft.allDay ? 24 * 60 * 60 : 60 * 60)
            }
            viewModel.draftDateChanged(.start)
        }
    }

    private var optionalEndBinding: Binding<Date?> {
        Binding {
            viewModel.draft.end
        } set: {
            viewModel.draft.end = $0
            viewModel.draftDateChanged(.end)
        }
    }

    private var locationBinding: Binding<String> {
        Binding {
            viewModel.draft.location ?? ""
        } set: {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.draft.location = trimmed.isEmpty ? nil : trimmed
            viewModel.markEdited(.location)
        }
    }

    private var urlBinding: Binding<String> {
        Binding {
            viewModel.draft.url?.absoluteString ?? ""
        } set: {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.draft.url = trimmed.isEmpty ? nil : URL(string: trimmed)
            viewModel.markEdited(.url)
        }
    }

    private var notesBinding: Binding<String> {
        Binding {
            viewModel.draft.notes
        } set: {
            viewModel.draft.notes = $0
            viewModel.markEdited(.notes)
        }
    }
}

private struct SourcePreviewCard: View {
    var image: NSImage
    var sourceText: String
    var confidenceLabel: String
    var lineCount: Int
    var isLowConfidence: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Source preview")

            HStack {
                Text(confidenceLabel)
                    .font(.caption)
                    .foregroundStyle(isLowConfidence ? .orange : .secondary)
                Spacer()
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Source text", isExpanded: $isExpanded) {
                TextEditor(text: .constant(sourceText))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 82, idealHeight: 96, maxHeight: 130)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("ocrTextEditor")
            }
            .font(.subheadline.weight(.semibold))
        }
        .cardStyle()
    }
}

private struct EventCard: View {
    @ObservedObject var viewModel: EventReviewViewModel
    var titleBinding: Binding<String>
    var locationBinding: Binding<String>
    var calendarBinding: Binding<String>
    var timeZoneBinding: Binding<String>
    var allDayBinding: Binding<Bool>
    var teamsBinding: Binding<Bool>
    var startBinding: Binding<Date?>
    var endBinding: Binding<Date?>
    var defaultStartDate: Date

    private var defaultEndDate: Date {
        (viewModel.draft.start ?? defaultStartDate).addingTimeInterval(viewModel.draft.allDay ? 24 * 60 * 60 : 60 * 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Event title", text: titleBinding, axis: .vertical)
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                        .lineLimit(1...2)
                        .accessibilityIdentifier("titleField")

                    TextField("Location", text: locationBinding)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("locationField")
                }

                Image(systemName: "calendar.badge.plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.quaternary.opacity(0.22), in: Circle())
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                EventRow(label: "all-day") {
                    Toggle("", isOn: allDayBinding)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("allDayToggle")
                }

                EventRow(label: "starts") {
                    DateTimeTextFields(
                        value: startBinding,
                        fallbackDate: defaultStartDate,
                        showsFallbackWhenNil: false,
                        allDay: viewModel.draft.allDay,
                        timeZone: viewModel.draft.eventTimeZone,
                        accessibilityIdentifier: "startPicker"
                    )
                }

                EventRow(label: "ends") {
                    DateTimeTextFields(
                        value: endBinding,
                        fallbackDate: defaultEndDate,
                        showsFallbackWhenNil: true,
                        allDay: viewModel.draft.allDay,
                        timeZone: viewModel.draft.eventTimeZone,
                        accessibilityIdentifier: "endPicker"
                    )
                }

                EventRow(label: "calendar") {
                    HStack(spacing: 8) {
                        CalendarSwatchDot(swatch: viewModel.selectedCalendarChoice?.swatch)
                        Picker("Calendar", selection: calendarBinding) {
                            if viewModel.calendars.isEmpty {
                                Text(viewModel.isLoadingCalendars ? "Loading calendars..." : "Default calendar")
                                    .tag("")
                            } else {
                                ForEach(viewModel.calendars) { calendar in
                                    Text(calendar.displayTitle).tag(calendar.id)
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(viewModel.calendars.isEmpty)
                        .accessibilityIdentifier("calendarPicker")
                    }
                }

                EventRow(label: "time zone") {
                    Picker("Time Zone", selection: timeZoneBinding) {
                        ForEach(viewModel.timeZoneChoices) { choice in
                            Text(choice.title).tag(choice.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("timeZonePicker")
                }

                EventRow(label: "Teams") {
                    Toggle("", isOn: teamsBinding)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("teamsMeetingToggle")
                }
            }

            TimeZonePreview(draft: viewModel.draft)
        }
        .cardStyle()
    }
}

private struct EventRow<Content: View>: View {
    var label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.body.weight(.semibold))
                .frame(width: 88, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DateTimeTextFields: View {
    @Binding var value: Date?
    var fallbackDate: Date
    var showsFallbackWhenNil: Bool
    var allDay: Bool
    var timeZone: TimeZone
    var accessibilityIdentifier: String

    @State private var dateText = ""
    @State private var timeText = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("M/D/YYYY", text: $dateText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 116)
                .onSubmit { commitIfValid() }
                .onChange(of: dateText) { _, _ in commitIfValid() }

            if !allDay {
                TextField("Time", text: $timeText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .onSubmit { commitIfValid() }
                    .onChange(of: timeText) { _, _ in commitIfValid() }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear { syncText() }
        .onChange(of: value) { _, _ in syncText() }
        .onChange(of: fallbackDate) { _, _ in
            if value == nil {
                syncText()
            }
        }
        .onChange(of: allDay) { _, _ in
            syncText()
            commitIfValid()
        }
        .onChange(of: timeZone.identifier) { _, _ in syncText() }
    }

    private func syncText() {
        let displayedDate = value ?? (showsFallbackWhenNil ? fallbackDate : nil)
        dateText = displayedDate.map { DateTextParser.dateString(from: $0, timeZone: timeZone) } ?? ""
        timeText = DateTextParser.timeString(from: displayedDate ?? fallbackDate, timeZone: timeZone)
    }

    private func commitIfValid() {
        let cleanedDate = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedDate.isEmpty {
            if value != nil {
                value = nil
            }
            return
        }

        guard let dateComponents = DateTextParser.dateComponents(from: cleanedDate, timeZone: timeZone) else {
            return
        }

        var components = dateComponents
        components.calendar = Calendar(identifier: .gregorian)
        components.calendar?.timeZone = timeZone
        components.timeZone = timeZone

        if allDay {
            components.hour = 0
            components.minute = 0
            components.second = 0
        } else {
            guard let timeComponents = DateTextParser.timeComponents(from: timeText, fallbackDate: fallbackDate, timeZone: timeZone) else {
                return
            }
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = 0
        }

        guard let parsedDate = components.date, parsedDate != value else {
            return
        }
        value = parsedDate
    }
}

private enum DateTextParser {
    static func dateString(from date: Date, timeZone: TimeZone) -> String {
        dateDisplayFormatter.timeZone = timeZone
        return dateDisplayFormatter.string(from: date)
    }

    static func timeString(from date: Date, timeZone: TimeZone) -> String {
        timeDisplayFormatter.timeZone = timeZone
        return timeDisplayFormatter.string(from: date)
    }

    static func dateComponents(from text: String, timeZone: TimeZone) -> DateComponents? {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.replacingOccurrences(of: #"\s*/\s*"#, with: "/", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\s*-\s*"#, with: "-", options: .regularExpression)

        if normalized.range(of: #"^\d{1,2}/\d{1,2}$"#, options: .regularExpression) != nil {
            let year = Calendar.current.component(.year, from: Date())
            normalized += "/\(year)"
        }

        let calendar = calendar(timeZone: timeZone)
        for formatter in parseDateFormatters {
            formatter.timeZone = timeZone
            formatter.calendar = calendar
            if let date = formatter.date(from: normalized) {
                return calendar.dateComponents([.year, .month, .day], from: date)
            }
        }
        return nil
    }

    static func timeComponents(from text: String, fallbackDate: Date, timeZone: TimeZone) -> DateComponents? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return calendar(timeZone: timeZone).dateComponents([.hour, .minute], from: fallbackDate)
        }

        let calendar = calendar(timeZone: timeZone)
        for formatter in parseTimeFormatters {
            formatter.timeZone = timeZone
            formatter.calendar = calendar
            if let date = formatter.date(from: normalized) {
                return calendar.dateComponents([.hour, .minute], from: date)
            }
        }
        return nil
    }

    private static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static let dateDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "M/d/yyyy"
        return formatter
    }()

    private static let timeDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let parseDateFormatters: [DateFormatter] = {
        ["M/d/yyyy", "M/d/yy", "M-d-yyyy", "MMM d yyyy", "MMMM d yyyy", "MMM d, yyyy", "MMMM d, yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.isLenient = true
            formatter.dateFormat = format
            return formatter
        }
    }()

    private static let parseTimeFormatters: [DateFormatter] = {
        ["h:mm a", "h a", "ha", "H:mm", "H"].map { format in
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.isLenient = true
            formatter.dateFormat = format
            return formatter
        }
    }()
}

private struct CalendarSwatchDot: View {
    var swatch: CalendarSwatch?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private var color: Color {
        guard let swatch else {
            return .accentColor
        }
        return Color(red: swatch.red, green: swatch.green, blue: swatch.blue, opacity: swatch.alpha)
    }
}

private struct TimeZonePreview: View {
    var draft: EventDraft

    var body: some View {
        if let start = draft.start, !draft.allDay {
            VStack(alignment: .leading, spacing: 0) {
                TimeZonePreviewRow(
                    systemImage: "location.north.fill",
                    title: "System time zone",
                    subtitle: TimeZone.current.friendlyName,
                    timeRange: timeRange(start: start, end: draft.end, timeZone: .current),
                    tint: .accentColor
                )

                Divider()

                TimeZonePreviewRow(
                    systemImage: "sun.max.fill",
                    title: comparisonZone.friendlyName,
                    subtitle: comparisonZone.identifier,
                    timeRange: timeRange(start: start, end: draft.end, timeZone: comparisonZone),
                    tint: .orange
                )
            }
            .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var comparisonZone: TimeZone {
        if draft.eventTimeZone.identifier != TimeZone.current.identifier {
            return draft.eventTimeZone
        }
        return TimeZone(identifier: "America/New_York") ?? .current
    }

    private func timeRange(start: Date, end: Date?, timeZone: TimeZone) -> String {
        Self.timeRangeFormatter.timeZone = timeZone
        let end = end ?? start.addingTimeInterval(60 * 60)
        return "\(Self.timeRangeFormatter.string(from: start)) - \(Self.timeRangeFormatter.string(from: end))"
    }

    private static let timeRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct TimeZonePreviewRow: View {
    var systemImage: String
    var title: String
    var subtitle: String
    var timeRange: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.subheadline)
            }

            Spacer()

            Text(timeRange)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct CalendarPreviewPanel: View {
    @ObservedObject var viewModel: EventReviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calendar Preview")
                    .font(.headline)
                Spacer()
                if viewModel.isLoadingConflicts {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    CalendarSwatchDot(swatch: viewModel.selectedCalendarChoice?.swatch)
                    Text(viewModel.selectedCalendarTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }

                Text(viewModel.eventTimeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let message = viewModel.calendarStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if viewModel.conflicts.isEmpty {
                Text(viewModel.isLoadingConflicts ? "Checking for conflicts..." : "No conflicts found for this slot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(viewModel.conflicts) { conflict in
                        ConflictRow(conflict: conflict, timeZone: viewModel.draft.eventTimeZone)
                    }
                }
            }
        }
        .cardStyle()
        .accessibilityIdentifier("calendarPreviewPanel")
    }
}

private struct AlternativesPanel: View {
    @ObservedObject var viewModel: EventReviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alternatives")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(viewModel.draft.alternatives) { alternative in
                        Button(alternative.label) {
                            viewModel.applyAlternative(alternative)
                        }
                        .buttonStyle(.bordered)
                        .lineLimit(1)
                    }
                }
            }
        }
        .cardStyle()
    }
}

private struct DetailsPanel: View {
    var urlBinding: Binding<String>
    var notesBinding: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            VStack(alignment: .leading, spacing: 7) {
                Text("URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Optional", text: urlBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("urlField")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: notesBinding)
                    .frame(minHeight: 84, idealHeight: 100, maxHeight: 130)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("notesEditor")
            }
        }
        .cardStyle()
    }
}

private struct ConflictRow: View {
    var conflict: CalendarConflict
    var timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conflict.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("\(timeText) - \(conflict.calendarTitle)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    private var timeText: String {
        if conflict.isAllDay {
            return "All day"
        }

        Self.timeFormatter.timeZone = timeZone
        return "\(Self.timeFormatter.string(from: conflict.start)) to \(Self.timeFormatter.string(from: conflict.end))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private extension View {
    func cardStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.018))
                    }
            }
    }
}

private extension Date {
    var roundedUpToNextHalfHour: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        let minute = components.minute ?? 0
        let targetMinute = minute < 30 ? 30 : 0
        let hourOffset = minute < 30 ? 0 : 1
        var rounded = components
        rounded.hour = (components.hour ?? 0) + hourOffset
        rounded.minute = targetMinute
        rounded.second = 0
        return calendar.date(from: rounded) ?? self
    }
}

private extension TimeZone {
    var friendlyName: String {
        if identifier == TimeZone.current.identifier {
            return localizedName(for: .standard, locale: .current) ?? identifier
        }

        let city = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return city.replacingOccurrences(of: "_", with: " ")
    }
}
