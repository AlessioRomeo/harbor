// Draws the background of the disk image's window, with an arrow from Harbor to Applications.
// It stays light because Finder draws the icon names in black on a disk image's background.
// Run: swift scripts/make-dmg-background.swift <output-1x.png> <output-2x.png>, then combine them
// into Resources/dmg-background.tiff with tiffutil -cathidpicheck.
import AppKit

/// The window's content size in points; scripts/dmg-settings.py places the icons on it.
let width: CGFloat = 640
let height: CGFloat = 400

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(scale: CGFloat, to path: String) {
    let pixels = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    pixels.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: pixels)

    NSGradient(starting: color(0xF6F6F8), ending: color(0xE6E7EB))!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // Icons sit centred at x 170 and 470, y 190 from the top; the arrow runs between them.
    let arrowY = height - 190
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: arrowY))
    arrow.line(to: NSPoint(x: 372, y: arrowY))
    arrow.move(to: NSPoint(x: 360, y: arrowY + 11))
    arrow.line(to: NSPoint(x: 374, y: arrowY))
    arrow.line(to: NSPoint(x: 360, y: arrowY - 11))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0x4A78B5).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    try! pixels.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(scale: 1, to: CommandLine.arguments[1])
render(scale: 2, to: CommandLine.arguments[2])
