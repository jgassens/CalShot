import AppKit
import UniformTypeIdentifiers

enum DropImageLoader {
    static let acceptedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .png,
        .tiff,
        NSPasteboard.PasteboardType(UTType.image.identifier),
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.png.identifier),
        NSPasteboard.PasteboardType(UTType.tiff.identifier)
    ]

    static func canLoadImage(from pasteboard: NSPasteboard) -> Bool {
        imageFileURL(from: pasteboard) != nil || NSImage(pasteboard: pasteboard) != nil
    }

    static func loadImage(from pasteboard: NSPasteboard) throws -> NSImage? {
        if let url = imageFileURL(from: pasteboard) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try ImageLoader.loadImage(from: url)
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return ImageNormalizer.normalized(image)
        }

        return nil
    }

    private static func imageFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           let url = urls.first {
            return url
        }

        if let value = pasteboard.string(forType: .fileURL),
           let url = URL(string: value),
           isImageFile(url) {
            return url
        }

        return nil
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return type.conforms(to: .image)
    }
}
