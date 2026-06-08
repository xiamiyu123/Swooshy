import Foundation
import Testing
@testable import Swooshy

struct TitleBarPinchConfirmationTests {
    @Test
    func dockPinchConfirmationRequiresSameGestureActionAndTarget() {
        let finder = dockAppTarget(name: "Finder")
        let notes = dockAppTarget(name: "Notes")

        #expect(
            matchesDockPinchConfirmation(pendingApplication: finder)
        )
        #expect(!matchesDockPinchConfirmation(
            pendingApplication: finder,
            gesture: .pinchOut,
        ))
        #expect(!matchesDockPinchConfirmation(
            pendingApplication: finder,
            action: .closeWindow,
        ))
        #expect(!matchesDockPinchConfirmation(
            pendingApplication: finder,
            application: notes
        ))
    }

    @Test
    func titleBarPinchConfirmationRequiresSameTarget() {
        let firstWindow = titleBarWindowTarget(appName: "Browser")
        let secondWindow = titleBarWindowTarget(appName: "Browser")

        #expect(
            matchesTitleBarPinchConfirmation(pendingApplication: firstWindow)
        )
        #expect(!matchesTitleBarPinchConfirmation(
            pendingApplication: firstWindow,
            application: secondWindow,
        ))
    }

    @Test
    func titleBarPinchConfirmationRequiresSameTabCloseReplacementMode() {
        let target = titleBarWindowTarget(appName: "Browser")

        #expect(!matchesTitleBarPinchConfirmation(
            pendingAction: .quitApplication,
            pendingApplication: target,
            pendingReplacesWithTabClose: true,
            action: .quitApplication,
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

    private func matchesDockPinchConfirmation(
        pendingGesture: DockGestureKind = .pinchIn,
        pendingAction: DockGestureAction = .quitApplication,
        pendingApplication: InteractionTarget,
        gesture: DockGestureKind = .pinchIn,
        action: DockGestureAction = .quitApplication,
        application: InteractionTarget? = nil
    ) -> Bool {
        Swooshy.dockPinchConfirmationMatches(
            pendingGesture: pendingGesture,
            pendingAction: pendingAction,
            pendingApplication: pendingApplication,
            gesture: gesture,
            action: action,
            application: application ?? pendingApplication
        )
    }

    private func matchesTitleBarPinchConfirmation(
        pendingAction: WindowAction = .closeWindow,
        pendingApplication: InteractionTarget,
        pendingReplacesWithTabClose: Bool = false,
        action: WindowAction = .closeWindow,
        application: InteractionTarget? = nil,
        replacesWithTabClose: Bool = false
    ) -> Bool {
        Swooshy.titleBarPinchConfirmationMatches(
            pendingAction: pendingAction,
            pendingApplication: pendingApplication,
            pendingReplacesWithTabClose: pendingReplacesWithTabClose,
            action: action,
            application: application ?? pendingApplication,
            replacesWithTabClose: replacesWithTabClose
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
