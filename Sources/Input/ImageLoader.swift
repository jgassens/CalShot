import AppKit
import UniformTypeIdentifiers

enum ImageLoaderError: Error, LocalizedError {
    case unreadable(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return "CalShot could not load an image from \(url.lastPathComponent)."
        }
    }
}

enum ImageLoader {
    static func openImagePanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.prompt = "Process"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func loadImage(from url: URL) throws -> NSImage {
        guard let image = NSImage(contentsOf: url) else {
            throw ImageLoaderError.unreadable(url)
        }
        return ImageNormalizer.normalized(image)
    }
}

enum ClipboardImageLoader {
    static func loadImage() -> NSImage? {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            return ImageNormalizer.normalized(image)
        }
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) {
            return ImageNormalizer.normalized(image)
        }
        if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) {
            return ImageNormalizer.normalized(image)
        }
        return nil
    }
}

enum ImageNormalizer {
    static func normalized(_ image: NSImage) -> NSImage {
        let copy = NSImage(size: image.size)
        copy.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1)
        copy.unlockFocus()
        return copy
    }
}

