import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "build/SmokeImages"
let outputURL = URL(
    fileURLWithPath: outputPath,
    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
).standardizedFileURL
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let canvas = NSSize(width: 1400, height: 1800)

func savePNG(named filename: String, draw: (NSRect) -> Void) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(origin: .zero, size: canvas))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CalShotSmokeImages", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode \(filename)"])
    }

    let url = outputURL.appendingPathComponent(filename)
    try data.write(to: url)
    print(url.path)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: y, width: width, height: height)
}

func roundedRect(_ rect: NSRect, radius: CGFloat = 24) {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func text(
    _ value: String,
    _ rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = .black,
    alignment: NSTextAlignment = .left,
    lineHeight: CGFloat? = nil
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    value.draw(in: rect, withAttributes: attributes)
}

func mono(_ value: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
        .foregroundColor: color
    ]
    value.draw(in: rect, withAttributes: attributes)
}

func noise(in rect: NSRect, color: NSColor, count: Int) {
    for index in 0..<count {
        let x = rect.minX + CGFloat((index * 73) % Int(max(rect.width, 1)))
        let y = rect.minY + CGFloat((index * 41) % Int(max(rect.height, 1)))
        color.withAlphaComponent(index.isMultiple(of: 2) ? 0.08 : 0.035).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: CGFloat(18 + (index % 30)), height: CGFloat(18 + (index % 30)))).fill()
    }
}

try savePNG(named: "01_university_seminar_flyer.png") { bounds in
    NSGradient(colors: [
        NSColor(calibratedRed: 0.92, green: 0.89, blue: 0.80, alpha: 1),
        NSColor(calibratedRed: 0.75, green: 0.84, blue: 0.83, alpha: 1)
    ])!.draw(in: bounds, angle: 90)
    noise(in: bounds, color: .black, count: 170)

    NSColor(calibratedRed: 0.05, green: 0.18, blue: 0.32, alpha: 1).setFill()
    roundedRect(rect(72, 1180, 1256, 470), radius: 42)
    text("Microglia and Memory", rect(130, 1420, 1160, 130), size: 82, weight: .heavy, color: .white)
    text("Immunology Seminar Series", rect(134, 1338, 850, 72), size: 42, weight: .semibold, color: NSColor(calibratedWhite: 0.93, alpha: 1))

    NSColor.white.withAlphaComponent(0.96).setFill()
    roundedRect(rect(120, 1005, 370, 250), radius: 30)
    text("SAT", rect(150, 1185, 300, 42), size: 34, weight: .bold, color: NSColor(calibratedRed: 0.05, green: 0.18, blue: 0.32, alpha: 1), alignment: .center)
    text("MAY 9", rect(145, 1090, 310, 92), size: 76, weight: .heavy, color: .black, alignment: .center)
    text("2026", rect(150, 1042, 300, 42), size: 34, weight: .semibold, color: .darkGray, alignment: .center)

    NSColor.white.withAlphaComponent(0.92).setFill()
    roundedRect(rect(535, 1005, 745, 250), radius: 30)
    text("3:00 PM - 4:00 PM", rect(590, 1156, 650, 60), size: 48, weight: .bold)
    text("Where: FO 2.702", rect(590, 1080, 650, 58), size: 44, weight: .semibold)
    text("Speaker: Dr. Maya Rivera", rect(590, 1018, 650, 54), size: 34, weight: .regular)

    text("Hosted by the Center for Neuroimmune Signaling", rect(120, 880, 1160, 60), size: 36, weight: .medium, color: NSColor(calibratedWhite: 0.15, alpha: 1), alignment: .center)
}

try savePNG(named: "02_concert_poster.png") { bounds in
    NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.05, blue: 0.13, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.36, blue: 0.18, alpha: 1)
    ])!.draw(in: bounds, angle: 70)
    noise(in: bounds, color: .white, count: 220)

    NSColor.black.withAlphaComponent(0.25).setFill()
    roundedRect(rect(86, 170, 1228, 1460), radius: 58)
    text("THE STATIC ARCADES", rect(135, 1380, 1130, 150), size: 88, weight: .black, color: .white, alignment: .center, lineHeight: 96)
    text("one night only", rect(210, 1280, 980, 60), size: 42, weight: .semibold, color: NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.55, alpha: 1), alignment: .center)

    NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.55, alpha: 1).setFill()
    roundedRect(rect(160, 1025, 1080, 130), radius: 26)
    text("FRIDAY, MAY 8", rect(190, 1054, 410, 70), size: 48, weight: .heavy, color: .black)
    text("DOORS 6 PM  |  SHOW 7 PM", rect(610, 1058, 600, 66), size: 38, weight: .bold, color: .black, alignment: .right)

    NSColor.white.withAlphaComponent(0.9).setFill()
    roundedRect(rect(215, 770, 970, 155), radius: 24)
    text("Venue: The Longhorn Room", rect(260, 844, 880, 50), size: 42, weight: .bold)
    text("221B Elm Street, Dallas, TX", rect(260, 790, 880, 44), size: 34, weight: .medium, color: .darkGray)

    text("with PALACE ROAD and DJ NORA", rect(170, 560, 1060, 72), size: 46, weight: .semibold, color: .white, alignment: .center)
    text("Tickets at example.com/static", rect(170, 400, 1060, 54), size: 34, weight: .medium, color: .white, alignment: .center)
}

try savePNG(named: "03_zoom_invite_email.png") { bounds in
    NSColor(calibratedRed: 0.87, green: 0.89, blue: 0.93, alpha: 1).setFill()
    bounds.fill()

    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    roundedRect(rect(105, 225, 1190, 1350), radius: 34)
    NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.62, alpha: 1).setFill()
    roundedRect(rect(105, 1395, 1190, 180), radius: 34)
    text("Calendar invitation", rect(160, 1486, 560, 56), size: 40, weight: .semibold, color: .white)
    text("From: program.office@example.edu", rect(160, 1428, 850, 48), size: 30, weight: .medium, color: NSColor(calibratedWhite: 0.92, alpha: 1))

    text("T32 Writing Workshop", rect(160, 1268, 1000, 80), size: 64, weight: .bold)
    NSColor(calibratedRed: 0.94, green: 0.96, blue: 1.0, alpha: 1).setFill()
    roundedRect(rect(160, 1060, 1080, 160), radius: 24)
    text("When: May 12 at 10:30 AM", rect(205, 1142, 900, 52), size: 42, weight: .semibold)
    text("Where: Zoom", rect(205, 1086, 900, 46), size: 36, weight: .medium)

    text("Join link:", rect(165, 915, 200, 48), size: 32, weight: .semibold, color: .darkGray)
    mono("https://example.com/t32-writing-room", rect(165, 855, 1050, 60), size: 38, weight: .medium, color: NSColor(calibratedRed: 0.08, green: 0.27, blue: 0.60, alpha: 1))
    text("Agenda", rect(165, 710, 260, 54), size: 38, weight: .bold)
    text("10:30 AM  Grant aims overview\n11:00 AM  Biosketch examples\n11:30 AM  Open work time", rect(165, 565, 960, 150), size: 34, weight: .regular, color: NSColor(calibratedWhite: 0.16, alpha: 1), lineHeight: 46)
}

try savePNG(named: "04_design_review_story.png") { bounds in
    NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.09, blue: 0.12, alpha: 1),
        NSColor(calibratedRed: 0.31, green: 0.27, blue: 0.42, alpha: 1)
    ])!.draw(in: bounds, angle: -30)
    noise(in: bounds, color: .white, count: 260)

    NSColor(calibratedRed: 0.88, green: 0.78, blue: 0.45, alpha: 1).setFill()
    roundedRect(rect(110, 1265, 1180, 190), radius: 18)
    text("DESIGN REVIEW", rect(150, 1315, 1100, 95), size: 82, weight: .black, color: .black, alignment: .center)

    text("student poster clinic", rect(180, 1190, 1040, 62), size: 48, weight: .semibold, color: .white, alignment: .center)
    NSColor.white.withAlphaComponent(0.92).setFill()
    roundedRect(rect(190, 905, 1020, 180), radius: 28)
    text("May 9 // 3-5 PM", rect(240, 988, 920, 58), size: 50, weight: .heavy)
    text("Room: Founders Hall", rect(240, 925, 920, 50), size: 40, weight: .semibold)

    text("bring a draft, leave with a plan", rect(190, 735, 1020, 70), size: 46, weight: .medium, color: NSColor(calibratedRed: 0.88, green: 0.78, blue: 0.45, alpha: 1), alignment: .center)
    text("Hosted by CalShot Lab", rect(190, 520, 1020, 46), size: 32, weight: .medium, color: .white, alignment: .center)
}

try savePNG(named: "05_bulletin_no_date.png") { bounds in
    NSColor(calibratedRed: 0.78, green: 0.70, blue: 0.56, alpha: 1).setFill()
    bounds.fill()
    noise(in: bounds, color: .black, count: 240)

    NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.88, alpha: 1).setFill()
    roundedRect(rect(170, 240, 1060, 1300), radius: 14)
    NSColor(calibratedRed: 0.78, green: 0.12, blue: 0.10, alpha: 1).setFill()
    roundedRect(rect(250, 1235, 900, 145), radius: 12)
    text("OPEN HOUSE", rect(275, 1274, 850, 72), size: 66, weight: .black, color: .white, alignment: .center)

    text("Visit the teaching lab", rect(260, 1115, 880, 72), size: 54, weight: .bold, alignment: .center)
    text("Venue: Building C", rect(265, 970, 860, 56), size: 44, weight: .semibold)
    text("No schedule shown", rect(265, 900, 860, 48), size: 36, weight: .medium, color: .darkGray)
    text("Drop in for tours, snacks, and demonstrations.", rect(265, 760, 860, 112), size: 38, weight: .regular, lineHeight: 48)
    text("Ask at the front desk for room details.", rect(265, 640, 860, 54), size: 34, weight: .regular, color: .darkGray)

    NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: rect(665, 1450, 70, 70)).fill()
}
