import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct MinimizedDockLedgerTests {
    private final class FakeDockBindingStore: DockMinimizedWindowBindingManaging {
        var orderedIdentities: [WindowIdentity]
        var snapshotsByIdentity: [WindowIdentity: WindowRecordSnapshot]

        init(eligibleSnapshots: [WindowRecordSnapshot]) {
            self.orderedIdentities = eligibleSnapshots.map(\.identity)
            self.snapshotsByIdentity = Dictionary(
                uniqueKeysWithValues: eligibleSnapshots.map { ($0.identity, $0) }
            )
        }

        func minimizedWindowSnapshotsEligibleForDockBinding() -> [WindowRecordSnapshot] {
            orderedIdentities.compactMap { snapshotsByIdentity[$0] }
                .filter { $0.boundDockMinimizedHandle == nil }
        }

        func bindDockMinimizedHandle(_ handle: DockMinimizedItemHandle, to windowIdentity: WindowIdentity) {
            guard let snapshot = snapshotsByIdentity[windowIdentity] else {
                return
            }

            snapshotsByIdentity[windowIdentity] = snapshot.withBoundDockMinimizedHandle(handle)
        }

        func unbindDockMinimizedHandle(_ handle: DockMinimizedItemHandle) {
            for (identity, snapshot) in snapshotsByIdentity where snapshot.boundDockMinimizedHandle == handle {
                snapshotsByIdentity[identity] = snapshot.withBoundDockMinimizedHandle(nil)
            }
        }

        func windowSnapshot(for identity: WindowIdentity) -> WindowRecordSnapshot? {
            snapshotsByIdentity[identity]
        }
    }

    private func appIdentity(
        name: String,
        processIdentifier: pid_t
    ) -> AppIdentity {
        AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleIdentifier: "com.example.\(name.lowercased())",
            processIdentifier: processIdentifier,
            localizedName: name
        )!
    }

    private func snapshot(
        name: String,
        processIdentifier: pid_t,
        windowIdentity: WindowIdentity,
        lastMinimizedAt: Date?
    ) -> WindowRecordSnapshot {
        WindowRecordSnapshot(
            identity: windowIdentity,
            appIdentity: appIdentity(name: name, processIdentifier: processIdentifier),
            ownerProcessIdentifier: processIdentifier,
            title: name,
            frame: CGRect(x: 0, y: 0, width: 640, height: 480),
            isMinimized: true,
            isFocused: false,
            isMain: false,
            isFullScreen: false,
            lastMinimizedAt: lastMinimizedAt,
            boundDockMinimizedHandle: nil
        )
    }

    private func dockItem(processIdentifier: pid_t) -> MinimizedDockLedger.SnapshotItem {
        let element = AXAttributeReader.applicationElement(for: processIdentifier)
        return MinimizedDockLedger.SnapshotItem(
            token: DockElementToken(element: element),
            element: element,
            frame: CGRect(x: CGFloat(processIdentifier), y: 0, width: 32, height: 32)
        )
    }

    @Test
    func bindsNewDockItemsToObservedMinimizedWindowsInChronologicalOrder() throws {
        let ledger = MinimizedDockLedger()
        let firstWindow = WindowIdentity()
        let secondWindow = WindowIdentity()
        let store = FakeDockBindingStore(
            eligibleSnapshots: [
                snapshot(
                    name: "Finder",
                    processIdentifier: 100,
                    windowIdentity: firstWindow,
                    lastMinimizedAt: minimizedAt(10)
                ),
                snapshot(
                    name: "Safari",
                    processIdentifier: 101,
                    windowIdentity: secondWindow,
                    lastMinimizedAt: minimizedAt(11)
                ),
            ]
        )

        let firstItem = dockItem(processIdentifier: 700)
        let secondItem = dockItem(processIdentifier: 701)
        ledger.reconcile(with: [firstItem, secondItem], registry: store)

        let firstHandle = try #require(ledger.handle(for: firstItem.token))
        let secondHandle = try #require(ledger.handle(for: secondItem.token))

        let firstTarget = try #require(ledger.target(for: firstHandle, registry: store))
        let secondTarget = try #require(ledger.target(for: secondHandle, registry: store))

        expectWindowTarget(firstTarget, identity: firstWindow, handle: firstHandle)
        expectWindowTarget(secondTarget, identity: secondWindow, handle: secondHandle)
    }

    @Test
    func leavesStartupDockItemsUnresolvedWithoutObservedWindowBinding() throws {
        let ledger = MinimizedDockLedger()
        let store = FakeDockBindingStore(eligibleSnapshots: [])
        let item = dockItem(processIdentifier: 800)

        ledger.reconcile(with: [item], registry: store)

        let handle = try #require(ledger.handle(for: item.token))
        #expect(ledger.target(for: handle, registry: store) == .unresolvedDockMinimizedItem(handle))
    }

    @Test
    func removedDockItemsUnbindResolvedWindows() throws {
        let ledger = MinimizedDockLedger()
        let windowIdentity = WindowIdentity()
        let store = FakeDockBindingStore(
            eligibleSnapshots: [
                snapshot(
                    name: "Ghostty",
                    processIdentifier: 102,
                    windowIdentity: windowIdentity,
                    lastMinimizedAt: minimizedAt(20)
                ),
            ]
        )
        let item = dockItem(processIdentifier: 900)

        ledger.reconcile(with: [item], registry: store)
        let handle = try #require(ledger.handle(for: item.token))
        #expect(store.windowSnapshot(for: windowIdentity)?.boundDockMinimizedHandle == handle)

        ledger.reconcile(with: [], registry: store)

        #expect(store.windowSnapshot(for: windowIdentity)?.boundDockMinimizedHandle == nil)
    }

    private func expectWindowTarget(
        _ target: InteractionTarget,
        identity: WindowIdentity,
        handle: DockMinimizedItemHandle
    ) {
        guard case .window(let resolvedWindowIdentity, _, let source) = target else {
            Issue.record("expected minimized Dock item to resolve to a window target")
            return
        }

        #expect(resolvedWindowIdentity == identity)
        #expect(source == .dockMinimizedItem(handle))
    }

    private func minimizedAt(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}
