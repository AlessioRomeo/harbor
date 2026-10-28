import AppKit
import HarborCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
                .toolbar(removing: .sidebarToggle)
                .overlay(alignment: .topTrailing) {
                    SidebarToggle()
                        .padding(.trailing, 10)
                }
        } detail: {
            DetailView()
                .overlay(alignment: .topLeading) {
                    if model.isSidebarHidden {
                        SidebarToggle()
                            .padding(.leading, model.isFullScreen ? 10 : 78)
                    }
                }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background(WindowStyler { model.isFullScreen = $0 })
        .focusedSceneValue(\.archivableSession, model.selectedController?.id)
        .sheet(isPresented: $model.isSwitcherOpen) {
            QuickSwitcher()
        }
        .confirmationDialog(
            archiveQuestion,
            isPresented: Binding(
                get: { !model.archiveNeedingConfirmation.isEmpty },
                set: { if !$0 { model.archiveNeedingConfirmation = [] } }
            )
        ) {
            Button("Archive") { model.archive(model.archiveNeedingConfirmation) }
        } message: {
            Text("Something is still running there. Archiving ends it; the output is kept.")
        }
        .confirmationDialog(
            deletionQuestion,
            isPresented: Binding(
                get: { !model.deletionNeedingConfirmation.isEmpty },
                set: { if !$0 { model.deletionNeedingConfirmation = [] } }
            )
        ) {
            Button("Delete", role: .destructive) { model.deletePermanently(model.deletionNeedingConfirmation) }
        } message: {
            Text("Names and saved output go too, and anything still running ends. This can't be undone.")
        }
    }
}

extension ContentView {
    private var archiveQuestion: String {
        let ids = model.archiveNeedingConfirmation
        return ids.count == 1 ? "Archive “\(ids.first.flatMap { model.workspace.session($0)?.name } ?? "")”?" : "Archive \(ids.count) sessions?"
    }

    private var deletionQuestion: String {
        let ids = model.deletionNeedingConfirmation
        return ids.count == 1 ? "Delete “\(ids.first.flatMap { model.workspace.session($0)?.name } ?? "")” for good?" : "Delete \(ids.count) sessions for good?"
    }
}

/// Shows or hides the sidebar, level with the window's close, minimise and zoom buttons.
private struct SidebarToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13))
                .frame(width: 24, height: PaneCanvas.titleBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(model.isSidebarHidden ? "Show sidebar (⌃⌘S)" : "Hide sidebar (⌃⌘S)")
        .ignoresSafeArea()
    }
}

private struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: Theme.terminalBackground).ignoresSafeArea()
            if let error = model.storageError {
                MessageView(title: "Harbor can't use its sessions file", message: error)
            } else if let session = model.selectedID.flatMap({ model.workspace.session($0) }), session.isArchived {
                ArchivedSessionView(session: session)
            } else if let layout = model.workspace.layout {
                PaneCanvas(layout: layout)
            } else {
                MessageView(title: "No session selected", message: "Pick one in the sidebar, or press ⌘T for a new one.")
            }
            if case .failed(let message) = model.host.state {
                NoticeCard(
                    icon: "bolt.horizontal.circle",
                    title: "Sessions are out of reach",
                    detail: message,
                    actionTitle: "Reconnect",
                    actionKey: "r",
                    action: model.reconnect
                )
            }
        }
    }
}

struct ConnectionNotice: View {
    let controller: TerminalController

    var body: some View {
        switch controller.connection {
        case .ended:
            HintPill(text: "Shell ended", key: "⏎", keyMeaning: "new shell")
        case .lost(let message):
            NoticeCard(icon: "exclamationmark.triangle", title: "This session lost its connection", detail: message)
        case .detached, .attached:
            EmptyView()
        }
    }
}

/// A quiet one-line hint, such as which key does what.
private struct HintPill: View {
    let text: String
    let key: String
    let keyMeaning: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
            Text("·").foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                Text(key)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Text(keyMeaning)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 24)
    }
}

/// Something that needs attention, with an optional way to fix it.
private struct NoticeCard: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String?
    var actionKey: KeyEquivalent?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
                    .keyboardShortcut(actionKey.map { KeyboardShortcut($0) })
                    .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06)))
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

struct MessageView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title3.weight(.medium))
            Text(message)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 440)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// In full screen macOS paints the title bar area with the window's background colour, which
/// would otherwise be a grey band above the terminal. It also tells the model when the window
/// is in full screen, where there's no title bar to keep clear of.
private struct WindowStyler: NSViewRepresentable {
    let onFullScreenChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        StylingView(onFullScreenChange: onFullScreenChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class StylingView: NSView {
        private let onFullScreenChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onFullScreenChange: @escaping (Bool) -> Void) {
            self.onFullScreenChange = onFullScreenChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.backgroundColor = Theme.terminalBackground
            window.titlebarAppearsTransparent = true
            DispatchQueue.main.async { [weak self] in self?.reportFullScreen() }
            let changes = [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didResizeNotification]
            for name in changes {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportFullScreen() }
                })
            }
        }

        private func reportFullScreen() {
            guard let window else { return }
            onFullScreenChange(window.styleMask.contains(.fullScreen))
        }
    }
}
