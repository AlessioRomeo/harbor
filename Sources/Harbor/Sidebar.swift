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
        .safeAreaInset(edge: .bottom) { SidebarFooter() }
    }

    private var sessionList: some View {
        @Bindable var model = model
        return List(selection: $model.selectedID) {
            ForEach(model.workspace.groups) { group in
                Section {
                    if model.workspace.liveSessions(in: group.id).isEmpty {
                        EmptyGroupRow(groupID: group.id)
                    }
                    ForEach(model.workspace.liveSessions(in: group.id)) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .itemProvider {
                                model.draggedSession = session.id
                                return NSItemProvider(object: session.id.uuidString as NSString)
                            }
                            .contextMenu { SessionMenu(session: session) }
                    }
                    .onMove { model.moveSessions(in: group.id, from: $0, to: $1) }
                    .onInsert(of: [.plainText]) { index, providers in
                        receive(providers, into: group.id, at: index)
                    }
                } header: {
                    GroupHeader(group: group)
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 40)
    }

    private func receive(_ providers: [NSItemProvider], into groupID: UUID, at index: Int) {
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String, let id = UUID(uuidString: text) else { return }
                DispatchQueue.main.async { model.moveSession(id, to: groupID, at: index) }
            }
        }
    }
}

private struct GroupHeader: View {
    @Environment(AppModel.self) private var model
    let group: SessionGroup

    var body: some View {
        RenamableText(id: group.id, name: group.name)
            .font(.subheadline.weight(.semibold))
            .padding(.top, 10)
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
                    .disabled(!model.workspace.liveSessions(in: group.id).isEmpty)
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
        .padding(.vertical, 6)
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
        .padding(.vertical, 7)
    }
}

private struct SessionMenu: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        Button("Rename…") { model.editingID = session.id }
        Menu("Move to") {
            ForEach(model.workspace.groups) { group in
                Button(group.name) { model.moveSession(session.id, to: group.id) }
                    .disabled(group.id == session.groupID)
            }
        }
        Divider()
        Button("Archive") { model.requestArchive(session.id) }
    }
}

private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Button {
                model.newGroup()
            } label: {
                Label("New Group", systemImage: "folder.badge.plus")
            }
            .opacity(model.isShowingArchive ? 0 : 1)
            Spacer()
            let archived = model.workspace.archivedSessions.count
            if archived > 0 || model.isShowingArchive {
                Button {
                    model.isShowingArchive.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.isShowingArchive ? "archivebox.fill" : "archivebox")
                        if archived > 0 {
                            Text("\(archived)").monospacedDigit()
                        }
                    }
                }
                .help(model.isShowingArchive ? "Back to sessions" : "Archived sessions")
            }
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
    @State private var sessionToDelete: Session?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedID) {
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
                    .padding(.vertical, 7)
                    .tag(session.id)
                    .contextMenu {
                        Button("Restore") { model.restore(session.id) }
                        Divider()
                        Button("Delete Permanently…") { sessionToDelete = session }
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
                .padding(.top, 10)
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 40)
        .confirmationDialog(
            "Delete “\(sessionToDelete?.name ?? "")” for good?",
            isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let sessionToDelete { model.deletePermanently(sessionToDelete.id) }
            }
        } message: {
            Text("Its name and saved output go too. This can't be undone.")
        }
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
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name", text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
            .focused($isFocused)
            .onSubmit { onSave(draft) }
            .padding(12)
            .onAppear {
                draft = name
                DispatchQueue.main.async { isFocused = true }
            }
    }
}
