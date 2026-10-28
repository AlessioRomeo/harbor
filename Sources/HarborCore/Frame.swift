import Foundation

public enum FrameType: UInt8, Sendable {
    case hello = 1
    case welcome
    case failure
    case request
    case sessions
    case output
    case input
    case resize
    case exited
}

public struct Frame: Equatable, Sendable {
    public static let headerSize = 5
    public static let maxPayloadSize = 64 << 20

    public let type: FrameType
    public let payload: [UInt8]

    public init(_ type: FrameType, payload: [UInt8] = []) {
        self.type = type
        self.payload = payload
    }

    public static func json(_ type: FrameType, _ value: some Encodable) throws -> Frame {
        Frame(type, payload: Array(try JSONEncoder().encode(value)))
    }

    public func decode<T: Decodable>(_: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(payload))
    }

    public func encoded() -> [UInt8] {
        let length = UInt32(payload.count)
        var bytes = [type.rawValue]
        bytes.reserveCapacity(Self.headerSize + payload.count)
        bytes += withUnsafeBytes(of: length.bigEndian, Array.init)
        bytes += payload
        return bytes
    }
}

public enum FrameError: Error, Equatable {
    case unknownType(UInt8)
    case tooLarge(Int)
}

public struct FrameDecoder {
    private var buffer: [UInt8] = []
    private var readIndex = 0

    public init() {}

    public mutating func append(_ bytes: some Sequence<UInt8>) {
        if readIndex > 0, readIndex >= buffer.count / 2 {
            buffer.removeFirst(readIndex)
            readIndex = 0
        }
        buffer.append(contentsOf: bytes)
    }

    public mutating func next() throws -> Frame? {
        let available = buffer.count - readIndex
        guard available >= Frame.headerSize else { return nil }
        let typeByte = buffer[readIndex]
        guard let type = FrameType(rawValue: typeByte) else { throw FrameError.unknownType(typeByte) }
        let length = buffer[(readIndex + 1)..<(readIndex + 5)].reduce(0) { Int($0) << 8 | Int($1) }
        guard length <= Frame.maxPayloadSize else { throw FrameError.tooLarge(length) }
        guard available >= Frame.headerSize + length else { return nil }
        let start = readIndex + Frame.headerSize
        let frame = Frame(type, payload: Array(buffer[start..<(start + length)]))
        readIndex = start + length
        return frame
    }
}
