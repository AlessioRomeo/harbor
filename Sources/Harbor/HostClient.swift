import Foundation
import HarborCore
import Observation
import os

/// The control connection to the session host: creates and ends sessions and follows their activity.
@Observable
final class HostClient {
    private static let logger = Logger(subsystem: "com.alessioromeo.harbor", category: "host-client")

    enum State: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    let paths: HarborPaths
    private(set) var state = State.connecting
    private(set) var activities: [UUID: SessionActivity] = [:]
    private(set) var hasReceivedSessions = false
    var onSessionsChanged: (() -> Void)?
    private var connection: HostConnection?

    init(paths: HarborPaths = .standard) {
        self.paths = paths
    }

    func connect() {
        state = .connecting
        let paths = paths
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try HostLauncher.connect(paths: paths) }
            DispatchQueue.main.async { self.connected(result) }
        }
    }

    private func connected(_ result: Result<HostConnection, any Error>) {
        switch result {
        case .success(let connection):
            self.connection = connection
            state = .connected
            connection.startReceiving { [weak self] result in
                DispatchQueue.main.async { self?.received(result, on: connection) }
            }
        case .failure(let failure as Failure):
            state = .failed("The running session host is from another version of Harbor (\(failure.message)). Quit Harbor, then run `pkill harbor-host`. This ends running sessions.")
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
    }

    private func received(_ result: Result<Frame, any Error>, on connection: HostConnection) {
        guard connection === self.connection else { return }
        switch result {
        case .success(let frame) where frame.type == .sessions:
            do {
                let statuses = try frame.decode([SessionStatus].self)
                activities = Dictionary(uniqueKeysWithValues: statuses.map { ($0.id, $0.activity) })
                hasReceivedSessions = true
                onSessionsChanged?()
            } catch {
                state = .failed("The session host sent an unreadable session list: \(error)")
            }
        case .success(let frame) where frame.type == .failure:
            let message = (try? frame.decode(Failure.self).message) ?? "unreadable failure"
            Self.logger.error("The session host refused a request: \(message)")
        case .success:
            break
        case .failure(let error):
            self.connection = nil
            hasReceivedSessions = false
            Self.logger.error("Lost the session host: \(String(describing: error))")
            state = .failed("The session host stopped. Reconnecting starts it again, and sessions come back with their output.")
        }
    }

    func send(_ request: HostRequest) {
        guard let connection else { return }
        do {
            try connection.send(request)
        } catch {
            Self.logger.error("Could not reach the session host: \(String(describing: error))")
            state = .failed("The session host stopped. Reconnecting starts it again, and sessions come back with their output.")
        }
    }
}
