import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onOpenImage: () -> Void
    private let onProcessClipboard: () -> Void
    private let onSendSelectedText: () -> Void
    private let onDropInput: (DroppedInput) -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(
        onOpenImage: @escaping () -> Void,
        onProcessClipboard: @escaping () -> Void,
        onSendSelectedText: @escaping () -> Void,
        onDropInput: @escaping (DroppedInput) -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onOpenImage = onOpenImage
        self.onProcessClipboard = onProcessClipboard
        self.onSendSelectedText = onSendSelectedText
        self.onDropInput = onDropInput
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
        super.init()
        configure()
    }

    private func configure() {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Image...", action: #selector(openImage), keyEquivalent: "o")
        open.target = self
        open.keyEquivalentModifierMask = [.command]
        menu.addItem(open)

        let clipboard = NSMenuItem(title: "Process Clipboard Image", action: #selector(processClipboard), keyEquivalent: "v")
        clipboard.target = self
        clipboard.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(clipboard)

        let selectedText = NSMenuItem(title: "Send Selected Text", action: #selector(sendSelectedText), keyEquivalent: "c")
        selectedText.target = self
        selectedText.keyEquivalentModifierMask = [.command, .option, .control]
        menu.addItem(selectedText)

        menu.addItem(NSMenuItem.separator())

        let updates = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let quit = NSMenuItem(title: "Quit CalShot", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.length = NSStatusItem.squareLength
        statusItem.view = StatusItemDropView(
            frame: NSRect(x: 0, y: 0, width: NSStatusItem.squareLength, height: NSStatusBar.system.thickness),
            menu: menu,
            onDropInput: onDropInput
        )
    }

    @objc private func openImage() {
        onOpenImage()
    }

    @objc private func processClipboard() {
        onProcessClipboard()
    }

    @objc private func sendSelectedText() {
        onSendSelectedText()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    @objc private func quitApp() {
        onQuit()
    }
}
