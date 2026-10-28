import AppKit
import HarborCore
import Observation
import SwiftTerm

/// One session's terminal view and its attachment to the host.
@Observable
final class TerminalController: NSObject, TerminalViewDelegate {
    enum Connection: Equatable {
        case detached
        case attached
        case ended(exitCode: Int32?)
        case lost(String)
    }

    private static let scrollbackLines = 10_000

    let id: UUID
    @ObservationIgnored let view: TerminalView
    private(set) var connection = Connection.detached
    /// The size the view settled on, known once it has been laid out in a window.
    @ObservationIgnored private(set) var layoutSize: TerminalSize?
    @ObservationIgnored var onLayout: (() -> Void)?
    @ObservationIgnored var onRestartRequest: (() -> Void)?
    @ObservationIgnored private var hostConnection: HostConnection?
    @ObservationIgnored private var isReplaying = false

    init(id: UUID, fontSize: CGFloat) {
        self.id = id
        view = TerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            font: Theme.terminalFont(size: fontSize),
            options: TerminalOptions(scrollback: Self.scrollbackLines)
        )
        super.init()
        view.terminalDelegate = self
        view.optionAsMetaKey = false
        view.nativeBackgroundColor = Theme.terminalBackground
        view.nativeForegroundColor = Theme.terminalForeground
        view.caretColor = Theme.caret
        view.selectedTextBackgroundColor = Theme.selection
        view.installColors(Theme.ansiColors)
    }

    func attach(socketPath: String) {
        hostConnection?.close()
        isReplaying = true
        do {
            let link = try HostConnection(socketPath: socketPath, attach: id)
            hostConnection = link
            connection = .attached
            let feeder = view.feedSender
            link.startReceiving { [weak self] result in
                switch result {
                case .success(let frame) where frame.type == .output:
                    feeder.feed(byteArray: frame.payload[...])
                    DispatchQueue.main.async { self?.finishReplay() }
                case .success(let frame) where frame.type == .exited:
                    let exited = try? frame.decode(Exited.self)
                    DispatchQueue.main.async { self?.connection = .ended(exitCode: exited?.exitCode) }
                case .success:
                    break
                case .failure(let error):
                    DispatchQueue.main.async { self?.connectionEnded(link, error: error) }
                }
            }
        } catch {
            isReplaying = false
            connection = .lost(error.localizedDescription)
        }
    }

    var exitCode: Int32? {
        if case .ended(let code) = connection { return code }
        return nil
    }

    /// The host started a new shell in this session while the view stayed attached.
    func markRestarted() {
        guard case .ended = connection, hostConnection != nil else { return }
        connection = .attached
    }

    func detach() {
        hostConnection?.close()
        hostConnection = nil
        connection = .detached
    }

    /// Replies the terminal generates to queries inside the replayed output arrive on the main
    /// queue after the feed; this runs after them, so they are dropped instead of typed into the shell.
    private func finishReplay() {
        guard isReplaying else { return }
        isReplaying = false
        if let layoutSize {
            sendFrame(.resize(layoutSize))
        }
    }

    private func connectionEnded(_ ended: HostConnection, error: any Error) {
        guard ended === hostConnection else { return }
        hostConnection = nil
        isReplaying = false
        if case .ended = connection { return }
        connection = .lost(String(describing: error))
    }

    private func sendFrame(_ frame: Frame) {
        guard let hostConnection else { return }
        do {
            try hostConnection.send(frame)
        } catch {
            connectionEnded(hostConnection, error: error)
        }
    }

    /// Like Terminal's Clear to Start: the cursor's line moves to the top and everything above it goes.
    func clear() {
        let row = view.terminalStateSnapshot().cursor.row
        if row > 0 {
            view.feed(text: "\u{1B}[\(row)S\u{1B}[\(row)A")
        }
        view.clearScrollback()
    }

    func setFontSize(_ size: CGFloat) {
        view.font = Theme.terminalFont(size: size)
    }

    // MARK: TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !isReplaying else { return }
        if case .ended = connection {
            if data.contains(0x0D) {
                onRestartRequest?()
            }
            return
        }
        sendFrame(Frame(.input, payload: Array(data)))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let size = TerminalSize(cols: UInt16(clamping: newCols), rows: UInt16(clamping: newRows))
        let isFirstLayout = layoutSize == nil
        layoutSize = size
        if !isReplaying {
            sendFrame(.resize(size))
        }
        if isFirstLayout {
            onLayout?()
        }
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
