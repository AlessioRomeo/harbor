import Testing
@testable import HarborCore

struct ModeTrackerTests {
    private func prelude(after output: String) -> String {
        var tracker = ModeTracker()
        tracker.feed(Array(output.utf8))
        return String(decoding: tracker.prelude(), as: UTF8.self)
    }

    @Test func defaultStateNeedsNoPrelude() {
        #expect(prelude(after: "plain text\r\n\u{1B}[1;31mred\u{1B}[0m") == "")
    }

    @Test func restoresAlternateScreenAndInputModes() {
        let output = "\u{1B}[?1049h\u{1B}[?1;2004h\u{1B}[?1002h\u{1B}[?1006h\u{1B}[?25l\u{1B}="
        #expect(prelude(after: output) == "\u{1B}[?1049h\u{1B}[?1h\u{1B}[?25l\u{1B}[?1002h\u{1B}[?1006h\u{1B}[?2004h\u{1B}=")
    }

    @Test func modesSwitchedOffAgainAreNotRestored() {
        #expect(prelude(after: "\u{1B}[?1049h\u{1B}[?2004h\u{1B}[?2004l\u{1B}[?1049l") == "")
    }

    @Test func followsSequencesSplitAcrossFeeds() {
        var tracker = ModeTracker()
        for byte in Array("\u{1B}[?1049h".utf8) {
            tracker.feed([byte])
        }
        #expect(String(decoding: tracker.prelude(), as: UTF8.self) == "\u{1B}[?1049h")
    }

    @Test func fullResetClearsEverything() {
        #expect(prelude(after: "\u{1B}[?1049h\u{1B}[?1000h\u{1B}c") == "")
    }

    @Test func keepsTheKittyKeyboardStack() {
        #expect(prelude(after: "\u{1B}[>1u\u{1B}[>3u") == "\u{1B}[>1u\u{1B}[>3u")
        #expect(prelude(after: "\u{1B}[>1u\u{1B}[>3u\u{1B}[<u") == "\u{1B}[>1u")
        #expect(prelude(after: "\u{1B}[>1u\u{1B}[<5u") == "")
    }

    @Test func ignoresNonPrivateAndUnrelatedSequences() {
        #expect(prelude(after: "\u{1B}[1049h\u{1B}[>4;1m\u{1B}]0;title\u{07}") == "")
    }
}
