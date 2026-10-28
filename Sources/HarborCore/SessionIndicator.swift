import Foundation

/// What the Claude Code hook last reported for a session.
public enum ClaudeEventKind: String, Codable, Sendable {
    case working
    case finished
    case failed
    case waiting
    case idle
    case ended
}

public struct ClaudeEvent: Equatable, Sendable {
    public var kind: ClaudeEventKind
    public var at: Date

    public init(kind: ClaudeEventKind, at: Date) {
        self.kind = kind
        self.at = at
    }
}

public enum AttentionReason: Equatable, Sendable {
    case finished
    case waiting
    case failed
}

/// What a session shows at a glance.
public enum SessionIndicator: Equatable, Sendable {
    case notStarted
    case idle
    case running
    case ended
    case claudeWorking
    case claudeIdle
    case needsAttention(AttentionReason)

    public var needsAttention: Bool {
        if case .needsAttention = self { return true }
        return false
    }

    /// Claude's last report counts only while a program (Claude) holds the terminal:
    /// once the shell is back in front, Claude has gone, even if it died without saying so.
    public init(host: SessionActivity?, claude: ClaudeEvent?, lastSeen: Date?) {
        switch host {
        case nil:
            self = .notStarted
        case .ended:
            self = .ended
        case .idle:
            self = .idle
        case .busy:
            self = Self.claudeIndicator(claude, lastSeen: lastSeen) ?? .running
        }
    }

    private static func claudeIndicator(_ claude: ClaudeEvent?, lastSeen: Date?) -> SessionIndicator? {
        guard let claude else { return nil }
        let isUnseen = lastSeen.map { claude.at > $0 } ?? true
        switch claude.kind {
        case .working: return .claudeWorking
        case .idle: return .claudeIdle
        case .ended: return nil
        case .finished: return isUnseen ? .needsAttention(.finished) : .claudeIdle
        case .waiting: return isUnseen ? .needsAttention(.waiting) : .claudeIdle
        case .failed: return isUnseen ? .needsAttention(.failed) : .claudeIdle
        }
    }
}

extension ClaudeEvent {
    /// How long the host may take to report that a program took the terminal.
    public static let hostReportDelay: TimeInterval = 2

    /// Claude reports from sessions whose shell is back in front, so Claude is gone even if it
    /// never said so. Reports newer than the host's delay may belong to a Claude just starting.
    public static func stale(_ events: [UUID: ClaudeEvent], activities: [UUID: SessionActivity], now: Date) -> [UUID] {
        events.compactMap { id, event in
            activities[id] == .idle && now.timeIntervalSince(event.at) > hostReportDelay ? id : nil
        }.sorted { $0.uuidString < $1.uuidString }
    }
}

extension ClaudeEvent {
    /// Of the sessions needing me, the one waiting longest, so ⌘J works through them oldest first.
    public static func longestWaiting(among ids: some Sequence<UUID>, events: [UUID: ClaudeEvent]) -> UUID? {
        ids.min { (events[$0]?.at ?? .distantFuture, $0.uuidString) < (events[$1]?.at ?? .distantFuture, $1.uuidString) }
    }
}
