import CoreGraphics
import Foundation

public enum SplitAxis: String, Codable, Sendable {
    /// Side by side.
    case horizontal
    /// One above the other.
    case vertical
}

public enum PaneEdge: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom

    var axis: SplitAxis { self == .left || self == .right ? .horizontal : .vertical }
    var placesFirst: Bool { self == .left || self == .top }
}

/// Where a session goes relative to a pane: beside it on an edge, or in its place.
public enum PaneDrop: Equatable, Sendable {
    case edge(PaneEdge)
    case center
}

/// How the window is divided between sessions: a binary split tree whose leaves are session ids.
public indirect enum PaneLayout: Codable, Equatable, Sendable {
    case pane(UUID)
    case split(SplitAxis, ratio: Double, first: PaneLayout, second: PaneLayout)

    public static let ratioRange: ClosedRange<Double> = 0.1...0.9
    public static let maxGridPanes = 12

    public var sessionIDs: [UUID] {
        switch self {
        case .pane(let id): [id]
        case .split(_, _, let first, let second): first.sessionIDs + second.sessionIDs
        }
    }

    public func contains(_ id: UUID) -> Bool {
        sessionIDs.contains(id)
    }

    // MARK: Building

    /// Splits `target`'s pane, putting `newID` on the given edge, half and half.
    public func splitting(_ target: UUID, with newID: UUID, at edge: PaneEdge) -> PaneLayout {
        mapPane(target) { existing in
            let added = PaneLayout.pane(newID)
            return edge.placesFirst
                ? .split(edge.axis, ratio: 0.5, first: added, second: existing)
                : .split(edge.axis, ratio: 0.5, first: existing, second: added)
        }
    }

    /// The pane that gets the keyboard when `id` goes: the first pane of the part that takes its space.
    public func successor(of id: UUID) -> UUID? {
        guard case .split(_, _, let first, let second) = self else { return nil }
        if first == .pane(id) { return second.sessionIDs.first }
        if second == .pane(id) { return first.sessionIDs.first }
        return first.contains(id) ? first.successor(of: id) : second.successor(of: id)
    }

    /// Removes a pane; its sibling takes the space. Nil when nothing is left.
    public func removing(_ id: UUID) -> PaneLayout? {
        switch self {
        case .pane(let paneID):
            return paneID == id ? nil : self
        case .split(let axis, let ratio, let first, let second):
            switch (first.removing(id), second.removing(id)) {
            case (nil, nil): return nil
            case (let remaining?, nil), (nil, let remaining?): return remaining
            case (let newFirst?, let newSecond?): return .split(axis, ratio: ratio, first: newFirst, second: newSecond)
            }
        }
    }

    /// Puts `newID` in `target`'s place. If `newID` is already on screen, the two swap.
    public func replacing(_ target: UUID, with newID: UUID) -> PaneLayout {
        guard target != newID else { return self }
        let alreadyShown = contains(newID)
        return mapLeaves { id in
            if id == target { return newID }
            if alreadyShown, id == newID { return target }
            return id
        }
    }

    /// Moves `id` (on screen or not) next to or into `target`'s pane.
    public func placing(_ id: UUID, at drop: PaneDrop, of target: UUID) -> PaneLayout {
        guard id != target else { return self }
        switch drop {
        case .center:
            return replacing(target, with: id)
        case .edge(let edge):
            guard let remaining = removing(id), remaining.contains(target) else { return self }
            return remaining.splitting(target, with: id, at: edge)
        }
    }

    /// An even grid filled row by row, at most `maxGridPanes` sessions.
    public static func grid(_ ids: [UUID]) -> PaneLayout? {
        let ids = Array(ids.prefix(maxGridPanes))
        guard !ids.isEmpty else { return nil }
        let rowCount = Int(Double(ids.count).squareRoot().rounded(.up))
        let perRow = Int((Double(ids.count) / Double(rowCount)).rounded(.up))
        let rows = stride(from: 0, to: ids.count, by: perRow).map { Array(ids[$0..<min($0 + perRow, ids.count)]) }
        return evenChain(rows.compactMap { evenChain($0.map(PaneLayout.pane), axis: .horizontal) }, axis: .vertical)
    }

    /// Children laid out along `axis` in equal parts.
    private static func evenChain(_ parts: [PaneLayout], axis: SplitAxis) -> PaneLayout? {
        guard let first = parts.first else { return nil }
        guard let rest = evenChain(Array(parts.dropFirst()), axis: axis) else { return first }
        return .split(axis, ratio: 1 / Double(parts.count), first: first, second: rest)
    }

    // MARK: Sizing

    static func clamped(_ ratio: Double) -> Double {
        ratio.isFinite ? min(max(ratio, ratioRange.lowerBound), ratioRange.upperBound) : 0.5
    }

    /// Sets the ratio of the split found by following `path` (false = first child, true = second).
    public func settingRatio(_ ratio: Double, at path: [Bool]) -> PaneLayout {
        let clamped = Self.clamped(ratio)
        guard case .split(let axis, let current, let first, let second) = self else { return self }
        guard let step = path.first else {
            return .split(axis, ratio: clamped, first: first, second: second)
        }
        let rest = Array(path.dropFirst())
        return step
            ? .split(axis, ratio: current, first: first, second: second.settingRatio(ratio, at: rest))
            : .split(axis, ratio: current, first: first.settingRatio(ratio, at: rest), second: second)
    }

    /// Every split shares its space in proportion to the panes on each side, so all panes along an axis match.
    public var evened: PaneLayout {
        guard case .split(let axis, _, let first, let second) = self else { return self }
        let firstCount = Double(first.paneCount(along: axis))
        let secondCount = Double(second.paneCount(along: axis))
        return .split(axis, ratio: Self.clamped(firstCount / (firstCount + secondCount)), first: first.evened, second: second.evened)
    }

    private func paneCount(along axis: SplitAxis) -> Int {
        switch self {
        case .pane: 1
        case .split(let splitAxis, _, let first, let second):
            splitAxis == axis
                ? first.paneCount(along: axis) + second.paneCount(along: axis)
                : max(first.paneCount(along: axis), second.paneCount(along: axis))
        }
    }

    /// Each pane's rectangle when the layout fills `bounds`.
    public func frames(in bounds: CGRect) -> [UUID: CGRect] {
        switch self {
        case .pane(let id):
            return [id: bounds]
        case .split(let axis, let ratio, let first, let second):
            let (firstRect, secondRect) = Self.divide(bounds, axis: axis, ratio: ratio)
            return first.frames(in: firstRect).merging(second.frames(in: secondRect)) { $1 }
        }
    }

    /// A split's place on screen, for drawing and dragging its divider.
    public struct SplitArea: Equatable, Sendable {
        /// Which child to take at each level to reach this split (false = first, true = second).
        public var path: [Bool]
        public var axis: SplitAxis
        public var ratio: Double
        public var bounds: CGRect

        /// The line between the two sides.
        public var dividerPosition: CGFloat {
            axis == .horizontal ? bounds.minX + bounds.width * ratio : bounds.minY + bounds.height * ratio
        }
    }

    public func splitAreas(in bounds: CGRect, path: [Bool] = []) -> [SplitArea] {
        guard case .split(let axis, let ratio, let first, let second) = self else { return [] }
        let (firstRect, secondRect) = Self.divide(bounds, axis: axis, ratio: ratio)
        return [SplitArea(path: path, axis: axis, ratio: ratio, bounds: bounds)]
            + first.splitAreas(in: firstRect, path: path + [false])
            + second.splitAreas(in: secondRect, path: path + [true])
    }

    public static func divide(_ bounds: CGRect, axis: SplitAxis, ratio: Double) -> (CGRect, CGRect) {
        switch axis {
        case .horizontal:
            let width = bounds.width * ratio
            return (
                CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height),
                CGRect(x: bounds.minX + width, y: bounds.minY, width: bounds.width - width, height: bounds.height)
            )
        case .vertical:
            let height = bounds.height * ratio
            return (
                CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height),
                CGRect(x: bounds.minX, y: bounds.minY + height, width: bounds.width, height: bounds.height - height)
            )
        }
    }

    /// The pane next to `id` in a direction, judged on a unit square with y growing downwards:
    /// the nearest pane beyond that edge that overlaps it, preferring the largest overlap.
    public func neighbour(of id: UUID, toward edge: PaneEdge) -> UUID? {
        let frames = frames(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let origin = frames[id] else { return nil }
        let epsilon = 1e-9
        let candidates = frames.filter { otherID, rect in
            guard otherID != id else { return false }
            switch edge {
            case .left: return abs(rect.maxX - origin.minX) < epsilon && Self.overlap(rect.minY...rect.maxY, origin.minY...origin.maxY) > 0
            case .right: return abs(rect.minX - origin.maxX) < epsilon && Self.overlap(rect.minY...rect.maxY, origin.minY...origin.maxY) > 0
            case .top: return abs(rect.maxY - origin.minY) < epsilon && Self.overlap(rect.minX...rect.maxX, origin.minX...origin.maxX) > 0
            case .bottom: return abs(rect.minY - origin.maxY) < epsilon && Self.overlap(rect.minX...rect.maxX, origin.minX...origin.maxX) > 0
            }
        }
        return candidates.max { a, b in
            let overlapA = edge.axis == .horizontal ? Self.overlap(a.value.minY...a.value.maxY, origin.minY...origin.maxY) : Self.overlap(a.value.minX...a.value.maxX, origin.minX...origin.maxX)
            let overlapB = edge.axis == .horizontal ? Self.overlap(b.value.minY...b.value.maxY, origin.minY...origin.maxY) : Self.overlap(b.value.minX...b.value.maxX, origin.minX...origin.maxX)
            return overlapA == overlapB ? a.key.uuidString > b.key.uuidString : overlapA < overlapB
        }?.key
    }

    private static func overlap(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(a.upperBound, b.upperBound) - max(a.lowerBound, b.lowerBound))
    }

    // MARK: Hygiene

    /// Keeps only panes of sessions in `ids`, each once.
    public func pruned(keeping ids: Set<UUID>) -> PaneLayout? {
        var seen: Set<UUID> = []
        return prunedVisiting(ids, &seen)
    }

    private func prunedVisiting(_ ids: Set<UUID>, _ seen: inout Set<UUID>) -> PaneLayout? {
        switch self {
        case .pane(let id):
            guard ids.contains(id), seen.insert(id).inserted else { return nil }
            return self
        case .split(let axis, let ratio, let first, let second):
            let newFirst = first.prunedVisiting(ids, &seen)
            let newSecond = second.prunedVisiting(ids, &seen)
            switch (newFirst, newSecond) {
            case (nil, nil): return nil
            case (let remaining?, nil), (nil, let remaining?): return remaining
            case (let a?, let b?):
                return .split(axis, ratio: Self.clamped(ratio), first: a, second: b)
            }
        }
    }

    // MARK: Helpers

    private func mapPane(_ target: UUID, _ transform: (PaneLayout) -> PaneLayout) -> PaneLayout {
        switch self {
        case .pane(let id):
            return id == target ? transform(self) : self
        case .split(let axis, let ratio, let first, let second):
            return .split(axis, ratio: ratio, first: first.mapPane(target, transform), second: second.mapPane(target, transform))
        }
    }

    private func mapLeaves(_ transform: (UUID) -> UUID) -> PaneLayout {
        switch self {
        case .pane(let id):
            return .pane(transform(id))
        case .split(let axis, let ratio, let first, let second):
            return .split(axis, ratio: ratio, first: first.mapLeaves(transform), second: second.mapLeaves(transform))
        }
    }
}
