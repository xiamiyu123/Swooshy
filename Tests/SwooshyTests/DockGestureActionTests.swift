import Testing
@testable import Swooshy

struct DockGestureActionTests {
    @Test
    func dockGestureActionsRemainInExpectedUserVisibleOrder() {
        #expect(DockGestureAction.allCases == [
            .minimizeWindow,
            .restoreWindow,
            .moveWindowToNextDisplay,
            .moveWindowToPreviousDisplay,
            .cycleWindowsForward,
            .cycleWindowsBackward,
            .toggleFullScreenWindow,
            .exitFullScreenWindow,
            .closeWindow,
            .closeTab,
            .quitApplication,
        ])
    }

    @Test
    func dockGestureDefaultsMatchFallbackBindings() {
        #expect(DockGestureBindings.defaults.count == DockGestureKind.allCases.count)

        for binding in DockGestureBindings.defaults {
            #expect(DockGestureBindings.fallbackBinding(for: binding.gesture) == binding)
        }
    }

    @Test
    func dockGestureActionsIncludeDisplayMoveOptionsWithoutChangingDefaults() {
        #expect(DockGestureAction.allCases.contains(.moveWindowToNextDisplay))
        #expect(DockGestureAction.allCases.contains(.moveWindowToPreviousDisplay))
        #expect(DockGestureBindings.defaults.contains { $0.action == .moveWindowToNextDisplay } == false)
        #expect(DockGestureBindings.defaults.contains { $0.action == .moveWindowToPreviousDisplay } == false)
    }

    @Test
    func dockGestureDisplayMoveActionsReuseWindowActionTitles() {
        #expect(
            DockGestureAction.moveWindowToNextDisplay.title(localeIdentifier: "en") ==
                WindowAction.moveToNextDisplay.title(localeIdentifier: "en")
        )
        #expect(
            DockGestureAction.moveWindowToPreviousDisplay.title(localeIdentifier: "zh-Hans") ==
                WindowAction.moveToPreviousDisplay.title(localeIdentifier: "zh-Hans")
        )
    }

    @Test
    func titleBarGestureDefaultsMatchFallbackBindingsForSupportedGestures() {
        #expect(TitleBarGestureBindings.defaults.count == TitleBarGestureBindings.supportedGestures.count)

        for binding in TitleBarGestureBindings.defaults {
            #expect(TitleBarGestureBindings.fallbackBinding(for: binding.gesture) == binding)
        }
    }

    @Test
    func titleBarBindingReturnsNilForUnsupportedGestures() {
        let unsupportedGesture = DockGestureKind.allCases.first {
            TitleBarGestureBindings.supportedGestures.contains($0) == false
        }

        if let unsupportedGesture {
            #expect(TitleBarGestureBindings.binding(for: unsupportedGesture, in: []) == nil)
        } else {
            #expect(TitleBarGestureBindings.supportedGestures == DockGestureKind.allCases)
        }
    }
}
