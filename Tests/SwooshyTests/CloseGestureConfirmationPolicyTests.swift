import Foundation
import Testing
@testable import Swooshy

@MainActor
struct CloseGestureConfirmationPolicyTests {
    @Test
    func dangerGestureConfirmationAppliesToSelectedDockAndTitleBarGestures() {
        let appWindow = makeWindow(name: "Calendar", bundleIdentifier: "com.apple.iCal")

        #expect(
            dockRequiresConfirmation(
                gesture: .swipeUp,
                action: .quitApplication,
                requiresDangerConfirmation: true
            )
        )

        #expect(
            dockRequiresConfirmation(
                action: .minimizeWindow,
                requiresDangerConfirmation: true
            )
        )

        #expect(
            titleBarRequiresConfirmation(
                gesture: .swipeLeft,
                action: .leftHalf,
                application: appWindow,
                requiresDangerConfirmation: true
            )
        )
    }

    @Test
    func dangerGestureConfirmationNotRequiredForUnselectedGestures() {
        let appWindow = makeWindow(name: "Calendar", bundleIdentifier: "com.apple.iCal")

        #expect(
            !dockRequiresConfirmation(
                action: .quitApplication,
                requiresDangerConfirmation: false
            )
        )

        #expect(
            !titleBarRequiresConfirmation(
                action: .closeWindow,
                application: appWindow,
                requiresDangerConfirmation: false
            )
        )
    }

    @Test
    func dangerGestureConfirmationSkipsSmartFullScreenExitReplacement() {
        let appWindow = makeWindow(name: "Calendar", bundleIdentifier: "com.apple.iCal")

        #expect(
            !titleBarRequiresConfirmation(
                gesture: .pinchIn,
                action: .closeWindow,
                application: appWindow,
                requiresDangerConfirmation: true,
                isReplacedBySmartFullScreenExit: true
            )
        )
    }

    private func dockRequiresConfirmation(
        gesture: DockGestureKind = .pinchIn,
        action: DockGestureAction,
        requiresDangerConfirmation: Bool = false
    ) -> Bool {
        CloseGestureConfirmationPolicy.requiresConfirmationForDockGesture(
            gesture: gesture,
            action: action,
            requiresDangerConfirmation: requiresDangerConfirmation
        )
    }

    private func titleBarRequiresConfirmation(
        gesture: DockGestureKind = .pinchIn,
        action: WindowAction,
        application: InteractionTarget,
        requiresDangerConfirmation: Bool = false,
        isReplacedBySmartFullScreenExit: Bool = false
    ) -> Bool {
        CloseGestureConfirmationPolicy.requiresConfirmationForTitleBarGesture(
            gesture: gesture,
            action: action,
            application: application,
            requiresDangerConfirmation: requiresDangerConfirmation,
            isReplacedBySmartFullScreenExit: isReplacedBySmartFullScreenExit
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
