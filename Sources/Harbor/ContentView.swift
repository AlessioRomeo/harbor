import HarborCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
        } detail: {
            DetailView()
        }
        .frame(minWidth: 720, minHeight: 420)
        .focusedSceneValue(\.archivableSession, model.selectedController?.id)
        .sheet(isPresented: $model.isSwitcherOpen) {
            QuickSwitcher()
        }
        .confirmationDialog(
            "Archive “\(model.archiveNeedingConfirmation.flatMap { model.workspace.session($0)?.name } ?? "")”?",
            isPresented: Binding(
                get: { model.archiveNeedingConfirmation != nil },
                set: { if !$0 { model.archiveNeedingConfirmation = nil } }
            )
        ) {
            Button("Archive") {
                if let id = model.archiveNeedingConfirmation { model.archive(id) }
            }
        } message: {
            Text("Something is still running in it. Archiving ends it; the output is kept.")
        }
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
            } else if let controller = model.selectedController {
                TerminalPane(controller: controller, focusRequest: model.editingID == nil ? model.terminalFocusRequest : nil, topInset: 22)
                    .ignoresSafeArea()
                if model.host.state == .connected {
                    ConnectionNotice(controller: controller)
                }
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

private struct ConnectionNotice: View {
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
