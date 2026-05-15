import AppKit
import ApplicationServices
import Carbon
import OSLog

enum SelectedTextCaptureError: Error, LocalizedError {
    case accessibilityPermissionRequired
    case noSelectedText

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "CalShot does not currently have Accessibility permission for this app bundle."
        case .noSelectedText:
            return "CalShot could not copy selected text from the active app. Select event text and try again."
        }
    }
}

enum SelectedTextCapture {
    #if DEBUG
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.local.CalShot", category: "SelectedTextCapture")
    #endif

    @MainActor
    static func copySelectedTextPreservingClipboard() async throws -> String {
        guard accessibilityIsTrustedOrPrompted() else {
            #if DEBUG
            logger.error("Accessibility trust check failed for selected text capture")
            #endif
            throw SelectedTextCaptureError.accessibilityPermissionRequired
        }

        if let selectedText = frontmostApplicationSelectedText() {
            #if DEBUG
            logger.info("Captured selected text through frontmost app Accessibility; characters=\(selectedText.count)")
            #endif
            return selectedText
        }

        if let selectedText = focusedSelectedText() {
            #if DEBUG
            logger.info("Captured selected text through Accessibility; characters=\(selectedText.count)")
            #endif
            return selectedText
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let startingChangeCount = pasteboard.changeCount

        #if DEBUG
        logger.info("Accessibility selected text unavailable; falling back to Command-C copy")
        #endif
        try? await Task.sleep(nanoseconds: 150_000_000)
        postCommandC()

        let copiedText = await waitForCopiedText(on: pasteboard, after: startingChangeCount)
        snapshot.restore(to: pasteboard)

        guard let copiedText else {
            #if DEBUG
            logger.error("Selected text capture failed after Accessibility and Command-C fallback")
            #endif
            throw SelectedTextCaptureError.noSelectedText
        }
        #if DEBUG
        logger.info("Captured selected text through Command-C fallback; characters=\(copiedText.count)")
        #endif
        return copiedText
    }

    private static func accessibilityIsTrustedOrPrompted() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func frontmostApplicationSelectedText() -> String? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            #if DEBUG
            logger.debug("No frontmost application available for selected-text capture")
            #endif
            return nil
        }

        let currentPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        guard application.processIdentifier != currentPID else {
            #if DEBUG
            logger.debug("Frontmost application is CalShot; skipping direct selected-text read")
            #endif
            return nil
        }

        #if DEBUG
        logger.debug(
            "Trying frontmost app selected text; bundle=\(application.bundleIdentifier ?? "unknown", privacy: .public) pid=\(application.processIdentifier)"
        )
        #endif

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        if let selectedText = focusedSelectedText(in: applicationElement, label: "frontmost app") {
            return selectedText
        }

        return descendantSelectedText(in: applicationElement)
    }

    private static func focusedSelectedText() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        if let focusedApplication = focusedApplication(from: systemWideElement) {
            #if DEBUG
            logger.debug("Trying system-wide focused application selected text")
            #endif
            if let selectedText = focusedSelectedText(in: focusedApplication, label: "focused app") {
                return selectedText
            }
        }

        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedStatus == .success, let focusedValue else {
            #if DEBUG
            logger.debug("Could not read focused Accessibility element; status=\(focusedStatus.rawValue)")
            #endif
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement
        return selectedText(from: focusedElement, label: "system-wide focused element")
    }

    private static func focusedApplication(from systemWideElement: AXUIElement) -> AXUIElement? {
        var focusedApplicationValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplicationValue
        )
        guard status == .success, let focusedApplicationValue else {
            #if DEBUG
            logger.debug("Could not read focused Accessibility app; status=\(status.rawValue)")
            #endif
            return nil
        }
        return (focusedApplicationValue as! AXUIElement)
    }

    private static func focusedSelectedText(in applicationElement: AXUIElement, label: String) -> String? {
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedStatus == .success, let focusedValue else {
            #if DEBUG
            logger.debug("Could not read focused Accessibility element in \(label, privacy: .public); status=\(focusedStatus.rawValue)")
            #endif
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement
        return selectedText(from: focusedElement, label: label)
    }

    private static func selectedText(from element: AXUIElement, label: String) -> String? {
        var selectedValue: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard selectedStatus == .success, let selectedText = selectedValue as? String else {
            #if DEBUG
            logger.debug("\(label, privacy: .public) has no selected text attribute; status=\(selectedStatus.rawValue)")
            #endif
            return nil
        }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func descendantSelectedText(in root: AXUIElement) -> String? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visitedCount = 0

        while let (element, depth) = queue.first {
            queue.removeFirst()
            visitedCount += 1

            if let selectedText = selectedText(from: element, label: "descendant element") {
                #if DEBUG
                logger.debug("Found selected text while scanning Accessibility descendants; depth=\(depth) visited=\(visitedCount)")
                #endif
                return selectedText
            }

            guard depth < 5, visitedCount < 250 else {
                continue
            }

            var childrenValue: CFTypeRef?
            let childrenStatus = AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            )
            guard childrenStatus == .success, let children = childrenValue as? [AXUIElement] else {
                continue
            }

            queue.append(contentsOf: children.prefix(60).map { ($0, depth + 1) })
        }

        #if DEBUG
        logger.debug("No selected text found while scanning Accessibility descendants; visited=\(visitedCount)")
        #endif
        return nil
    }

    private static func postCommandC() {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    @MainActor
    private static func waitForCopiedText(on pasteboard: NSPasteboard, after startingChangeCount: Int) async -> String? {
        for _ in 0..<24 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            guard pasteboard.changeCount != startingChangeCount else {
                continue
            }

            let text = pasteboard.string(forType: .string)
                ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
                ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.plain-text"))
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed?.isEmpty == false {
                return trimmed
            }
        }
        return nil
    }
}

private struct PasteboardSnapshot {
    private var items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var captured: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    captured[type] = data
                }
            }
            return captured
        } ?? []

        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let pasteboardItems = items.map { capturedItem in
            let item = NSPasteboardItem()
            for (type, data) in capturedItem {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(pasteboardItems)
    }
}
