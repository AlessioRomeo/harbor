import Darwin
import Foundation
import HarborCore
import SwiftTerm

/// One shell on its pseudo-terminal, with its output history and the client attached to it, if any.
final class HostSession: LocalProcessDelegate, @unchecked Sendable {
    let id: UUID
    private(set) var history = OutputHistory()
    private(set) var exitCode: Int32?
    private(set) var hasExited = false
    var attached: ClientConnection?
    var size: TerminalSize
    var isBeingKilled = false
    private var process: LocalProcess!
    private let onExit: (HostSession) -> Void
    private let queue: DispatchQueue

    /// `restoredOutput` is what an earlier shell of this session left, shown above the new one.
    init(id: UUID, size: TerminalSize, restoredOutput: [UInt8]?, queue: DispatchQueue, onExit: @escaping (HostSession) -> Void) {
        self.id = id
        self.size = size
        self.queue = queue
        self.onExit = onExit
        if let restoredOutput {
            history.append(restoredOutput)
            history.append(OutputHistory.newShellMarker)
        }
        process = LocalProcess(delegate: self, dispatchQueue: queue)
    }

    /// Starts a new shell in place of one that exited, keeping the history and the attached client.
    func restart(with launcher: ShellLauncher, size newSize: TerminalSize) {
        precondition(hasExited, "restart needs an exited shell")
        history.append(OutputHistory.newShellMarker)
        attached?.send(Frame(.output, payload: OutputHistory.newShellMarker))
        hasExited = false
        exitCode = nil
        size = newSize
        process = LocalProcess(delegate: self, dispatchQueue: queue)
        start(with: launcher)
    }

    func start(with launcher: ShellLauncher) {
        process.startProcess(
            executable: launcher.executable,
            args: [],
            environment: launcher.environment(for: id),
            execName: launcher.loginName,
            currentDirectory: launcher.directory
        )
    }

    var activity: SessionActivity {
        if hasExited { return .ended(exitCode: exitCode) }
        let shell = process.shellPid
        let foreground = tcgetpgrp(process.childfd)
        return shell > 0 && foreground > 0 && foreground != shell ? .busy : .idle
    }

    func send(_ input: [UInt8]) {
        process.send(data: input[...])
    }

    func resize(to newSize: TerminalSize) {
        size = newSize
        var windowSize = winsize(ws_row: newSize.rows, ws_col: newSize.cols, ws_xpixel: 0, ws_ypixel: 0)
        process.updateWindowSize(&windowSize)
    }

    func clearHistory() {
        history.clear()
        requestRedraw()
    }

    /// The kernel only signals a size change, so a client that attaches at the same size
    /// asks the foreground program (zsh, claude) to repaint this way.
    func requestRedraw() {
        guard !hasExited else { return }
        let foreground = tcgetpgrp(process.childfd)
        if foreground > 0 {
            killpg(foreground, SIGWINCH)
        }
    }

    /// Interactive shells ignore SIGTERM, so hang up the shell's process group and the
    /// foreground job. Returns the groups signalled, which outlive the shell when a job ignores HUP.
    func hangUp() -> [pid_t] {
        let shell = process.shellPid
        guard shell > 0 else { return [] }
        let foreground = tcgetpgrp(process.childfd)
        let groups = foreground > 0 && foreground != shell ? [foreground, shell] : [shell]
        for group in groups {
            killpg(group, SIGHUP)
        }
        return groups
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        history.append(slice)
        attached?.send(Frame(.output, payload: Array(slice)))
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        hasExited = true
        self.exitCode = exitCode
        onExit(self)
    }

    func processFailedToStart(_ source: LocalProcess, error: LocalProcessError) {
        dataReceived(slice: Array("\r\nHarbor could not start the shell: \(error)\r\n".utf8)[...])
        processTerminated(source, exitCode: nil)
    }

    func getWindowSize() -> winsize {
        winsize(ws_row: size.rows, ws_col: size.cols, ws_xpixel: 0, ws_ypixel: 0)
    }
}
