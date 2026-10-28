import AppKit
import HarborCore
import SwiftUI
import UniformTypeIdentifiers

/// The sessions on screen. Panes are placed from the layout's frames and keyed by session, so a
/// terminal keeps its view (and scrollback, selection) however the layout around it changes.
struct PaneCanvas: View {
    @Environment(AppModel.self) private var model
    let layout: PaneLayout
    /// Ratios being dragged right now; saved when the drag ends.
    @State private var liveRatios: [[Bool]: Double] = [:]

    private static let headerClearance: CGFloat = 28

    var body: some View {
        let isSingle = layout.sessionIDs.count == 1
        GeometryReader { geometry in
            let top = isSingle ? 0 : Self.headerClearance
            let bounds = CGRect(x: 0, y: top, width: geometry.size.width, height: max(0, geometry.size.height - top))
            let shown = liveRatios.reduce(layout) { $0.settingRatio($1.value, at: $1.key) }
            let zoomed = model.isZoomed ? model.workspace.focusedPane.flatMap { layout.contains($0) ? $0 : nil } : nil
            let frames = zoomed.map { [$0: bounds] } ?? shown.frames(in: bounds)
            ZStack(alignment: .topLeading) {
                Color(nsColor: Theme.terminalBackground)
                ForEach(shown.sessionIDs, id: \.self) { id in
                    if let frame = frames[id], let controller = model.controllers[id] {
                        PaneView(controller: controller, isSingle: isSingle, size: frame.size)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                ForEach(zoomed == nil ? shown.splitAreas(in: bounds) : [], id: \.path) { area in
                    DividerHandle(area: area) { ratio in
                        liveRatios[area.path] = ratio
                    } onEnd: { ratio in
                        liveRatios[area.path] = nil
                        model.setSplitRatio(ratio, at: area.path)
                    } onDoubleClick: {
                        model.evenOutPanes()
                    }
                }
            }
            .coordinateSpace(.named(Self.coordinateSpace))
        }
        .ignoresSafeArea()
    }
}

private struct PaneView: View {
    @Environment(AppModel.self) private var model
    let controller: TerminalController
    let isSingle: Bool
    let size: CGSize
    @State private var drop: PaneDrop?

    private var isFocused: Bool { model.selectedID == controller.id }
    private var needsAttention: Bool { model.indicator(of: controller.id).needsAttention }

    var body: some View {
        VStack(spacing: 0) {
            if !isSingle {
                PaneHeader(id: controller.id, isFocused: isFocused)
            }
            ZStack(alignment: .bottom) {
                TerminalPane(
                    controller: controller,
                    focusRequest: isFocused && model.editingID == nil ? model.terminalFocusRequest : nil,
                    topInset: isSingle ? 22 : 0
                )
                if model.host.state == .connected {
                    ConnectionNotice(controller: controller)
                }
            }
            .overlay {
                Color.black
                    .opacity(isSingle || isFocused ? 0 : 0.18)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
            }
        }
        .overlay {
            Rectangle()
                .strokeBorder(Theme.attention.opacity(needsAttention && !isFocused ? 0.65 : 0), lineWidth: 1.5)
                .shadow(color: Theme.attention.opacity(needsAttention && !isFocused ? 0.35 : 0), radius: 6)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: needsAttention)
        }
        .overlay(alignment: .topLeading) {
            if let drop {
                let rect = drop.previewRect(in: size).insetBy(dx: 6, dy: 6)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.12), value: drop)
            }
        }
        .onDrop(of: [.plainText], delegate: PaneDropDelegate(target: controller.id, size: size, drop: $drop, model: model))
    }
}

/// Sessions dragged from the sidebar or by a pane's header land beside this pane or in its place.
private struct PaneDropDelegate: DropDelegate {
    let target: UUID
    let size: CGSize
    @Binding var drop: PaneDrop?
    let model: AppModel

    func validateDrop(info: DropInfo) -> Bool {
        model.draggedSession != target
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard model.draggedSession != target else {
            drop = nil
            return DropProposal(operation: .forbidden)
        }
        drop = PaneDrop(at: info.location, in: size)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        drop = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let placement = PaneDrop(at: info.location, in: size)
        drop = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let target = target
        let model = model
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async { model.place(id, at: placement, of: target) }
        }
        return true
    }
}

private struct PaneHeader: View {
    @Environment(AppModel.self) private var model
    let id: UUID
    let isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(model.workspace.session(id)?.name ?? "")
                .font(.callout.weight(isFocused ? .semibold : .regular))
                .foregroundStyle(isFocused ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if model.isZoomed {
                Button {
                    model.toggleZoom()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Show all panes (⇧⌘↩)")
            }
            if isHovered {
                Button {
                    model.selectedID = id
                    model.closeFocusedPane()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Take off screen (⇧⌘W)")
            }
            StatusIndicator(indicator: model.indicator(of: id))
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Theme.paneHeader)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = id }
        .onHover { isHovered = $0 }
        .onDrag {
            model.draggedSession = id
            return NSItemProvider(object: id.uuidString as NSString)
        }
    }
}

/// A hairline between panes with a wider grip; drag to resize, double-click to even out.
private struct DividerHandle: View {
    let area: PaneLayout.SplitArea
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void
    let onDoubleClick: () -> Void

    private static let grip: CGFloat = 8

    var body: some View {
        let isHorizontal = area.axis == .horizontal
        let position = area.dividerPosition
        let rect = isHorizontal
            ? CGRect(x: position - Self.grip / 2, y: area.bounds.minY, width: Self.grip, height: area.bounds.height)
            : CGRect(x: area.bounds.minX, y: position - Self.grip / 2, width: area.bounds.width, height: Self.grip)
        ZStack {
            Color.clear.contentShape(Rectangle())
            Rectangle()
                .fill(Theme.divider)
                .frame(width: isHorizontal ? 1 : nil, height: isHorizontal ? nil : 1)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .onHover { inside in
            if inside {
                (isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture(count: 2, perform: onDoubleClick)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(PaneCanvas.coordinateSpace))
                .onChanged { onChange(ratio(at: $0.location)) }
                .onEnded { onEnd(ratio(at: $0.location)) }
        )
    }

    /// Room for about 24 columns, or a header and 6 rows, on each side of the divider.
    private static let minimumPaneWidth: CGFloat = 230
    private static let minimumPaneHeight: CGFloat = 150

    private func ratio(at location: CGPoint) -> Double {
        let isHorizontal = area.axis == .horizontal
        let length = isHorizontal ? area.bounds.width : area.bounds.height
        let offset = isHorizontal ? location.x - area.bounds.minX : location.y - area.bounds.minY
        let minimum = isHorizontal ? Self.minimumPaneWidth : Self.minimumPaneHeight
        guard length > minimum * 2 else { return area.ratio }
        return min(max(offset, minimum), length - minimum) / length
    }
}

extension PaneCanvas {
    static let coordinateSpace = "paneCanvas"
}
