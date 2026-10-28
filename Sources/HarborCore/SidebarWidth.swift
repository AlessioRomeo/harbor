import Foundation

/// How wide the sidebar is, kept within the range it reads well at.
public enum SidebarWidth {
    public static let range: ClosedRange<Double> = 220...360
    public static let standard: Double = 250
    /// Dragging the divider below this hides the sidebar instead of narrowing it.
    public static let hidingThreshold: Double = 100

    public static func clamped(_ width: Double) -> Double {
        min(max(width, range.lowerBound), range.upperBound)
    }

    /// The width AppKit's split view saved for the sidebar, from frames like
    /// `"0.000000, 0.000000, 200.500000, 734.000000, NO, NO"` (x, y, width, height, collapsed, hidden).
    /// A collapsed sidebar saved no width worth keeping.
    public static func fromSavedSplitViewFrames(_ frames: [String]) -> Double? {
        guard let sidebar = frames.first else { return nil }
        let fields = sidebar.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 5, fields[4] == "NO", let width = Double(fields[2]), width > 0 else { return nil }
        return width
    }
}
