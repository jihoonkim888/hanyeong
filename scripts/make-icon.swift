// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // All measurements are on the 1024-point macOS icon grid.
    let scale = size / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }
    func draw(_ text: String, font: NSFont, color: NSColor, centeredIn box: NSRect) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let bounds = string.size()
        string.draw(at: NSPoint(x: box.midX - bounds.width / 2, y: box.midY - bounds.height / 2))
    }

    let tile = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 185 * scale, yRadius: 185 * scale)
    NSGradient(
        starting: NSColor(srgbRed: 0.36, green: 0.60, blue: 1.00, alpha: 1),
        ending: NSColor(srgbRed: 0.13, green: 0.33, blue: 0.90, alpha: 1)
    )!.draw(in: tile, angle: -90)

    let korean = NSFont(name: "AppleSDGothicNeo-Bold", size: 400 * scale) ?? .boldSystemFont(ofSize: 400 * scale)
    draw("한", font: korean, color: .white, centeredIn: rect(130, 370, 560, 500))

    // The badge sits on a ring of the background colour so it reads as a separate key.
    let badge = rect(548, 158, 300, 300)
    let badgeBlue = NSColor(srgbRed: 0.15, green: 0.36, blue: 0.92, alpha: 1)
    badgeBlue.setFill()
    NSBezierPath(roundedRect: badge.insetBy(dx: -26 * scale, dy: -26 * scale), xRadius: 100 * scale, yRadius: 100 * scale).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: badge, xRadius: 76 * scale, yRadius: 76 * scale).fill()
    draw("A", font: .systemFont(ofSize: 200 * scale, weight: .bold), color: badgeBlue, centeredIn: badge)

    return bitmap
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(size: CGFloat(points * factor)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
