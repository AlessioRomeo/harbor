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

    let id: UUID
    @ObservationIgnored let view: TerminalView
    private(set) var connection = Connection.detached
    /// The size the view settled on, known once it has been laid out in a window.
    @ObservationIgnored private(set) var layoutSize: TerminalSize?
    @ObservationIgnored var onLayout: (() -> Void)?
    @ObservationIgnored var onRestartRequest: (() -> Void)?
    @ObservationIgnored var onInput: (() -> Void)?
    /// A click in the terminal: its pane should take the focus.
    @ObservationIgnored var onActivate: (() -> Void)?
    @ObservationIgnored private var hostConnection: HostConnection?
    @ObservationIgnored private var isReplaying = false

    init(id: UUID, fontSize: CGFloat) {
        self.id = id
        view = HarborTerminalView.harbor(fontSize: fontSize)
        super.init()
        view.terminalDelegate = self
        (view as? HarborTerminalView)?.onMouseDown = { [weak self] in self?.onActivate?() }
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
        onInput?()
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

/// SwiftTerm doesn't let subclasses see focus changes, but it does let them see clicks.
/// The click's column also tells which match of a selected word the selection is.
final class HarborTerminalView: TerminalView {
    var onMouseDown: (() -> Void)?
    private var mouseDownCell: (column: Int, row: Int)?

    override func mouseDown(with event: NSEvent) {
        mouseDownCell = cell(at: convert(event.locationInWindow, from: nil))
        onMouseDown?()
        super.mouseDown(with: event)
    }

    /// The screen cell under a point, assuming the view shows the live screen rather than scrollback.
    private func cell(at point: NSPoint) -> (column: Int, row: Int)? {
        guard let dimensions = terminalInputStateSnapshot()?.dimensions, dimensions.cols > 0, dimensions.rows > 0,
              bounds.width > 0, bounds.height > 0 else { return nil }
        let cellHeight = bounds.height / CGFloat(dimensions.rows)
        let y = isFlipped ? point.y : bounds.height - point.y
        return (Int(point.x / (bounds.width / CGFloat(dimensions.cols))), Int(y / cellHeight))
    }

    /// Replaces a selection inside the line being typed by pressing the keys a person would.
    /// False when the selection isn't part of the cursor's row, so the key should go on as usual.
    func replaceSelection(with replacement: String) -> Bool {
        guard let (edit, row, cursorColumn) = editableSelection() else { return false }
        let applicationCursor = terminalInputStateSnapshot()?.applicationCursor ?? false
        selectNone()
        send(data: edit.keystrokes(cursorColumn: cursorColumn, in: row, applicationCursor: applicationCursor, replacement: replacement)[...])
        return true
    }

    @objc func cut(_ sender: Any?) {
        copy(sender as Any)
        _ = replaceSelection(with: "")
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(cut(_:)) {
            return editableSelection() != nil
        }
        return super.validateUserInterfaceItem(item)
    }

    private func editableSelection() -> (SelectionEdit, SelectionEdit.Row, Int)? {
        guard selectionActive, let selected = getSelection(), let mouseDownCell else { return nil }
        let state = terminalStateSnapshot()
        guard mouseDownCell.row == state.cursor.row else { return nil }
        guard let line = state.visibleRows.first(where: { $0.row == state.cursor.row }) else { return nil }
        let characters = line.text.map(String.init)
        let widths = line.cellWidths.filter { $0 > 0 }
        guard characters.count <= widths.count else { return nil }
        let row = SelectionEdit.Row(characters: characters, cellWidths: Array(widths.prefix(characters.count)))
        guard let edit = SelectionEdit(selected: selected, in: row, hintColumn: mouseDownCell.column) else { return nil }
        return (edit, row, state.cursor.col)
    }
}

/// Backspace, Delete or typing over a selection in the line being typed edits it, as in a text field.
enum SelectionEditing {
    private static let deleteKeys: Set<UInt16> = [51, 117]
    /// AppKit's private-use range for arrows, F-keys and the like.
    private static let functionKeys: ClosedRange<UInt32> = 0xF700...0xF8FF

    static func install() {
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let view = NSApp.keyWindow?.firstResponder as? HarborTerminalView, view.selectionActive,
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return event }
            if deleteKeys.contains(event.keyCode) {
                return view.replaceSelection(with: "") ? nil : event
            }
            guard let typed = event.characters, !typed.isEmpty,
                  typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !functionKeys.contains($0.value) })
            else { return event }
            return view.replaceSelection(with: typed) ? nil : event
        }
    }
}

extension TerminalView {
    private static let scrollbackLines = 10_000

    /// A terminal view set up the way every Harbor terminal looks and behaves.
    static func harbor(fontSize: CGFloat) -> TerminalView {
        let view = HarborTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            font: Theme.terminalFont(size: fontSize),
            options: TerminalOptions(scrollback: scrollbackLines)
        )
        view.optionAsMetaKey = false
        view.nativeBackgroundColor = Theme.terminalBackground
        view.nativeForegroundColor = Theme.terminalForeground
        view.caretColor = Theme.caret
        view.selectedTextBackgroundColor = Theme.selection
        view.installColors(Theme.ansiColors)
        return view
    }
}
