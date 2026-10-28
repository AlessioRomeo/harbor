import Foundation
import Testing
@testable import HarborCore

struct WorkspaceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func startsWithGeneralAndOneSession() {
        let workspace = Workspace.initial(now: now)
        #expect(workspace.groups.map(\.name) == ["General"])
        #expect(workspace.groups.first?.id == Workspace.generalGroupID)
        #expect(workspace.sessions.map(\.name) == ["Shell"])
        #expect(workspace.sessions.first?.groupID == workspace.groups.first?.id)
    }

    @Test func addsSessionsAtTheEndOfTheirGroup() throws {
        var workspace = Workspace()
        let me = workspace.addGroup(named: "Me")
        let work = workspace.addGroup(named: "Studio")
        try workspace.addSession(named: "a", to: me)
        try workspace.addSession(named: "x", to: work)
        try workspace.addSession(named: "b", to: me)
        #expect(workspace.liveSessions(in: me).map(\.name) == ["a", "b"])
        #expect(workspace.liveSessions(in: work).map(\.name) == ["x"])
    }

    @Test func blankNamesFallBack() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "  ")
        let session = try workspace.addSession(named: "", to: group)
        workspace.renameSession(session, to: "   ")
        workspace.renameGroup(group, to: " Work ")
        #expect(workspace.groups.first?.name == "Work")
        #expect(workspace.session(session)?.name == "Shell")
    }

    @Test func movesSessionsWithinAndAcrossGroups() throws {
        var workspace = Workspace()
        let me = workspace.addGroup(named: "Me")
        let work = workspace.addGroup(named: "Work")
        let a = try workspace.addSession(named: "a", to: me)
        try workspace.addSession(named: "b", to: me)
        try workspace.addSession(named: "x", to: work)

        try workspace.moveSession(a, to: me)
        #expect(workspace.liveSessions(in: me).map(\.name) == ["b", "a"])

        try workspace.moveSession(a, to: work, at: 0)
        #expect(workspace.liveSessions(in: work).map(\.name) == ["a", "x"])
        #expect(workspace.liveSessions(in: me).map(\.name) == ["b"])

        #expect(throws: WorkspaceError.unknownGroup) { try workspace.moveSession(a, to: UUID()) }
    }

    @Test func keepsGeneral() throws {
        var workspace = Workspace()
        workspace.addGroup(named: "Me")
        workspace.ensureGeneralGroup()
        workspace.ensureGeneralGroup()
        #expect(workspace.groups.map(\.name) == ["General", "Me"])
        #expect(throws: WorkspaceError.generalGroupStays) { try workspace.deleteGroup(Workspace.generalGroupID) }
    }

    @Test func deletesOnlyGroupsWithoutLiveSessions() throws {
        var workspace = Workspace()
        let me = workspace.addGroup(named: "Me")
        let empty = workspace.addGroup(named: "Empty")
        try workspace.addSession(named: "a", to: me)
        #expect(throws: WorkspaceError.groupNotEmpty) { try workspace.deleteGroup(me) }
        try workspace.deleteGroup(empty)
        #expect(workspace.groups.map(\.name) == ["Me"])
    }

    @Test func reordersGroupsWithinBounds() {
        var workspace = Workspace()
        let a = workspace.addGroup(named: "A")
        workspace.addGroup(named: "B")
        workspace.moveGroup(a, by: 5)
        #expect(workspace.groups.map(\.name) == ["B", "A"])
        workspace.moveGroup(a, by: -5)
        #expect(workspace.groups.map(\.name) == ["A", "B"])
    }

    @Test func activityOnlyMovesForward() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let id = try workspace.addSession(named: "a", to: group, now: now)
        workspace.recordActivity(id, at: now.addingTimeInterval(60))
        workspace.recordActivity(id, at: now)
        #expect(workspace.session(id)?.lastActivityAt == now.addingTimeInterval(60))
    }

    @Test func killsHostSessionsTheWorkspaceDoesNotShow() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let live = try workspace.addSession(named: "live", to: group)
        let stranger = UUID()
        #expect(workspace.sessionsToKill(running: [live, stranger]) == [KillOrder(id: stranger, saveOutput: false)])
    }
}

struct WorkspaceStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("workspace-\(UUID().uuidString).json")
    }

    @Test func roundTrips() throws {
        let store = WorkspaceStore(url: temporaryURL())
        defer { try? FileManager.default.removeItem(at: store.url) }
        #expect(try store.load() == nil)
        let workspace = Workspace.initial(now: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(workspace)
        #expect(try store.load() == workspace)
    }

    @Test func refusesACorruptFile() throws {
        let store = WorkspaceStore(url: temporaryURL())
        defer { try? FileManager.default.removeItem(at: store.url) }
        try Data("{ not json".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
    }
}
