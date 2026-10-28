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

// Three panes: a large one on the left, two stacked on the right.
let inset: CGFloat = 112
let gap: CGFloat = 26
let area = tile.insetBy(dx: inset, dy: inset)
let leftWidth = (area.width - gap) * 0.6
let left = NSRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height)
let rightX = left.maxX + gap
let rightWidth = area.maxX - rightX
let paneHeight = (area.height - gap) / 2
let topRight = NSRect(x: rightX, y: area.minY + paneHeight + gap, width: rightWidth, height: paneHeight)
let bottomRight = NSRect(x: rightX, y: area.minY, width: rightWidth, height: paneHeight)

for (pane, focused) in [(left, true), (topRight, false), (bottomRight, false)] {
    let path = NSBezierPath(roundedRect: pane, xRadius: 34, yRadius: 34)
    (focused ? color(0x0F1013, 0.92) : color(0x0F1013, 0.6)).setFill()
    path.fill()
    path.lineWidth = 3
    (focused ? color(0x7AA2D6, 0.55) : color(0xFFFFFF, 0.07)).setStroke()
    path.stroke()
}

// Prompt chevron and cursor in the focused pane.
let chevron = NSBezierPath()
let cx = left.minX + 70, cy = left.midY + 60
chevron.move(to: NSPoint(x: cx, y: cy + 62))
chevron.line(to: NSPoint(x: cx + 66, y: cy))
chevron.line(to: NSPoint(x: cx, y: cy - 62))
chevron.lineWidth = 30
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
color(0xD6D8DD).setStroke()
chevron.stroke()
color(0x7AA2D6).setFill()
NSBezierPath(roundedRect: NSRect(x: cx + 104, y: cy - 66, width: 70, height: 26), xRadius: 8, yRadius: 8).fill()

// A few quiet lines of output in the other panes.
color(0xFFFFFF, 0.13).setFill()
for (pane, widths) in [(topRight, [0.62, 0.42]), (bottomRight, [0.5, 0.7, 0.35])] {
    for (index, share) in widths.enumerated() {
        let y = pane.maxY - 62 - CGFloat(index) * 40
        NSBezierPath(roundedRect: NSRect(x: pane.minX + 36, y: y, width: (pane.width - 72) * share, height: 16), xRadius: 8, yRadius: 8).fill()
    }
}

// The amber signal: something needs me.
let dot = NSRect(x: topRight.maxX - 62, y: topRight.maxY - 62, width: 32, height: 32)
context.setShadow(offset: .zero, blur: 22, color: color(0xE8B464, 0.85).cgColor)
color(0xE8B464).setFill()
NSBezierPath(ovalIn: dot).fill()
context.restoreGState()

image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
