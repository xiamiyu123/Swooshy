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
            .moveToNextDisplay,
            .moveToPreviousDisplay,
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
        let shortcuts: [WindowAction: String] = [
            .leftHalf: "1",
            .rightHalf: "2",
            .maximize: "3",
            .center: "4",
            .minimize: "5",
            .closeWindow: "6",
            .quitApplication: "7",
            .cycleSameAppWindowsForward: "8",
            .cycleSameAppWindowsBackward: "9",
            .toggleFullScreen: "0",
        ]
        let actionsWithoutShortcuts: [WindowAction] = [
            .closeTab,
            .exitFullScreen,
            .moveToNextDisplay,
            .moveToPreviousDisplay,
        ]

        #expect(shortcuts.allSatisfy { action, shortcut in action.menuKeyEquivalent == shortcut })
        #expect(actionsWithoutShortcuts.allSatisfy { $0.menuKeyEquivalent.isEmpty })
    }

    @Test
    func areaPreviewAppliesToLayoutActionsThatResizeToTargetFrames() {
        let previewActions: Set<WindowAction> = [
            .leftHalf,
            .rightHalf,
            .maximize,
            .center,
            .topLeftQuarter,
            .topRightQuarter,
            .bottomLeftQuarter,
            .bottomRightQuarter,
        ]

        #expect(Set(WindowAction.allCases.filter(\.supportsSnapPreview)) == previewActions)
        #expect(!WindowAction.exitFullScreen.supportsSnapPreview)
    }

    @Test
    func browserTabCloseReplacementOnlyAppliesToCloseAndQuitActions() {
        let replacementActions: Set<WindowAction> = [
            .closeWindow,
            .quitApplication,
        ]

        #expect(Set(WindowAction.gestureCases.filter(\.supportsBrowserTabCloseReplacement)) == replacementActions)
    }

    @Test
    func gestureCasesIncludeGestureOnlyActionsWithoutAffectingShortcutActions() {
        #expect(WindowAction.gestureCases.contains(.exitFullScreen))
        #expect(!WindowAction.allCases.contains(.exitFullScreen))
    }
}
