import Foundation
import Testing
@testable import Swooshy

struct TitleBarPinchConfirmationTests {
    @Test
    func dockPinchConfirmationRequiresSameGestureActionAndTarget() {
        let finder = InteractionTarget.application(
            makeAppIdentity(name: "Finder"),
            source: .dockAppItem(DockItemHandle())
        )
        let notes = InteractionTarget.application(
            makeAppIdentity(name: "Notes"),
            source: .dockAppItem(DockItemHandle())
        )

        #expect(
            dockPinchConfirmationMatches(
                pendingGesture: .pinchIn,
                pendingAction: .quitApplication,
                pendingApplication: finder,
                gesture: .pinchIn,
                action: .quitApplication,
                application: finder
            )
        )
        #expect(
            dockPinchConfirmationMatches(
                pendingGesture: .pinchIn,
                pendingAction: .quitApplication,
                pendingApplication: finder,
                gesture: .pinchOut,
                action: .quitApplication,
                application: finder
            ) == false
        )
        #expect(
            dockPinchConfirmationMatches(
                pendingGesture: .pinchIn,
                pendingAction: .quitApplication,
                pendingApplication: finder,
                gesture: .pinchIn,
                action: .closeWindow,
                application: finder
            ) == false
        )
        #expect(
            dockPinchConfirmationMatches(
                pendingGesture: .pinchIn,
                pendingAction: .quitApplication,
                pendingApplication: finder,
                gesture: .pinchIn,
                action: .quitApplication,
                application: notes
            ) == false
        )
    }

    @Test
    func titleBarPinchConfirmationRequiresSameTarget() {
        let app = makeAppIdentity(name: "Browser")
        let firstWindow = InteractionTarget.window(WindowIdentity(), app: app, source: .titleBar)
        let secondWindow = InteractionTarget.window(WindowIdentity(), app: app, source: .titleBar)

        #expect(
            titleBarPinchConfirmationMatches(
                pendingAction: .closeWindow,
                pendingApplication: firstWindow,
                pendingReplacesWithTabClose: false,
                action: .closeWindow,
                application: firstWindow,
                replacesWithTabClose: false
            )
        )
        #expect(
            titleBarPinchConfirmationMatches(
                pendingAction: .closeWindow,
                pendingApplication: firstWindow,
                pendingReplacesWithTabClose: false,
                action: .closeWindow,
                application: secondWindow,
                replacesWithTabClose: false
            ) == false
        )
    }

    @Test
    func titleBarPinchConfirmationRequiresSameTabCloseReplacementMode() {
        let target = InteractionTarget.window(
            WindowIdentity(),
            app: makeAppIdentity(name: "Browser"),
            source: .titleBar
        )

        #expect(
            titleBarPinchConfirmationMatches(
                pendingAction: .quitApplication,
                pendingApplication: target,
                pendingReplacesWithTabClose: true,
                action: .quitApplication,
                application: target,
                replacesWithTabClose: false
            ) == false
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
