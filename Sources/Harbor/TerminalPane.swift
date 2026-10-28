import AppKit
import SwiftTerm
import SwiftUI

/// Shows a session's terminal view, reusing it across SwiftUI updates so scrollback and selection survive.
struct TerminalPane: NSViewRepresentable {
    let controller: TerminalController
    var topInset: CGFloat = 0

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.topInset = topInset
        container.show(controller.view)
    }
}

final class TerminalContainerView: NSView {
    var topInset: CGFloat = 0 {
        didSet { needsLayout = true }
    }
    private var terminalView: TerminalView?

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

    private func focusTerminal() {
        guard let window, let terminalView else { return }
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
