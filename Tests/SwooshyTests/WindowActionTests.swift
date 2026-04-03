import Testing
@testable import Swooshy

struct WindowActionTests {
    @Test
    func allCasesRemainInExpectedUserVisibleOrder() {
        #expect(WindowAction.allCases == [
            .leftHalf,
            .rightHalf,
            .maximize,
            .center,
            .topLeftQuarter,
            .topRightQuarter,
            .bottomLeftQuarter,
            .bottomRightQuarter,
            .minimize,
            .closeWindow,
            .closeTab,
            .quitApplication,
            .cycleSameAppWindowsForward,
            .cycleSameAppWindowsBackward,
            .toggleFullScreen,
        ])
    }

    @Test
    func gestureCasesAppendExitFullScreenToAllCases() {
        #expect(WindowAction.gestureCases == WindowAction.allCases + [.exitFullScreen])
    }

    @Test
    func menuKeyEquivalentsRemainStableForShortcutActions() {
        #expect(WindowAction.leftHalf.menuKeyEquivalent == "1")
        #expect(WindowAction.rightHalf.menuKeyEquivalent == "2")
        #expect(WindowAction.maximize.menuKeyEquivalent == "3")
        #expect(WindowAction.center.menuKeyEquivalent == "4")
        #expect(WindowAction.minimize.menuKeyEquivalent == "5")
        #expect(WindowAction.closeWindow.menuKeyEquivalent == "6")
        #expect(WindowAction.quitApplication.menuKeyEquivalent == "7")
        #expect(WindowAction.cycleSameAppWindowsForward.menuKeyEquivalent == "8")
        #expect(WindowAction.cycleSameAppWindowsBackward.menuKeyEquivalent == "9")
        #expect(WindowAction.toggleFullScreen.menuKeyEquivalent == "0")
        #expect(WindowAction.closeTab.menuKeyEquivalent.isEmpty)
        #expect(WindowAction.exitFullScreen.menuKeyEquivalent.isEmpty)
    }

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
