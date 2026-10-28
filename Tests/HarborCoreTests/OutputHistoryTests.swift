import Testing
@testable import HarborCore

struct OutputHistoryTests {
    @Test func keepsEverythingUnderCapacity() {
        var history = OutputHistory(capacity: 1000)
        history.append(Array("hello\r\n".utf8))
        #expect(history.replay() == Array("hello\r\n".utf8))
    }

    @Test func trimsToCapacityAtALineBoundary() {
        var history = OutputHistory(capacity: 100)
        for index in 0..<50 {
            history.append(Array("line \(index)\r\n".utf8))
        }
        let replay = String(decoding: history.replay(), as: UTF8.self)
        #expect(history.count <= 100 + 25)
        #expect(replay.hasPrefix("line "))
        #expect(replay.hasSuffix("line 49\r\n"))
    }

    @Test func restoresModesThatWereTrimmedAway() {
        var history = OutputHistory(capacity: 100)
        history.append(Array("\u{1B}[?1049h\u{1B}[?1006h".utf8))
        history.append([UInt8](repeating: UInt8(ascii: "x"), count: 300))
        history.append(Array("\u{1B}[Hscreen".utf8))
        let replay = String(decoding: history.replay(), as: UTF8.self)
        #expect(replay.hasPrefix("\u{1B}[?1049h\u{1B}[?1006h"))
        #expect(replay.hasSuffix("\u{1B}[Hscreen"))
    }

    @Test func clearKeepsTheCurrentLineAndModes() {
        var history = OutputHistory(capacity: 1000)
        history.append(Array("\u{1B}[?2004hold output\r\nprompt$ ".utf8))
        history.clear()
        #expect(history.replay() == Array("\u{1B}[?2004hprompt$ ".utf8))
    }

    @Test func boundaryPrefersEscapeOrLineFeed() {
        let bytes = Array("abc\u{1B}[mdef\nghi".utf8)
        #expect(OutputHistory.boundary(in: bytes, atOrAfter: 1) == 3)
        #expect(OutputHistory.boundary(in: bytes, atOrAfter: 4) == 10)
    }

    @Test func boundaryNeverSplitsACharacter() {
        let bytes = Array("ééé".utf8)
        #expect(OutputHistory.boundary(in: bytes, atOrAfter: 1) == 2)
    }
}
