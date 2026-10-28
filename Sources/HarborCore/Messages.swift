import Foundation

public let protocolVersion = 1

public struct Hello: Codable, Sendable {
    public var version: Int
    public var attach: UUID?

    public init(version: Int = protocolVersion, attach: UUID? = nil) {
        self.version = version
        self.attach = attach
    }
}

public struct Welcome: Codable, Sendable {
    public var version: Int

    public init(version: Int) {
        self.version = version
    }
}

public struct Failure: Codable, Sendable, Error, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

public struct TerminalSize: Codable, Sendable, Equatable {
    public var cols: UInt16
    public var rows: UInt16

    public init(cols: UInt16, rows: UInt16) {
        self.cols = cols
        self.rows = rows
    }
}

public enum HostRequest: Codable, Sendable, Equatable {
    case create(id: UUID, size: TerminalSize)
    case kill(id: UUID, saveOutput: Bool)
    case clear(id: UUID)
}

public enum SessionActivity: Codable, Sendable, Equatable {
    case idle
    case busy
    case ended(exitCode: Int32?)
}

public struct SessionStatus: Codable, Sendable, Equatable {
    public var id: UUID
    public var activity: SessionActivity

    public init(id: UUID, activity: SessionActivity) {
        self.id = id
        self.activity = activity
    }
}

public struct Exited: Codable, Sendable, Equatable {
    public var exitCode: Int32?

    public init(exitCode: Int32?) {
        self.exitCode = exitCode
    }
}
