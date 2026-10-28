import Foundation

/// Reads and writes the workspace file. A file that exists but can't be read is an error, never an empty workspace.
public struct WorkspaceStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> Workspace? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Workspace.self, from: Data(contentsOf: url))
    }

    public func save(_ workspace: Workspace) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(workspace).write(to: url, options: .atomic)
    }
}

public struct KillOrder: Equatable, Sendable {
    public var id: UUID
    public var saveOutput: Bool
}

extension Workspace {
    /// Host sessions the workspace doesn't show as live. Archived ones keep their output; unknown ones don't.
    public func sessionsToKill(running hostSessions: Set<UUID>) -> [KillOrder] {
        hostSessions.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            guard let session = session(id) else { return KillOrder(id: id, saveOutput: false) }
            return session.isArchived ? KillOrder(id: id, saveOutput: true) : nil
        }
    }
}
