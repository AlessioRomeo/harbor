import AppKit
import HarborCore
import Observation
import os

@Observable
final class AppModel {
    private static let logger = Logger(subsystem: "com.alessioromeo.harbor", category: "workspace")
    private static let fontSizeKey = "terminalFontSize"
    private static let selectionKey = "selectedSessionID"
    static let newSessionName = "New session"

    let host: HostClient
    private let store: WorkspaceStore
    private(set) var workspace = Workspace()
    /// Set when the workspace file can't be read or written; nothing is saved while it is set.
    private(set) var storageError: String?
    private(set) var controllers: [UUID: TerminalController] = [:]
    private(set) var fontSize: CGFloat
    var editingID: UUID? {
        didSet {
            if editingID == nil {
                terminalFocusRequest += 1
            }
        }
    }
    /// Bumped whenever the selected terminal should take the keyboard.
    private(set) var terminalFocusRequest = 0
    var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectionKey)
            prepareSelectedController()
            terminalFocusRequest += 1
            markSelectedSeen()
        }
    }
    private var pendingCreations: Set<UUID> = []
    private(set) var claudeEvents: [UUID: ClaudeEvent] = [:]
    private let claudeStore: ClaudeEventStore
    private var claudeWatcher: DirectoryWatcher?
    private var attentionIDs: Set<UUID> = []
    private let notifier = AttentionNotifier()

    init(paths: HarborPaths = .standard) {
        host = HostClient(paths: paths)
        store = WorkspaceStore(url: paths.workspace)
        claudeStore = ClaudeEventStore(directory: paths.claudeEvents)
        let stored = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = stored > 0 ? stored : Theme.defaultFontSize
    }

    func start() {
        loadWorkspace()
        host.onSessionsChanged = { [weak self] in self?.sessionsChanged() }
        host.connect()
        if storageError == nil {
            startWatchingClaude()
        }
    }

    private func loadWorkspace() {
        do {
            try host.paths.prepare()
            if let saved = try store.load() {
                workspace = saved
            } else {
                workspace = .initial()
                try store.save(workspace)
            }
        } catch {
            storageError = "Harbor couldn't read its sessions file (\(host.paths.workspace.path)): \(error.localizedDescription). Nothing will be saved until it's fixed or moved away."
            return
        }
        let stored = UserDefaults.standard.string(forKey: Self.selectionKey).flatMap(UUID.init(uuidString:))
        selectedID = stored.flatMap { workspace.session($0) }.map(\.id) ?? workspace.liveSessions.first?.id
    }

    @discardableResult
    private func update<Result>(_ change: (inout Workspace) throws -> Result) rethrows -> Result {
        var updated = workspace
        let result = try change(&updated)
        guard updated != workspace else { return result }
        workspace = updated
        guard storageError == nil else { return result }
        do {
            try store.save(workspace)
        } catch {
            storageError = "Harbor couldn't save its sessions file: \(error.localizedDescription)"
        }
        return result
    }

    /// Workspace errors here come from stale UI state, such as a menu acting on a group that just went away.
    private func attempt(_ change: (inout Workspace) throws -> Void) {
        do {
            try update(change)
        } catch {
            Self.logger.error("Ignored a workspace change: \(String(describing: error))")
        }
    }

    // MARK: Host

    private func sessionsChanged() {
        guard storageError == nil else { return }
        for order in workspace.sessionsToKill(running: Set(host.activities.keys)) {
            host.send(.kill(id: order.id, saveOutput: order.saveOutput))
        }
        for controller in controllers.values {
            if case .ended = controller.connection, let activity = host.activities[controller.id], activity != .ended(exitCode: controller.exitCode) {
                controller.markRestarted()
            }
            advance(controller)
        }
        refreshAttention()
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

    func reconnect() {
        for controller in controllers.values {
            controller.detach()
        }
        controllers.removeAll()
        pendingCreations.removeAll()
        host.connect()
        prepareSelectedController()
    }

    var selectedController: TerminalController? {
        selectedID.flatMap { controllers[$0] }
    }

    private func prepareSelectedController() {
        guard let id = selectedID, let session = workspace.session(id), !session.isArchived, controllers[id] == nil else { return }
        let controller = TerminalController(id: id, fontSize: fontSize)
        controller.onLayout = { [weak self, weak controller] in
            guard let self, let controller else { return }
            advance(controller)
        }
        controller.onRestartRequest = { [weak self, weak controller] in
            guard let self, let controller, let size = controller.layoutSize else { return }
            host.send(.create(id: controller.id, size: size))
        }
        controllers[id] = controller
    }

    func indicator(of id: UUID) -> SessionIndicator {
        SessionIndicator(host: host.activities[id], claude: claudeEvents[id], lastSeen: workspace.session(id)?.lastSeenAt)
    }

    // MARK: Claude

    private func startWatchingClaude() {
        installClaudeHook()
        claudeWatcher = DirectoryWatcher(url: host.paths.claudeEvents) { [weak self] in self?.claudeEventsChanged() }
        if claudeWatcher == nil {
            Self.logger.error("Can't watch \(self.host.paths.claudeEvents.path); Claude's status won't update")
        }
        notifier.onOpen = { [weak self] id in self?.selectedID = id }
        notifier.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.markSelectedSeen() }
        }
        claudeEventsChanged()
    }

    /// The hook settings point at a fixed path, so the script there follows the installed app.
    private func installClaudeHook() {
        guard let bundled = Bundle.main.url(forResource: "claude-hook", withExtension: "sh") else {
            Self.logger.error("The app bundle has no claude-hook.sh")
            return
        }
        do {
            let target = host.paths.claudeHook
            let contents = try Data(contentsOf: bundled)
            guard (try? Data(contentsOf: target)) != contents else { return }
            try contents.write(to: target, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        } catch {
            Self.logger.error("Could not install the Claude hook: \(String(describing: error))")
        }
    }

    private func claudeEventsChanged() {
        claudeEvents = claudeStore.load()
        markSelectedSeen()
    }

    /// Looking at a session in the active app is what clears its attention.
    private func markSelectedSeen() {
        if NSApp.isActive, let id = selectedID, workspace.session(id) != nil {
            update { $0.markSeen(id, at: Date()) }
            notifier.withdraw(sessionID: id)
        }
        refreshAttention()
    }

    private func refreshAttention() {
        let needing = Set(workspace.liveSessions.filter { indicator(of: $0.id).needsAttention }.map(\.id))
        let fresh = needing.subtracting(attentionIDs)
        attentionIDs = needing
        notifier.setBadge(needing.count)
        for id in fresh {
            guard let session = workspace.session(id), case .needsAttention(let reason) = indicator(of: id) else { continue }
            let body = switch reason {
            case .finished: "Claude finished."
            case .waiting: "Claude is waiting for you."
            case .failed: "Claude stopped with an error."
            }
            notifier.notify(sessionID: id, title: session.name, body: body)
        }
    }

    // MARK: Groups and sessions

    var currentGroupID: UUID? {
        selectedID.flatMap { workspace.session($0) }.map(\.groupID) ?? workspace.groups.first?.id
    }

    func newSession(in groupID: UUID? = nil) {
        let group = groupID ?? currentGroupID ?? update { $0.addGroup(named: Workspace.defaultGroupName) }
        var created: UUID?
        attempt { created = try $0.addSession(named: Self.newSessionName, to: group) }
        guard let created else { return }
        selectedID = created
        editingID = created
    }

    func newGroup() {
        editingID = update { $0.addGroup(named: "New group") }
    }

    func rename(_ id: UUID, to name: String) {
        update {
            if $0.session(id) != nil {
                $0.renameSession(id, to: name)
            } else {
                $0.renameGroup(id, to: name)
            }
        }
        if editingID == id {
            editingID = nil
        }
    }

    func moveGroup(_ id: UUID, by offset: Int) {
        update { $0.moveGroup(id, by: offset) }
    }

    func deleteGroup(_ id: UUID) {
        attempt { try $0.deleteGroup(id) }
    }

    func moveSession(_ id: UUID, to groupID: UUID, at position: Int? = nil) {
        attempt { try $0.moveSession(id, to: groupID, at: position) }
    }

    /// SwiftUI reports the destination before the moved rows are removed.
    func moveSessions(in groupID: UUID, from offsets: IndexSet, to destination: Int) {
        let ids = workspace.liveSessions(in: groupID).map(\.id)
        guard let source = offsets.first else { return }
        moveSession(ids[source], to: groupID, at: source < destination ? destination - 1 : destination)
    }

    // MARK: Terminal

    func clearSelected() {
        guard let controller = selectedController else { return }
        controller.clear()
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
