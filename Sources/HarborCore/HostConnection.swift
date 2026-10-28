import Darwin
import Foundation

public enum HostConnectionError: Error, Equatable {
    case closed
    case unexpectedFrame(FrameType)
}

/// A blocking connection to the session host. Safe with one thread sending and one receiving.
public final class HostConnection: @unchecked Sendable {
    private let fd: Int32
    private var decoder = FrameDecoder()
    private var isClosed = false

    /// Connects and completes the handshake. Pass `attach` to stream one session's output.
    public init(socketPath: String, attach: UUID? = nil, version: Int = protocolVersion, timeout: TimeInterval = 5) throws {
        fd = try UnixSocket.connect(path: socketPath)
        do {
            try send(.json(.hello, Hello(version: version, attach: attach)))
            let reply = try receive(timeout: timeout)
            switch reply.type {
            case .welcome:
                break
            case .failure:
                throw try reply.decode(Failure.self)
            default:
                throw HostConnectionError.unexpectedFrame(reply.type)
            }
        } catch {
            close()
            throw error
        }
    }

    deinit {
        Darwin.close(fd)
    }

    public func send(_ frame: Frame) throws {
        try UnixSocket.writeAll(fd, frame.encoded())
    }

    public func send(_ request: HostRequest) throws {
        try send(.json(.request, request))
    }

    /// Waits for the next frame; `timeout` nil waits forever.
    public func receive(timeout: TimeInterval? = nil) throws -> Frame {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while true {
            if let frame = try decoder.next() { return frame }
            let remaining = deadline.map { max(0, $0.timeIntervalSinceNow) }
            let bytes = try UnixSocket.read(fd, timeout: remaining)
            if bytes.isEmpty { throw HostConnectionError.closed }
            decoder.append(bytes)
        }
    }

    /// Receives on a dedicated thread until the connection ends, which is reported once as the error.
    public func startReceiving(_ handler: @escaping @Sendable (Result<Frame, any Error>) -> Void) {
        let thread = Thread { [self] in
            while true {
                do {
                    handler(.success(try receive()))
                } catch {
                    handler(.failure(error))
                    return
                }
            }
        }
        thread.name = "Harbor host connection"
        thread.start()
    }

    /// Ends the connection and wakes a blocked receiver; the descriptor closes when the last user lets go.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        Darwin.shutdown(fd, SHUT_RDWR)
    }
}
