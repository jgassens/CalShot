import AppKit

enum TextPreviewImage {
    static func make(from text: String, size: NSSize = NSSize(width: 720, height: 360)) -> NSImage {
        makeCard(title: "Selected Text", subtitle: nil, body: text, size: size)
    }

    static func makeEmail(
        subject: String,
        from: String?,
        sentDate: String?,
        body: String,
        size: NSSize = NSSize(width: 720, height: 360)
    ) -> NSImage {
        let subtitle = [from, sentDate]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        return makeCard(
            title: subject.isEmpty ? "Email" : subject,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            body: body,
            size: size
        )
    }

    private static func makeCard(title: String, subtitle: String?, body: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let inset: CGFloat = 28
        let cardRect = bounds.insetBy(dx: inset, dy: inset)
        let card = NSBezierPath(roundedRect: cardRect, xRadius: 16, yRadius: 16)
        NSColor.textBackgroundColor.setFill()
        card.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineBreakMode = .byTruncatingTail
        bodyParagraph.lineSpacing = 4
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: bodyParagraph
        ]

        title.draw(
            in: NSRect(x: cardRect.minX + 22, y: cardRect.maxY - 58, width: cardRect.width - 44, height: 30),
            withAttributes: titleAttributes
        )

        let bodyTop: CGFloat
        if let subtitle {
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            subtitle.draw(
                in: NSRect(x: cardRect.minX + 22, y: cardRect.maxY - 84, width: cardRect.width - 44, height: 22),
                withAttributes: subtitleAttributes
            )
            bodyTop = cardRect.height - 120
        } else {
            bodyTop = cardRect.height - 94
        }

        let previewText = body
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(7)
            .joined(separator: "\n")

        previewText.draw(
            in: NSRect(x: cardRect.minX + 22, y: cardRect.minY + 26, width: cardRect.width - 44, height: bodyTop),
            withAttributes: bodyAttributes
        )

        image.unlockFocus()
        return image
    }
}
