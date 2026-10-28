import AppKit
import SwiftTerm
import SwiftUI

enum Theme {
    static let terminalBackground = NSColor(hex: 0x17181B)
    static let terminalForeground = NSColor(hex: 0xD6D8DD)
    static let caret = NSColor(hex: 0xC9CCD3)
    static let selection = NSColor(hex: 0x3A3F4B)
    static let secondaryText = Color(nsColor: NSColor(hex: 0x8B8F98))
    static let quietIndicator = Color(nsColor: NSColor(hex: 0x6E727B))
    static let running = Color(nsColor: NSColor(hex: 0x7AA2D6))

    static let terminalPadding: CGFloat = 14
    static let defaultFontSize: CGFloat = 13
    static let fontSizeRange: ClosedRange<CGFloat> = 9...28

    static func terminalFont(size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static let ansiColors: [SwiftTerm.Color] = [
        0x2A2C31, 0xD9797F, 0x9CC48A, 0xDDBF7A, 0x7AA2D6, 0xC49BD6, 0x7FC1C8, 0xC9CCD3,
        0x5C6068, 0xE8898F, 0xADD49C, 0xEACD8C, 0x8DB4E6, 0xD3ABE3, 0x92D0D6, 0xECEEF2,
    ].map { hex in
        SwiftTerm.Color(red8: UInt16(hex >> 16 & 0xFF), green8: UInt16(hex >> 8 & 0xFF), blue8: UInt16(hex & 0xFF))
    }
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
            green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
