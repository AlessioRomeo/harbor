import AppKit
import HarborCore
import Observation
import os

@Observable
final class AppModel {
    private static let logger = Logger(subsystem: "com.alessioromeo.harbor", category: "workspace")
    private static let fontSizeKey = "terminalFontSize"
    private static let selectionKey = "selectedSessionID"
    private static let autoArchiveKey = "autoArchiveDays"
    static let autoArchiveChoices = [3, 7, 14, 0]
    private static let activityResolution: TimeInterval = 60
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
    /// The session with the keyboard: the focused pane, or an archived session being looked at.
    /// Selecting a live session that isn't on screen puts it in the focused pane's place.
    var selectedID: UUID? {
        didSet {
            if selectedID == nil, oldValue != nil, let focused = workspace.focusedPane {
                selectedID = focused
            }
            guard selectedID != oldValue else { return }
            UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectionKey)
            if let selectedID {
                bringOnScreen(selectedID)
            }
            prepareVisibleControllers()
            terminalFocusRequest += 1
            markSelectedSeen()
            if let selectedID, let session = workspace.session(selectedID) {
                isShowingArchive = session.isArchived
            }
        }
    }
    private var pendingCreations: Set<UUID> = []
    private var hasHandledSessions = false
    private(set) var claudeEvents: [UUID: ClaudeEvent] = [:]
    private let claudeStore: ClaudeEventStore
    private var claudeWatcher: DirectoryWatcher?
    private var attentionIDs: Set<UUID>?
    private let notifier = AttentionNotifier()
    private var autoArchiveTimer: Timer?
    /// A session waiting for me to confirm that archiving may end what runs in it.
    var archiveNeedingConfirmation: UUID?
    var isSwitcherOpen = false
    /// The sidebar lists archived sessions instead of groups.
    var isShowingArchive = false
    var autoArchiveDays: Int {
        didSet {
            UserDefaults.standard.set(autoArchiveDays, forKey: Self.autoArchiveKey)
            autoArchiveQuietSessions()
        }
    }

    init(paths: HarborPaths = .standard) {
        host = HostClient(paths: paths)
        store = WorkspaceStore(url: paths.workspace)
        claudeStore = ClaudeEventStore(directory: paths.claudeEvents)
        let stored = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = stored > 0 ? stored : Theme.defaultFontSize
        autoArchiveDays = UserDefaults.standard.object(forKey: Self.autoArchiveKey) as? Int ?? 7
    }

    func start() {
        loadWorkspace()
        host.onSessionsChanged = { [weak self] in self?.sessionsChanged() }
        host.connect()
        if storageError == nil {
            startWatchingClaude()
            autoArchiveTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.autoArchiveQuietSessions() }
            }
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
        update {
            $0.ensureGeneralGroup()
            $0.pruneLayout()
        }
        let stored = UserDefaults.standard.string(forKey: Self.selectionKey)
            .flatMap(UUID.init(uuidString:))
            .flatMap { workspace.session($0) }
        if let stored, stored.isArchived || workspace.layout == nil || workspace.layout?.contains(stored.id) == true {
            selectedID = stored.id
        } else {
            selectedID = workspace.focusedPane ?? workspace.liveSessions.first?.id
        }
    }

    @discardableResult
    private func update<Result>(_ change: (inout Workspace) throws -> Result) rethrows -> Result {
        var updated = workspace
        let result = try change(&updated)
        guard updated != workspace else { return result }
        workspace = updated
        if paneCount < 2 {
            isZoomed = false
        }
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
        let isFirstList = !hasHandledSessions
        hasHandledSessions = true
        for (id, activity) in host.activities where activity == .busy {
            noteActivity(id)
        }
        clearStaleClaudeEvents()
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
        if isFirstList {
            autoArchiveQuietSessions()
        }
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
        hasHandledSessions = false
        for controller in controllers.values {
            controller.detach()
        }
        controllers.removeAll()
        pendingCreations.removeAll()
        host.connect()
        prepareVisibleControllers()
    }

    var selectedController: TerminalController? {
        selectedID.flatMap { controllers[$0] }
    }

    /// Every pane on screen needs its terminal; ones that left the screen keep theirs, still attached.
    private func prepareVisibleControllers() {
        for id in workspace.layout?.sessionIDs ?? [] where controllers[id] == nil {
            makeController(for: id)
        }
    }

    private func makeController(for id: UUID) {
        let controller = TerminalController(id: id, fontSize: fontSize)
        controller.onLayout = { [weak self, weak controller] in
            guard let self, let controller else { return }
            advance(controller)
        }
        controller.onRestartRequest = { [weak self, weak controller] in
            guard let self, let controller, let size = controller.layoutSize else { return }
            host.send(.create(id: controller.id, size: size))
        }
        controller.onInput = { [weak self] in self?.noteActivity(id) }
        controller.onActivate = { [weak self] in self?.selectedID = id }
        controllers[id] = controller
    }

    // MARK: Panes

    var paneCount: Int {
        workspace.layout?.sessionIDs.count ?? 0
    }

    /// Pane commands act only while the panes are what's on screen, not an archived session.
    var arePanesShown: Bool {
        selectedID.map { workspace.layout?.contains($0) == true } ?? false
    }

    private func bringOnScreen(_ id: UUID) {
        guard let session = workspace.session(id), !session.isArchived else { return }
        update { workspace in
            if workspace.layout?.contains(id) == true {
                workspace.focusPane(id)
            } else if let layout = workspace.layout, let focused = workspace.focusedPane {
                workspace.setLayout(layout.replacing(focused, with: id), focus: id)
            } else {
                workspace.setLayout(.pane(id), focus: id)
            }
        }
    }

    /// A new session beside the focused pane, in the same group, named straight away.
    func splitFocusedPane(toward edge: PaneEdge) {
        guard arePanesShown, let focused = workspace.focusedPane, let layout = workspace.layout, let group = workspace.session(focused)?.groupID else {
            newSession()
            return
        }
        var created: UUID?
        attempt { workspace in
            let id = try workspace.addSession(named: Self.newSessionName, to: group)
            workspace.setLayout(layout.splitting(focused, with: id, at: edge), focus: id)
            created = id
        }
        guard let created else { return }
        selectedID = created
        editingID = created
    }

    /// Takes the focused pane off screen; its session keeps running in the sidebar.
    func closeFocusedPane() {
        guard arePanesShown, paneCount > 1, let focused = workspace.focusedPane else { return }
        update { $0.removeFromLayout(focused) }
        selectedID = workspace.focusedPane
    }

    func moveFocus(toward edge: PaneEdge) {
        guard arePanesShown, let focused = workspace.focusedPane, let next = workspace.layout?.neighbour(of: focused, toward: edge) else { return }
        selectedID = next
    }

    func evenOutPanes() {
        guard arePanesShown, let layout = workspace.layout else { return }
        update { $0.setLayout(layout.evened) }
    }

    /// The focused pane fills the window; moving the focus shows another pane the same way.
    var isZoomed = false
    /// The session being dragged right now, so its own pane offers no place to drop it.
    var draggedSession: UUID?

    func toggleZoom() {
        isZoomed = arePanesShown && paneCount > 1 && !isZoomed
    }

    /// Puts a session beside a pane, or in its place; a session already on screen moves there.
    func place(_ id: UUID, at drop: PaneDrop, of target: UUID) {
        guard id != target, let session = workspace.session(id), !session.isArchived, let layout = workspace.layout else { return }
        update { $0.setLayout(layout.placing(id, at: drop, of: target), focus: id) }
        selectedID = id
    }

    /// The group's live sessions as an even grid, the focused one keeping the keyboard if it's among them.
    func showGroupAsGrid(_ groupID: UUID) {
        let ids = workspace.liveSessions(in: groupID).map(\.id)
        guard let grid = PaneLayout.grid(ids) else { return }
        let focus = selectedID.flatMap { grid.contains($0) ? $0 : nil } ?? grid.sessionIDs.first
        isZoomed = false
        update { $0.setLayout(grid, focus: focus) }
        if let focus {
            selectedID = focus
        }
        prepareVisibleControllers()
    }

    func showCurrentGroupAsGrid() {
        if let group = currentGroupID {
            showGroupAsGrid(group)
        }
    }

    /// The session that has needed me longest, on screen or not.
    func jumpToNextNeedingAttention() {
        let needing = workspace.liveSessions.map(\.id).filter { indicator(of: $0).needsAttention }
        guard let next = ClaudeEvent.longestWaiting(among: needing, events: claudeEvents) else {
            NSSound.beep()
            return
        }
        selectedID = next
    }

    func setSplitRatio(_ ratio: Double, at path: [Bool]) {
        guard let layout = workspace.layout else { return }
        update { $0.setLayout(layout.settingRatio(ratio, at: path)) }
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
        for (id, event) in claudeEvents {
            noteActivity(id, at: event.at)
        }
        markSelectedSeen()
    }

    /// The host only reports changes, so an event too young to judge when the shell came back
    /// is judged again once the host has had time to report a new Claude.
    private func clearStaleClaudeEvents() {
        let now = Date()
        let isTooYoungToJudge = claudeEvents.contains { id, event in
            host.activities[id] == .idle && now.timeIntervalSince(event.at) <= ClaudeEvent.hostReportDelay
        }
        if isTooYoungToJudge {
            DispatchQueue.main.asyncAfter(deadline: .now() + ClaudeEvent.hostReportDelay + 0.1) { [weak self] in
                self?.clearStaleClaudeEvents()
            }
        }
        let stale = ClaudeEvent.stale(claudeEvents, activities: host.activities, now: now)
        guard !stale.isEmpty else { return }
        for id in stale {
            do {
                try claudeStore.remove(id)
            } catch {
                Self.logger.error("Could not clear Claude's report for \(id): \(String(describing: error))")
            }
        }
        claudeEvents = claudeStore.load()
    }

    /// Looking at a session in the active app is what clears its attention.
    private func markSelectedSeen() {
        if NSApp.isActive, let id = selectedID, workspace.session(id) != nil {
            update { $0.markSeen(id, at: Date()) }
            notifier.withdraw(sessionID: id)
        }
        refreshAttention()
    }

    /// Only sessions that start needing me while Harbor is in the background are announced;
    /// what already needed me when the host first answered just shows in the badge.
    private func refreshAttention() {
        guard host.hasReceivedSessions else { return }
        let needing = Set(workspace.liveSessions.filter { indicator(of: $0.id).needsAttention }.map(\.id))
        let fresh = needing.subtracting(attentionIDs ?? [])
        let isFirstCount = attentionIDs == nil
        attentionIDs = needing
        notifier.setBadge(needing.count)
        guard !isFirstCount, !NSApp.isActive, !fresh.isEmpty else { return }
        notifier.requestAttention()
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
        selectedID.flatMap { workspace.session($0) }.map(\.groupID) ?? Workspace.generalGroupID
    }

    func newSession(in groupID: UUID? = nil) {
        update { $0.ensureGeneralGroup() }
        let group = groupID ?? Workspace.generalGroupID
        var created: UUID?
        attempt { created = try $0.addSession(named: Self.newSessionName, to: group) }
        guard let created else { return }
        selectedID = created
        editingID = created
    }

    /// The name popover opens once the new title is on screen; asked for at once, it never shows.
    func newGroup() {
        let id = update { $0.addGroup(named: "New group") }
        DispatchQueue.main.async { [weak self] in self?.editingID = id }
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

    // MARK: Archive

    /// Saves at most once a minute per session; auto-archive counts in days.
    private func noteActivity(_ id: UUID, at date: Date = Date()) {
        guard let session = workspace.session(id), !session.isArchived,
              date.timeIntervalSince(session.lastActivityAt) >= Self.activityResolution else { return }
        update { $0.recordActivity(id, at: date) }
    }

    /// Archiving ends the shell, so a session with something running asks first.
    func requestArchive(_ id: UUID) {
        switch indicator(of: id) {
        case .running, .claudeWorking, .claudeIdle, .needsAttention:
            archiveNeedingConfirmation = id
        case .notStarted, .idle, .ended:
            archive(id)
        }
    }

    func archive(_ id: UUID) {
        archiveNeedingConfirmation = nil
        guard let session = workspace.session(id), !session.isArchived else { return }
        controllers.removeValue(forKey: id)?.detach()
        pendingCreations.remove(id)
        if host.activities[id] != nil {
            host.send(.kill(id: id, saveOutput: true))
        }
        let sidebarNeighbour = neighbour(of: session)
        update { $0.archive(id, at: Date()) }
        if selectedID == id {
            selectedID = workspace.focusedPane ?? sidebarNeighbour
        }
        notifier.withdraw(sessionID: id)
        refreshAttention()
    }

    func restore(_ id: UUID) {
        update { $0.restore(id, at: Date()) }
        controllers.removeValue(forKey: id)
        selectedID = nil
        selectedID = id
    }

    func deletePermanently(_ id: UUID) {
        let sidebarNeighbour = workspace.session(id).flatMap(neighbour(of:))
        controllers.removeValue(forKey: id)?.detach()
        if host.activities[id] != nil {
            host.send(.kill(id: id, saveOutput: false))
        }
        update { $0.deleteSession(id) }
        if selectedID == id {
            selectedID = workspace.focusedPane ?? sidebarNeighbour
        }
        do {
            let saved = host.paths.savedOutput(for: id)
            if FileManager.default.fileExists(atPath: saved.path) {
                try FileManager.default.removeItem(at: saved)
            }
            try claudeStore.remove(id)
        } catch {
            Self.logger.error("Could not remove the files of \(id): \(String(describing: error))")
        }
        refreshAttention()
    }

    /// The live session to show instead: the next one in the same group, else the previous, else any.
    private func neighbour(of session: Session) -> UUID? {
        let siblings = workspace.liveSessions(in: session.groupID).map(\.id)
        if let index = siblings.firstIndex(of: session.id) {
            let others = siblings.indices.filter { $0 != index }
            if let next = others.first(where: { $0 > index }) ?? others.last {
                return siblings[next]
            }
        }
        return workspace.liveSessions.first { $0.id != session.id }?.id
    }

    func savedOutput(of id: UUID) -> Data? {
        try? Data(contentsOf: host.paths.savedOutput(for: id))
    }

    private func autoArchiveQuietSessions() {
        guard autoArchiveDays > 0, host.hasReceivedSessions, storageError == nil else { return }
        let indicators = Dictionary(uniqueKeysWithValues: workspace.liveSessions.map { ($0.id, indicator(of: $0.id)) })
        let quiet = workspace.sessionsToAutoArchive(
            now: Date(),
            idleInterval: TimeInterval(autoArchiveDays) * 24 * 3600,
            indicators: indicators,
            onScreen: Set(workspace.layout?.sessionIDs ?? []).union(selectedID.map { [$0] } ?? [])
        )
        for id in quiet {
            archive(id)
        }
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
