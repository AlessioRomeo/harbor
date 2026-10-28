import Foundation

public struct SearchResult: Equatable, Sendable {
    public var session: Session
    public var groupName: String?
}

extension Workspace {
    /// Sessions whose name or group contains every word of the query, ignoring case and accents.
    /// Live sessions come first; within each, names that start with the query, then other name matches.
    public func search(_ query: String) -> [SearchResult] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let groupNames = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        let candidates = liveSessions + archivedSessions
        guard !words.isEmpty else {
            return candidates.map { SearchResult(session: $0, groupName: groupNames[$0.groupID]) }
        }
        let scored: [(result: SearchResult, rank: Int, order: Int)] = candidates.enumerated().compactMap { order, session in
            let groupName = groupNames[session.groupID]
            let haystack = "\(session.name) \(groupName ?? "")"
            guard words.allSatisfy({ Self.contains(haystack, $0) }) else { return nil }
            let rank: Int
            if Self.hasPrefix(session.name, query.trimmingCharacters(in: .whitespaces)) {
                rank = 0
            } else if words.allSatisfy({ Self.contains(session.name, $0) }) {
                rank = 1
            } else {
                rank = 2
            }
            return (SearchResult(session: session, groupName: groupName), (session.isArchived ? 10 : 0) + rank, order)
        }
        return scored.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }.map(\.result)
    }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private static func contains(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: options) != nil
    }

    private static func hasPrefix(_ text: String, _ prefix: String) -> Bool {
        text.range(of: prefix, options: options.union(.anchored)) != nil
    }
}
