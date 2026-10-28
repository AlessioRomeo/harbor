import AppKit
import HarborCore
import Observation

@Observable
final class AppModel {
    private static let fontSizeKey = "terminalFontSize"
    private static let sessionKey = "sessionID"

    let host = HostClient()
    private(set) var controllers: [UUID: TerminalController] = [:]
    private(set) var selectedID: UUID?
    private(set) var fontSize: CGFloat
    private var pendingCreations: Set<UUID> = []

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = stored > 0 ? stored : Theme.defaultFontSize
    }

    func start() {
        host.onSessionsChanged = { [weak self] in self?.sessionsChanged() }
        host.connect()
    }

    var selectedController: TerminalController? {
        selectedID.flatMap { controllers[$0] }
    }

    private func sessionsChanged() {
        let id = storedSessionID()
        selectedID = id
        if let controller = controllers[id] {
            advance(controller)
            return
        }
        let controller = TerminalController(id: id, fontSize: fontSize)
        controller.onLayout = { [weak self, weak controller] in
            guard let self, let controller else { return }
            advance(controller)
        }
        controllers[id] = controller
    }

    /// A session is created at the size its view settled on, so the shell's first prompt fits;
    /// the view attaches once the host lists the session.
    private func advance(_ controller: TerminalController) {
        guard controller.connection == .detached, let size = controller.layoutSize, host.hasReceivedSessions else { return }
        if host.activities[controller.id] == nil {
            guard pendingCreations.insert(controller.id).inserted else { return }
            host.send(.create(id: controller.id, size: size))
        } else {
            pendingCreations.remove(controller.id)
            controller.attach(socketPath: host.paths.socket.path)
        }
    }

    private func storedSessionID() -> UUID {
        if let text = UserDefaults.standard.string(forKey: Self.sessionKey), let id = UUID(uuidString: text) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: Self.sessionKey)
        return id
    }

    func clearSelected() {
        guard let controller = selectedController else { return }
        controller.clearScrollback()
        host.send(.clear(id: controller.id))
    }

    func changeFontSize(by delta: CGFloat) {
        setFontSize(fontSize + delta)
    }

    func resetFontSize() {
        setFontSize(Theme.defaultFontSize)
    }

    private func setFontSize(_ size: CGFloat) {
        fontSize = min(max(size, Theme.fontSizeRange.lowerBound), Theme.fontSizeRange.upperBound)
        UserDefaults.standard.set(Double(fontSize), forKey: Self.fontSizeKey)
        for controller in controllers.values {
            controller.setFontSize(fontSize)
        }
    }
}
