import AppKit

@MainActor
final class ProcessingCoordinator {
    private let merger: EventDraftMerger
    private let calendarService: CalendarService
    private let reviewPresenter: ReviewWindowPresenter
    private let urlResolutionService: EventURLResolutionService

    init() {
        self.merger = EventDraftMerger()
        self.calendarService = CalendarService()
        self.reviewPresenter = ReviewWindowPresenter()
        self.urlResolutionService = .live
    }

    init(
        merger: EventDraftMerger,
        calendarService: CalendarService,
        reviewPresenter: ReviewWindowPresenter,
        urlResolutionService: EventURLResolutionService = .live
    ) {
        self.merger = merger
        self.calendarService = calendarService
        self.reviewPresenter = reviewPresenter
        self.urlResolutionService = urlResolutionService
    }

    func openImage() {
        NSApp.activate(ignoringOtherApps: true)
        guard let url = ImageLoader.openImagePanel() else { return }
        do {
            let image = try ImageLoader.loadImage(from: url)
            process(image)
        } catch {
            showAlert(title: "Could not open image", message: error.localizedDescription)
        }
    }

    func processClipboardImage() {
        NSApp.activate(ignoringOtherApps: true)
        guard let image = ClipboardImageLoader.loadImage() else {
            showAlert(title: "No clipboard image", message: "Copy a screenshot or image, then choose Process Clipboard Image again.")
            return
        }
        process(image)
    }

    func processImage(_ image: NSImage) {
        NSApp.activate(ignoringOtherApps: true)
        process(image)
    }

    func processDroppedInput(_ input: DroppedInput) {
        switch input {
        case .image(let image):
            processImage(image)
        case .emailFile(let url):
            processEmail(at: url)
        }
    }

    func processImage(at url: URL, smokeSummaryURL: URL? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        do {
            let image = try ImageLoader.loadImage(from: url)
            process(image, smokeSummaryURL: smokeSummaryURL)
        } catch {
            showAlert(title: "Could not open image", message: error.localizedDescription)
        }
    }

    func processSelectedTextUsingCopyShortcut() {
        Task { @MainActor in
            do {
                let text = try await SelectedTextCapture.copySelectedTextPreservingClipboard()
                processText(text)
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                showSelectedTextError(error)
            }
        }
    }

    func processText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showAlert(title: "No selected text", message: "Select event text, then choose Send to CalShot again.")
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let document = OCRDocument.textOnly(trimmed)
            var draft = merger.makeDraft(from: document)
            draft = await urlResolutionService.resolvingMeetingRedirects(in: draft, document: document)
            let image = TextPreviewImage.make(from: trimmed)
            reviewPresenter.show(image: image, document: document, draft: draft, calendarService: calendarService)
        }
    }

    func processEmail(at url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let didAccess = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let email = try EmailMessageLoader.load(from: url)
                let imageOCRText = try await ocrText(from: email.imageAttachments)
                let text = email.combinedTextForParsing(imageOCRText: imageOCRText)
                let document = OCRDocument.textOnly(text)
                var draft = merger.makeDraft(from: document)
                draft = await urlResolutionService.resolvingMeetingRedirects(in: draft, document: document)
                applyEmailSubjectTitle(email.cleanedSubject, to: &draft)

                let preview = TextPreviewImage.makeEmail(
                    subject: email.cleanedSubject,
                    from: email.from,
                    sentDate: email.sentDate,
                    body: email.bodyText
                )
                reviewPresenter.show(image: preview, document: document, draft: draft, calendarService: calendarService)
            } catch {
                showAlert(title: "Could not read email", message: error.localizedDescription)
            }
        }
    }

    private func process(_ image: NSImage, smokeSummaryURL: URL? = nil) {
        Task { @MainActor in
            do {
                let document = try await OCRService.recognizeDocument(in: image)
                var draft = merger.makeDraft(from: document)
                draft = await urlResolutionService.resolvingMeetingRedirects(in: draft, document: document)
                #if DEBUG
                if let smokeSummaryURL {
                    SmokeSummary.write(draft, to: smokeSummaryURL)
                }
                #endif
                reviewPresenter.show(image: image, document: document, draft: draft, calendarService: calendarService)
            } catch {
                let document = OCRDocument.empty
                let draft = EventDraft.empty(notes: "OCR failed: \(error.localizedDescription)")
                #if DEBUG
                if let smokeSummaryURL {
                    SmokeSummary.write(draft, to: smokeSummaryURL)
                }
                #endif
                reviewPresenter.show(image: image, document: document, draft: draft, calendarService: calendarService)
            }
        }
    }

    private func ocrText(from attachments: [EmailImageAttachment]) async throws -> [String] {
        var recognized: [String] = []
        for attachment in attachments {
            guard let image = NSImage(data: attachment.data) else { continue }
            let document: OCRDocument
            do {
                document = try await OCRService.recognizeDocument(in: image)
            } catch {
                #if DEBUG
                NSLog("[CalShot Email] OCR skipped for \(attachment.filename ?? attachment.mimeType): \(error.localizedDescription)")
                #endif
                continue
            }
            let text = document.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                recognized.append(text)
            }
        }
        return recognized
    }

    private func applyEmailSubjectTitle(_ subject: String, to draft: inout EventDraft) {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let email = EmailMessage(
            subject: trimmed,
            from: nil,
            sentDate: nil,
            bodyText: "",
            links: [],
            imageAttachments: []
        )

        if email.shouldPreferSubject(over: draft.title) {
            draft.title = trimmed
            draft.sources[.title] = .heuristic(label: "email subject", text: trimmed)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func showSelectedTextError(_ error: Error) {
        if case SelectedTextCaptureError.accessibilityPermissionRequired = error {
            showAccessibilityPermissionAlert()
        } else {
            showAlert(title: "Could not send selected text", message: error.localizedDescription)
        }
    }

    private func showAccessibilityPermissionAlert() {
        let appPath = Bundle.main.bundleURL.path
        let alert = NSAlert()
        alert.messageText = "CalShot needs Accessibility access"
        alert.informativeText = """
        Open Accessibility settings, make sure this exact app is enabled, then quit and reopen CalShot:

        \(appPath)

        If you see more than one CalShot entry, remove the old ones and add this copy.
        """
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
