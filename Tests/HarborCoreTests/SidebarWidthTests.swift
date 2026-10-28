import Testing
@testable import HarborCore

struct SidebarWidthTests {
    @Test func readsTheWidthTheSplitViewSaved() {
        let frames = ["0.000000, 0.000000, 200.500000, 734.000000, NO, NO", "0.000000, 0.000000, 1058.000000, 734.000000, NO, NO"]
        #expect(SidebarWidth.fromSavedSplitViewFrames(frames) == 200.5)
    }

    @Test func ignoresACollapsedOrMalformedSave() {
        #expect(SidebarWidth.fromSavedSplitViewFrames(["0.000000, 0.000000, 0.000000, 734.000000, YES, NO"]) == nil)
        #expect(SidebarWidth.fromSavedSplitViewFrames(["0, 0, wide, 734, NO, NO"]) == nil)
        #expect(SidebarWidth.fromSavedSplitViewFrames(["0, 0, 250"]) == nil)
        #expect(SidebarWidth.fromSavedSplitViewFrames([]) == nil)
    }

    @Test func keepsTheWidthInRange() {
        #expect(SidebarWidth.clamped(140) == 200)
        #expect(SidebarWidth.clamped(280) == 280)
        #expect(SidebarWidth.clamped(900) == 360)
    }
}
