import AppKit
import SwiftUI

@MainActor
final class ReviewWindowPresenter {
    private var controllers: [ReviewWindowController] = []

    func show(image: NSImage, document: OCRDocument, draft: EventDraft, calendarService: CalendarService) {
        let viewModel = EventReviewViewModel(
            image: image,
            document: document,
            draft: draft,
            calendarService: calendarService
        )

        let controller = ReviewWindowController(viewModel: viewModel)
        controllers.append(controller)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.controllers.removeAll { $0 === controller }
        }
        controller.show()
    }
}

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(viewModel: EventReviewViewModel) {
        let root = EventReviewView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: root)
        let contentRect = Self.preferredContentRect()
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Review Event"
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentViewController = hosting
        window.minSize = Self.minimumWindowSize(for: contentRect)
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        viewModel.closeWindow = { [weak self] in self?.window?.close() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        if let window {
            Self.place(window)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                Self.place(window)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private static func preferredContentRect() -> NSRect {
        let visibleFrame = mainDisplayVisibleFrame()
        let width = min(680, max(560, visibleFrame.width * 0.42))
        let height = min(820, max(640, visibleFrame.height * 0.74))
        return NSRect(x: visibleFrame.midX - width / 2, y: visibleFrame.midY - height / 2, width: width, height: height)
    }

    private static func place(_ window: NSWindow) {
        let frame = Self.preferredWindowFrame(for: window)
        window.setFrame(frame, display: true, animate: false)
    }

    private static func preferredWindowFrame(for window: NSWindow) -> NSRect {
        let visibleFrame = mainDisplayVisibleFrame()
        let margin: CGFloat = 20
        var frame = window.frame
        frame.size.width = min(frame.size.width, 700, visibleFrame.width - margin * 2)
        frame.size.height = min(frame.size.height, 840, visibleFrame.height - margin * 2)
        frame.origin.x = visibleFrame.midX - frame.size.width / 2
        frame.origin.y = visibleFrame.midY - frame.size.height / 2
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX + margin), visibleFrame.maxX - frame.size.width - margin)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + margin), visibleFrame.maxY - frame.size.height - margin)
        return frame
    }

    private static func minimumWindowSize(for contentRect: NSRect) -> NSSize {
        NSSize(width: min(520, contentRect.width), height: min(600, contentRect.height))
    }

    private static func mainDisplayVisibleFrame() -> NSRect {
        let displayFrame = primaryDisplayFrame()
        let matchingScreen = NSScreen.screens.first { screen in
            abs(screen.frame.minX - displayFrame.minX) < 1 &&
                abs(screen.frame.minY - displayFrame.minY) < 1 &&
                abs(screen.frame.width - displayFrame.width) < 1 &&
                abs(screen.frame.height - displayFrame.height) < 1
        }

        if let visibleFrame = matchingScreen?.visibleFrame {
            return visibleFrame
        }

        let topInset: CGFloat = 32
        let bottomInset: CGFloat = 80
        return NSRect(
            x: displayFrame.minX,
            y: displayFrame.minY + bottomInset,
            width: displayFrame.width,
            height: max(1, displayFrame.height - topInset - bottomInset)
        )
    }

    private static func primaryDisplayFrame() -> NSRect {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return CGDisplayBounds(CGMainDisplayID())
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else {
            return CGDisplayBounds(CGMainDisplayID())
        }

        let frames = displays.prefix(Int(displayCount)).map(CGDisplayBounds)
        return frames.first { abs($0.minX) < 1 && abs($0.minY) < 1 }
            ?? CGDisplayBounds(CGMainDisplayID())
    }
}
