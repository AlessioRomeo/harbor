import Foundation
import Testing
@testable import HarborCore

struct ArchiveTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let week: TimeInterval = 7 * 24 * 3600

    @Test func archivesAndRestoresAtTheEndOfTheGroup() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let a = try workspace.addSession(named: "a", to: group, now: now)
        try workspace.addSession(named: "b", to: group, now: now)

        workspace.archive(a, at: now)
        #expect(workspace.liveSessions(in: group).map(\.name) == ["b"])
        #expect(workspace.archivedSessions.map(\.name) == ["a"])

        let later = now.addingTimeInterval(60)
        workspace.restore(a, at: later)
        #expect(workspace.liveSessions(in: group).map(\.name) == ["b", "a"])
        #expect(workspace.session(a)?.lastActivityAt == later)
        #expect(workspace.archivedSessions.isEmpty)
    }

    @Test func restoresIntoGeneralWhenItsOwnGroupIsGone() throws {
        var workspace = Workspace()
        workspace.addGroup(named: "Me")
        let old = workspace.addGroup(named: "Old")
        let id = try workspace.addSession(named: "a", to: old, now: now)
        workspace.archive(id, at: now)
        try workspace.deleteGroup(old)
        workspace.restore(id, at: now)
        #expect(workspace.session(id)?.groupID == Workspace.generalGroupID)
        #expect(workspace.groups.map(\.name) == ["General", "Me"])
    }

    @Test func listsTheMostRecentlyArchivedFirst() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let a = try workspace.addSession(named: "a", to: group, now: now)
        let b = try workspace.addSession(named: "b", to: group, now: now)
        workspace.archive(a, at: now)
        workspace.archive(b, at: now.addingTimeInterval(1))
        #expect(workspace.archivedSessions.map(\.name) == ["b", "a"])
    }

    @Test func autoArchivesOnlyQuietSessions() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let old = now.addingTimeInterval(-week - 1)
        let idle = try workspace.addSession(named: "idle", to: group, now: old)
        let unstarted = try workspace.addSession(named: "unstarted", to: group, now: old)
        let running = try workspace.addSession(named: "running", to: group, now: old)
        let claude = try workspace.addSession(named: "claude", to: group, now: old)
        let attention = try workspace.addSession(named: "attention", to: group, now: old)
        let selected = try workspace.addSession(named: "selected", to: group, now: old)
        let visible = try workspace.addSession(named: "visible", to: group, now: old)
        let recent = try workspace.addSession(named: "recent", to: group, now: now.addingTimeInterval(-60))
        let archived = try workspace.addSession(named: "archived", to: group, now: old)
        workspace.archive(archived, at: old)

        let indicators: [UUID: SessionIndicator] = [
            idle: .idle, running: .running, claude: .claudeIdle,
            attention: .needsAttention(.finished), selected: .idle, visible: .idle, recent: .idle,
        ]
        let chosen = workspace.sessionsToAutoArchive(now: now, idleInterval: week, indicators: indicators, onScreen: [selected, visible])
        #expect(chosen == [idle, unstarted])
    }
}

struct ActionTargetTests {
    @Test func actsOnlyOnSelectedSessionsOfTheClickedKind() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let a = try workspace.addSession(named: "a", to: group)
        let b = try workspace.addSession(named: "b", to: group)
        let c = try workspace.addSession(named: "c", to: group)
        let old = try workspace.addSession(named: "old", to: group)
        workspace.archive(old, at: Date())
        let selection: Set<UUID> = [a, b, c, old, UUID()]

        #expect(workspace.targets(of: a, selection: selection) == [a, b, c])
        #expect(workspace.targets(of: old, selection: selection) == [old])

        workspace.archive(b, at: Date())
        #expect(workspace.targets(of: a, selection: selection) == [a, c])
        #expect(workspace.targets(of: old, selection: selection) == [old, b])
    }

    @Test func aRowOutsideTheSelectionActsAlone() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let a = try workspace.addSession(named: "a", to: group)
        let b = try workspace.addSession(named: "b", to: group)
        let c = try workspace.addSession(named: "c", to: group)
        #expect(workspace.targets(of: c, selection: [a, b]) == [c])
    }
}

struct SearchTests {
    private func workspace() throws -> Workspace {
        var workspace = Workspace()
        let me = workspace.addGroup(named: "Me")
        let work = workspace.addGroup(named: "Studio")
        try workspace.addSession(named: "api server", to: me)
        try workspace.addSession(named: "Invoice export", to: work)
        let old = try workspace.addSession(named: "Café notes", to: me)
        try workspace.addSession(named: "deploy api", to: me)
        workspace.archive(old, at: Date())
        return workspace
    }

    @Test func matchesNamesIgnoringCaseAndAccents() throws {
        #expect(try workspace().search("cafe").map(\.session.name) == ["Café notes"])
        #expect(try workspace().search("INVOICE").map(\.session.name) == ["Invoice export"])
    }

    @Test func ranksPrefixMatchesFirst() throws {
        #expect(try workspace().search("api").map(\.session.name) == ["api server", "deploy api"])
    }

    @Test func matchesGroupNamesAndEveryWord() throws {
        #expect(try workspace().search("studio").map(\.session.name) == ["Invoice export"])
        #expect(try workspace().search("api me deploy").map(\.session.name) == ["deploy api"])
    }

    @Test func listsLiveBeforeArchived() throws {
        let names = try workspace().search("").map(\.session.name)
        #expect(names.last == "Café notes")
        #expect(names.count == 4)
    }
}
