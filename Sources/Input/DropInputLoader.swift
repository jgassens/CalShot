import AppKit

enum DroppedInput {
    case image(NSImage)
    case emailFile(URL)
}

enum DropInputLoader {
    static let diagnosticLogURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("CalShot", isDirectory: true)
        .appendingPathComponent("DragPasteboard.log")

    static let emailPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        NSPasteboard.PasteboardType("public.file-url"),
        NSPasteboard.PasteboardType("public.email-message"),
        NSPasteboard.PasteboardType("message/rfc822"),
        NSPasteboard.PasteboardType("public.message"),
        NSPasteboard.PasteboardType("com.microsoft.outlook.mail-message"),
        NSPasteboard.PasteboardType("com.microsoft.outlook.email-message"),
        NSPasteboard.PasteboardType("com.microsoft.outlook.message"),
        NSPasteboard.PasteboardType("com.microsoft.outlook.item"),
        NSPasteboard.PasteboardType("com.microsoft.outlook.mailitem"),
        NSPasteboard.PasteboardType("com.microsoft.outlook.email"),
        NSPasteboard.PasteboardType("com.microsoft.outlook.outlookitem"),
        NSPasteboard.PasteboardType("com.microsoft.outlook15.message"),
        NSPasteboard.PasteboardType("com.microsoft.outlook16.message"),
        NSPasteboard.PasteboardType("com.microsoft.outlook16.mail-message"),
        NSPasteboard.PasteboardType("com.microsoft.Outlook.Message"),
        NSPasteboard.PasteboardType("com.microsoft.Outlook.Messages"),
        NSPasteboard.PasteboardType("com.microsoft.Outlook.mail-message"),
        NSPasteboard.PasteboardType("com.microsoft.Outlook.MailMessage"),
        NSPasteboard.PasteboardType("com.microsoft.Outlook.Email"),
        NSPasteboard.PasteboardType("com.microsoft.Outlook.EmailMessage"),
        NSPasteboard.PasteboardType("com.microsoft.Outlook.MailItem"),
        NSPasteboard.PasteboardType("com.microsoft.Outlook.FilePromise"),
        NSPasteboard.PasteboardType("com.microsoft.kOlxMessagePasteboardType"),
        NSPasteboard.PasteboardType("com.microsoft.kOlxContactsAndGroupsPasteboardType"),
        NSPasteboard.PasteboardType("WMOutlookInternalFilePromisePboardType"),
        NSPasteboard.PasteboardType("MSOutlookPboardType"),
        NSPasteboard.PasteboardType("Microsoft Outlook Mail")
    ]

    static let acceptedPasteboardTypes: [NSPasteboard.PasteboardType] = {
        let filePromiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }
        var types = DropImageLoader.acceptedPasteboardTypes + emailPasteboardTypes + filePromiseTypes
        var seen: Set<String> = []
        types.removeAll { type in
            !seen.insert(type.rawValue).inserted
        }
        return types
    }()

    static func canLoad(from pasteboard: NSPasteboard) -> Bool {
        DropImageLoader.canLoadImage(from: pasteboard)
            || emailFileURL(from: pasteboard) != nil
            || hasPromisedEmailFile(from: pasteboard)
    }

    static func canAcceptDrop(from pasteboard: NSPasteboard) -> Bool {
        canLoad(from: pasteboard) || looksLikeEmailOrMessageDrag(pasteboard)
    }

    static func loadImmediate(from pasteboard: NSPasteboard) throws -> DroppedInput? {
        if let emailURL = emailFileURL(from: pasteboard) {
            return .emailFile(emailURL)
        }

        if let image = try DropImageLoader.loadImage(from: pasteboard) {
            return .image(image)
        }

        return nil
    }

    @discardableResult
    static func receivePromisedEmailFiles(
        from pasteboard: NSPasteboard,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> Bool {
        let receivers = promisedEmailReceivers(from: pasteboard)
        guard !receivers.isEmpty else { return false }

        do {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("CalShotEmailDrops", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

            for receiver in receivers {
                receiver.receivePromisedFiles(
                    atDestination: destination,
                    options: [:],
                    operationQueue: .main
                ) { url, error in
                    if let error {
                        completion(.failure(error))
                        return
                    }

                    guard isEmailFile(url) || looksLikeEmailOrMessageDrag(pasteboard) else {
                        completion(.failure(DropInputLoaderError.unsupportedPromisedFile(url)))
                        return
                    }
                    completion(.success(url))
                }
            }
            return true
        } catch {
            completion(.failure(error))
            return true
        }
    }

    private static func emailFileURL(from pasteboard: NSPasteboard) -> URL? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first(where: isEmailFile) {
            return url
        }

        if let value = pasteboard.string(forType: .fileURL),
           let url = URL(string: value),
           isEmailFile(url) {
            return url
        }

        return nil
    }

    private static func hasPromisedEmailFile(from pasteboard: NSPasteboard) -> Bool {
        !promisedEmailReceivers(from: pasteboard).isEmpty
    }

    private static func promisedEmailReceivers(from pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []

        let explicitEmailReceivers = receivers.filter { receiver in
            receiver.fileTypes.contains(where: isEmailFileType)
        }
        if !explicitEmailReceivers.isEmpty {
            return explicitEmailReceivers
        }

        guard looksLikeEmailOrMessageDrag(pasteboard) else { return [] }

        return receivers.filter { receiver in
            receiver.fileTypes.isEmpty
                || receiver.fileTypes.contains("public.file-url")
                || receiver.fileTypes.contains("dyn.ah62d4rv4gu8yc6durvwwa3xmrvw1gkdusm1044pxqzb085xyqz1hk64uqm10c6xenv61a3k")
                || receiver.fileTypes.contains("NSPromiseContentsPboardType")
        }
    }

    private static func looksLikeEmailOrMessageDrag(_ pasteboard: NSPasteboard) -> Bool {
        let typeNames = pasteboard.types?.map { $0.rawValue.lowercased() } ?? []
        return typeNames.contains { type in
            type.contains("outlook")
                || type.contains("email")
                || type.contains("message")
                || type.contains("eml")
        }
    }

    private static func isEmailFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "eml"
    }

    private static func isEmailFileType(_ type: String) -> Bool {
        let lower = type.lowercased()
        return lower == "eml"
            || lower == "message/rfc822"
            || lower == "public.email-message"
            || lower.contains("outlook")
            || lower.contains("email")
            || lower.contains("message")
    }
}

enum DropPasteboardDiagnostics {
    static func resetLog() {
        guard let url = DropInputLoader.diagnosticLogURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "CalShot drag diagnostics\n".write(to: url, atomically: true, encoding: .utf8)
    }

    static func log(_ event: String, pasteboard: NSPasteboard) {
        #if DEBUG
        guard let url = DropInputLoader.diagnosticLogURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lines: [String] = []
        lines.append("")
        lines.append("[\(Self.timestamp())] \(event)")
        lines.append("canLoad=\(DropInputLoader.canLoad(from: pasteboard)) canAcceptDrop=\(DropInputLoader.canAcceptDrop(from: pasteboard))")
        lines.append("types:")
        for type in pasteboard.types ?? [] {
            lines.append("  - \(type.rawValue)")
        }

        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        lines.append("filePromiseReceivers=\(receivers.count)")
        for receiver in receivers {
            lines.append("  fileTypes=\(receiver.fileTypes.joined(separator: ", "))")
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            lines.append("fileURLs:")
            for url in urls {
                lines.append("  - \(url.lastPathComponent) [.\(url.pathExtension)]")
            }
        }

        let body = lines.joined(separator: "\n") + "\n"
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(body.utf8))
                try? handle.close()
            }
        } else {
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

enum DropInputLoaderError: Error, LocalizedError {
    case unsupportedPromisedFile(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedPromisedFile(let url):
            return "CalShot could not use promised file \(url.lastPathComponent)."
        }
    }
}
