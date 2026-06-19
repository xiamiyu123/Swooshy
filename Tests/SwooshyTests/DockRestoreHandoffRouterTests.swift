import Foundation
import Testing
@testable import Swooshy

@MainActor
struct DockRestoreHandoffRouterTests {
    private let windowIdentity = WindowIdentity(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    )

    @Test
    func consumesDirectRestoreForSameDockAppItemWithinTTL() {
        var now = date(0)
        var router = DockRestoreHandoffRouter(ttl: 1.5) { now }
        let app = appIdentity(processIdentifier: 100)

        router.record(reference(app: app))
        now = date(1.0)

        #expect(router.consumeRestoreWindow(for: dockAppTarget(app)) == windowIdentity)
    }

    @Test
    func consumesOnlyOnce() {
        var now = date(0)
        var router = DockRestoreHandoffRouter(ttl: 1.5) { now }
        let app = appIdentity(processIdentifier: 100)

        router.record(reference(app: app))
        now = date(0.5)

        #expect(router.consumeRestoreWindow(for: dockAppTarget(app)) == windowIdentity)
        #expect(router.consumeRestoreWindow(for: dockAppTarget(app)) == nil)
    }

    @Test
    func expiredHandoffFallsBackToAppRestore() {
        var now = date(0)
        var router = DockRestoreHandoffRouter(ttl: 1.5) { now }
        let app = appIdentity(processIdentifier: 100)

        router.record(reference(app: app))
        now = date(1.6)

        #expect(router.consumeRestoreWindow(for: dockAppTarget(app)) == nil)
    }

    @Test
    func sameBundleWithDifferentProcessIdentifierDoesNotMatch() {
        var now = date(0)
        var router = DockRestoreHandoffRouter(ttl: 1.5) { now }
        let oldApp = appIdentity(processIdentifier: 100)
        let restartedApp = appIdentity(processIdentifier: 101)

        router.record(reference(app: oldApp))
        now = date(0.5)

        #expect(router.consumeRestoreWindow(for: dockAppTarget(restartedApp)) == nil)
    }

    @Test
    func minimizedDockItemTargetsKeepTheirOriginalPriority() {
        var now = date(0)
        var router = DockRestoreHandoffRouter(ttl: 1.5) { now }
        let app = appIdentity(processIdentifier: 100)
        let handle = DockMinimizedItemHandle()

        router.record(reference(app: app))
        now = date(0.5)

        let minimizedItemTarget = InteractionTarget.window(
            WindowIdentity(),
            app: app,
            source: .dockMinimizedItem(handle)
        )
        #expect(router.consumeRestoreWindow(for: minimizedItemTarget) == nil)
        #expect(router.consumeRestoreWindow(for: .unresolvedDockMinimizedItem(handle)) == nil)
        #expect(router.consumeRestoreWindow(for: dockAppTarget(app)) == windowIdentity)
    }

    private func reference(app: AppIdentity) -> MinimizedWindowReference {
        MinimizedWindowReference(
            appIdentity: app,
            windowIdentity: windowIdentity
        )
    }

    private func dockAppTarget(_ app: AppIdentity) -> InteractionTarget {
        .application(app, source: .dockAppItem(DockItemHandle()))
    }

    private func appIdentity(processIdentifier: pid_t) -> AppIdentity {
        AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/Codex.app"),
            bundleIdentifier: "com.example.codex",
            processIdentifier: processIdentifier,
            localizedName: "Codex"
        )!
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}
