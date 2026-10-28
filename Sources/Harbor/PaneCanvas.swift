import AppKit
import HarborCore
import SwiftUI

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
            let frames = shown.frames(in: bounds)
            ZStack(alignment: .topLeading) {
                Color(nsColor: Theme.terminalBackground)
                ForEach(shown.sessionIDs, id: \.self) { id in
                    if let frame = frames[id], let controller = model.controllers[id] {
                        PaneView(controller: controller, isSingle: isSingle)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                ForEach(shown.splitAreas(in: bounds), id: \.path) { area in
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

    private var isFocused: Bool { model.selectedID == controller.id }

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

    private func ratio(at location: CGPoint) -> Double {
        let ratio = area.axis == .horizontal
            ? (location.x - area.bounds.minX) / max(area.bounds.width, 1)
            : (location.y - area.bounds.minY) / max(area.bounds.height, 1)
        return min(max(ratio, PaneLayout.ratioRange.lowerBound), PaneLayout.ratioRange.upperBound)
    }
}

extension PaneCanvas {
    static let coordinateSpace = "paneCanvas"
}
