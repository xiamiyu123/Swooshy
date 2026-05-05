import Foundation
import Testing
@testable import Swooshy

@MainActor
struct CloseGestureConfirmationPolicyTests {
    @Test
    func legacyBrowserWindowCloseConfirmationOnlyAppliesToTitleBarWindowClose() {
        let browserWindow = InteractionTarget.window(
            WindowIdentity(),
            app: makeAppIdentity(
                name: "Safari",
                bundleIdentifier: "com.apple.Safari"
            ),
            source: .titleBar
        )

        #expect(
            CloseGestureConfirmationPolicy.confirmationActionForTitleBarGesture(
                gesture: .pinchIn,
                action: .closeWindow,
                application: browserWindow,
                legacyBrowserWindowCloseConfirmationEnabled: true,
                closeAndQuitConfirmationEnabled: false
            ) == .closeWindow
        )

        #expect(
            CloseGestureConfirmationPolicy.confirmationActionForTitleBarGesture(
                gesture: .pinchIn,
                action: .quitApplication,
                application: browserWindow,
                legacyBrowserWindowCloseConfirmationEnabled: true,
                closeAndQuitConfirmationEnabled: false
            ) == nil
        )

        #expect(
            CloseGestureConfirmationPolicy.confirmationActionForDockGesture(
                gesture: .pinchIn,
                action: .quitApplication,
                closeAndQuitConfirmationEnabled: false
            ) == nil
        )
    }

    @Test
    func closeAndQuitConfirmationAppliesToDockAndTitleBarPinchGestures() {
        let appWindow = InteractionTarget.window(
            WindowIdentity(),
            app: makeAppIdentity(
                name: "Calendar",
                bundleIdentifier: "com.apple.iCal"
            ),
            source: .titleBar
        )

        #expect(
            CloseGestureConfirmationPolicy.confirmationActionForDockGesture(
                gesture: .pinchIn,
                action: .quitApplication,
                closeAndQuitConfirmationEnabled: true
            ) == .quitApplication
        )

        #expect(
            CloseGestureConfirmationPolicy.confirmationActionForDockGesture(
                gesture: .pinchIn,
                action: .closeWindow,
                closeAndQuitConfirmationEnabled: true
            ) == .closeWindow
        )

        #expect(
            CloseGestureConfirmationPolicy.confirmationActionForTitleBarGesture(
                gesture: .pinchIn,
                action: .quitApplication,
                application: appWindow,
                legacyBrowserWindowCloseConfirmationEnabled: false,
                closeAndQuitConfirmationEnabled: true
            ) == .quitApplication
        )
    }

    @Test
    func confirmationSkipsNonPinchGestures() {
        let appWindow = InteractionTarget.window(
            WindowIdentity(),
            app: makeAppIdentity(
                name: "Safari",
                bundleIdentifier: "com.apple.Safari"
            ),
            source: .titleBar
        )

        #expect(
            CloseGestureConfirmationPolicy.confirmationActionForDockGesture(
                gesture: .swipeDown,
                action: .closeWindow,
                closeAndQuitConfirmationEnabled: true
            ) == nil
        )

        #expect(
            CloseGestureConfirmationPolicy.confirmationActionForTitleBarGesture(
                gesture: .swipeDown,
                action: .closeWindow,
                application: appWindow,
                legacyBrowserWindowCloseConfirmationEnabled: true,
                closeAndQuitConfirmationEnabled: true
            ) == nil
        )
    }

    private func makeAppIdentity(name: String, bundleIdentifier: String) -> AppIdentity {
        AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleIdentifier: bundleIdentifier,
            processIdentifier: 100,
            localizedName: name
        )!
    }
}
