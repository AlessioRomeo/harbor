import HarborCore
import SwiftUI

/// ⌘F: type part of a name, pick with the arrows and Return.
struct QuickSwitcher: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFieldFocused: Bool

    private var results: [SearchResult] {
        Array(model.workspace.search(query).prefix(50))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find a session", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)
                    .onSubmit(open)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.session.id) { index, result in
                            ResultRow(result: result, isHighlighted: index == highlighted)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    highlighted = index
                                    open()
                                }
                        }
                        if results.isEmpty {
                            Text("No session matches")
                                .foregroundStyle(.secondary)
                                .padding(24)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: highlighted) { _, index in
                    if results.indices.contains(index) {
                        proxy.scrollTo(results[index].session.id)
                    }
                }
            }
        }
        .frame(width: 520, height: 380)
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { highlighted = 0 }
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(results.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onExitCommand { dismiss() }
    }

    private func open() {
        guard results.indices.contains(highlighted) else { return }
        model.selectedID = results[highlighted].session.id
        dismiss()
    }
}

private struct ResultRow: View {
    @Environment(AppModel.self) private var model
    let result: SearchResult
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(result.session.name)
                .lineLimit(1)
                .foregroundStyle(result.session.isArchived ? .secondary : .primary)
            if let groupName = result.groupName {
                Text(groupName)
                    .font(.callout)
                    .foregroundStyle(Theme.quietIndicator)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if result.session.isArchived {
                Image(systemName: "archivebox")
                    .foregroundStyle(Theme.quietIndicator)
                    .help("Archived")
            } else {
                StatusIndicator(indicator: model.indicator(of: result.session.id))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHighlighted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}
