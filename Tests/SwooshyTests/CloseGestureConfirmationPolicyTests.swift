import Foundation
import Testing
@testable import Swooshy

@MainActor
struct CloseGestureConfirmationPolicyTests {
    @Test
    func legacyBrowserWindowCloseConfirmationOnlyAppliesToTitleBarWindowClose() {
        let browserWindow = makeWindow(name: "Safari", bundleIdentifier: "com.apple.Safari")

        #expect(
            titleBarConfirmationAction(
                action: .closeWindow,
                application: browserWindow,
                legacyBrowserWindowCloseConfirmationEnabled: true
            ) == .closeWindow
        )

        #expect(
            titleBarConfirmationAction(
                action: .quitApplication,
                application: browserWindow,
                legacyBrowserWindowCloseConfirmationEnabled: true
            ) == nil
        )

        #expect(
            dockConfirmationAction(
                action: .quitApplication,
                closeAndQuitConfirmationEnabled: false
            ) == nil
        )
    }

    @Test
    func closeAndQuitConfirmationAppliesToDockAndTitleBarPinchGestures() {
        let appWindow = makeWindow(name: "Calendar", bundleIdentifier: "com.apple.iCal")

        #expect(
            dockConfirmationAction(
                action: .quitApplication,
                closeAndQuitConfirmationEnabled: true
            ) == .quitApplication
        )

        #expect(
            dockConfirmationAction(
                action: .closeWindow,
                closeAndQuitConfirmationEnabled: true
            ) == .closeWindow
        )

        #expect(
            titleBarConfirmationAction(
                action: .quitApplication,
                application: appWindow,
                closeAndQuitConfirmationEnabled: true
            ) == .quitApplication
        )
    }

    @Test
    func confirmationSkipsNonPinchGestures() {
        let appWindow = makeWindow(name: "Safari", bundleIdentifier: "com.apple.Safari")

        #expect(
            dockConfirmationAction(
                gesture: .swipeDown,
                action: .closeWindow,
                closeAndQuitConfirmationEnabled: true
            ) == nil
        )

        #expect(
            titleBarConfirmationAction(
                gesture: .swipeDown,
                action: .closeWindow,
                application: appWindow,
                legacyBrowserWindowCloseConfirmationEnabled: true,
                closeAndQuitConfirmationEnabled: true
            ) == nil
        )
    }

    private func dockConfirmationAction(
        gesture: DockGestureKind = .pinchIn,
        action: DockGestureAction,
        closeAndQuitConfirmationEnabled: Bool = false
    ) -> CloseGestureConfirmationAction? {
        CloseGestureConfirmationPolicy.confirmationActionForDockGesture(
            gesture: gesture,
            action: action,
            closeAndQuitConfirmationEnabled: closeAndQuitConfirmationEnabled
        )
    }

    private func titleBarConfirmationAction(
        gesture: DockGestureKind = .pinchIn,
        action: WindowAction,
        application: InteractionTarget,
        legacyBrowserWindowCloseConfirmationEnabled: Bool = false,
        closeAndQuitConfirmationEnabled: Bool = false
    ) -> CloseGestureConfirmationAction? {
        CloseGestureConfirmationPolicy.confirmationActionForTitleBarGesture(
            gesture: gesture,
            action: action,
            application: application,
            legacyBrowserWindowCloseConfirmationEnabled: legacyBrowserWindowCloseConfirmationEnabled,
            closeAndQuitConfirmationEnabled: closeAndQuitConfirmationEnabled
        )
    }

    private func makeWindow(name: String, bundleIdentifier: String) -> InteractionTarget {
        .window(
            WindowIdentity(),
            app: AppIdentity(
                bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
                bundleIdentifier: bundleIdentifier,
                processIdentifier: 100,
                localizedName: name
            )!,
            source: .titleBar
        )
    }
}
