/// The most recent output of a session, bounded in size, replayable into a fresh terminal.
public struct OutputHistory: Sendable {
    public static let defaultCapacity = 4 << 20

    private static let trimSlack = 256 << 10
    private static let boundarySearchLimit = 64 << 10

    public let capacity: Int
    private var bytes: [UInt8] = []
    private var modesAtStart = ModeTracker()

    public init(capacity: Int = OutputHistory.defaultCapacity) {
        self.capacity = capacity
    }

    public var count: Int { bytes.count }

    public mutating func append(_ output: some Sequence<UInt8>) {
        bytes.append(contentsOf: output)
        if bytes.count > capacity + min(Self.trimSlack, capacity / 4) {
            trim(to: capacity)
        }
    }

    /// Drops everything before the line being written, the way Terminal's Clear to Start keeps the prompt.
    public mutating func clear() {
        let keepFrom = bytes.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
        modesAtStart.feed(bytes[..<keepFrom])
        bytes.removeFirst(keepFrom)
    }

    /// Puts the terminal back in its default modes and marks where a new shell starts.
    public static let newShellMarker = Array((
        "\u{1B}[?1047l\u{1B}[?1l\u{1B}[?25h\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l\u{1B}[?1004l"
            + "\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l\u{1B}[?2004l\u{1B}>\u{1B}[<99u\u{1B}[0m"
            + "\r\n\u{1B}[2m─── new shell ───\u{1B}[0m\r\n"
    ).utf8)

    public func replay() -> [UInt8] {
        modesAtStart.prelude() + bytes
    }

    private mutating func trim(to size: Int) {
        let cut = Self.boundary(in: bytes, atOrAfter: bytes.count - size)
        modesAtStart.feed(bytes[..<cut])
        bytes.removeFirst(cut)
    }

    /// A cut at ESC or LF never lands inside a control sequence or a UTF-8 character.
    /// Without one nearby, it falls back to the next UTF-8 character start.
    static func boundary(in bytes: [UInt8], atOrAfter target: Int) -> Int {
        let searchEnd = min(bytes.count, target + boundarySearchLimit)
        if let index = bytes[target..<searchEnd].firstIndex(where: { $0 == 0x1B || $0 == 0x0A }) {
            return bytes[index] == 0x0A ? index + 1 : index
        }
        var index = target
        while index < bytes.count, bytes[index] & 0xC0 == 0x80 {
            index += 1
        }
        return index
    }
}
