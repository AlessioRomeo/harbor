import HarborCore
import SwiftUI
import UniformTypeIdentifiers

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedID) {
            ForEach(model.workspace.groups) { group in
                Section {
                    if model.workspace.liveSessions(in: group.id).isEmpty {
                        EmptyGroupRow(groupID: group.id)
                    }
                    ForEach(model.workspace.liveSessions(in: group.id)) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .itemProvider { NSItemProvider(object: session.id.uuidString as NSString) }
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
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    model.newGroup()
                } label: {
                    Label("New Group", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
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
            StatusIndicator(status: model.state(of: session.id))
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
    }
}

/// A name that turns into a text field while `model.editingID` points at it.
private struct RenamableText: View {
    @Environment(AppModel.self) private var model
    let id: UUID
    let name: String
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if model.editingID == id {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onAppear {
                    draft = name
                    DispatchQueue.main.async { isFocused = true }
                }
                .onSubmit { model.rename(id, to: draft) }
                .onChange(of: isFocused) { _, focused in
                    if !focused, model.editingID == id {
                        model.rename(id, to: draft)
                    }
                }
                .onExitCommand { model.editingID = nil }
        } else {
            Text(name).lineLimit(1)
        }
    }
}
