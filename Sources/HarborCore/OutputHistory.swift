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

    public mutating func clear() {
        modesAtStart.feed(bytes)
        bytes.removeAll()
    }

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
