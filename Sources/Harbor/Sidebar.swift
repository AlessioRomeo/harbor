import HarborCore
import SwiftUI
import UniformTypeIdentifiers

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isShowingArchive {
                ArchiveList()
            } else {
                sessionList
            }
        }
        .contentMargins(.top, model.isFullScreen ? PaneCanvas.titleBarHeight : 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) { SidebarFooter() }
    }

    private var sessionList: some View {
        @Bindable var model = model
        return List(selection: $model.sidebarSelection) {
            ForEach(model.workspace.groups) { group in
                Section {
                    GroupHeader(group: group)
                        .selectionDisabled()
                    let isCollapsed = model.collapsedGroups.contains(group.id)
                    if !isCollapsed, model.workspace.liveSessions(in: group.id).isEmpty {
                        EmptyGroupRow(groupID: group.id)
                    }
                    ForEach(isCollapsed ? [] : model.workspace.liveSessions(in: group.id)) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .itemProvider {
                                model.draggedSession = session.id
                                return SessionDrag.provider(for: session.id)
                            }
                            .contextMenu { SessionMenu(session: session) }
                    }
                    .onMove { model.moveSessions(in: group.id, from: $0, to: $1) }
                    .onInsert(of: [SessionDrag.type]) { index, providers in
                        SessionDrag.load(providers) { model.moveSession($0, to: group.id, at: index) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, SidebarMetrics.rowHeight)
    }
}

/// Rows sit 32 pt tall with the name inset evenly; group titles get room above and below.
private enum SidebarMetrics {
    static let rowHeight: CGFloat = 32
    static let rowInset = EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
    static let headerInset = EdgeInsets(top: 16, leading: 6, bottom: 6, trailing: 4)
    /// Group titles start with the fold arrow, which takes the place of the leading inset.
    static let groupHeaderInset = EdgeInsets(top: 16, leading: 0, bottom: 6, trailing: 4)
}

private struct GroupHeader: View {
    @Environment(AppModel.self) private var model
    let group: SessionGroup
    @State private var isHovered = false

    var body: some View {
        let isCollapsed = model.collapsedGroups.contains(group.id)
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { model.toggleCollapsed(group.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.quietIndicator)
            .help(isCollapsed ? "Show \(group.name)'s sessions" : "Fold \(group.name) away")
            RenamableText(id: group.id, name: group.name)
                .textCase(.uppercase)
                .tracking(0.6)
                .contentShape(Rectangle())
                .onTapGesture { model.showGroupAsGrid(group.id) }
                .help("Show \(group.name)'s sessions side by side")
            if isCollapsed, model.groupNeedsAttention(group.id) {
                Circle()
                    .fill(Theme.attention)
                    .frame(width: 7, height: 7)
                    .help("A session in \(group.name) needs you")
            }
            Spacer(minLength: 4)
            Button {
                model.newSession(in: group.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.quietIndicator)
            .opacity(isHovered ? 1 : 0)
            .help("New session in \(group.name)")
        }
        .font(.caption.weight(.semibold))
        .padding(SidebarMetrics.groupHeaderInset)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { model.toggleCollapsed(group.id) }
        }
        .contextMenu {
            Button("New Session") { model.newSession(in: group.id) }
            Button("Show as Grid") { model.showGroupAsGrid(group.id) }
                .disabled(model.workspace.liveSessions(in: group.id).isEmpty)
            Button("Rename…") { model.editingID = group.id }
            Divider()
            Button("Move Up") { model.moveGroup(group.id, by: -1) }
                .disabled(model.workspace.groups.first?.id == group.id)
            Button("Move Down") { model.moveGroup(group.id, by: 1) }
                .disabled(model.workspace.groups.last?.id == group.id)
            Divider()
            Button("Delete Group") { model.deleteGroup(group.id) }
                .disabled(group.id == Workspace.generalGroupID || !model.workspace.liveSessions(in: group.id).isEmpty)
        }
    }
}

/// Stands in for the sessions of an empty group, so the group reads as a group.
private struct EmptyGroupRow: View {
    @Environment(AppModel.self) private var model
    let groupID: UUID

    var body: some View {
        Button {
            model.newSession(in: groupID)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("New session")
            }
            .font(.callout)
            .foregroundStyle(Theme.quietIndicator)
        }
        .buttonStyle(.plain)
        .padding(SidebarMetrics.rowInset)
        .selectionDisabled()
    }
}

private struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        HStack(spacing: 10) {
            RenamableText(id: session.id, name: session.name)
            Spacer(minLength: 4)
            StatusIndicator(indicator: model.indicator(of: session.id))
        }
        .padding(SidebarMetrics.rowInset)
    }
}

private struct SessionMenu: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        let targets = model.targets(of: session.id)
        if targets.count == 1 {
            Button("Rename…") { model.editingID = session.id }
        }
        Menu(targets.count == 1 ? "Move to" : "Move \(targets.count) Sessions to") {
            ForEach(model.workspace.groups) { group in
                Button(group.name) { model.moveSessions(targets, to: group.id) }
                    .disabled(targets.allSatisfy { model.workspace.session($0)?.groupID == group.id })
            }
        }
        Divider()
        Button(targets.count == 1 ? "Archive" : "Archive \(targets.count) Sessions") { model.requestArchive(targets) }
        Button(targets.count == 1 ? "Delete Permanently…" : "Delete \(targets.count) Sessions Permanently…") {
            model.deletionNeedingConfirmation = targets
        }
    }
}

private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Button {
                model.newSession()
            } label: {
                Label("New Session", systemImage: "plus")
            }
            .help("New session in General")
            .opacity(model.isShowingArchive ? 0 : 1)
            .disabled(model.isShowingArchive)
            Spacer()
            let archived = model.workspace.archivedSessions.count
            if archived > 0 || model.isShowingArchive {
                Button {
                    model.isShowingArchive.toggle()
                } label: {
                    Image(systemName: model.isShowingArchive ? "archivebox.fill" : "archivebox")
                }
                .help(model.isShowingArchive ? "Back to sessions" : "Archived sessions")
            }
            Button {
                model.newGroup()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New group (⇧⌘N)")
            .opacity(model.isShowingArchive ? 0 : 1)
            .disabled(model.isShowingArchive)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Old sessions, out of the way but a click from coming back.
private struct ArchiveList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Section {
                ForEach(model.workspace.archivedSessions) { session in
                    HStack(spacing: 10) {
                        Text(session.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let archivedAt = session.archivedAt {
                            Text(archivedAt, format: .relative(presentation: .named, unitsStyle: .narrow))
                                .font(.caption)
                                .foregroundStyle(Theme.quietIndicator)
                        }
                    }
                    .padding(SidebarMetrics.rowInset)
                    .tag(session.id)
                    .contextMenu {
                        let targets = model.targets(of: session.id)
                        Button(targets.count == 1 ? "Restore" : "Restore \(targets.count) Sessions") { model.restore(targets) }
                        Divider()
                        Button(targets.count == 1 ? "Delete Permanently…" : "Delete \(targets.count) Sessions Permanently…") {
                            model.deletionNeedingConfirmation = targets
                        }
                    }
                }
                if model.workspace.archivedSessions.isEmpty {
                    Text("Nothing archived")
                        .foregroundStyle(Theme.quietIndicator)
                        .selectionDisabled()
                }
            } header: {
                Button {
                    model.isShowingArchive = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Archived")
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .padding(SidebarMetrics.headerInset)
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, SidebarMetrics.rowHeight)
    }
}

/// A name that is renamed in a small popover while `model.editingID` points at it.
private struct RenamableText: View {
    @Environment(AppModel.self) private var model
    let id: UUID
    let name: String

    var body: some View {
        Text(name)
            .lineLimit(1)
            .popover(isPresented: isEditing, arrowEdge: .trailing) {
                RenamePopover(name: name) { model.rename(id, to: $0) }
            }
    }

    private var isEditing: Binding<Bool> {
        Binding(
            get: { model.editingID == id },
            set: { if !$0, model.editingID == id { model.editingID = nil } }
        )
    }
}

private struct RenamePopover: View {
    let name: String
    let onSave: (String) -> Void

    var body: some View {
        NameField(initialText: name, onSubmit: onSave)
            .frame(width: 220)
            .padding(12)
    }
}

/// A text field that takes the keyboard as soon as its popover opens. A SwiftUI field doesn't
/// reliably do that while a terminal in the main window holds the keyboard.
private struct NameField: NSViewRepresentable {
    let initialText: String
    let onSubmit: (String) -> Void

    func makeNSView(context: Context) -> FocusingTextField {
        let field = FocusingTextField(string: initialText)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    func updateNSView(_ field: FocusingTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSubmit: onSubmit)
    }

    final class Coordinator: NSObject {
        var onSubmit: (String) -> Void

        init(onSubmit: @escaping (String) -> Void) {
            self.onSubmit = onSubmit
        }

        @objc func submit(_ sender: NSTextField) {
            onSubmit(sender.stringValue)
        }
    }

    final class FocusingTextField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                window.makeKey()
                window.makeFirstResponder(self)
                self.currentEditor()?.selectAll(nil)
            }
        }
    }
}
