import AppKit

final class StatusItemDropView: NSView {
    private let statusMenu: NSMenu
    private let onDropInput: (DroppedInput) -> Void
    private let icon = NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: "CalShot")?
        .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
    private var isDragTargeted = false

    init(frame frameRect: NSRect, menu: NSMenu, onDropInput: @escaping (DroppedInput) -> Void) {
        self.statusMenu = menu
        self.onDropInput = onDropInput
        super.init(frame: frameRect)
        registerForDraggedTypes(DropInputLoader.acceptedPasteboardTypes)
        toolTip = "CalShot"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSStatusItem.squareLength, height: NSStatusBar.system.thickness)
    }

    override var allowsVibrancy: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY - 4), in: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isDragTargeted {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
        }

        guard let icon else { return }
        let iconSize = NSSize(width: 18, height: 18)
        let iconRect = NSRect(
            x: bounds.midX - iconSize.width / 2,
            y: bounds.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        drawIcon(icon, in: iconRect, color: .white)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DropPasteboardDiagnostics.log("draggingEntered", pasteboard: sender.draggingPasteboard)

        guard DropInputLoader.canAcceptDrop(from: sender.draggingPasteboard) else {
            return []
        }
        isDragTargeted = true
        needsDisplay = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        DropInputLoader.canAcceptDrop(from: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragTargeted = false
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DropPasteboardDiagnostics.log("prepareForDragOperation", pasteboard: sender.draggingPasteboard)
        return DropInputLoader.canAcceptDrop(from: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DropPasteboardDiagnostics.log("performDragOperation", pasteboard: sender.draggingPasteboard)

        defer {
            isDragTargeted = false
            needsDisplay = true
        }

        do {
            if let input = try DropInputLoader.loadImmediate(from: sender.draggingPasteboard) {
                onDropInput(input)
                return true
            }
            let isReceivingPromise = DropInputLoader.receivePromisedEmailFiles(from: sender.draggingPasteboard) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isDragTargeted = false
                    self?.needsDisplay = true

                    switch result {
                    case .success(let url):
                        self?.onDropInput(.emailFile(url))
                    case .failure(let error):
                        self?.showUnsupportedDropAlert(error)
                    }
                }
            }

            if isReceivingPromise {
                return true
            }

            if DropInputLoader.canAcceptDrop(from: sender.draggingPasteboard) {
                showUnsupportedDropAlert(nil)
                return true
            }

            return false
        } catch {
            showUnsupportedDropAlert(error)
            return false
        }
    }

    private func drawIcon(_ image: NSImage, in rect: NSRect, color: NSColor) {
        guard let tinted = image.tinted(with: color) else {
            image.draw(in: rect)
            return
        }
        tinted.draw(in: rect)
    }

    private func showUnsupportedDropAlert(_ error: Error?) {
        let diagnosticPath = DropInputLoader.diagnosticLogURL?.path
        let detail: String
        if let error {
            detail = "\n\n\(error.localizedDescription)"
        } else {
            detail = ""
        }

        let diagnosticText = diagnosticPath.map {
            "\n\nA drag diagnostic log was written here:\n\($0)"
        } ?? ""

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "CalShot could not read that drop"
        alert.informativeText = """
        The menu icon saw the drag, but macOS did not provide a usable image or .eml file. Try dropping the email through Yoink or Finder, or send me the diagnostic log so I can map Outlook's pasteboard type.\(detail)\(diagnosticText)
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage? {
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        defer { tinted.unlockFocus() }

        draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.isTemplate = false
        return tinted
    }
}
