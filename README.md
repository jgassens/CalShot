# CalShot

CalShot is a native macOS menu-bar agent app that turns a screenshot or image into an Apple Calendar event.

The app processes everything locally. It uses Apple Vision for OCR, Chrono plus native Apple detectors for parsing, a mandatory editable review window, EventKit write-only calendar access, and an `.ics` fallback when direct calendar saving is unavailable.

CalShot is prepared for direct macOS distribution as a Developer ID signed DMG. See `DISTRIBUTION.md` for the release, notarization, and verification workflow.

This README is the project roadmap and implementation contract. Some later-phase features have already been implemented while the product was exercised against real Outlook and calendar workflows; keep the tests and distribution scripts as the current source of truth.

---

## Current target milestone

**Implement Phase 0+1 first.**

Phase 0+1 means:

1. Fresh native macOS app scaffold.
2. Menu-bar agent shell.
3. Open Image input.
4. Clipboard image input.
5. Menu-bar icon image drop.
6. Vision OCR.
7. Chrono date/time parsing through JavaScriptCore.
8. Native extraction through `NSDataDetector` and `NaturalLanguage`.
9. Event draft merger.
10. Mandatory review UI.
11. EventKit write-only save to the default calendar.
12. `.ics` export/open fallback.
13. Unit tests and a local build/run verification script.

Do **not** implement the Yoink-style shelf, file promises, global hotkey, screenshot capture, ScreenCaptureKit, or Duckling until the current menu-bar-drop path is passing.

---

## Product goal

CalShot should make this workflow fast:

```text
User has a screenshot of an event flyer / email / poster / webpage
        │
        ▼
User opens image, uses clipboard image, or drags an image onto the menu-bar icon
        │
        ▼
CalShot OCRs the image locally
        │
        ▼
CalShot extracts title, date, time, location, URL, and notes
        │
        ▼
User reviews and edits the draft
        │
        ▼
CalShot writes the event to Apple Calendar
```

The app should never silently create an event from OCR. Review is mandatory.

---

## Non-goals for v1

These are intentionally out of scope for Phase 0+1:

- No cloud OCR.
- No LLM calls.
- No telemetry.
- No Duckling sidecar.
- No Google Calendar or Outlook integration.
- No custom calendar picker.
- No deduplication against existing events.
- No saved screenshot history.
- No Yoink-style shelf yet.
- No global hotkey yet.
- No screenshot capture yet.
- No App Store distribution in this slice. Direct Developer ID DMG distribution is supported.

The first milestone is a reliable local OCR-to-review-to-calendar loop.

---

## Source basis

Use these references when implementing or correcting behavior:

- Apple `LSUIElement`: <https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement>
- Apple Vision text recognition: <https://developer.apple.com/documentation/vision/recognizing-text-in-images>
- Apple `VNRecognizeTextRequest`: <https://developer.apple.com/documentation/vision/vnrecognizetextrequest>
- Apple `NSDataDetector`: <https://developer.apple.com/documentation/foundation/nsdatadetector>
- Apple JavaScriptCore: <https://developer.apple.com/documentation/javascriptcore>
- Apple EventKit write-only access: <https://developer.apple.com/documentation/eventkit/ekeventstore/requestwriteonlyaccesstoevents%28completion%3A%29>
- Apple EventKit access overview: <https://developer.apple.com/documentation/eventkit/accessing-the-event-store>
- Apple Calendars entitlement: <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.calendars>
- Chrono: <https://github.com/wanasit/chrono>
- Chrono npm package: <https://www.npmjs.com/package/chrono-node>
- XcodeGen: <https://github.com/yonaskolb/xcodegen>
- Codex native macOS build guidance: <https://developers.openai.com/codex/use-cases/native-macos-apps>
- Codex config reference: <https://developers.openai.com/codex/config-reference>
- iCalendar RFC 5545: <https://datatracker.ietf.org/doc/html/rfc5545>

---

## Technical choices

### App type

Use a native macOS app:

```text
SwiftUI for ordinary app UI
AppKit for menu-bar, agent behavior, panels, drag/drop, and desktop-specific behavior
XcodeGen for project generation
macOS 14+ deployment target
```

Use `LSUIElement=true` so CalShot runs as a menu-bar agent and does not appear in the Dock.

### Project generator

`project.yml` is the source of truth.

`CalShot.xcodeproj` is generated locally with XcodeGen and should normally be gitignored. Do not manually edit the generated project as the durable source of truth.

### OCR

Use Apple Vision:

```swift
VNRecognizeTextRequest
recognitionLevel = .accurate
usesLanguageCorrection = true
```

OCR must preserve structured output, not just a raw string.

### Date/time parser

Use Chrono first, bundled into one JavaScript file and executed through JavaScriptCore.

Do not use `chrono.parseDate` as the main bridge. Use `chrono.parse`, because the app needs matched text, ranges, start/end components, and certainty metadata.

Use `forwardDate: true` for event parsing so relative dates prefer future events.

### Native extractors

Use `NSDataDetector` for:

- dates as a fallback;
- postal addresses;
- URLs;
- phone numbers when useful for notes.

Use `NaturalLanguage` only as a soft signal for place names and organization names. It should not be treated as a reliable venue extractor by itself.

### Calendar integration

Use EventKit write-only access on macOS 14+.

Save to:

```swift
eventStore.defaultCalendarForNewEvents
```

Do not build a custom calendar picker in v1. Write-only access cannot read the calendar list. A calendar picker would require full access, which is intentionally out of scope.

### Fallback calendar output

When EventKit permission is denied, unavailable, or saving fails, create an `.ics` file and open it with Calendar.app.

### Privacy

The default privacy model is strict:

- local OCR only;
- local parsing only;
- no network calls for screenshots or OCR text;
- bounded redirect checks only for user-provided event links, so short URLs can become direct Teams/Zoom/Meet/Webex event links;
- no telemetry;
- no OCR text in release logs;
- temp screenshots deleted after processing;
- no persistent history unless explicitly added later.

---

## Repository layout

Recommended layout:

```text
CalShot/
├── README.md
├── AGENTS.md
├── project.yml
├── .gitignore
├── .codex/
│   └── config.toml                  # optional repo-scoped Codex settings only
├── script/
│   ├── build_and_run.sh
│   ├── bundle_chrono.sh
│   ├── generate_smoke_images.sh
│   └── smoke_images.sh
├── Resources/
│   ├── Info.plist
│   ├── CalShot.entitlements
│   ├── chrono.bundle.js
│   └── Licenses/
│       └── chrono-node-MIT.txt
├── Sources/
│   ├── App/
│   │   ├── CalShotApp.swift
│   │   ├── AppDelegate.swift
│   │   ├── MenuBarController.swift
│   │   └── PermissionsController.swift
│   ├── Input/
│   │   ├── ImageInputController.swift
│   │   ├── OpenImageLoader.swift
│   │   ├── ClipboardImageLoader.swift
│   │   └── ImageNormalizer.swift
│   ├── OCR/
│   │   ├── OCRService.swift
│   │   ├── OCRDocument.swift
│   │   └── OCRLineMerger.swift
│   ├── Parsing/
│   │   ├── ChronoBridge.swift
│   │   ├── DateTimeCandidate.swift
│   │   ├── DataDetectorExtractor.swift
│   │   ├── NaturalLanguageExtractor.swift
│   │   ├── LocationExtractor.swift
│   │   ├── EventDraftMerger.swift
│   │   └── ParseAlternative.swift
│   ├── Calendar/
│   │   ├── CalendarService.swift
│   │   ├── ICSExporter.swift
│   │   └── EventDraft.swift
│   ├── Review/
│   │   ├── ReviewWindowController.swift
│   │   ├── EventReviewView.swift
│   │   ├── ScreenshotPreviewView.swift
│   │   └── OCRTextView.swift
│   ├── Shelf/                         # later phase only
│   │   ├── EdgeTriggerWindow.swift
│   │   ├── EdgePanel.swift
│   │   ├── DropZoneView.swift
│   │   └── DropImageLoader.swift
│   ├── Capture/                       # later phase only
│   │   ├── ScreenshotCapture.swift
│   │   └── HotkeyManager.swift
│   └── Settings/                      # later phase unless needed earlier
│       ├── SettingsView.swift
│       └── HotkeySettingsView.swift
└── Tests/
    ├── OCR/
    │   ├── OCRLineMergerTests.swift
    │   └── OCRDocumentTests.swift
    ├── Parsing/
    │   ├── ChronoBridgeTests.swift
    │   ├── DataDetectorExtractorTests.swift
    │   ├── LocationExtractorTests.swift
    │   └── EventDraftMergerTests.swift
    ├── Calendar/
    │   ├── CalendarServiceMockTests.swift
    │   └── ICSExporterTests.swift
    └── Fixtures/
        ├── seminar_flyer.txt
        ├── concert_poster.txt
        ├── zoom_invite.txt
        ├── no_date.txt
        └── ambiguous_times.txt
```

---

## Build and run contract

Codex should use a shell-first loop.

Expected commands:

```bash
xcodegen generate
xcodebuild -project CalShot.xcodeproj -scheme CalShot -destination 'platform=macOS' build
xcodebuild -project CalShot.xcodeproj -scheme CalShot -destination 'platform=macOS' test
./script/build_and_run.sh --verify
./script/smoke_images.sh
```

`script/build_and_run.sh` must launch the built `.app` bundle, not the raw executable. This matters because Info.plist keys, bundle resources, privacy strings, entitlements, and menu-bar agent behavior depend on the app bundle. The build product should be staged to `dev/CalShot.app` so there is a stable Finder-friendly app path inside the working folder.

The script should support at least:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --image build/SmokeImages/01_university_seminar_flyer.png
./script/build_and_run.sh --clean
```

Suggested behavior:

```text
--clean
  Remove generated Xcode/DerivedData artifacts and dev/CalShot.app.
  Regenerate project.
  Build app.

--verify
  Regenerate project.
  Build app.
  Run unit tests.
  Confirm chrono.bundle.js exists in the built app bundle.
  Confirm Info.plist contains LSUIElement=true.
  Confirm NSCalendarsWriteOnlyAccessUsageDescription is present.
  Confirm calendar entitlement is present.
  Confirm dev/CalShot.app exists.
  Launch dev/CalShot.app and confirm the process exists.

--image <path>
  Stage the image into the app sandbox container for debug smoke testing.
  Launch dev/CalShot.app with that image as input.

no args
  Regenerate project if needed.
  Build Debug.
  Stage and open dev/CalShot.app.
```

`script/smoke_images.sh` should regenerate realistic deterministic image fixtures, run them through the built app bundle, and compare debug-only parsed-field summaries. It should not assert against full OCR text.

Codex local instructions belong in `AGENTS.md`. Repo-scoped Codex settings may go in `.codex/config.toml` if needed. Do not invent unsupported Codex environment files.

---

## Required Info.plist and entitlements

### Info.plist

Include:

```xml
<key>CFBundleDisplayName</key>
<string>CalShot</string>

<key>LSUIElement</key>
<true/>

<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>CalShot creates calendar events from screenshots after you review them.</string>
```

Do not use a vague calendar privacy string. It should say that the app creates calendar events after user review.

### Entitlements

If sandboxing or hardened runtime is enabled, include:

```xml
<key>com.apple.security.personal-information.calendars</key>
<true/>
```

For local development, keep the entitlements file present even if signing configuration changes later.

---

## Core data model

Use explicit models with field sources and parser alternatives.

```swift
struct OCRLine: Equatable, Sendable {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    let lineIndex: Int
}

struct OCRDocument: Equatable, Sendable {
    let lines: [OCRLine]
    let rawText: String
    let averageConfidence: Float
}
```

```swift
enum EventField: Hashable, Sendable {
    case title
    case start
    case end
    case allDay
    case location
    case url
    case notes
}

enum FieldSource: Equatable, Sendable {
    case chrono(text: String, confidence: Double)
    case dataDetector(text: String)
    case naturalLanguage(text: String)
    case heuristic(label: String, text: String)
    case userEdited
}

struct EventDraft: Equatable, Sendable {
    var title: String
    var start: Date?
    var end: Date?
    var allDay: Bool
    var location: String?
    var url: URL?
    var notes: String
    var alternatives: [ParseAlternative]
    var sources: [EventField: FieldSource]
}
```

```swift
struct ParseAlternative: Equatable, Sendable, Identifiable {
    let id: UUID
    let label: String
    let draftPatch: EventDraftPatch
    let source: FieldSource
    let confidence: Double
}
```

```swift
struct DateTimeCandidate: Equatable, Sendable, Identifiable {
    let id: UUID
    let matchedText: String
    let range: Range<String.Index>?
    let start: Date
    let end: Date?
    let hasCertainDate: Bool
    let hasCertainStartTime: Bool
    let hasCertainEndTime: Bool
    let isDateOnly: Bool
    let source: FieldSource
    let confidence: Double
}
```

The parser should produce candidates. The merger should decide which candidate becomes the default draft.

---

## Phase 0 — Project scaffold and app shell

Goal: create a clean buildable macOS project that Codex can repeatedly build, test, and launch.

### Slice 0.1 — Repo scaffold

Deliverables:

- `project.yml`
- `.gitignore`
- `README.md`
- `AGENTS.md`
- `script/build_and_run.sh`
- `Resources/Info.plist`
- `Resources/CalShot.entitlements`
- empty source/test folder structure

Acceptance criteria:

- `xcodegen generate` creates `CalShot.xcodeproj`.
- `CalShot.xcodeproj` is not the durable source of truth.
- The app target is named `CalShot`.
- The scheme is named `CalShot`.
- The bundle display name is `CalShot`.
- The bundle ID is `com.jgassens.CalShot`.
- Deployment target is macOS 14+.

### Slice 0.2 — Menu-bar agent shell

Deliverables:

- `CalShotApp.swift`
- `AppDelegate.swift`
- `MenuBarController.swift`
- simple menu-bar icon
- menu items:
  - `Open Image…`
  - `Process Clipboard Image`
  - `Preferences…` disabled or placeholder
  - `Quit CalShot`

Acceptance criteria:

- App launches as a menu-bar app.
- App does not appear in the Dock.
- Menu-bar item is visible.
- Quit works.
- `Open Image…` may initially show a placeholder alert.
- `Process Clipboard Image` may initially show a placeholder alert.

### Slice 0.3 — Build/run/test loop

Deliverables:

- `script/build_and_run.sh`
- initial test target
- at least one smoke test

Acceptance criteria:

- `./script/build_and_run.sh --verify` builds and runs tests.
- The script launches the `.app` bundle, not the raw binary.
- The script fails loudly if `chrono.bundle.js`, Info.plist keys, or expected resources are missing once those are introduced.

---

## Phase 1 — First shippable OCR-to-calendar workflow

Goal: open or paste an image, OCR it, parse a draft, review it, and create a calendar event or `.ics` fallback.

### Slice 1.1 — Image input and normalization

Deliverables:

- `ImageInputController.swift`
- `OpenImageLoader.swift`
- `ClipboardImageLoader.swift`
- `ImageNormalizer.swift`

Behavior:

- `Open Image…` presents `NSOpenPanel`.
- Accept common image types through `UTType.image`.
- Clipboard path reads image data from `NSPasteboard`.
- Normalize input into a type the OCR service can consume, preferably `CGImage` plus original `NSImage` for preview.

Acceptance criteria:

- Opening a PNG works.
- Opening a JPEG works.
- Opening a TIFF or HEIC should work if the system can load it.
- Clipboard image works when a screenshot is copied to the clipboard.
- If no clipboard image exists, the app shows a clear non-blocking error.
- Image orientation is handled correctly enough that text is not flipped or rotated unexpectedly.

Fallbacks:

- If clipboard loading fails, route user to `Open Image…`.
- If image normalization fails, show the image-loading error and do not proceed to OCR.

### Slice 1.2 — Vision OCR service

Deliverables:

- `OCRService.swift`
- `OCRDocument.swift`
- `OCRLineMerger.swift`

Behavior:

- Use `VNRecognizeTextRequest`.
- Use `.accurate` recognition.
- Use language correction.
- Extract best candidate text per observation.
- Preserve confidence.
- Preserve bounding boxes.
- Sort lines in visual reading order.
- Produce `OCRDocument`.

OCR ordering rule:

```text
Vision bounding boxes are normalized.
Sort primarily top-to-bottom, then left-to-right.
Keep a coordinate helper so SwiftUI previews can later overlay OCR boxes correctly.
```

Acceptance criteria:

- OCR returns structured lines.
- Raw text is joined from ordered lines.
- Average confidence is computed.
- Synthetic line-ordering tests pass.
- Empty OCR result is handled without crashing.

Fallbacks:

- If OCR confidence is low, continue to review UI but mark parse confidence low.
- If OCR returns no text, open the review UI with blank fields and the image preview.

### Slice 1.3 — Chrono bundle and JavaScriptCore bridge

Deliverables:

- `script/bundle_chrono.sh`
- `Resources/chrono.bundle.js`
- `ChronoBridge.swift`
- `DateTimeCandidate.swift`
- `ChronoBridgeTests.swift`
- license file under `Resources/Licenses/`

Behavior:

- Bundle `chrono-node` into a single IIFE file.
- Expose exactly one stable global wrapper:

```javascript
CalShotChrono.parse(text, refDateISO, timeZoneOrOffset)
```

- Swift calls that wrapper through JavaScriptCore.
- The bridge returns structured JSON, not loosely parsed strings.

The wrapper result should include at least:

```json
{
  "matchedText": "May 9 at 3 PM",
  "index": 10,
  "startDateISO": "2026-05-09T15:00:00.000-05:00",
  "endDateISO": null,
  "hasCertainDate": true,
  "hasCertainStartTime": true,
  "hasCertainEndTime": false,
  "knownValues": {},
  "impliedValues": {},
  "debug": null
}
```

Use `chrono.parse`, not `chrono.parseDate`.

Use `forwardDate: true`.

Handle timezone carefully. Prefer passing a numeric offset in minutes or a tested, documented mapping rather than assuming every IANA identifier will behave correctly in Chrono.

Acceptance criteria:

- `May 9, 2026` parses as a date candidate with no certain start time.
- `May 9 at 3 PM` parses as a date/time candidate with certain start time.
- `May 9, 3-5 PM` parses with an end time.
- `Friday at noon` resolves against a frozen reference date.
- Relative dates are future-biased.
- Tests do not depend on `Date()` or the developer machine's current date.

Fallbacks:

- If JavaScriptCore fails to load Chrono, fall back to `NSDataDetector` date extraction.
- If Chrono returns malformed JSON, log a debug-only diagnostic and continue with native extraction.

### Slice 1.4 — Native extractors

Deliverables:

- `DataDetectorExtractor.swift`
- `NaturalLanguageExtractor.swift`
- `LocationExtractor.swift`

Behavior:

`NSDataDetector` should extract:

- dates;
- addresses;
- URLs;
- phone numbers, optional for notes.

`NaturalLanguage` should extract soft candidates for:

- place names;
- organization names.

Location extractor priority:

```text
1. Full postal address from NSDataDetector
2. Line after cue labels: Location, Where, Venue, Room, Building, Place
3. Same-line cue labels: "Location: FO 2.702"
4. NaturalLanguage place or organization candidate
```

Do not use generic `at` text as a location fallback. Event text like `May 9 at 3 PM` or `Starts at 7 PM` is date/time evidence, not venue evidence.

Acceptance criteria:

- `123 Main St, Dallas, TX` is detected as an address.
- `Location: FO 2.702` becomes `FO 2.702`.
- `Zoom: https://...` extracts URL and can set location to `Zoom` or notes to include the URL.
- A plain organization name is not blindly used as location if a stronger location candidate exists.

Fallbacks:

- If no location is found, leave location blank.
- Do not fabricate a venue.

### Slice 1.5 — Event draft merger

Deliverables:

- `EventDraft.swift`
- `EventDraftMerger.swift`
- `ParseAlternative.swift`
- parser fixture tests

Behavior:

The merger combines OCR lines, Chrono candidates, native detector results, and heuristics into an editable `EventDraft`.

Canonical rules:

```text
Date-only match
  -> all-day event.

Date + start time, no end
  -> timed event with end = start + 1 hour.

Date + time range
  -> timed event with parsed end.

Multiple plausible dates/times
  -> choose the best default and include alternatives.

No date
  -> draft is shown, but Create Event is disabled.

Title
  -> best prominent leftover OCR line.
  -> fallback: first non-date, non-location, non-url line.
  -> fallback: Untitled Event.

Location
  -> address first.
  -> cue-word location second.
  -> NaturalLanguage soft signal third.
  -> blank if unknown.

URL
  -> prefer first http/https URL; otherwise fall back to the first detected URL.

Notes
  -> include OCR text or relevant source snippets according to UI decision.
  -> do not include full OCR text in release logs.
```

Candidate scoring should consider:

- source reliability;
- Chrono certainty;
- OCR confidence;
- cue words such as `date`, `time`, `when`, `starts`, `doors`, `talk`, `location`, `where`;
- line prominence if available;
- whether the candidate appears near event-like title text.

Acceptance criteria:

Fixture tests pass for:

```text
May 9, 2026                         -> all-day event
May 9 at 3 PM                       -> timed event with 1-hour default
May 9, 3-5 PM                       -> timed range
Friday at noon                      -> stable relative parse with frozen reference date
Doors 6 PM, talk 7 PM               -> alternatives
Location: FO 2.702                  -> room-style location
123 Main St, Dallas, TX             -> address
Zoom: https://...                   -> URL extraction
No date anywhere                    -> Create disabled until user supplies date
```

Fallbacks:

- If parser confidence is low, show the review UI and require user correction.
- If only a date is known, default to all-day rather than inventing noon.
- If only a time is known and no date is known, do not create an event until the user provides a date.

### Slice 1.6 — Mandatory review UI

Deliverables:

- `ReviewWindowController.swift`
- `EventReviewView.swift`
- `ScreenshotPreviewView.swift`
- `OCRTextView.swift`

Layout:

```text
Left column:
  screenshot preview
  OCR text
  OCR confidence
  parse diagnostics or alternatives

Right column:
  title field
  all-day toggle
  start date/time field
  end date/time field
  location field
  URL field
  notes field
  alternatives selector
  Create Event button
  Cancel button
```

Behavior:

- The review window appears after OCR/parsing.
- Every parsed field is editable.
- The Create Event button is disabled until a valid start date exists.
- Low-confidence fields are visibly marked.
- Alternatives are selectable and update the draft.
- User edits change the field source to `.userEdited`.
- Return triggers Create Event only when the draft is valid.
- Escape cancels.

Acceptance criteria:

- A valid parsed event can be edited and saved.
- A no-date event opens with Create disabled.
- User can manually supply a date and then save.
- The screenshot preview is visible.
- OCR text is visible and selectable/copyable.

Fallbacks:

- If OCR fails completely, show review UI with blank fields and image preview.
- If parser fails completely, show review UI with OCR text and blank event fields.

### Slice 1.7 — EventKit write-only save

Deliverables:

- `CalendarService.swift`
- `CalendarServiceMockTests.swift`

Behavior:

- Request write-only access to events.
- Create `EKEvent` from `EventDraft`.
- Use `eventStore.defaultCalendarForNewEvents`.
- Save with span `.thisEvent`.
- Do not read the user's calendar list.
- Do not build a calendar picker.

Event mapping:

```text
title       -> EKEvent.title
start       -> EKEvent.startDate
end         -> EKEvent.endDate
allDay      -> EKEvent.isAllDay
location    -> EKEvent.location
url         -> EKEvent.url
notes       -> EKEvent.notes
calendar    -> eventStore.defaultCalendarForNewEvents
```

Acceptance criteria:

- Permission prompt appears on first use.
- Granted permission creates an event.
- Denied permission triggers `.ics` fallback.
- Save failure triggers `.ics` fallback.
- Tests use mocks and do not touch the real calendar.

Fallbacks:

- If calendar permission is denied, export/open `.ics`.
- If default calendar is nil, export/open `.ics`.
- If save throws, export/open `.ics`.

### Slice 1.8 — `.ics` exporter fallback

Deliverables:

- `ICSExporter.swift`
- `ICSExporterTests.swift`

Behavior:

Generate a valid minimal iCalendar file.

Required fields:

```text
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//CalShot//CalShot//EN
BEGIN:VEVENT
UID:<uuid>@calshot.local
DTSTAMP:<utc timestamp>
DTSTART:<start>
DTEND:<end>
SUMMARY:<escaped title>
LOCATION:<escaped location, if present>
DESCRIPTION:<escaped notes, if present>
URL:<url, if present>
END:VEVENT
END:VCALENDAR
```

All-day events:

```text
DTSTART;VALUE=DATE:20260509
DTEND;VALUE=DATE:20260510
```

Timed events:

```text
DTSTART:20260509T200000Z
DTEND:20260509T210000Z
```

Escape text values correctly:

```text
\  -> \\
;  -> \;
,  -> \,
newline -> \n
```

Acceptance criteria:

- All-day `.ics` output uses `VALUE=DATE`.
- All-day `DTEND` is exclusive next day.
- Timed `.ics` output has valid UTC `DTSTART` and `DTEND`.
- Text escaping tests pass.
- `.ics` file opens in Calendar.app.

Fallbacks:

- If opening Calendar.app fails, reveal the `.ics` file in Finder.

### Slice 1.9 — Phase 0+1 verification

Deliverables:

- complete test suite for Phase 0+1
- `./script/build_and_run.sh --verify`
- manual acceptance checklist in this README marked complete when done

Automated acceptance:

```bash
xcodegen generate
xcodebuild -project CalShot.xcodeproj -scheme CalShot -destination 'platform=macOS' test
./script/build_and_run.sh --verify
./script/build_dmg.sh
```

Manual acceptance:

```text
Open Image… with a screenshot.
Process Clipboard Image with a copied screenshot.
OCR text appears.
Review window appears.
Parsed date/time/location are editable.
Create Event is disabled when no date exists.
Calendar permission prompt appears when saving.
Granted permission saves to Calendar.
Denied permission exports/opens .ics.
Temporary files are deleted.
Release logs do not contain OCR text.
```

Phase 0+1 is not complete until both automated and manual checks pass.

---

## Phase 2 — Yoink-style right-edge shelf

Goal: add the drag-and-drop shelf after the core pipeline is stable.

Do not start this phase until Phase 0+1 and menu-bar icon drop are green.

### Slice 2.1 — Edge trigger window

Deliverables:

- `EdgeTriggerWindow.swift`

Behavior:

- Transparent 4-8 px strip on the right edge of the main display.
- Accepts drag enter.
- Expands the visible shelf panel.
- Does not interfere with normal desktop use more than necessary.

Acceptance criteria:

- Dragging an image toward the right edge opens the panel.
- The app remains a menu-bar agent.
- The trigger strip is not visually distracting.

Fallbacks:

- Add a setting to disable the trigger strip.
- If edge trigger becomes annoying, show shelf only from menu-bar command.

### Slice 2.2 — Floating edge panel

Deliverables:

- `EdgePanel.swift`
- `DropZoneView.swift`

Behavior:

- Floating panel anchored to the right edge.
- Drop zone accepts image input.
- Panel collapses after successful drop or cancel.
- Reuses the Phase 1 image processing pipeline.

Acceptance criteria:

- Dropped image enters the same OCR/parse/review flow.
- Panel positioning survives normal display resize.
- Panel does not create a Dock icon.

Fallbacks:

- If the shelf positioning is unstable, keep menu-bar `Open Image…` as the reliable path.

### Slice 2.3 — Robust drag/drop types

Deliverables:

- `DropImageLoader.swift`

Accept:

```text
public.file-url
public.image
public.png
public.jpeg
public.tiff
NSPasteboard file promises
NSImage-compatible data
```

Acceptance criteria:

- Finder image file drop works.
- Screenshot thumbnail drop works if macOS provides a usable file or image representation.
- Mail/Safari/Photos image drops work where possible.
- Failed file promise falls back to image data if available.

Fallbacks:

- If file promise support is incomplete, keep file URL and clipboard paths reliable.

### Slice 2.4 — Multi-monitor refinement

Deliverables:

- trigger strategy for multiple `NSScreen`s

Acceptance criteria:

- Main-display behavior remains stable.
- Secondary display behavior is defined.

Fallbacks:

- v1 shelf may support only main display if multi-monitor behavior becomes noisy.

---

## Phase 3 — Hotkey and screenshot capture

Goal: let users capture a region and process it without manually opening the image.

Do not start this phase until Phase 2 is usable or explicitly deferred.

### Slice 3.1 — Configurable global hotkey

Preferred dependency:

```text
KeyboardShortcuts by Sindre Sorhus
```

Fallback:

```text
Carbon Event HotKey or another small native hotkey bridge
```

Deliverables:

- `HotkeyManager.swift`
- `HotkeySettingsView.swift`

Behavior:

- Default shortcut can be set in Settings.
- Avoid hardcoding one permanent shortcut.
- Hotkey triggers the screenshot capture flow.

Acceptance criteria:

- User can configure the shortcut.
- Shortcut survives relaunch.
- Shortcut conflict errors are visible.

Fallbacks:

- If the package causes build/signing friction, use a simple native hotkey bridge.
- If hotkey registration fails, keep menu-bar capture command.

### Slice 3.2 — Region screenshot capture

Personal/dev path:

```text
/usr/sbin/screencapture -i -x <tempfile>
```

Longer-term path:

```text
ScreenCaptureKit one-off screenshot / picker flow
```

Deliverables:

- `ScreenshotCapture.swift`

Behavior:

- Hotkey or menu command starts an interactive region screenshot.
- Captured image goes through the same OCR/parse/review pipeline.
- Cancel is treated as cancel, not as an error.

Acceptance criteria:

- Region screenshot capture works.
- Temporary captured file is deleted after processing.
- Canceling capture does not show noisy errors.

Fallbacks:

- If Screen Recording permission blocks capture, show a clear permission explanation and keep Open Image / Clipboard paths working.
- If `screencapture` is unsuitable for distribution, switch to ScreenCaptureKit.

---

## Phase 4 — Quality, preferences, and robustness

Goal: make the app comfortable for daily use after the main workflow is working.

Possible slices:

### Slice 4.1 — Preferences

Settings:

- default event duration;
- delete temp screenshots after save;
- keep local history, off by default;
- enable/disable edge shelf;
- choose OCR language correction behavior;
- show/hide OCR text by default;
- advanced parser diagnostics in debug builds.

### Slice 4.2 — Better parse UI

Features:

- field-level source badges;
- clickable alternatives;
- click OCR text to assign to title/location/date;
- visual overlay of OCR bounding boxes;
- low-confidence warning.

### Slice 4.3 — Better event notes

Possible notes format:

```text
Created by CalShot from screenshot.

Detected URL: ...
Detected phone: ...

OCR excerpt:
...
```

Do not dump large OCR text into notes unless the user accepts that behavior.

### Slice 4.4 — Error handling and diagnostics

Requirements:

- release logs should not include OCR text;
- debug logs may include parser diagnostics;
- errors should name the failed stage: image load, OCR, parse, review, calendar save, `.ics` export.

---

## Phase 5 — Optional Duckling backend

Goal: add Duckling only if fixture tests show Chrono plus native detectors are not good enough.

Do not add Duckling before Phase 0+1 is green.

### Decision criteria

Add Duckling only if at least one of these becomes true:

- Chrono fails too many real fixture screenshots.
- Multi-locale date parsing becomes important.
- Duration/range ambiguity materially reduces usefulness.
- The app is worth sidecar packaging complexity.

### Architecture

Duckling must implement the same backend protocol as Chrono. Do not wire it directly into the merger.

```swift
protocol DateTimeParserBackend {
    func parse(
        text: String,
        referenceDate: Date,
        timeZone: TimeZone
    ) async throws -> [DateTimeCandidate]
}
```

Backends:

```text
ChronoParserBackend
DataDetectorDateBackend
DucklingSidecarBackend
```

### Duckling sidecar constraints

If added:

- pin a known Duckling commit;
- include its BSD license;
- bind only to `127.0.0.1`;
- use a chosen high port;
- start/stop sidecar as needed;
- send locale, timezone, reference time, and dimensions;
- test with frozen reference dates;
- do not expose OCR text over the network beyond local loopback.

Fallbacks:

- If Duckling sidecar fails to start, use Chrono.
- If Duckling parse fails, use Chrono and native detectors.
- If packaging/signing becomes too costly, keep Duckling out.

---

## Phase 6 — Distribution, signing, sandboxing, and notarization

Goal: make CalShot distributable beyond local development.

Current direct-distribution lane:

```bash
./script/build_dmg.sh
CALSHOT_NOTARY_PROFILE=calshot-notary ./script/build_dmg.sh --notarize
./script/generate_appcast.sh --artifact dist/CalShot-<version>-<build>-notarized.dmg --release-tag v<version>
```

The release script builds a Release archive, signs with a Developer ID Application identity, verifies bundle resources, Sparkle updater settings, and entitlements, creates a DMG with an `/Applications` symlink, optionally submits to Apple notarization, staples the result, and writes a SHA-256 sidecar. Sparkle reads `appcast.xml` from the latest GitHub Release and installs signed DMG updates when `CFBundleVersion` increases.

Possible slices:

### Slice 6.1 — Signing and hardened runtime

- configure signing team;
- confirm entitlements;
- confirm bundle resources;
- confirm Calendar permission prompt;
- launch signed `.app` bundle.

### Slice 6.2 — Sandboxing review

- decide whether to sandbox;
- verify EventKit write-only access under sandbox;
- verify image file access through user-selected files;
- verify clipboard image access;
- verify screenshot capture approach.

### Slice 6.3 — Notarization

- archive app;
- notarize;
- staple;
- verify Gatekeeper acceptance;
- publish the exact DMG that passed verification.
- test on a clean Mac user account.

### Slice 6.4 — Sparkle appcast updates

- bump `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`;
- build and notarize the DMG;
- generate a signed Sparkle appcast with `script/generate_appcast.sh`;
- upload the DMG and `appcast.xml` to the matching GitHub Release;
- install the previous version and confirm Check for Updates finds the new build.

### Slice 6.5 — App Store decision

The App Store path may require replacing `screencapture` with ScreenCaptureKit and checking every entitlement/dependency. Keep this separate from the local personal-use app.

---

## Parser behavior specification

### Date and time

Rules:

```text
Date-only candidate
  -> all-day event.

Certain date + certain start time + no end
  -> timed event, default duration 1 hour.

Certain date + certain start time + certain end time
  -> timed range.

Only time, no date
  -> cannot create event until user supplies date.

Multiple candidates
  -> pick best default, preserve alternatives.

Relative date
  -> parse using frozen reference date in tests and future-biased behavior in app.
```

Do not infer noon from a date-only parse. A date-only event is all-day.

### Title

Preferred title source:

```text
1. Prominent leftover OCR line not consumed by date/time/location/URL.
2. First event-like leftover line.
3. First non-empty OCR line not consumed by another field.
4. Untitled Event.
```

Avoid titles that are only:

- dates;
- times;
- URLs;
- addresses;
- phone numbers;
- generic labels like `Location` or `When`.

### Location

Priority:

```text
1. Full postal address from NSDataDetector.
2. Explicit cue: Location:, Where:, Venue:, Room:, Building:.
3. Room/building pattern near a location cue.
4. NaturalLanguage place/org candidate.
5. Blank.
```

Do not hallucinate venues.

### URL

Rules:

```text
First http/https URL -> draft.url
If no web URL exists, first detected URL -> draft.url
Zoom/Teams/Meet URL -> include in notes and optionally set location to Zoom/Online
Multiple URLs -> first default, others in notes or alternatives
```

### Confidence

Keep confidence simple at first:

```text
High confidence:
  OCR average is acceptable and parser source is Chrono with certain date/time or strong NSDataDetector address.

Medium confidence:
  OCR average is acceptable but location/title required heuristics.

Low confidence:
  OCR confidence is low, parser certainty is weak, or key fields came only from soft signals.
```

The review UI should mark low-confidence fields. It should not block the user from saving if required fields are valid.

---

## Test plan

### Parser fixture tests

Required fixtures:

```text
May 9, 2026
  Expected: all-day, start date 2026-05-09, end date exclusive next day or EventKit all-day equivalent.

May 9 at 3 PM
  Expected: timed, start 3 PM local, end 4 PM local.

May 9, 3-5 PM
  Expected: timed range, start 3 PM local, end 5 PM local.

Friday at noon
  Expected: stable future Friday relative to frozen reference date.

Doors 6 PM, talk 7 PM
  Expected: alternatives preserved; default should be explainable.

Location: FO 2.702
  Expected: location FO 2.702.

123 Main St, Dallas, TX
  Expected: address detected.

Zoom: https://example.com/meeting
  Expected: URL detected; online location/notes behavior stable.

No date anywhere
  Expected: draft exists; Create disabled until date supplied.
```

### Chrono-specific tests

```text
Uses chrono.parse, not parseDate.
Returns matched text and index.
Returns start and optional end.
Returns certainty flags.
Uses forwardDate.
Handles frozen reference date.
Handles timezone/offset strategy.
Does not make date-only events timed.
```

### OCR tests

```text
Sort top-to-bottom, then left-to-right.
Merge fragmented same-line OCR when appropriate.
Preserve confidence.
Compute average confidence.
Handle empty OCR result.
```

### Calendar tests

Use mocks. Do not touch the real calendar in automated tests.

```text
Write-only success.
Permission denied.
Default calendar unavailable.
Save failure.
.ics fallback invoked.
```

### `.ics` tests

```text
All-day DTSTART;VALUE=DATE.
All-day exclusive DTEND.
Timed UTC DTSTART/DTEND.
UID present.
DTSTAMP present.
Escaped title/location/notes.
URL included when present.
```

### Manual tests

```text
Open Image… path.
Clipboard image path.
OCR success path.
OCR failure path.
Parser success path.
No-date parser path.
Calendar permission granted path.
Calendar permission denied path.
.ics file opens in Calendar.app.
Temp files deleted.
No release logging of OCR text.
```

---

## Codex operating rules

Codex should follow these rules while implementing the project.

### Work in small slices

Do not attempt the whole app in one pass. Implement one slice, build, test, then move on.

The preferred order is:

```text
0.1 repo scaffold
0.2 menu-bar shell
0.3 build loop
1.1 image input
1.2 OCR
1.3 Chrono bridge
1.4 native extractors
1.5 draft merger
1.6 review UI
1.7 EventKit save
1.8 .ics fallback
1.9 verification
```

### Never skip tests for parser behavior

Parser behavior will regress easily. Add fixture tests before polishing UI.

Use frozen reference dates. Do not let tests depend on the actual current date.

### Do not add later-phase features early

Until Phase 0+1 is green, do not add:

- right-edge shelf;
- file promises;
- global hotkey;
- screenshot capture;
- ScreenCaptureKit;
- Duckling;
- custom calendar picker;
- saved history;
- cloud APIs;
- LLM calls.

### Do not request full calendar access in v1

Use write-only access and the default calendar. A calendar picker requires reading calendars and therefore does not fit v1.

### Do not run raw executable for app verification

Launch the `.app` bundle. The raw executable does not validate Info.plist behavior, resources, privacy strings, or menu-bar agent behavior correctly.

### Do not log private OCR text in release builds

Debug-only diagnostics are acceptable. Release logs should not contain screenshots, OCR text, parsed event text, URLs, or locations.

### Keep fallbacks working

Even after later phases are added, these paths must remain reliable:

```text
Open Image…
Process Clipboard Image
Editable review UI
.ics fallback
```

---

## AGENTS.md recommendation

Create `AGENTS.md` with concise instructions for Codex. Suggested content:

````markdown
# AGENTS.md

## Build

Run:

```bash
xcodegen generate
xcodebuild -project CalShot.xcodeproj -scheme CalShot -destination 'platform=macOS' build
xcodebuild -project CalShot.xcodeproj -scheme CalShot -destination 'platform=macOS' test
./script/build_and_run.sh --verify
```

## Rules

- `project.yml` is authoritative. Do not manually preserve changes only inside the generated `.xcodeproj`.
- Launch the built `.app` bundle, not the raw executable.
- Implement README phases in order.
- Phase 0+1 comes before shelf, hotkey, screenshot capture, ScreenCaptureKit, or Duckling.
- Use EventKit write-only access and the default calendar in v1.
- Do not add a calendar picker in v1.
- Do not add cloud OCR, telemetry, or LLM calls.
- Keep network access limited to resolving user-provided event links.
- Do not log OCR text in release builds.
- Parser tests must use frozen reference dates.
````

---

## Definition of done

Phase 0+1 is done when:

```text
The app launches as CalShot in the menu bar.
The app does not appear in the Dock.
Open Image… loads an image.
Process Clipboard Image loads a copied screenshot.
Vision OCR produces structured OCRDocument output.
ChronoBridge parses dates/times with certainty metadata.
NSDataDetector extracts addresses and URLs.
EventDraftMerger creates a reasonable draft and alternatives.
Review UI is mandatory and editable.
Create Event is disabled without a date.
EventKit write-only save works when permission is granted.
.ics fallback works when permission is denied or save fails.
Tests pass.
script/build_and_run.sh --verify passes.
No release logs contain OCR text.
```

Only after that should the project move to the right-edge shelf and hotkey/capture phases.
