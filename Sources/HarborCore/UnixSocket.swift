import Darwin
import Foundation

public enum SocketError: Error, Equatable {
    case pathTooLong(String)
    case system(call: String, errno: Int32)
    case timedOut
}

public enum UnixSocket {
    public static func listen(path: String) throws -> Int32 {
        let fd = try makeSocket()
        do {
            try withAddress(path) { address, length in
                guard Darwin.bind(fd, address, length) == 0 else { throw systemError("bind") }
            }
            guard Darwin.listen(fd, 16) == 0 else { throw systemError("listen") }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    public static func connect(path: String) throws -> Int32 {
        let fd = try makeSocket()
        do {
            try withAddress(path) { address, length in
                guard Darwin.connect(fd, address, length) == 0 else { throw systemError("connect") }
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    public static func accept(_ listener: Int32) throws -> Int32 {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { throw systemError("accept") }
        do {
            try configure(fd)
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    public static func peerUID(_ fd: Int32) throws -> uid_t {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { throw systemError("getpeereid") }
        return uid
    }

    public static func writeAll(_ fd: Int32, _ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                throw systemError("write")
            }
            offset += written
        }
    }

    /// Reads what is available, waiting up to `timeout` seconds (nil waits forever). Empty means end of stream.
    public static func read(_ fd: Int32, maxCount: Int = 64 << 10, timeout: TimeInterval? = nil) throws -> [UInt8] {
        if let timeout {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(timeout * 1000))
            if ready < 0 { throw systemError("poll") }
            if ready == 0 { throw SocketError.timedOut }
        }
        var buffer = [UInt8](repeating: 0, count: maxCount)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, maxCount) }
            if count >= 0 { return Array(buffer[..<count]) }
            if errno != EINTR { throw systemError("read") }
        }
    }

    private static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw systemError("socket") }
        do {
            try configure(fd)
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    private static func configure(_ fd: Int32) throws {
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw systemError("fcntl") }
        var on: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw systemError("setsockopt")
        }
    }

    private static func withAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Void) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else { throw SocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    private static func systemError(_ call: String) -> SocketError {
        .system(call: call, errno: errno)
    }
}
