import Darwin
import Foundation
import HarborCore
import os

public enum SessionHostError: Error {
    case alreadyRunning
}

/// Owns every session's shell and serves them over a Unix socket. All state lives on `queue`.
public final class SessionHost: @unchecked Sendable {
    public static let killGracePeriod: TimeInterval = 2
    private static let statusInterval: TimeInterval = 1
    private static let logger = Logger(subsystem: "com.alessioromeo.harbor", category: "host")

    private let paths: HarborPaths
    private let launcher: ShellLauncher
    private let queue = DispatchQueue(label: "com.alessioromeo.harbor.host")
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var statusTimer: DispatchSourceTimer?
    private var sessions: [UUID: HostSession] = [:]
    private var dyingSessions: [UUID: HostSession] = [:]
    private var clients: [UUID: ClientConnection] = [:]
    private var lastStatuses: [SessionStatus] = []

    public init(paths: HarborPaths, launcher: ShellLauncher) {
        self.paths = paths
        self.launcher = launcher
    }

    public func start() throws {
        try paths.prepare()
        let socketPath = paths.socket.path
        if let probe = try? UnixSocket.connect(path: socketPath) {
            close(probe)
            throw SessionHostError.alreadyRunning
        }
        unlink(socketPath)
        try queue.sync {
            listener = try UnixSocket.listen(path: socketPath)
            let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
            source.setEventHandler { [unowned self] in acceptClient() }
            source.resume()
            acceptSource = source

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.statusInterval, repeating: Self.statusInterval)
            timer.setEventHandler { [unowned self] in publishStatusIfChanged() }
            timer.resume()
            statusTimer = timer
        }
    }

    /// Saves every session's output so it survives logout, then stops serving.
    public func shutdown() {
        queue.sync {
            for session in sessions.values {
                saveOutput(of: session)
            }
            acceptSource?.cancel()
            statusTimer?.cancel()
            for client in clients.values {
                client.close()
            }
            if listener >= 0 {
                close(listener)
                listener = -1
                unlink(paths.socket.path)
            }
        }
    }

    private func acceptClient() {
        let fd: Int32
        do {
            fd = try UnixSocket.accept(listener)
        } catch {
            Self.logger.error("Accept failed: \(String(describing: error))")
            return
        }
        let client = ClientConnection(
            fd: fd,
            queue: queue,
            onFrame: { [unowned self] in handle($1, from: $0) },
            onClose: { [unowned self] in clientClosed($0) }
        )
        clients[client.id] = client
        guard (try? UnixSocket.peerUID(fd)) == getuid() else {
            Self.logger.error("Rejected a client owned by another user")
            client.close()
            return
        }
    }

    private func clientClosed(_ client: ClientConnection) {
        clients[client.id] = nil
        if case .attached(let id) = client.role, sessions[id]?.attached === client {
            sessions[id]?.attached = nil
        }
    }

    private func handle(_ frame: Frame, from client: ClientConnection) {
        do {
            switch (client.role, frame.type) {
            case (.pending, .hello):
                try greet(client, hello: frame.decode(Hello.self))
            case (.control, .request):
                try perform(frame.decode(HostRequest.self), for: client)
            case (.attached(let id), .input):
                sessions[id]?.send(frame.payload)
            case (.attached(let id), .resize):
                guard let size = frame.terminalSize else {
                    client.fail("Malformed resize frame")
                    return
                }
                sessions[id]?.resize(to: size)
            default:
                client.fail("Unexpected \(frame.type) frame")
            }
        } catch let failure as Failure {
            client.reject(failure)
        } catch {
            client.fail("Malformed \(frame.type) frame: \(error)")
        }
    }

    private func greet(_ client: ClientConnection, hello: Hello) throws {
        guard hello.version == protocolVersion else {
            client.fail("Harbor host speaks protocol \(protocolVersion), client speaks \(hello.version)")
            return
        }
        guard let id = hello.attach else {
            client.role = .control
            client.send(try .json(.welcome, Welcome(version: protocolVersion)))
            client.send(try .json(.sessions, currentStatuses()))
            return
        }
        guard let session = sessions[id] else {
            client.fail("No session \(id)")
            return
        }
        session.attached?.close()
        session.attached = client
        client.role = .attached(id)
        client.send(try .json(.welcome, Welcome(version: protocolVersion)))
        client.send(Frame(.output, payload: session.history.replay()))
        if session.hasExited {
            client.send(try .json(.exited, Exited(exitCode: session.exitCode)))
        }
    }

    private func perform(_ request: HostRequest, for client: ClientConnection) throws {
        switch request {
        case .create(let id, let size):
            guard sessions[id] == nil, dyingSessions[id] == nil else {
                throw Failure("Session \(id) already exists")
            }
            let session = HostSession(id: id, size: size, queue: queue) { [unowned self] in sessionExited($0) }
            sessions[id] = session
            session.start(with: launcher)
        case .kill(let id, let saveOutput):
            guard let session = sessions.removeValue(forKey: id) else { return }
            if saveOutput {
                self.saveOutput(of: session)
            }
            session.attached?.close()
            guard !session.hasExited else { break }
            session.isBeingKilled = true
            dyingSessions[id] = session
            let groups = session.hangUp()
            queue.asyncAfter(deadline: .now() + Self.killGracePeriod) {
                for group in groups {
                    killpg(group, SIGKILL)
                }
            }
        case .clear(let id):
            sessions[id]?.clearHistory()
        }
        publishStatusIfChanged()
    }

    private func sessionExited(_ session: HostSession) {
        if session.isBeingKilled {
            dyingSessions[session.id] = nil
            return
        }
        if let frame = try? Frame.json(.exited, Exited(exitCode: session.exitCode)) {
            session.attached?.send(frame)
        }
        publishStatusIfChanged()
    }

    private func saveOutput(of session: HostSession) {
        do {
            try Data(session.history.replay()).write(to: paths.savedOutput(for: session.id), options: .atomic)
        } catch {
            Self.logger.error("Could not save output of \(session.id): \(String(describing: error))")
        }
    }

    private func currentStatuses() -> [SessionStatus] {
        sessions.values
            .map { SessionStatus(id: $0.id, activity: $0.activity) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func publishStatusIfChanged() {
        let statuses = currentStatuses()
        guard statuses != lastStatuses else { return }
        lastStatuses = statuses
        guard let frame = try? Frame.json(.sessions, statuses) else { return }
        for client in clients.values {
            if case .control = client.role {
                client.send(frame)
            }
        }
    }
}
