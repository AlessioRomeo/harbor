// Draws Harbor's app icon at 1024 pt; turn it into Resources/AppIcon.icns with sips and iconutil. Run: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments[1]

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// macOS icon grid: an 824 pt tile centred on the 1024 canvas, with a soft drop shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45).cgColor)
color(0x1B1C20).setFill()
tilePath.fill()
context.restoreGState()

context.saveGState()
tilePath.addClip()
NSGradient(colors: [color(0x2B2D33), color(0x16171B)])!.draw(in: tile, angle: -90)
// A faint sheen along the top edge.
NSGradient(colors: [color(0xFFFFFF, 0.07), color(0xFFFFFF, 0)])!.draw(in: NSRect(x: tile.minX, y: tile.maxY - 260, width: tile.width, height: 260), angle: -90)

// One bold prompt chevron, readable down to Finder's smallest size.
let chevron = NSBezierPath()
let cx = tile.minX + 298, cy = tile.midY - 10
chevron.move(to: NSPoint(x: cx, y: cy + 170))
chevron.line(to: NSPoint(x: cx + 180, y: cy))
chevron.line(to: NSPoint(x: cx, y: cy - 170))
chevron.lineWidth = 92
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
color(0xE6E8EC).setStroke()
chevron.stroke()

// The amber beacon: something needs me.
let dot = NSRect(x: tile.maxX - 272, y: cy - 190, width: 120, height: 120)
context.setShadow(offset: .zero, blur: 60, color: color(0xE8B464, 0.75).cgColor)
color(0xEDB863).setFill()
NSBezierPath(ovalIn: dot).fill()
context.restoreGState()

image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
