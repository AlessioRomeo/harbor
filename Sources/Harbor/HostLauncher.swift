import Darwin
import Foundation
import HarborCore

nonisolated enum HostLauncherError: LocalizedError {
    case helperMissing(String)
    case spawnFailed(Int32)
    case didNotStart

    var errorDescription: String? {
        switch self {
        case .helperMissing(let path): "The session host is missing from the app bundle (\(path))."
        case .spawnFailed(let code): "The session host could not be started (error \(code))."
        case .didNotStart: "The session host did not start in time."
        }
    }
}

/// Connects to the running session host, starting it first if nobody is listening.
nonisolated enum HostLauncher {
    private static let startTimeout: TimeInterval = 5

    static func connect(paths: HarborPaths) throws -> HostConnection {
        do {
            return try HostConnection(socketPath: paths.socket.path)
        } catch is SocketError {
            try spawnHost()
        }
        let deadline = Date().addingTimeInterval(startTimeout)
        while true {
            do {
                return try HostConnection(socketPath: paths.socket.path)
            } catch is SocketError where Date() < deadline {
                usleep(50_000)
            } catch is SocketError {
                throw HostLauncherError.didNotStart
            }
        }
    }

    /// The host gets its own session so it outlives the app, and no descriptors of ours.
    private static func spawnHost() throws {
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/harbor-host").path
        guard FileManager.default.isExecutableFile(atPath: path) else { throw HostLauncherError.helperMissing(path) }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd: Int32 in 0...2 {
            posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
        }

        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        defer { argv.forEach { free($0) } }
        let result = posix_spawn(&pid, path, &actions, &attributes, argv, environ)
        guard result == 0 else { throw HostLauncherError.spawnFailed(result) }
        let child = pid
        Thread.detachNewThread {
            var status: Int32 = 0
            waitpid(child, &status, 0)
        }
    }
}
