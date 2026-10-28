import Foundation

public struct SessionGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
}

public struct Session: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var groupID: UUID
    public var createdAt: Date
    public var lastActivityAt: Date
    public var archivedAt: Date?
    /// When I last looked at the session; Claude's reports after this need my attention.
    public var lastSeenAt: Date?

    public var isArchived: Bool { archivedAt != nil }
}

public enum WorkspaceError: Error, Equatable {
    case groupNotEmpty
    case unknownGroup
    case unknownSession
}

/// Groups and sessions in display order. Sessions keep their place in `sessions`,
/// so a group's order is the order of its sessions in that array.
public struct Workspace: Codable, Equatable, Sendable {
    public static let defaultGroupName = "Me"
    public static let defaultSessionName = "Shell"

    public private(set) var groups: [SessionGroup]
    public private(set) var sessions: [Session]

    public init(groups: [SessionGroup] = [], sessions: [Session] = []) {
        self.groups = groups
        self.sessions = sessions
    }

    public static func initial(now: Date = Date()) -> Workspace {
        var workspace = Workspace()
        let group = workspace.addGroup(named: defaultGroupName)
        workspace.insertSession(named: defaultSessionName, in: group, now: now)
        return workspace
    }

    public func session(_ id: UUID) -> Session? {
        sessions.first { $0.id == id }
    }

    public func liveSessions(in groupID: UUID) -> [Session] {
        sessions.filter { $0.groupID == groupID && !$0.isArchived }
    }

    public var liveSessions: [Session] {
        sessions.filter { !$0.isArchived }
    }

    // MARK: Groups

    @discardableResult
    public mutating func addGroup(named name: String) -> UUID {
        let group = SessionGroup(id: UUID(), name: Self.cleaned(name, fallback: "New Group"))
        groups.append(group)
        return group.id
    }

    public mutating func renameGroup(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = Self.cleaned(name, fallback: groups[index].name)
    }

    public mutating func moveGroup(_ id: UUID, by offset: Int) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), groups.count - 1)
        groups.insert(groups.remove(at: index), at: target)
    }

    /// Only a group without live sessions can go; its archived sessions return to the first group when restored.
    public mutating func deleteGroup(_ id: UUID) throws {
        guard groups.contains(where: { $0.id == id }) else { throw WorkspaceError.unknownGroup }
        guard liveSessions(in: id).isEmpty else { throw WorkspaceError.groupNotEmpty }
        groups.removeAll { $0.id == id }
    }

    // MARK: Sessions

    @discardableResult
    public mutating func addSession(named name: String, to groupID: UUID, now: Date = Date()) throws -> UUID {
        guard groups.contains(where: { $0.id == groupID }) else { throw WorkspaceError.unknownGroup }
        return insertSession(named: name, in: groupID, now: now)
    }

    @discardableResult
    private mutating func insertSession(named name: String, in groupID: UUID, now: Date) -> UUID {
        let session = Session(
            id: UUID(),
            name: Self.cleaned(name, fallback: Self.defaultSessionName),
            groupID: groupID,
            createdAt: now,
            lastActivityAt: now,
            archivedAt: nil,
            lastSeenAt: now
        )
        let lastInGroup = sessions.lastIndex { $0.groupID == groupID }
        sessions.insert(session, at: lastInGroup.map { $0 + 1 } ?? sessions.endIndex)
        return session.id
    }

    public mutating func renameSession(_ id: UUID, to name: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].name = Self.cleaned(name, fallback: sessions[index].name)
    }

    /// Moves a session into `groupID`, before the live session currently at `position` there (or last).
    public mutating func moveSession(_ id: UUID, to groupID: UUID, at position: Int? = nil) throws {
        guard groups.contains(where: { $0.id == groupID }) else { throw WorkspaceError.unknownGroup }
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw WorkspaceError.unknownSession }
        var session = sessions.remove(at: index)
        session.groupID = groupID
        let targets = liveSessions(in: groupID)
        if let position, position < targets.count, let anchor = sessions.firstIndex(where: { $0.id == targets[position].id }) {
            sessions.insert(session, at: anchor)
        } else if let last = sessions.lastIndex(where: { $0.groupID == groupID }) {
            sessions.insert(session, at: last + 1)
        } else {
            sessions.append(session)
        }
    }

    public mutating func recordActivity(_ id: UUID, at date: Date) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].lastActivityAt = max(sessions[index].lastActivityAt, date)
    }

    /// Archived sessions, most recently archived first.
    public var archivedSessions: [Session] {
        sessions.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    public mutating func archive(_ id: UUID, at date: Date) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), !sessions[index].isArchived else { return }
        sessions[index].archivedAt = date
    }

    /// Brings a session back at the end of its group, or of the first group if its own is gone.
    public mutating func restore(_ id: UUID, at date: Date) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].isArchived else { return }
        var session = sessions.remove(at: index)
        if !groups.contains(where: { $0.id == session.groupID }) {
            session.groupID = groups.first?.id ?? addGroup(named: Self.defaultGroupName)
        }
        session.archivedAt = nil
        session.lastActivityAt = date
        session.lastSeenAt = date
        let lastInGroup = sessions.lastIndex { $0.groupID == session.groupID }
        sessions.insert(session, at: lastInGroup.map { $0 + 1 } ?? sessions.endIndex)
    }

    public mutating func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    /// Live sessions quiet for `idleInterval` that nothing holds open: no program running,
    /// nothing waiting for me, and not the one on screen.
    public func sessionsToAutoArchive(now: Date, idleInterval: TimeInterval, indicators: [UUID: SessionIndicator], selected: UUID?) -> [UUID] {
        liveSessions.compactMap { session in
            guard session.id != selected, now.timeIntervalSince(session.lastActivityAt) >= idleInterval else { return nil }
            switch indicators[session.id] ?? .notStarted {
            case .idle, .notStarted, .ended: return session.id
            case .running, .claudeWorking, .claudeIdle, .needsAttention: return nil
            }
        }
    }

    public mutating func markSeen(_ id: UUID, at date: Date) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].lastSeenAt = date
    }

    private static func cleaned(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
