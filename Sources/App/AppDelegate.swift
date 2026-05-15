import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var globalTextHotkeyController: GlobalTextHotkeyController?
    private let coordinator = ProcessingCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        menuBarController = MenuBarController(
            onOpenImage: { [weak self] in self?.coordinator.openImage() },
            onProcessClipboard: { [weak self] in self?.coordinator.processClipboardImage() },
            onSendSelectedText: { [weak self] in self?.coordinator.processSelectedTextUsingCopyShortcut() },
            onDropInput: { [weak self] input in self?.coordinator.processDroppedInput(input) },
            onQuit: { NSApp.terminate(nil) }
        )
        globalTextHotkeyController = GlobalTextHotkeyController(
            onHotkey: { [weak self] in self?.coordinator.processSelectedTextUsingCopyShortcut() }
        )

        #if DEBUG
        DropPasteboardDiagnostics.resetLog()
        let launchConfiguration = Self.debugLaunchConfiguration()
        for url in launchConfiguration.imageURLs {
            coordinator.processImage(at: url, smokeSummaryURL: launchConfiguration.smokeSummaryURL)
        }
        for url in launchConfiguration.emailURLs {
            coordinator.processEmail(at: url)
        }
        #endif
    }

    @objc(sendTextToCalShot:userData:error:)
    func sendTextToCalShot(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let selectedText = pasteboard.string(forType: .string)
            ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
            ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.plain-text"))

        guard let selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "CalShot could not read selected text from the Services pasteboard." as NSString
            return
        }

        coordinator.processText(selectedText)
    }

    #if DEBUG
    private struct DebugLaunchConfiguration {
        var imageURLs: [URL] = []
        var emailURLs: [URL] = []
        var smokeSummaryURL: URL?
    }

    private static func debugLaunchConfiguration() -> DebugLaunchConfiguration {
        var configuration = DebugLaunchConfiguration()
        var iterator = CommandLine.arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            if argument == "--calshot-open-image", let path = iterator.next() {
                configuration.imageURLs.append(URL(fileURLWithPath: path))
            } else if argument.hasPrefix("--calshot-open-image=") {
                let path = String(argument.dropFirst("--calshot-open-image=".count))
                configuration.imageURLs.append(URL(fileURLWithPath: path))
            } else if argument == "--calshot-open-email", let path = iterator.next() {
                configuration.emailURLs.append(URL(fileURLWithPath: path))
            } else if argument.hasPrefix("--calshot-open-email=") {
                let path = String(argument.dropFirst("--calshot-open-email=".count))
                configuration.emailURLs.append(URL(fileURLWithPath: path))
            } else if argument == "--calshot-smoke-summary-file", let path = iterator.next() {
                configuration.smokeSummaryURL = URL(fileURLWithPath: path)
            } else if argument.hasPrefix("--calshot-smoke-summary-file=") {
                let path = String(argument.dropFirst("--calshot-smoke-summary-file=".count))
                configuration.smokeSummaryURL = URL(fileURLWithPath: path)
            }
        }

        return configuration
    }
    #endif
}
