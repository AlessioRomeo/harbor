import AppKit
import HarborCore
import SwiftTerm
import SwiftUI

/// An archived session: its saved output, read-only, with a way back.
struct ArchivedSessionView: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        ZStack(alignment: .bottom) {
            if let output = model.savedOutput(of: session.id) {
                SavedOutputPane(output: output, fontSize: model.fontSize)
                    .id(session.id)
                    .ignoresSafeArea()
            } else {
                MessageView(title: session.name, message: "No output was saved for this session.")
            }
            HStack(spacing: 14) {
                Image(systemName: "archivebox")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.body.weight(.medium))
                    if let archivedAt = session.archivedAt {
                        Text("Archived \(archivedAt, format: .relative(presentation: .named))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Restore") { model.restore([session.id]) }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06)))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

private struct SavedOutputPane: NSViewRepresentable {
    let output: Data
    let fontSize: CGFloat

    func makeCoordinator() -> OutputFeeder {
        OutputFeeder(output: output)
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.topInset = 22
        container.takesFocus = false
        let view = TerminalView.harbor(fontSize: fontSize)
        view.terminalDelegate = context.coordinator
        container.show(view)
        return container
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {}
}

/// Feeds the saved output once the view has its real width, so lines wrap the way they were written.
/// Input goes nowhere: the session is archived.
final class OutputFeeder: NSObject, TerminalViewDelegate {
    private var output: Data?

    init(output: Data) {
        self.output = output
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard let output else { return }
        self.output = nil
        source.feed(byteArray: Array(output)[...])
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {}

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
