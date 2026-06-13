import Foundation
import Testing
@testable import Swooshy

struct DangerGestureConfirmationTests {
    @Test
    func dockDangerGestureConfirmationRequiresSelectedGestureAndTarget() {
        let finder = dockAppTarget(name: "Finder")
        let notes = dockAppTarget(name: "Notes")

        #expect(
            matchesDockDangerGestureConfirmation(pendingApplication: finder)
        )
        #expect(!matchesDockDangerGestureConfirmation(
            pendingApplication: finder,
            confirmationGesture: .pinchOut,
        ))
        #expect(!matchesDockDangerGestureConfirmation(
            pendingApplication: finder,
            application: notes
        ))
    }

    @Test
    func titleBarDangerGestureConfirmationRequiresSelectedGestureAndTarget() {
        let firstWindow = titleBarWindowTarget(appName: "Browser")
        let secondWindow = titleBarWindowTarget(appName: "Browser")

        #expect(
            matchesTitleBarDangerGestureConfirmation(pendingApplication: firstWindow)
        )
        #expect(!matchesTitleBarDangerGestureConfirmation(
            pendingApplication: firstWindow,
            confirmationGesture: .swipeUp
        ))
        #expect(!matchesTitleBarDangerGestureConfirmation(
            pendingApplication: firstWindow,
            application: secondWindow,
        ))
    }

    private func dockAppTarget(name: String) -> InteractionTarget {
        .application(
            makeAppIdentity(name: name),
            source: .dockAppItem(DockItemHandle())
        )
    }

    private func titleBarWindowTarget(appName: String) -> InteractionTarget {
        .window(
            WindowIdentity(),
            app: makeAppIdentity(name: appName),
            source: .titleBar
        )
    }

    private func matchesDockDangerGestureConfirmation(
        pendingConfirmationGesture: DockGestureKind = .swipeDown,
        pendingApplication: InteractionTarget,
        confirmationGesture: DockGestureKind = .swipeDown,
        application: InteractionTarget? = nil
    ) -> Bool {
        Swooshy.dockDangerGestureConfirmationMatches(
            pendingConfirmationGesture: pendingConfirmationGesture,
            pendingApplication: pendingApplication,
            confirmationGesture: confirmationGesture,
            application: application ?? pendingApplication
        )
    }

    private func matchesTitleBarDangerGestureConfirmation(
        pendingConfirmationGesture: DockGestureKind = .pinchIn,
        pendingApplication: InteractionTarget,
        confirmationGesture: DockGestureKind = .pinchIn,
        application: InteractionTarget? = nil
    ) -> Bool {
        Swooshy.titleBarDangerGestureConfirmationMatches(
            pendingConfirmationGesture: pendingConfirmationGesture,
            pendingApplication: pendingApplication,
            confirmationGesture: confirmationGesture,
            application: application ?? pendingApplication
        )
    }

    private func makeAppIdentity(name: String) -> AppIdentity {
        AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleIdentifier: "com.example.\(name.lowercased())",
            processIdentifier: 100,
            localizedName: name
        )!
    }
}
