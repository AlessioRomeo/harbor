import Testing
@testable import HarborCore

struct SelectionEditTests {
    private func row(_ text: String, widths: [Int]? = nil) -> SelectionEdit.Row {
        let characters = text.map(String.init)
        return SelectionEdit.Row(characters: characters, cellWidths: widths ?? characters.map { _ in 1 })
    }

    private func keys(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\u{1B}[C", with: "→")
            .replacingOccurrences(of: "\u{1B}[D", with: "←")
            .replacingOccurrences(of: "\u{1B}OC", with: "⇢")
            .replacingOccurrences(of: "\u{1B}OD", with: "⇠")
            .replacingOccurrences(of: "\u{7F}", with: "⌫")
    }

    private let line = "% git commit -m wip"

    @Test func deletesASelectionLeftOfTheCursor() throws {
        let edit = try #require(SelectionEdit(selected: "commit", in: row(line), hintColumn: 7, cursorColumn: 19))
        #expect(edit.range == 6..<12)
        #expect(keys(edit.keystrokes(cursorColumn: 19, in: row(line), applicationCursor: false)) == "←←←←←←←⌫⌫⌫⌫⌫⌫")
    }

    @Test func movesRightWhenTheCursorIsBefore() throws {
        let edit = try #require(SelectionEdit(selected: "wip", in: row(line), hintColumn: 17, cursorColumn: 2))
        #expect(keys(edit.keystrokes(cursorColumn: 2, in: row(line), applicationCursor: false)).hasPrefix("→→→→→→→→→→→→→→→→→⌫⌫⌫"))
    }

    @Test func typesTheReplacementAfterDeleting() throws {
        let edit = try #require(SelectionEdit(selected: "wip", in: row(line), hintColumn: 17, cursorColumn: 19))
        #expect(keys(edit.keystrokes(cursorColumn: 19, in: row(line), applicationCursor: false, replacement: "x")) == "⌫⌫⌫x")
    }

    @Test func usesApplicationCursorKeys() throws {
        let edit = try #require(SelectionEdit(selected: "git", in: row(line), hintColumn: 3, cursorColumn: 0))
        #expect(keys(edit.keystrokes(cursorColumn: 0, in: row(line), applicationCursor: true)) == "⇢⇢⇢⇢⇢⌫⌫⌫")
    }

    @Test func picksTheOccurrenceUnderTheMouse() throws {
        let text = "% echo a a a"
        let edit = try #require(SelectionEdit(selected: "a", in: row(text), hintColumn: 9, cursorColumn: 12))
        #expect(edit.range == 9..<10)
    }

    @Test func countsCharactersNotCellsForWideText() throws {
        let text = "% 日本 ok"
        let edit = try #require(SelectionEdit(selected: "ok", in: row(text, widths: [1, 1, 2, 2, 1, 1, 1]), hintColumn: 8, cursorColumn: 9))
        #expect(edit.range == 5..<7)
        #expect(keys(edit.keystrokes(cursorColumn: 9, in: row(text, widths: [1, 1, 2, 2, 1, 1, 1]), applicationCursor: false)) == "⌫⌫")
        #expect(keys(edit.keystrokes(cursorColumn: 2, in: row(text, widths: [1, 1, 2, 2, 1, 1, 1]), applicationCursor: false)).hasPrefix("→→→→→⌫"))
    }

    @Test func refusesTextPastTheEndOfTheInput() {
        let withRightPrompt = "% git push" + String(repeating: " ", count: 20) + "main"
        #expect(SelectionEdit(selected: "main", in: row(withRightPrompt), hintColumn: 31, cursorColumn: 10) == nil)
        #expect(SelectionEdit(selected: "push", in: row(withRightPrompt), hintColumn: 7, cursorColumn: 10) != nil)
    }

    @Test func refusesWhatIsNotOnTheRow() {
        #expect(SelectionEdit(selected: "push", in: row(line), hintColumn: 0, cursorColumn: 19) == nil)
        #expect(SelectionEdit(selected: "git\ncommit", in: row(line), hintColumn: 0, cursorColumn: 19) == nil)
        #expect(SelectionEdit(selected: "", in: row(line), hintColumn: 0, cursorColumn: 19) == nil)
    }
}
