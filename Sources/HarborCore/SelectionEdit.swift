import Foundation

/// Turns "replace this selected part of the line being typed" into the keys a person would press:
/// arrows to the selection's end, a Backspace per selected character, then the new text.
public struct SelectionEdit: Equatable, Sendable {
    /// Characters of the row, with the cells each one takes.
    public struct Row: Equatable, Sendable {
        public var characters: [String]
        public var cellWidths: [Int]

        public init(characters: [String], cellWidths: [Int]) {
            self.characters = characters
            self.cellWidths = cellWidths
        }

        /// The character at a cell column, or the count if the column is past the end.
        func characterIndex(atColumn column: Int) -> Int {
            var cell = 0
            for (index, width) in cellWidths.enumerated() {
                if column < cell + max(width, 1) { return index }
                cell += max(width, 1)
            }
            return characters.count
        }
    }

    /// The selected characters, as indices into the row.
    public var range: Range<Int>

    /// Finds `selected` in the row; with several matches, the one nearest `hintColumn`.
    public init?(selected: String, in row: Row, hintColumn: Int) {
        let needle = selected.map(String.init)
        guard !needle.isEmpty, !selected.contains(where: \.isNewline), needle.count <= row.characters.count else { return nil }
        let starts = (0...(row.characters.count - needle.count)).filter { Array(row.characters[$0..<($0 + needle.count)]) == needle }
        let hint = row.characterIndex(atColumn: hintColumn)
        let distance = { (start: Int) in start > hint ? start - hint : max(0, hint - (start + needle.count - 1)) }
        guard let start = starts.min(by: { distance($0) < distance($1) }) else { return nil }
        range = start..<(start + needle.count)
    }

    /// The bytes that remove the selection, or replace it with `replacement`, for a cursor at `cursorColumn`.
    public func keystrokes(cursorColumn: Int, in row: Row, applicationCursor: Bool, replacement: String = "") -> [UInt8] {
        let cursor = row.characterIndex(atColumn: cursorColumn)
        let moves = range.upperBound - cursor
        let arrow = moves >= 0
            ? (applicationCursor ? "\u{1B}OC" : "\u{1B}[C")
            : (applicationCursor ? "\u{1B}OD" : "\u{1B}[D")
        let keys = String(repeating: arrow, count: abs(moves)) + String(repeating: "\u{7F}", count: range.count) + replacement
        return Array(keys.utf8)
    }
}
