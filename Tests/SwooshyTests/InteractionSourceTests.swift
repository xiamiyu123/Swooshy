import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

struct InteractionSourceTests {
    @Test
    func minimizedDockItemSourceIsIdentified() {
        let sources: [(source: InteractionSource, isDockMinimizedItem: Bool)] = [
            (.dockMinimizedItem(DockMinimizedItemHandle()), true),
            (.dockAppItem(DockItemHandle()), false),
            (.titleBar, false),
            (.browserTabFallback, false),
        ]

        for (source, isDockMinimizedItem) in sources {
            #expect(source.isDockMinimizedItem == isDockMinimizedItem)
        }
    }
}

struct InteractionTargetTests {
    @Test
    func logDescriptionUsesAppIdentityAndSourceLabel() {
        let app = makeAppIdentity()

        #expect(
            InteractionTarget.application(
                app,
                source: .dockAppItem(DockItemHandle())
            ).logDescription == "Calendar [com.apple.iCal] via dock-app-item"
        )
        #expect(
            InteractionTarget.window(
                WindowIdentity(),
                app: app,
                source: .titleBar
            ).logDescription == "Calendar [com.apple.iCal] via title-bar"
        )
    }

    @Test
    func unresolvedDockMinimizedItemKeepsStandaloneLogDescription() {
        #expect(
            InteractionTarget.unresolvedDockMinimizedItem(
                DockMinimizedItemHandle()
            ).logDescription == "unresolved minimized Dock item"
        )
    }

    private func makeAppIdentity() -> AppIdentity {
        AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/Calendar.app"),
            bundleIdentifier: "com.apple.iCal",
            processIdentifier: 42,
            localizedName: "Calendar"
        )!
    }
}

struct DockElementTokenTests {
    @Test
    func windowIdentifierTokensAreDistinctFromElementHashTokens() {
        let windowIdentifierToken = DockElementToken(
            processIdentifier: 42,
            windowIdentifier: 7
        )
        let matchingWindowIdentifierToken = DockElementToken(
            processIdentifier: 42,
            windowIdentifier: 7
        )
        let elementHashToken = DockElementToken(
            processIdentifier: 42,
            rawHash: 7
        )

        #expect(windowIdentifierToken == matchingWindowIdentifierToken)
        #expect(windowIdentifierToken != elementHashToken)
    }
}
