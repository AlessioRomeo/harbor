import Foundation

/// Reads the files the Claude Code hook writes, one per Harbor session, named after the session.
/// The file's modification time is the event time: it is finer than anything a shell script can print.
public struct ClaudeEventStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() -> [UUID: ClaudeEvent] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [:] }
        var events: [UUID: ClaudeEvent] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let id = UUID(uuidString: String(name.dropLast(5))) else { continue }
            let url = directory.appendingPathComponent(name)
            guard
                let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(Record.self, from: data),
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            events[id] = ClaudeEvent(kind: record.event, at: modified)
        }
        return events
    }

    public func remove(_ id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private struct Record: Decodable {
        var event: ClaudeEventKind
    }
}
