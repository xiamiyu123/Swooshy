import Testing
@testable import Swooshy

struct WindowActionTests {
    @Test
    func areaPreviewAppliesToLayoutActionsThatResizeToTargetFrames() {
        #expect(WindowAction.leftHalf.supportsSnapPreview)
        #expect(WindowAction.rightHalf.supportsSnapPreview)
        #expect(WindowAction.maximize.supportsSnapPreview)
        #expect(WindowAction.center.supportsSnapPreview)
        #expect(WindowAction.topLeftQuarter.supportsSnapPreview)
        #expect(WindowAction.topRightQuarter.supportsSnapPreview)
        #expect(WindowAction.bottomLeftQuarter.supportsSnapPreview)
        #expect(WindowAction.bottomRightQuarter.supportsSnapPreview)

        for action in WindowAction.allCases where
            action != .leftHalf &&
            action != .rightHalf &&
            action != .maximize &&
            action != .center &&
            action != .topLeftQuarter &&
            action != .topRightQuarter &&
            action != .bottomLeftQuarter &&
            action != .bottomRightQuarter
        {
            #expect(action.supportsSnapPreview == false)
        }

        #expect(WindowAction.exitFullScreen.supportsSnapPreview == false)
    }

    @Test
    func gestureCasesIncludeGestureOnlyActionsWithoutAffectingShortcutActions() {
        #expect(WindowAction.gestureCases.contains(.exitFullScreen))
        #expect(WindowAction.allCases.contains(.exitFullScreen) == false)
    }
}
