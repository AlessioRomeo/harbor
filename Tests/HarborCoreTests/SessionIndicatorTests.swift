import Foundation
import Testing
@testable import HarborCore

struct SessionIndicatorTests {
    private let seen = Date(timeIntervalSince1970: 1_800_000_000)
    private var before: Date { seen.addingTimeInterval(-5) }
    private var after: Date { seen.addingTimeInterval(5) }

    private func indicator(_ host: SessionActivity?, _ kind: ClaudeEventKind?, at date: Date? = nil) -> SessionIndicator {
        SessionIndicator(host: host, claude: kind.map { ClaudeEvent(kind: $0, at: date ?? after) }, lastSeen: seen)
    }

    @Test func showsTheShellWithoutClaude() {
        #expect(indicator(nil, nil) == .notStarted)
        #expect(indicator(.idle, nil) == .idle)
        #expect(indicator(.busy, nil) == .running)
        #expect(indicator(.ended(exitCode: 0), nil) == .ended)
    }

    @Test func raisesAttentionForReportsAfterILooked() {
        #expect(indicator(.busy, .finished) == .needsAttention(.finished))
        #expect(indicator(.busy, .waiting) == .needsAttention(.waiting))
        #expect(indicator(.busy, .failed) == .needsAttention(.failed))
    }

    @Test func looksQuietOnceSeen() {
        #expect(indicator(.busy, .finished, at: before) == .claudeIdle)
        #expect(indicator(.busy, .waiting, at: before) == .claudeIdle)
        #expect(indicator(.busy, .failed, at: before) == .claudeIdle)
    }

    @Test func neverSeenMeansUnseen() {
        let indicator = SessionIndicator(host: .busy, claude: ClaudeEvent(kind: .finished, at: seen), lastSeen: nil)
        #expect(indicator == .needsAttention(.finished))
    }

    @Test func followsClaudeWhileItRuns() {
        #expect(indicator(.busy, .working) == .claudeWorking)
        #expect(indicator(.busy, .idle) == .claudeIdle)
        #expect(indicator(.busy, .ended) == .running)
    }

    @Test func ignoresClaudeOnceTheShellIsBackInFront() {
        #expect(indicator(.idle, .finished) == .idle)
        #expect(indicator(.idle, .working) == .idle)
        #expect(indicator(.ended(exitCode: 0), .waiting) == .ended)
    }
}

struct ClaudeEventStoreTests {
    @Test func readsOneEventPerSessionWithTheFileTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let file = directory.appendingPathComponent("\(id.uuidString).json")
        try Data(#"{"event":"waiting"}"#.utf8).write(to: file)
        let stamp = Date(timeIntervalSince1970: 1_800_000_123)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        try Data("junk".utf8).write(to: directory.appendingPathComponent("not-a-session.json"))
        try Data(#"{"event":"bogus"}"#.utf8).write(to: directory.appendingPathComponent("\(UUID().uuidString).json"))

        let store = ClaudeEventStore(directory: directory)
        #expect(store.load() == [id: ClaudeEvent(kind: .waiting, at: stamp)])
        try store.remove(id)
        #expect(store.load().isEmpty)
    }
}

struct ClaudeHookScriptTests {
    private static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/claude-hook.sh")

    private func run(_ argument: String, sessionID: String?, input: String = "{}") throws -> (status: Int32, home: URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [Self.script.path, argument]
        var environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        environment["HARBOR_SESSION_ID"] = sessionID
        process.environment = environment
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return (process.terminationStatus, home)
    }

    private func recorded(in home: URL, for id: String) -> String? {
        let file = home.appendingPathComponent("Library/Application Support/Harbor/claude/\(id).json")
        return (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func recordsTheEventForItsSession() throws {
        let id = UUID().uuidString
        let result = try run("finished", sessionID: id)
        defer { try? FileManager.default.removeItem(at: result.home) }
        #expect(result.status == 0)
        #expect(recorded(in: result.home, for: id) == #"{"event":"finished"}"#)
    }

    @Test func doesNothingOutsideHarbor() throws {
        let result = try run("finished", sessionID: nil)
        defer { try? FileManager.default.removeItem(at: result.home) }
        #expect(result.status == 0)
        #expect(!FileManager.default.fileExists(atPath: result.home.appendingPathComponent("Library").path))
    }

    @Test func refusesASessionIDThatIsNotAUUID() throws {
        let result = try run("finished", sessionID: "../../evil")
        defer { try? FileManager.default.removeItem(at: result.home) }
        #expect(result.status == 0)
        #expect(!FileManager.default.fileExists(atPath: result.home.appendingPathComponent("Library").path))
    }

    @Test func tellsClearApartFromQuitting() throws {
        let id = UUID().uuidString
        let cleared = try run("session-end", sessionID: id, input: #"{"hook_event_name":"SessionEnd","reason":"clear"}"#)
        defer { try? FileManager.default.removeItem(at: cleared.home) }
        #expect(recorded(in: cleared.home, for: id) == #"{"event":"idle"}"#)

        let quit = try run("session-end", sessionID: id, input: #"{"reason":"prompt_input_exit"}"#)
        defer { try? FileManager.default.removeItem(at: quit.home) }
        #expect(recorded(in: quit.home, for: id) == #"{"event":"ended"}"#)
    }

    @Test func ignoresUnknownEvents() throws {
        let id = UUID().uuidString
        let result = try run("rm -rf", sessionID: id)
        defer { try? FileManager.default.removeItem(at: result.home) }
        #expect(result.status == 0)
        #expect(recorded(in: result.home, for: id) == nil)
    }
}
