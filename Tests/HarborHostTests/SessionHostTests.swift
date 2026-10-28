import Darwin
import Foundation
import HarborCore
import Testing
@testable import HarborHost

@Suite(.serialized)
final class SessionHostTests {
    private let paths: HarborPaths
    private let host: SessionHost
    private let size = TerminalSize(cols: 80, rows: 24)

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("harbor-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let shellConfig = directory.appendingPathComponent("zdotdir", isDirectory: true)
        try FileManager.default.createDirectory(at: shellConfig, withIntermediateDirectories: true)
        paths = HarborPaths(directory: directory)
        let launcher = ShellLauncher(
            executable: "/bin/zsh",
            loginName: "-zsh",
            directory: directory.path,
            environment: ["PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "ZDOTDIR": shellConfig.path, "HOME": directory.path]
        )
        host = SessionHost(paths: paths, launcher: launcher)
        try host.start()
    }

    deinit {
        host.shutdown()
        try? FileManager.default.removeItem(at: paths.directory)
    }

    private func connect(attach: UUID? = nil) throws -> HostConnection {
        try HostConnection(socketPath: paths.socket.path, attach: attach)
    }

    private func createSession(on control: HostConnection) throws -> UUID {
        let id = UUID()
        try control.send(.create(id: id, size: size))
        try waitForStatus(on: control) { $0.contains { $0.id == id } }
        return id
    }

    @discardableResult
    private func waitForStatus(on control: HostConnection, timeout: TimeInterval = 5, until done: ([SessionStatus]) -> Bool) throws -> [SessionStatus] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let frame = try control.receive(timeout: max(0, deadline.timeIntervalSinceNow))
            if frame.type == .sessions {
                let statuses = try frame.decode([SessionStatus].self)
                if done(statuses) { return statuses }
            }
        }
    }

    private func readOutput(from session: HostConnection, timeout: TimeInterval = 5, until text: String) throws -> String {
        try readOutput(from: session, timeout: timeout) { $0.contains(text) }
    }

    private func readOutput(from session: HostConnection, timeout: TimeInterval = 5, until done: (String) -> Bool) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var output: [UInt8] = []
        while true {
            let frame = try session.receive(timeout: max(0, deadline.timeIntervalSinceNow))
            if frame.type == .output {
                output += frame.payload
            }
            let decoded = String(decoding: output, as: UTF8.self)
            if done(decoded) { return decoded }
        }
    }

    private func type(_ text: String, into session: HostConnection) throws {
        try session.send(Frame(.input, payload: Array(text.utf8)))
    }

    @Test func runsCommandsAndReplaysOutputOnReattach() throws {
        let control = try connect()
        let id = try createSession(on: control)

        let first = try connect(attach: id)
        try type("echo hi-$((40+2))\n", into: first)
        _ = try readOutput(from: first, until: "hi-42")
        first.close()

        let second = try connect(attach: id)
        let replay = try second.receive(timeout: 5)
        #expect(replay.type == .output)
        #expect(String(decoding: replay.payload, as: UTF8.self).contains("hi-42"))
    }

    @Test func shellKnowsItsSessionID() throws {
        let control = try connect()
        let id = try createSession(on: control)
        let session = try connect(attach: id)
        try type("echo id=$HARBOR_SESSION_ID.\n", into: session)
        _ = try readOutput(from: session, until: "id=\(id.uuidString).")
    }

    @Test func reportsBusyWhileAJobRunsInTheForeground() throws {
        let control = try connect()
        let id = try createSession(on: control)
        let session = try connect(attach: id)
        try type("sleep 3\n", into: session)
        try waitForStatus(on: control) { $0.first { $0.id == id }?.activity == .busy }
        try waitForStatus(on: control) { $0.first { $0.id == id }?.activity == .idle }
    }

    @Test func killEndsAnInteractiveShellBeforeTheGracePeriod() throws {
        let control = try connect()
        let id = try createSession(on: control)
        let session = try connect(attach: id)
        try type("echo pid=$$.\n", into: session)
        let output = try readOutput(from: session) { $0.contains(/pid=\d+\./) }
        let pidText = try #require(output.firstMatch(of: /pid=(\d+)\./)?.1)
        let pid = try #require(pid_t(pidText))

        try control.send(.kill(id: id, saveOutput: true))
        try waitForStatus(on: control) { !$0.contains { $0.id == id } }

        let deadline = Date().addingTimeInterval(SessionHost.killGracePeriod * 0.75)
        while kill(pid, 0) == 0, Date() < deadline {
            usleep(20_000)
        }
        #expect(kill(pid, 0) != 0, "shell \(pid) survived the hangup")
        let saved = try Data(contentsOf: paths.savedOutput(for: id))
        #expect(String(decoding: saved, as: UTF8.self).contains("pid=\(pid)."))
    }

    @Test func killEndsAForegroundJobThatIgnoresHangup() throws {
        let control = try connect()
        let id = try createSession(on: control)
        let session = try connect(attach: id)
        try type("sh -c 'trap \"\" HUP; echo job=$$.; exec sleep 300'\n", into: session)
        let output = try readOutput(from: session) { $0.contains(/job=\d+\./) }
        let pidText = try #require(output.firstMatch(of: /job=(\d+)\./)?.1)
        let pid = try #require(pid_t(pidText))
        try waitForStatus(on: control) { $0.first { $0.id == id }?.activity == .busy }

        try control.send(.kill(id: id, saveOutput: false))
        let deadline = Date().addingTimeInterval(SessionHost.killGracePeriod + 2)
        while kill(pid, 0) == 0, Date() < deadline {
            usleep(50_000)
        }
        #expect(kill(pid, 0) != 0, "job \(pid) survived the kill")
    }

    @Test func reportsWhenTheShellExits() throws {
        let control = try connect()
        let id = try createSession(on: control)
        let session = try connect(attach: id)
        try type("exit 3\n", into: session)
        try waitForStatus(on: control) { $0.first { $0.id == id }?.activity == .ended(exitCode: 3) }

        let reattached = try connect(attach: id)
        #expect(try reattached.receive(timeout: 5).type == .output)
        let exited = try reattached.receive(timeout: 5)
        #expect(exited.type == .exited)
        #expect(try exited.decode(Exited.self) == Exited(exitCode: 3))
    }

    @Test func newestAttachReplacesTheOldOne() throws {
        let control = try connect()
        let id = try createSession(on: control)
        let older = try connect(attach: id)
        _ = try connect(attach: id)
        #expect(throws: HostConnectionError.closed) {
            while true {
                _ = try older.receive(timeout: 5)
            }
        }
    }

    @Test func refusesAMismatchedProtocolVersion() {
        #expect(throws: Failure.self) {
            try HostConnection(socketPath: paths.socket.path, version: protocolVersion + 1)
        }
    }

    @Test func refusesToAttachAnUnknownSession() {
        #expect(throws: Failure.self) {
            try HostConnection(socketPath: paths.socket.path, attach: UUID())
        }
    }

    @Test func refusesToStartTwice() throws {
        let second = SessionHost(paths: paths, launcher: try ShellLauncher.userLoginShell())
        #expect(throws: SessionHostError.alreadyRunning) { try second.start() }
    }
}
