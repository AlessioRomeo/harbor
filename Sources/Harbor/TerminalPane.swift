import AppKit
import SwiftTerm
import SwiftUI

/// Shows a session's terminal view, reusing it across SwiftUI updates so scrollback and selection survive.
struct TerminalPane: NSViewRepresentable {
    let controller: TerminalController
    /// nil while something else, such as a name being edited, should keep the keyboard.
    var focusRequest: Int?
    var topInset: CGFloat = 0

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.topInset = topInset
        container.show(controller.view)
        if let focusRequest {
            container.focus(request: focusRequest)
        }
    }
}

final class TerminalContainerView: NSView {
    var topInset: CGFloat = 0 {
        didSet { needsLayout = true }
    }
    /// Off for read-only output, so keys like Return reach the window's buttons.
    var takesFocus = true
    private var terminalView: TerminalView?
    private var handledFocusRequest: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.terminalBackground.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ view: TerminalView) {
        guard view !== terminalView else { return }
        terminalView?.removeFromSuperview()
        terminalView = view
        addSubview(view)
        needsLayout = true
        focusTerminal()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusTerminal()
    }

    func focus(request: Int) {
        guard request != handledFocusRequest else { return }
        handledFocusRequest = request
        DispatchQueue.main.async { [weak self] in self?.focusTerminal() }
    }

    private func focusTerminal() {
        guard takesFocus, let window, let terminalView else { return }
        window.makeFirstResponder(terminalView)
    }

    override func layout() {
        super.layout()
        let padding = Theme.terminalPadding
        terminalView?.frame = NSRect(
            x: padding,
            y: padding,
            width: max(0, bounds.width - padding * 2),
            height: max(0, bounds.height - padding * 2 - topInset)
        )
    }
}
