import Foundation

public struct HarborPaths: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Set to run a separate Harbor, with its own host and sessions, for trying out a build.
    public static let dataDirectoryVariable = "HARBOR_DATA_DIR"

    public static var standard: HarborPaths {
        if let override = ProcessInfo.processInfo.environment[dataDirectoryVariable], !override.isEmpty {
            return HarborPaths(directory: URL(fileURLWithPath: override, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return HarborPaths(directory: support.appendingPathComponent("Harbor", isDirectory: true))
    }

    public var socket: URL { directory.appendingPathComponent("host.sock") }
    public var workspace: URL { directory.appendingPathComponent("workspace.json") }
    public var claudeEvents: URL { directory.appendingPathComponent("claude", isDirectory: true) }
    public var claudeHook: URL { directory.appendingPathComponent("claude-hook.sh") }
    public var savedOutputDirectory: URL { directory.appendingPathComponent("scrollback", isDirectory: true) }

    public func savedOutput(for id: UUID) -> URL {
        savedOutputDirectory.appendingPathComponent("\(id.uuidString).bin")
    }

    /// The socket hands out shells, so only the owner may enter the directory.
    public func prepare() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try fileManager.createDirectory(at: savedOutputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: claudeEvents, withIntermediateDirectories: true)
    }
}
