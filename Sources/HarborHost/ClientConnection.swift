import Darwin
import Foundation
import HarborCore
import os

/// One accepted socket. Reads arrive on the host queue; writes go through a private queue
/// so a slow client never blocks the host, and the descriptor closes only after pending writes.
final class ClientConnection: @unchecked Sendable {
    enum Role {
        case pending
        case control
        case attached(UUID)
    }

    private static let logger = Logger(subsystem: "com.alessioromeo.harbor", category: "connection")

    let id = UUID()
    var role = Role.pending
    private let fd: Int32
    private let readSource: DispatchSourceRead
    private let writeQueue = DispatchQueue(label: "com.alessioromeo.harbor.client-write")
    private let onFrame: (ClientConnection, Frame) -> Void
    private let onClose: (ClientConnection) -> Void
    private var decoder = FrameDecoder()
    private var isClosed = false

    init(fd: Int32, queue: DispatchQueue, onFrame: @escaping (ClientConnection, Frame) -> Void, onClose: @escaping (ClientConnection) -> Void) {
        self.fd = fd
        self.onFrame = onFrame
        self.onClose = onClose
        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let writeQueue = writeQueue
        readSource.setEventHandler { [unowned self] in
            readAvailable()
        }
        readSource.setCancelHandler {
            writeQueue.async { Darwin.close(fd) }
        }
        readSource.resume()
    }

    func send(_ frame: Frame) {
        guard !isClosed else { return }
        let bytes = frame.encoded()
        let fd = fd
        writeQueue.async {
            do {
                try UnixSocket.writeAll(fd, bytes)
            } catch {
                Self.logger.debug("Write to client failed: \(String(describing: error))")
            }
        }
    }

    func reject(_ failure: Failure) {
        do {
            send(try .json(.failure, failure))
        } catch {
            Self.logger.error("Could not encode failure: \(String(describing: error))")
        }
    }

    func fail(_ message: String) {
        reject(Failure(message))
        close()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        readSource.cancel()
        onClose(self)
    }

    private func readAvailable() {
        do {
            let bytes = try UnixSocket.read(fd)
            guard !bytes.isEmpty else {
                close()
                return
            }
            decoder.append(bytes)
            while !isClosed, let frame = try decoder.next() {
                onFrame(self, frame)
            }
        } catch {
            Self.logger.error("Dropping client: \(String(describing: error))")
            close()
        }
    }
}
