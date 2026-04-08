import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct MinimizedDockLedgerTests {
    private final class FakeDockBindingStore: DockMinimizedWindowBindingManaging {
        var eligibleSnapshots: [WindowRecordSnapshot]
        var snapshotsByIdentity: [WindowIdentity: WindowRecordSnapshot]

        init(eligibleSnapshots: [WindowRecordSnapshot]) {
            self.eligibleSnapshots = eligibleSnapshots
            self.snapshotsByIdentity = Dictionary(
                uniqueKeysWithValues: eligibleSnapshots.map { ($0.identity, $0) }
            )
        }

        func minimizedWindowSnapshotsEligibleForDockBinding() -> [WindowRecordSnapshot] {
            eligibleSnapshots.filter { $0.boundDockMinimizedHandle == nil }
        }

        func bindDockMinimizedHandle(_ handle: DockMinimizedItemHandle, to windowIdentity: WindowIdentity) {
            guard var snapshot = snapshotsByIdentity[windowIdentity] else {
                return
            }

            snapshot = WindowRecordSnapshot(
                identity: snapshot.identity,
                appIdentity: snapshot.appIdentity,
                ownerProcessIdentifier: snapshot.ownerProcessIdentifier,
                title: snapshot.title,
                frame: snapshot.frame,
                isMinimized: snapshot.isMinimized,
                isFocused: snapshot.isFocused,
                isMain: snapshot.isMain,
                lastMinimizedAt: snapshot.lastMinimizedAt,
                boundDockMinimizedHandle: handle
            )
            snapshotsByIdentity[windowIdentity] = snapshot
            eligibleSnapshots = eligibleSnapshots.map { $0.identity == windowIdentity ? snapshot : $0 }
        }

        func unbindDockMinimizedHandle(_ handle: DockMinimizedItemHandle) {
            for (identity, snapshot) in snapshotsByIdentity where snapshot.boundDockMinimizedHandle == handle {
                let updatedSnapshot = WindowRecordSnapshot(
                    identity: snapshot.identity,
                    appIdentity: snapshot.appIdentity,
                    ownerProcessIdentifier: snapshot.ownerProcessIdentifier,
                    title: snapshot.title,
                    frame: snapshot.frame,
                    isMinimized: snapshot.isMinimized,
                    isFocused: snapshot.isFocused,
                    isMain: snapshot.isMain,
                    lastMinimizedAt: snapshot.lastMinimizedAt,
                    boundDockMinimizedHandle: nil
                )
                snapshotsByIdentity[identity] = updatedSnapshot
            }

            eligibleSnapshots = eligibleSnapshots.map { snapshot in
                guard snapshot.boundDockMinimizedHandle == handle else {
                    return snapshot
                }

                return WindowRecordSnapshot(
                    identity: snapshot.identity,
                    appIdentity: snapshot.appIdentity,
                    ownerProcessIdentifier: snapshot.ownerProcessIdentifier,
                    title: snapshot.title,
                    frame: snapshot.frame,
                    isMinimized: snapshot.isMinimized,
                    isFocused: snapshot.isFocused,
                    isMain: snapshot.isMain,
                    lastMinimizedAt: snapshot.lastMinimizedAt,
                    boundDockMinimizedHandle: nil
                )
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
            lastMinimizedAt: lastMinimizedAt,
            boundDockMinimizedHandle: nil
        )
    }

    private func dockItem(processIdentifier: pid_t) -> MinimizedDockLedger.SnapshotItem {
        let element = AXUIElementCreateApplication(processIdentifier)
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
                    lastMinimizedAt: Date(timeIntervalSinceReferenceDate: 10)
                ),
                snapshot(
                    name: "Safari",
                    processIdentifier: 101,
                    windowIdentity: secondWindow,
                    lastMinimizedAt: Date(timeIntervalSinceReferenceDate: 11)
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

        if case .window(let resolvedWindowIdentity, _, let source) = firstTarget {
            #expect(resolvedWindowIdentity == firstWindow)
            #expect(source == .dockMinimizedItem(firstHandle))
        } else {
            Issue.record("expected first minimized Dock item to resolve to a window target")
        }

        if case .window(let resolvedWindowIdentity, _, let source) = secondTarget {
            #expect(resolvedWindowIdentity == secondWindow)
            #expect(source == .dockMinimizedItem(secondHandle))
        } else {
            Issue.record("expected second minimized Dock item to resolve to a window target")
        }
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
                    lastMinimizedAt: Date(timeIntervalSinceReferenceDate: 20)
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
}
