import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

struct PaneLayoutTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    /// a | b over c | d
    private var twoByTwo: PaneLayout {
        .split(
            .vertical, ratio: 0.5,
            first: .split(.horizontal, ratio: 0.5, first: .pane(a), second: .pane(b)),
            second: .split(.horizontal, ratio: 0.5, first: .pane(c), second: .pane(d))
        )
    }

    @Test func splitsOnEachEdge() {
        #expect(PaneLayout.pane(a).splitting(a, with: b, at: .right) == .split(.horizontal, ratio: 0.5, first: .pane(a), second: .pane(b)))
        #expect(PaneLayout.pane(a).splitting(a, with: b, at: .left) == .split(.horizontal, ratio: 0.5, first: .pane(b), second: .pane(a)))
        #expect(PaneLayout.pane(a).splitting(a, with: b, at: .top) == .split(.vertical, ratio: 0.5, first: .pane(b), second: .pane(a)))
        #expect(PaneLayout.pane(a).splitting(a, with: b, at: .bottom) == .split(.vertical, ratio: 0.5, first: .pane(a), second: .pane(b)))
    }

    @Test func removingCollapsesToTheSibling() {
        #expect(twoByTwo.removing(a)?.sessionIDs == [b, c, d])
        #expect(PaneLayout.split(.horizontal, ratio: 0.3, first: .pane(a), second: .pane(b)).removing(a) == .pane(b))
        #expect(PaneLayout.pane(a).removing(a) == nil)
        #expect(twoByTwo.removing(e) == twoByTwo)
    }

    @Test func replacingSwapsWhenAlreadyOnScreen() {
        let pair = PaneLayout.split(.horizontal, ratio: 0.5, first: .pane(a), second: .pane(b))
        #expect(pair.replacing(a, with: c).sessionIDs == [c, b])
        #expect(pair.replacing(a, with: b).sessionIDs == [b, a])
        #expect(pair.replacing(a, with: a) == pair)
    }

    @Test func placingMovesAPaneWithoutLosingAnything() {
        let moved = twoByTwo.placing(a, at: .edge(.bottom), of: d)
        #expect(Set(moved.sessionIDs) == [a, b, c, d])
        #expect(moved.neighbour(of: d, toward: .bottom) == a)

        let fromOffScreen = twoByTwo.placing(e, at: .edge(.left), of: a)
        #expect(fromOffScreen.sessionIDs.count == 5)
        #expect(fromOffScreen.neighbour(of: a, toward: .left) == e)

        #expect(twoByTwo.placing(a, at: .edge(.right), of: a) == twoByTwo)
        let pair = PaneLayout.split(.horizontal, ratio: 0.5, first: .pane(a), second: .pane(b))
        #expect(pair.placing(a, at: .edge(.right), of: b).sessionIDs == [b, a])
    }

    @Test func placingAPaneOnTheSideItAlreadyHoldsChangesNothing() {
        #expect(twoByTwo.placing(b, at: .edge(.right), of: a) == twoByTwo)
        #expect(twoByTwo.placing(c, at: .edge(.left), of: d) == twoByTwo)
        #expect(twoByTwo.placing(b, at: .edge(.left), of: a) != twoByTwo)
    }

    @Test func findsNeighboursInAGrid() {
        #expect(twoByTwo.neighbour(of: a, toward: .right) == b)
        #expect(twoByTwo.neighbour(of: a, toward: .bottom) == c)
        #expect(twoByTwo.neighbour(of: d, toward: .top) == b)
        #expect(twoByTwo.neighbour(of: a, toward: .left) == nil)
    }

    @Test func findsNeighboursInAnUnevenTree() {
        // a on the left; b over c on the right, b taking most of the height
        let layout = PaneLayout.split(
            .horizontal, ratio: 0.5,
            first: .pane(a),
            second: .split(.vertical, ratio: 0.8, first: .pane(b), second: .pane(c))
        )
        #expect(layout.neighbour(of: a, toward: .right) == b)
        #expect(layout.neighbour(of: c, toward: .left) == a)
        #expect(layout.neighbour(of: b, toward: .bottom) == c)
    }

    @Test func buildsEvenGrids() {
        func shape(_ count: Int) -> [Int] {
            let ids = (0..<count).map { _ in UUID() }
            guard let grid = PaneLayout.grid(ids) else { return [] }
            #expect(grid.sessionIDs == ids)
            let frames = grid.frames(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let rows = Dictionary(grouping: ids) { (frames[$0]!.minY * 1000).rounded() }
            return rows.keys.sorted().map { rows[$0]!.count }
        }
        #expect(PaneLayout.grid([]) == nil)
        #expect(shape(1) == [1])
        #expect(shape(2) == [1, 1])
        #expect(shape(3) == [2, 1])
        #expect(shape(4) == [2, 2])
        #expect(shape(5) == [2, 2, 1])
        #expect(shape(6) == [2, 2, 2])
        #expect(shape(7) == [3, 3, 1])
    }

    @Test func wideAreasGetMoreColumns() {
        func rows(_ count: Int, aspect: Double) -> Int {
            let ids = (0..<count).map { _ in UUID() }
            let frames = PaneLayout.grid(ids, aspectRatio: aspect)!.frames(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Set(ids.map { (frames[$0]!.minY * 1000).rounded() }).count
        }
        #expect(rows(2, aspect: 1.6) == 1)
        #expect(rows(3, aspect: 2.2) == 1)
        #expect(rows(4, aspect: 1.6) == 2)
        #expect(rows(2, aspect: 0.8) == 2)
    }

    @Test func gridPanesShareARowEvenly() {
        let ids = [a, b, c]
        let frames = PaneLayout.grid(ids)!.frames(in: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(abs(frames[a]!.width - 150) < 0.001)
        #expect(abs(frames[b]!.width - 150) < 0.001)
        #expect(abs(frames[c]!.width - 300) < 0.001)
    }

    @Test func capsTheGrid() {
        let ids = (0..<20).map { _ in UUID() }
        #expect(PaneLayout.grid(ids)?.sessionIDs == Array(ids.prefix(PaneLayout.maxGridPanes)))
    }

    @Test func clampsRatiosAlongAPath() {
        let layout = twoByTwo.settingRatio(0.99, at: [true])
        guard case .split(_, let top, _, .split(_, let nested, _, _)) = layout else {
            Issue.record("unexpected shape")
            return
        }
        #expect(top == 0.5)
        #expect(nested == PaneLayout.ratioRange.upperBound)
    }

    @Test func evensOutByPaneCount() {
        let lopsided = PaneLayout.split(
            .horizontal, ratio: 0.8,
            first: .pane(a),
            second: .split(.horizontal, ratio: 0.2, first: .pane(b), second: .pane(c))
        )
        let frames = lopsided.evened.frames(in: CGRect(x: 0, y: 0, width: 300, height: 100))
        for id in [a, b, c] {
            #expect(abs(frames[id]!.width - 100) < 0.001)
        }
    }

    @Test func evenedRatiosSurvivePruning() {
        var long = PaneLayout.pane(a)
        var last = a
        for _ in 0..<11 {
            let next = UUID()
            long = long.splitting(last, with: next, at: .right)
            last = next
        }
        let row = long.sessionIDs.filter { $0 != a }
        let evened = long.evened
        let pruned = evened.pruned(keeping: Set([a] + row))
        #expect(pruned == evened)
        guard case .split(_, let ratio, _, _) = evened else { return }
        #expect(PaneLayout.ratioRange.contains(ratio))
    }

    @Test func prunesUnknownAndRepeatedPanes() {
        let messy = PaneLayout.split(
            .horizontal, ratio: 5,
            first: .split(.vertical, ratio: 0.5, first: .pane(a), second: .pane(e)),
            second: .split(.vertical, ratio: 0.5, first: .pane(b), second: .pane(a))
        )
        let pruned = messy.pruned(keeping: [a, b])
        #expect(pruned == .split(.horizontal, ratio: PaneLayout.ratioRange.upperBound, first: .pane(a), second: .pane(b)))
        #expect(messy.pruned(keeping: []) == nil)
    }

    @Test func describesEverySplitForItsDivider() {
        let areas = twoByTwo.splitAreas(in: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(areas.map(\.path) == [[], [false], [true]])
        #expect(areas[0].axis == .vertical)
        #expect(areas[0].dividerPosition == 50)
        #expect(areas[1].dividerPosition == 100)
        #expect(areas[2].bounds == CGRect(x: 0, y: 50, width: 200, height: 50))
        #expect(PaneLayout.pane(a).splitAreas(in: .zero).isEmpty)

        let nested = PaneLayout.split(.horizontal, ratio: 0.5, first: .pane(a), second: .split(.horizontal, ratio: 0.5, first: .pane(b), second: .pane(c)))
        let root = nested.splitAreas(in: CGRect(x: 0, y: 0, width: 300, height: 100))[0]
        #expect(root.firstPaneCount == 1)
        #expect(root.secondPaneCount == 2)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(twoByTwo)
        #expect(try JSONDecoder().decode(PaneLayout.self, from: data) == twoByTwo)
    }
}

struct PaneDropTests {
    private let size = CGSize(width: 400, height: 200)

    @Test func edgesWinNearTheBorder() {
        #expect(PaneDrop(at: CGPoint(x: 20, y: 100), in: size) == .edge(.left))
        #expect(PaneDrop(at: CGPoint(x: 390, y: 100), in: size) == .edge(.right))
        #expect(PaneDrop(at: CGPoint(x: 200, y: 10), in: size) == .edge(.top))
        #expect(PaneDrop(at: CGPoint(x: 200, y: 195), in: size) == .edge(.bottom))
        #expect(PaneDrop(at: CGPoint(x: 200, y: 100), in: size) == .center)
    }

    @Test func previewsTheHalfThatWouldBeTaken() {
        #expect(PaneDrop.edge(.left).previewRect(in: size) == CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(PaneDrop.edge(.bottom).previewRect(in: size) == CGRect(x: 0, y: 100, width: 400, height: 100))
        #expect(PaneDrop.center.previewRect(in: size) == CGRect(origin: .zero, size: size))
    }
}

struct WorkspaceLayoutTests {
    @Test func keepsOnlyLiveSessionsInTheLayout() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let a = try workspace.addSession(named: "a", to: group)
        let b = try workspace.addSession(named: "b", to: group)
        let c = try workspace.addSession(named: "c", to: group)
        workspace.setLayout(PaneLayout.grid([a, b, c, UUID()]))
        #expect(workspace.layout?.sessionIDs == [a, b, c])

        workspace.archive(b, at: Date())
        #expect(workspace.layout?.sessionIDs == [a, c])
        workspace.deleteSession(a)
        #expect(workspace.layout == .pane(c))
    }

    @Test func keepsTheFocusOnAPaneThatExists() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let a = try workspace.addSession(named: "a", to: group)
        let b = try workspace.addSession(named: "b", to: group)
        let c = try workspace.addSession(named: "c", to: group)
        workspace.setLayout(.split(.horizontal, ratio: 0.5, first: .pane(a), second: .pane(b)), focus: b)
        #expect(workspace.focusedPane == b)

        workspace.focusPane(c)
        #expect(workspace.focusedPane == b)

        workspace.setLayout(workspace.layout?.replacing(b, with: c), focus: c)
        #expect(workspace.focusedPane == c)

        workspace.archive(c, at: Date())
        #expect(workspace.layout == .pane(a))
        #expect(workspace.focusedPane == a)

        workspace.removeFromLayout(a)
        #expect(workspace.layout == nil)
        #expect(workspace.focusedPane == nil)
    }

    @Test func focusGoesToThePaneThatTakesTheSpace() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let a = try workspace.addSession(named: "a", to: group)
        let b = try workspace.addSession(named: "b", to: group)
        let c = try workspace.addSession(named: "c", to: group)
        let pair = PaneLayout.split(.horizontal, ratio: 0.5, first: .pane(a), second: .pane(b))
        workspace.setLayout(.split(.horizontal, ratio: 0.6, first: pair, second: .pane(c)), focus: b)
        workspace.removeFromLayout(b)
        #expect(workspace.focusedPane == a)
    }

    @Test func anExplicitFocusWinsOverTheCurrentOne() throws {
        var workspace = Workspace()
        let group = workspace.addGroup(named: "Me")
        let a = try workspace.addSession(named: "a", to: group)
        let b = try workspace.addSession(named: "b", to: group)
        let pair = PaneLayout.split(.horizontal, ratio: 0.5, first: .pane(a), second: .pane(b))
        workspace.setLayout(pair, focus: a)
        workspace.setLayout(pair, focus: b)
        #expect(workspace.focusedPane == b)
        workspace.setLayout(pair)
        #expect(workspace.focusedPane == b)
    }

    @Test func readsFilesWrittenBeforeLayouts() throws {
        let json = #"{"groups":[{"id":"2D4D1909-AA35-40B7-8655-DA028C46F0A7","name":"Me"}],"sessions":[]}"#
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
        #expect(workspace.layout == nil)
        #expect(workspace.groups.map(\.name) == ["Me"])
    }
}
